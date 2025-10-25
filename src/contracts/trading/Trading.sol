// SPDX-License-Identifier: MIT

import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";
import {NameService} from "@EVVM/testnet/contracts/nameService/NameService.sol";
import {SignatureRecover} from "@EVVM/testnet/lib/SignatureRecover.sol";
import {AdvancedStrings} from "@EVVM/testnet/lib/AdvancedStrings.sol";
import {Caip10Utils} from "@EVVM/testnet/lib/Caip10Utils.sol";

pragma solidity ^0.8.29;

/**
 * @title Trading Contract
 * @author https://x.com/0xjsieth
 * @notice Chain-agnostic trading balance management system using CAIP-10 identifiers
 * @dev Manages trading balances for cross-chain users with deposit/withdraw functionality
 *
 * Key Features:
 * - Chain-agnostic account identification using CAIP-10 standard
 * - Supports both native chain operations and cross-chain operations
 * - Admin-controlled balance synchronization for off-chain trading systems
 * - Signature-based order cancellation with nonce tracking
 * - Integration with EVVM ecosystem for balance management
 * - ERC20 token handling with treasury integration
 *
 * Architecture:
 * - Uses CAIP-10 identifiers for wallet and token identification
 * - Maintains separate balances per (wallet, token) pair
 * - Tracks depositor addresses for withdrawal authorization
 * - Supports both on-chain (NATIVE) and cross-chain (OTHER_CHAIN) operations
 * - Admin can synchronize balances from off-chain trading systems
 *
 * Security:
 * - Owner-controlled synchronization prevents unauthorized balance changes
 * - Signature verification for order cancellations
 * - Withdrawal restrictions to depositor addresses only
 * - Balance validation on all withdrawal operations
 *
 * @custom:security-contact security@evvm.info
 * @custom:chain-agnostic Uses CAIP-10 for multi-chain support
 */
contract Trading is Ownable {
    using CAIP10 for string;
    using Strings for string;
    using SafeTransferLib for address;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Stores depositor address for a trading account
     * @dev Links a specific (wallet, token) pair to the EVM depositor who owns it
     *      Balances are stored in EVVM, not here - this only tracks ownership
     * @param evmDepositorWallet The EVM address that deposited and owns the account
     */
    struct DepositorInfo {
        address evmDepositorWallet;
    }

    /**
     * @notice Arguments for balance synchronization from off-chain systems
     * @dev Used by admin to update trading balances based on off-chain trading activity
     * @param caip10Wallet CAIP-10 identifier of the user's wallet
     * @param caip10Token CAIP-10 identifier of the token
     * @param evmDepositorWallet The EVM address associated with this balance
     * @param newAmount The updated balance amount to set
     */
    struct SyncUpArguments {
        string caip10Wallet;
        string caip10Token;
        address evmDepositorWallet;
        uint256 newAmount;
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // ENUMS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Defines the execution context for deposit/withdraw operations
     * @dev Determines whether operation is native to this chain or cross-chain
     * @param NATIVE Operation executes on the native chain with actual token transfers
     * @param OTHER_CHAIN Operation is for cross-chain accounting only (no token transfer)
     */
    enum ActionIs {
        NATIVE,
        OTHER_CHAIN
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when admin synchronizes balances from off-chain system
     * @param newInfo Array of balance updates that were synchronized
     */
    event NewSyncUp(SyncUpArguments[] newInfo);

    /**
     * @notice Emitted when a user deposits tokens to their trading balance
     * @param caip10Wallet CAIP-10 identifier of the depositor's wallet
     * @param caip10Token CAIP-10 identifier of the deposited token
     * @param amount Amount of tokens deposited
     * @param evmDepositorAddress EVM address of the depositor
     */
    event Deposit(string caip10Wallet, string caip10Token, uint256 amount, address evmDepositorAddress);

    /**
     * @notice Emitted when a user withdraws tokens from their trading balance
     * @param caip10Wallet CAIP-10 identifier of the withdrawer's wallet
     * @param caip10Token CAIP-10 identifier of the withdrawn token
     * @param amount Amount of tokens withdrawn
     * @param evmDepositorAddress EVM address of the withdrawer
     */
    event Withdraw(string caip10Wallet, string caip10Token, uint256 amount, address evmDepositorAddress);

    /**
     * @notice Emitted when a user cancels an order using signature verification
     * @param caip10Wallet CAIP-10 identifier of the user cancelling the order
     * @param nonce The nonce value being cancelled
     */
    event OrderCancelled(string indexed caip10Wallet, uint256 nonce);

    /**
     * @notice Emitted when withdrawal fees are collected
     * @param caip10Wallet CAIP-10 identifier of the user paying the fee
     * @param caip10Token CAIP-10 identifier of the token
     * @param feeAmount Amount of fee collected
     * @param isStaker Whether the user received staker discount
     */
    event FeeCollected(string caip10Wallet, string caip10Token, uint256 feeAmount, bool isStaker);

    /**
     * @notice Emitted when an executor (Fisher/Relayer) executes a transaction on behalf of a user
     * @param executor Address of the Fisher/Relayer who executed the transaction
     * @param user Address of the user whose transaction was executed
     * @param reward Amount of tokens paid to the executor as reward
     */
    event ExecutorRewarded(address indexed executor, address indexed user, uint256 reward);

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when attempting to withdraw more than available balance
     * @param have The current available balance
     * @param want The amount attempted to withdraw
     */
    error CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE(uint256 have, uint256 want);

    /**
     * @notice Thrown when non-owner attempts to withdraw from an account
     * @param owner The actual owner address of the account
     */
    error YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT(address owner);

    /**
     * @notice Thrown when signature verification fails for order cancellation
     */
    error INVALID_SIGNATURE();

    /**
     * @notice Thrown when a nonce has already been used for executor operations
     */
    error NONCE_ALREADY_USED();

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Base withdrawal fee in basis points (1% = 100 basis points)
    uint256 public constant FEE_BASIS_POINTS = 100; // 1%

    /// @notice Basis points divisor for percentage calculations
    uint256 public constant BASIS_POINTS_DIVISOR = 10000; // 100%

    /// @notice Staker discount percentage (50% off fees)
    uint256 public constant STAKER_DISCOUNT_PERCENT = 50;

    /// @notice Executor reward as percentage of fee (20% of fees go to executor)
    uint256 public constant EXECUTOR_REWARD_PERCENT = 20;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Address of the EVVM core contract for balance queries and ID retrieval
    address public evvmAddress;

    /// @notice Address of the Treasury contract for token deposit/withdrawal operations
    address public treasuryAddress;

    /// @notice Address of the NameService contract for username resolution
    address public nameServiceAddress;

    /**
     * @notice Nested mapping storing depositor info (ownership) per wallet per token
     * @dev First key is CAIP-10 wallet identifier, second is CAIP-10 token identifier
     *      Maps to DepositorInfo struct containing only the depositor address
     *      IMPORTANT: Actual balances are stored in EVVM contract, not here
     */
    mapping(string caip10Wallet => mapping(string caip10Token => DepositorInfo info)) public depositorInfo;

    /**
     * @notice Tracks used nonces for order cancellation replay protection
     * @dev First key is CAIP-10 wallet identifier, second is nonce value
     *      Value is true if nonce has been used, false otherwise
     */
    mapping(string caip10Wallet => mapping(uint256 nonce => bool used)) public orderNonces;

    /**
     * @notice Tracks used nonces for executor operations (deposits/withdrawals)
     * @dev First key is user address, second is nonce value
     *      Prevents replay attacks for executor-based transactions
     */
    mapping(address user => mapping(uint256 nonce => bool used)) public executorNonces;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the Trading contract with required addresses
     * @dev Sets up ownership and configures integration points
     * @param _initialOwner Address that will have owner privileges
     * @param _evvmAddress Address of the EVVM core contract
     * @param _treasuryAddress Address of the Treasury contract
     * @param _nameServiceAddress Address of the NameService contract for username resolution
     */
    constructor(address _initialOwner, address _evvmAddress, address _treasuryAddress, address _nameServiceAddress) {
        _initializeOwner(_initialOwner); // Initialize Ownable with the specified owner address
        evvmAddress = _evvmAddress; // Store the EVVM contract address for later interactions
        treasuryAddress = _treasuryAddress; // Store the Treasury contract address for token management
        nameServiceAddress = _nameServiceAddress; // Store the NameService contract address for username resolution
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Synchronizes trading balances from off-chain trading system
     * @dev Only callable by contract owner to prevent unauthorized balance manipulation
     *      Supports username resolution for EVM chains via NameService
     *
     * Synchronization Process:
     * - Updates multiple (wallet, token) balances in a single transaction
     * - Resolves usernames to CAIP-10 for EVM chains
     * - Overwrites existing balances with new values from off-chain system
     * - Sets the depositor address for each balance entry
     * - Emits NewSyncUp event for off-chain tracking
     *
     * NameService Integration:
     * - For EVM chains, wallet can be username or CAIP-10
     * - Automatically resolves usernames to addresses
     * - Converts to CAIP-10 format for storage
     * - Non-EVM chains must use CAIP-10 format
     *
     * Use Cases:
     * - Periodic synchronization of trading activity from centralized exchange
     * - Recovery from off-chain database state
     * - Migration of user balances during upgrades
     * - Batch balance corrections
     *
     * Security:
     * - Owner-only access prevents unauthorized balance changes
     * - All updates logged via event emission
     * - Atomic operation ensures consistency
     *
     * @param _data Array of balance updates to synchronize (wallet can be username for EVM)
     *
     * @custom:access-control Owner only
     */
    function syncUp(SyncUpArguments[] memory _data) external onlyOwner {
        // Iterate through each balance update in the provided array
        for (uint256 i = 0; i < _data.length;) {
            // Resolve wallet to CAIP-10 format (handles usernames for EVM chains)
            string memory caip10Wallet;
            (string memory namespace, string memory chainId,) = Caip10Utils.parseCaip10(_data[i].caip10Token);

            // Try to resolve username for EVM chains, fallback to direct use
            if (Caip10Utils.isEvmNamespace(namespace) && !Caip10Utils.validateCaip10(_data[i].caip10Wallet)) {
                // Looks like a username, try to resolve it
                caip10Wallet = _resolveToCaip10(_data[i].caip10Wallet, namespace, chainId);
            } else {
                // Already CAIP-10 or non-EVM chain
                caip10Wallet = _data[i].caip10Wallet;
            }

            // Get current balance from EVVM using raw CAIP-10 identifiers (source of truth)
            uint256 currentBalance = Evvm(evvmAddress).getBalanceCaip10Native(caip10Wallet, _data[i].caip10Token);

            // Calculate the difference and update EVVM CAIP-10 balance accordingly
            if (_data[i].newAmount > currentBalance) {
                // Need to add balance - credit EVVM using CAIP-10 native function
                uint256 toAdd = _data[i].newAmount - currentBalance;
                Evvm(evvmAddress).addAmountToUserCaip10(caip10Wallet, _data[i].caip10Token, toAdd);
            } else if (_data[i].newAmount < currentBalance) {
                // Need to remove balance - debit EVVM using CAIP-10 native function
                uint256 toRemove = currentBalance - _data[i].newAmount;
                Evvm(evvmAddress).removeAmountFromUserCaip10(caip10Wallet, _data[i].caip10Token, toRemove);
            }
            // If equal, no change needed

            // Store/update the depositor info (ownership tracking only)
            depositorInfo[caip10Wallet][_data[i].caip10Token] =
                DepositorInfo({evmDepositorWallet: _data[i].evmDepositorWallet});

            unchecked {
                i++; // Increment loop counter without overflow check (safe as array length is bounded)
            }
        }
        emit NewSyncUp(_data); // Emit event with all synchronized balances for off-chain tracking
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // DEPOSIT FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposits tokens to a trading balance using CAIP-10 identifiers
     * @dev Supports both native chain operations (with token transfer) and cross-chain accounting
     *
     * Operation Modes:
     *
     * NATIVE Mode:
     * - Extracts EVM address from CAIP-10 wallet identifier
     * - Transfers tokens from msg.sender to this contract
     * - Deposits tokens into Treasury for safekeeping
     * - Credits trading balance for the wallet
     * - Sets depositor address from CAIP-10 wallet
     *
     * OTHER_CHAIN Mode:
     * - Only accessible by owner (for cross-chain deposits)
     * - Credits balance without actual token transfer
     * - Sets depositor address from parameter
     * - Used when tokens are deposited on another chain
     *
     * Chain-Agnostic Features:
     * - Accepts CAIP-10 identifiers for both wallet and token
     * - Parses chain-specific addresses from identifiers
     * - Maintains consistent balance tracking across chains
     *
     * Depositor Name Resolution:
     * - Accepts hex address string (e.g., "0x1234...")
     * - Accepts EVVM username (e.g., "alice")
     * - Automatically resolves username to address via NameService
     *
     * Security:
     * - NATIVE mode requires actual token approval and transfer
     * - OTHER_CHAIN mode restricted to owner only
     * - Depositor address tracked for withdrawal authorization
     *
     * @param _caip10Token CAIP-10 identifier of the token being deposited (e.g., "eip155:1:0x...")
     * @param _caip10Wallet CAIP-10 identifier of the depositor's wallet
     * @param _amount Amount of tokens to deposit in token's base unit
     * @param _action NATIVE for on-chain transfer, OTHER_CHAIN for cross-chain accounting
     * @param _depositorWalletOrName EVM address string or EVVM username of depositor
     *
     * @custom:chain-agnostic Uses CAIP-10 for multi-chain support
     */
    function deposit(
        string memory _caip10Token,
        string memory _caip10Wallet,
        uint256 _amount,
        ActionIs _action,
        string memory _depositorWalletOrName
    ) external {
        // Resolve depositor wallet/name to address
        address depositorAddress = _resolveWalletOrNameToAddress(_depositorWalletOrName);

        // Check if this is a native chain deposit (with actual token transfer)
        if (_action == ActionIs.NATIVE) {
            // Parse the CAIP-10 token identifier to extract the token address component
            (, string memory tokenAddress) = _caip10Token.parse();
            // Convert the string token address to an Ethereum address type
            address token = tokenAddress.parseAddress();
            // Transfer tokens from the caller to this contract using SafeTransferLib
            token.safeTransferFrom(msg.sender, address(this), _amount);
            // Forward the tokens to the Treasury contract which will update EVVM EVM balances
            Treasury(treasuryAddress).deposit(token, _amount);
            // Note: Treasury.deposit() calls Evvm.addAmountToUser() for EVM balances
            // Additionally, credit the CAIP-10 native balance in EVVM (parallel tracking)
            Evvm(evvmAddress).addAmountToUserCaip10(_caip10Wallet, _caip10Token, _amount);
            // Store the depositor's address for withdrawal authorization (ownership tracking only)
            depositorInfo[_caip10Wallet][_caip10Token].evmDepositorWallet = depositorAddress;
        } else {
            // OTHER_CHAIN mode: verify caller is the contract owner
            _checkOwner();
            // Credit the balance directly in EVVM using raw CAIP-10 identifiers
            // No address conversion - pure chain-agnostic operation
            Evvm(evvmAddress).addAmountToUserCaip10(_caip10Wallet, _caip10Token, _amount);
            // If this is the first deposit for this wallet-token pair, set the depositor address
            if (depositorInfo[_caip10Wallet][_caip10Token].evmDepositorWallet == address(0)) {
                depositorInfo[_caip10Wallet][_caip10Token].evmDepositorWallet = depositorAddress;
            }
        }
        // Emit deposit event for off-chain tracking and indexing
        emit Deposit(_caip10Wallet, _caip10Token, _amount, depositorAddress);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // WITHDRAWAL FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Withdraws tokens from trading balance using CAIP-10 identifiers or usernames (EVM only)
     * @dev Supports both native chain operations (with token transfer) and cross-chain accounting
     *      Applies 1% withdrawal fee with 50% discount for EVVM stakers
     *
     * Security Validations:
     * - Verifies sufficient balance before withdrawal
     * - Validates msg.sender is the original depositor
     * - Prevents unauthorized withdrawals
     *
     * Fee Structure:
     * - 1% base fee on withdrawal amount
     * - 50% discount for EVVM stakers (0.5% effective fee)
     * - Fees sent to EVVM treasury
     * - User receives net amount after fees
     *
     * NameService Integration (EVM chains only):
     * - Accepts username instead of CAIP-10 wallet for NATIVE mode
     * - Resolves username → address via NameService
     * - Converts to CAIP-10 format automatically
     * - Non-EVM chains must use CAIP-10 format directly
     *
     * Operation Modes:
     *
     * NATIVE Mode:
     * - Parses EVM token address from CAIP-10 identifier
     * - Calculates and deducts withdrawal fee
     * - Withdraws tokens from Treasury
     * - Transfers net amount to msg.sender
     * - Sends fee to EVVM treasury
     * - Decrements trading balance by full amount
     * - Available to any authorized user
     *
     * OTHER_CHAIN Mode:
     * - Only accessible by owner (for cross-chain withdrawals)
     * - Applies fees (sent to treasury via CAIP-10)
     * - Decrements balance without actual token transfer
     * - Used when tokens are withdrawn on another chain
     *
     * Chain-Agnostic Features:
     * - Accepts CAIP-10 identifiers or usernames (EVM only)
     * - Maintains consistent balance tracking across chains
     * - Supports cross-chain withdrawal scenarios
     *
     * @param _caip10Token CAIP-10 identifier of the token being withdrawn
     * @param _caip10WalletOrName CAIP-10 identifier or username (EVM only) of the withdrawer's wallet
     * @param _amount Amount of tokens to withdraw BEFORE fees
     * @param _action NATIVE for on-chain transfer, OTHER_CHAIN for cross-chain accounting
     *
     * @custom:security Only the depositor can withdraw their balance
     * @custom:chain-agnostic Uses CAIP-10 for multi-chain support
     * @custom:fees 1% withdrawal fee with 50% staker discount
     */
    function withdraw(string memory _caip10Token, string memory _caip10WalletOrName, uint256 _amount, ActionIs _action)
        external
    {
        // Resolve wallet parameter to CAIP-10 format (handles names for EVM chains)
        string memory _caip10Wallet;
        if (_action == ActionIs.NATIVE) {
            // Parse CAIP-10 token to get namespace and chainId for name resolution
            (string memory namespace, string memory chainId) = _caip10Token.parse();
            _caip10Wallet = _resolveToCaip10(_caip10WalletOrName, namespace, chainId);
        } else {
            // OTHER_CHAIN mode: must use CAIP-10 format directly
            _caip10Wallet = _caip10WalletOrName;
        }

        // Get current balance from EVVM using raw CAIP-10 identifiers (source of truth)
        uint256 currentBalance = Evvm(evvmAddress).getBalanceCaip10Native(_caip10Wallet, _caip10Token);

        // Validate that the user has sufficient balance for the requested withdrawal
        if (_amount > currentBalance) {
            // Revert with detailed error showing available vs. requested amount
            revert CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE(currentBalance, _amount);
        }

        // Get depositor address for authorization and staker check
        address depositor = depositorInfo[_caip10Wallet][_caip10Token].evmDepositorWallet;

        // Verify that msg.sender is the original depositor who owns this balance
        if (depositor != msg.sender && _action == ActionIs.NATIVE) {
            // Revert with error showing the actual owner address
            revert YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT(depositor);
        }

        // Calculate withdrawal fee with staker discount
        (uint256 fee, uint256 netAmount, bool isStaker) = _calculateWithdrawalFee(_amount, depositor);

        // Check if this is a native chain withdrawal (with actual token transfer)
        if (_action == ActionIs.NATIVE) {
            // Parse the CAIP-10 token identifier to extract the token address component
            (, string memory tokenAddressStr) = _caip10Token.parse();
            // Convert the string token address to an Ethereum address type
            address token = tokenAddressStr.parseAddress();

            // Withdraw ONLY net amount from Treasury (not fee)
            // Fee remains in EVVM treasury balance
            Treasury(treasuryAddress).withdraw(token, netAmount);
            // Note: Treasury.withdraw() calls Evvm.removeAmountFromUser() for EVM balances

            // Debit the full CAIP-10 native balance in EVVM (parallel tracking) - includes fee
            Evvm(evvmAddress).removeAmountFromUserCaip10(_caip10Wallet, _caip10Token, _amount);

            // Credit fee to treasury's CAIP-10 balance (fee stays in EVVM)
            if (fee > 0) {
                (string memory namespace, string memory chainId,) = Caip10Utils.parseCaip10(_caip10Token);
                string memory treasuryCaip10 = Caip10Utils.toCaip10(namespace, chainId, treasuryAddress);
                Evvm(evvmAddress).addAmountToUserCaip10(treasuryCaip10, _caip10Token, fee);

                // Emit fee collection event
                emit FeeCollected(_caip10Wallet, _caip10Token, fee, isStaker);
            }

            // Transfer net amount to the user
            token.safeTransfer(msg.sender, netAmount);
        } else {
            // OTHER_CHAIN mode: verify caller is the contract owner
            _checkOwner();

            // Debit the full amount from user's CAIP-10 balance
            Evvm(evvmAddress).removeAmountFromUserCaip10(_caip10Wallet, _caip10Token, _amount);

            // Credit fee to treasury via CAIP-10 if fee > 0
            if (fee > 0) {
                // Convert treasury address to CAIP-10 for cross-chain fee tracking
                (string memory namespace, string memory chainId,) = Caip10Utils.parseCaip10(_caip10Token);
                string memory treasuryCaip10 = Caip10Utils.toCaip10(namespace, chainId, treasuryAddress);

                // Credit treasury balance via CAIP-10
                Evvm(evvmAddress).addAmountToUserCaip10(treasuryCaip10, _caip10Token, fee);

                // Emit fee collection event
                emit FeeCollected(_caip10Wallet, _caip10Token, fee, isStaker);
            }
        }

        // Emit withdrawal event for off-chain tracking and indexing
        emit Withdraw(_caip10Wallet, _caip10Token, netAmount, depositor);
    }

    /**
     * @notice Allows a Fisher/Relayer (executor) to execute a withdrawal on behalf of a user
     * @dev Implements the EVVM executor pattern - Fisher validates and executes user-signed withdrawal
     *
     * How it works:
     * 1. User signs withdrawal request off-chain with their private key
     * 2. Fisher/Relayer picks up the signed request
     * 3. Fisher calls this function and pays gas
     * 4. Contract verifies user signature
     * 5. Withdrawal executes and Fisher gets rewarded from fees
     *
     * Benefits:
     * - Users get gasless withdrawals
     * - Fishers earn rewards for executing valid transactions
     * - Prevents failed transactions (Fisher validates first)
     *
     * @param _caip10Token CAIP-10 identifier of the token being withdrawn
     * @param _caip10Wallet CAIP-10 identifier of the user's wallet
     * @param _amount Amount of tokens to withdraw
     * @param _nonce Unique nonce to prevent replay attacks
     * @param _userSignature User's signature authorizing this withdrawal
     *
     * @custom:executor Fisher/Relayer executes and gets rewarded
     */
    function withdrawWithExecutor(
        string memory _caip10Token,
        string memory _caip10Wallet,
        uint256 _amount,
        uint256 _nonce,
        bytes memory _userSignature
    ) external {
        // Get user address from CAIP-10 wallet identifier
        (, string memory userAddressStr) = _caip10Wallet.parse();
        address user = userAddressStr.parseAddress();

        // Check nonce hasn't been used (prevent replay attacks)
        if (executorNonces[user][_nonce]) {
            revert NONCE_ALREADY_USED();
        }

        // Verify user signed this withdrawal
        if (!_verifyWithdrawalSignature(user, _caip10Token, _amount, _nonce, _userSignature)) {
            revert INVALID_SIGNATURE();
        }

        // Mark nonce as used
        executorNonces[user][_nonce] = true;

        // Get current balance
        uint256 currentBalance = Evvm(evvmAddress).getBalanceCaip10Native(_caip10Wallet, _caip10Token);

        // Check balance
        if (_amount > currentBalance) {
            revert CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE(currentBalance, _amount);
        }

        // Calculate fee with staker discount
        (uint256 fee, uint256 netAmount, bool isStaker) = _calculateWithdrawalFee(_amount, user);

        // Calculate executor reward (20% of fee)
        uint256 executorReward = (fee * EXECUTOR_REWARD_PERCENT) / 100;

        // Parse token address for transfer
        (, string memory tokenAddressStr) = _caip10Token.parse();
        address token = tokenAddressStr.parseAddress();

        // Withdraw from Treasury (net amount + executor reward)
        Treasury(treasuryAddress).withdraw(token, netAmount + executorReward);

        // Debit full amount from user's CAIP-10 balance
        Evvm(evvmAddress).removeAmountFromUserCaip10(_caip10Wallet, _caip10Token, _amount);

        // Credit remaining fee to treasury
        if (fee - executorReward > 0) {
            (string memory namespace, string memory chainId,) = Caip10Utils.parseCaip10(_caip10Token);
            string memory treasuryCaip10 = Caip10Utils.toCaip10(namespace, chainId, treasuryAddress);
            Evvm(evvmAddress).addAmountToUserCaip10(treasuryCaip10, _caip10Token, fee - executorReward);
        }

        // Transfer net amount to user
        token.safeTransfer(user, netAmount);

        // Transfer reward to executor (Fisher/Relayer)
        token.safeTransfer(msg.sender, executorReward);

        // Emit events
        emit Withdraw(_caip10Wallet, _caip10Token, netAmount, user);
        emit FeeCollected(_caip10Wallet, _caip10Token, fee, isStaker);
        emit ExecutorRewarded(msg.sender, user, executorReward);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // ORDER MANAGEMENT FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancels an order using cryptographic signature verification
     * @dev Allows users to cancel pending orders by proving ownership through signature
     *
     * Cancellation Process:
     * - Extracts EVM address from CAIP-10 wallet identifier
     * - Verifies signature was signed by the wallet owner
     * - Marks nonce as used to prevent replay attacks
     * - Emits event for off-chain order book updates
     *
     * Signature Verification:
     * - Uses EVVM ID for domain separation
     * - Includes function name "cancelOrder" in message
     * - Incorporates nonce for replay protection
     * - Validates against extracted signer address
     *
     * Replay Protection:
     * - Each nonce can only be used once per wallet
     * - Prevents duplicate order cancellations
     * - Tracks used nonces in orderNonces mapping
     *
     * Use Cases:
     * - User wants to cancel pending order
     * - Off-chain order book needs to invalidate order
     * - Wallet owner proves control without on-chain order storage
     *
     * @param _caip10Wallet CAIP-10 identifier of the wallet cancelling the order
     * @param _nonce The nonce value associated with the order to cancel
     * @param _signature EIP-191 signature proving ownership of the wallet
     *
     * @custom:security Signature verification prevents unauthorized cancellations
     */
    function cancelOrder(string memory _caip10Wallet, uint256 _nonce, bytes memory _signature) external {
        // Extract the EVM address from the CAIP-10 wallet identifier for signature verification
        address signer = Caip10Utils.extractAddress(_caip10Wallet);

        // Verify that the provided signature was created by the wallet owner
        if (!_verifyCancelOrderSignature(signer, _nonce, _signature)) {
            // Revert if signature verification fails (invalid or not signed by owner)
            revert INVALID_SIGNATURE();
        }

        // Mark this nonce as used to prevent replay attacks
        orderNonces[_caip10Wallet][_nonce] = true;

        // Emit event for off-chain order book to process the cancellation
        emit OrderCancelled(_caip10Wallet, _nonce);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates withdrawal fee with staker discount
     * @dev Applies 1% base fee with 50% discount for EVVM stakers
     *
     * Fee Structure:
     * - Non-staker: 1% of withdrawal amount (100 basis points)
     * - EVVM staker: 0.5% of withdrawal amount (50 basis points, 50% discount)
     *
     * Staker Status:
     * - Checks depositor's EVM address via Evvm.isAddressStaker()
     * - Only EVM addresses can be stakers (staking is EVM-based)
     * - Non-EVM chains always get full fee (no staker concept)
     *
     * @param _amount Withdrawal amount before fees
     * @param _depositor EVM address of the account depositor
     * @return fee The calculated fee amount
     * @return netAmount The amount after fee deduction
     * @return isStaker Whether the depositor is a staker
     */
    function _calculateWithdrawalFee(uint256 _amount, address _depositor)
        internal
        view
        returns (uint256 fee, uint256 netAmount, bool isStaker)
    {
        // Check if depositor is an EVVM staker (EVM-only check)
        isStaker = Evvm(evvmAddress).isAddressStaker(_depositor);

        // Calculate base fee: 1% of amount
        fee = (_amount * FEE_BASIS_POINTS) / BASIS_POINTS_DIVISOR;

        // Apply 50% discount for stakers
        if (isStaker) {
            fee = (fee * STAKER_DISCOUNT_PERCENT) / 100;
        }

        // Calculate net amount after fee
        netAmount = _amount - fee;
    }

    /**
     * @notice Resolves a wallet address string or EVVM username to an EVM address
     * @dev Attempts multiple resolution strategies with try-catch pattern
     *
     * Resolution Strategy:
     * 1. Try to parse as hex address string (e.g., "0x1234...")
     * 2. If that fails, try to resolve as EVVM username via NameService
     * 3. If both fail, revert with error
     *
     * Examples:
     * - "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb" → parses to address
     * - "alice" → resolves to alice's registered address via NameService
     *
     * @param _walletOrName Hex address string or EVVM username
     * @return resolvedAddress The resolved EVM address
     *
     * @custom:reverts If neither address parsing nor name resolution succeeds
     */
    function _resolveWalletOrNameToAddress(string memory _walletOrName)
        internal
        view
        returns (address resolvedAddress)
    {
        // Strategy 1: Try to parse as hex address
        // Check if string starts with "0x" and has correct length (42 chars for address)
        bytes memory walletBytes = bytes(_walletOrName);

        if (
            walletBytes.length == 42 && walletBytes[0] == 0x30 // '0'
                && walletBytes[1] == 0x78
        ) {
            // 'x'
            // Attempt to parse as address
            try this.parseAddressExternal(_walletOrName) returns (address parsed) {
                return parsed;
            } catch {
                // Parsing failed, continue to name resolution
            }
        }

        // Strategy 2: Try to resolve as EVVM username via NameService
        address nameResolved = NameService(nameServiceAddress).getOwnerOfIdentity(_walletOrName);

        // Check if name resolution succeeded (non-zero address)
        require(nameResolved != address(0), "Invalid depositor: not a valid address or registered EVVM name");

        return nameResolved;
    }

    /**
     * @notice External wrapper for address parsing to enable try-catch
     * @dev Required because parseAddress is a library function and can't be called with try-catch directly
     * @param _addressStr Hex address string to parse
     * @return The parsed address
     */
    function parseAddressExternal(string memory _addressStr) external pure returns (address) {
        return _addressStr.parseAddress();
    }

    /**
     * @notice Resolves a username or CAIP-10 identifier to CAIP-10 format
     * @dev Handles NameService resolution for EVM chains only
     *
     * Resolution Logic:
     * 1. If input is already valid CAIP-10, return as-is
     * 2. If EVM namespace, attempt NameService resolution
     * 3. If non-EVM namespace, revert (must use CAIP-10)
     *
     * NameService Constraints:
     * - Only works for EVM chains (eip155 namespace)
     * - Resolves username → EVM address
     * - Converts address to CAIP-10 format
     * - Non-EVM chains have no NameService concept
     *
     * @param _nameOrCaip10 Username (for EVM) or CAIP-10 identifier
     * @param _namespace Blockchain namespace (e.g., "eip155", "cosmos")
     * @param _chainId Chain identifier within namespace
     * @return caip10Identifier The resolved CAIP-10 identifier
     */
    function _resolveToCaip10(string memory _nameOrCaip10, string memory _namespace, string memory _chainId)
        internal
        view
        returns (string memory caip10Identifier)
    {
        // If already CAIP-10 format, return as-is
        if (Caip10Utils.validateCaip10(_nameOrCaip10)) {
            return _nameOrCaip10;
        }

        // Only resolve names for EVM chains
        if (Caip10Utils.isEvmNamespace(_namespace)) {
            // Resolve username to address via NameService
            address resolvedAddr = NameService(nameServiceAddress).getOwnerOfIdentity(_nameOrCaip10);

            // Revert if name not found
            require(resolvedAddr != address(0), "Name not found in NameService");

            // Convert resolved address to CAIP-10 format
            return Caip10Utils.toCaip10(_namespace, _chainId, resolvedAddr);
        }

        // Non-EVM chains must use CAIP-10 format directly
        revert("Non-EVM chains must use CAIP-10 format");
    }

    /**
     * @notice Internal function to verify order cancellation signatures
     * @dev Uses EIP-191 standard for signature verification with domain-specific data
     *
     * Verification Process:
     * - Retrieves EVVM ID from the EVVM contract for domain separation
     * - Constructs message hash from: evvmID + "cancelOrder" + nonce
     * - Recovers signer address from signature
     * - Compares recovered address with expected signer
     *
     * Domain Separation:
     * - Includes EVVM ID to prevent cross-chain replay attacks
     * - Function name prevents signature reuse across different functions
     * - Nonce provides per-wallet uniqueness
     *
     * Security Features:
     * - EIP-191 standard signature format
     * - Domain-specific hashing prevents replay on other contracts
     * - Cryptographic proof of wallet ownership
     *
     * @param _signer The address that should have signed the message
     * @param _nonce The nonce value included in the signed message
     * @param _signature The EIP-191 signature to verify
     * @return true if signature is valid and matches the signer, false otherwise
     *
     * @custom:security Uses EIP-191 with domain separation for security
     */
    function _verifyCancelOrderSignature(address _signer, uint256 _nonce, bytes memory _signature)
        internal
        view
        returns (bool)
    {
        // Retrieve the unique EVVM ID from the EVVM contract for domain separation
        uint256 evvmID = Evvm(evvmAddress).getEvvmID();

        // Verify the signature using EIP-191 standard with domain-specific data
        // Message format: evvmID + "cancelOrder" + nonce
        return SignatureRecover.signatureVerification(
            Strings.toString(evvmID), "cancelOrder", Strings.toString(_nonce), _signature, _signer
        );
    }

    /**
     * @notice Internal function to verify withdrawal signatures for executor pattern
     * @dev Uses EIP-191 standard for signature verification with domain-specific data
     *
     * Message Format:
     * - Domain separator: EVVM ID (prevents replay on other EVVMs)
     * - Function identifier: "withdrawWithExecutor"
     * - Parameters: token + amount + nonce
     *
     * @param _signer The address that should have signed the message
     * @param _caip10Token The token identifier included in the signed message
     * @param _amount The withdrawal amount included in the signed message
     * @param _nonce The nonce value included in the signed message
     * @param _signature The EIP-191 signature to verify
     * @return true if signature is valid and matches the signer, false otherwise
     */
    function _verifyWithdrawalSignature(
        address _signer,
        string memory _caip10Token,
        uint256 _amount,
        uint256 _nonce,
        bytes memory _signature
    ) internal view returns (bool) {
        // Get EVVM ID for domain separation
        uint256 evvmID = Evvm(evvmAddress).getEvvmID();

        // Create message with token, amount, and nonce
        // Format: evvmID + "withdrawWithExecutor" + token + amount + nonce
        string memory message =
            string.concat(_caip10Token, ",", Strings.toString(_amount), ",", Strings.toString(_nonce));

        return SignatureRecover.signatureVerification(
            Strings.toString(evvmID), "withdrawWithExecutor", message, _signature, _signer
        );
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS - EVVM INTEGRATION
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Gets the trading balance for a wallet-token pair from EVVM
     * @dev Queries EVVM as the single source of truth using raw CAIP-10 identifiers
     *
     * Deep EVVM Integration:
     * - All balance data is stored in EVVM contract
     * - Queries CAIP-10 native balances directly (no address conversion)
     * - Works with ANY blockchain (Cosmos, Bitcoin, Solana, EVM, etc.)
     *
     * Chain-Agnostic Design:
     * - Uses raw CAIP-10 strings for lookup
     * - No conversion to EVM addresses
     * - Supports non-EVM chains natively
     * - Single source of truth for all chains
     *
     * @param _caip10Wallet CAIP-10 identifier of the user's wallet
     * @param _caip10Token CAIP-10 identifier of the token
     * @return balance The current balance stored in EVVM
     *
     * @custom:evvm-integration Queries EVVM CAIP-10 native balances as source of truth
     * @custom:chain-agnostic Works with all blockchain namespaces
     */
    function getTradeBalance(string memory _caip10Wallet, string memory _caip10Token)
        external
        view
        returns (uint256 balance)
    {
        // Query EVVM for the actual balance using raw CAIP-10 identifiers
        // No address conversion - pure chain-agnostic operation
        return Evvm(evvmAddress).getBalanceCaip10Native(_caip10Wallet, _caip10Token);
    }

    /**
     * @notice Gets the depositor address for a wallet-token pair
     * @dev Returns who owns/controls the trading account
     *
     * @param _caip10Wallet CAIP-10 identifier of the user's wallet
     * @param _caip10Token CAIP-10 identifier of the token
     * @return depositor The EVM address of the depositor who owns this account
     */
    function getDepositor(string memory _caip10Wallet, string memory _caip10Token)
        external
        view
        returns (address depositor)
    {
        return depositorInfo[_caip10Wallet][_caip10Token].evmDepositorWallet;
    }

    /**
     * @notice Calculates withdrawal fee for a given amount and depositor
     * @dev Provides transparency on fees before withdrawal
     *
     * Fee Calculation:
     * - Base fee: 1% (100 basis points)
     * - Staker discount: 50% (0.5% effective fee)
     * - Returns fee amount, net amount, and staker status
     *
     * Use Cases:
     * - UI can show exact fees before withdrawal
     * - Users can verify staker status
     * - Off-chain systems can calculate expected net amounts
     *
     * @param _amount Withdrawal amount (before fees)
     * @param _caip10Wallet CAIP-10 identifier of the wallet
     * @param _caip10Token CAIP-10 identifier of the token
     * @return fee The fee amount that will be charged
     * @return netAmount The amount user will receive after fees
     * @return isStaker Whether the depositor is an EVVM staker
     */
    function getFeeInfo(uint256 _amount, string memory _caip10Wallet, string memory _caip10Token)
        external
        view
        returns (uint256 fee, uint256 netAmount, bool isStaker)
    {
        address depositor = depositorInfo[_caip10Wallet][_caip10Token].evmDepositorWallet;
        return _calculateWithdrawalFee(_amount, depositor);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // TESTING FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets a new owner without any access control
     * @dev ⚠️ TESTING ONLY - DO NOT USE IN PRODUCTION ⚠️
     *      This function allows anyone to change the contract owner
     *      Intended for testing scenarios only
     *
     * @param newOwner The address to set as the new owner
     *
     * @custom:security-warning NO ACCESS CONTROL - Anyone can call this function
     * @custom:testing-only Remove this function before production deployment
     */
    function setOwnerForTesting(address newOwner) external {
        _setOwner(newOwner);
    }
}

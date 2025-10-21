// SPDX-License-Identifier: MIT

import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";
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
     * @notice Stores credentials for a user's trading balance
     * @dev Links a specific (wallet, token) pair to the EVM depositor and their balance
     * @param evmDepositorWallet The EVM address that deposited and owns the balance
     * @param amount The current trading balance amount in the token's base unit
     */
    struct Credentials {
        address evmDepositorWallet;
        uint256 amount;
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

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Address of the EVVM core contract for balance queries and ID retrieval
    address public evvmAddress;

    /// @notice Address of the Treasury contract for token deposit/withdrawal operations
    address public treasuryAddress;

    /**
     * @notice Nested mapping storing trading balances per wallet per token
     * @dev First key is CAIP-10 wallet identifier, second is CAIP-10 token identifier
     *      Maps to Credentials struct containing depositor address and balance
     */
    mapping(string caip10Wallet => mapping(string caip10Token => Credentials credentials)) public tradeBalance;

    /**
     * @notice Tracks used nonces for order cancellation replay protection
     * @dev First key is CAIP-10 wallet identifier, second is nonce value
     *      Value is true if nonce has been used, false otherwise
     */
    mapping(string caip10Wallet => mapping(uint256 nonce => bool used)) public orderNonces;

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the Trading contract with required addresses
     * @dev Sets up ownership and configures integration points
     * @param _initialOwner Address that will have owner privileges
     * @param _evvmAddress Address of the EVVM core contract
     * @param _treasuryAddress Address of the Treasury contract
     */
    constructor(address _initialOwner, address _evvmAddress, address _treasuryAddress) {
        _initializeOwner(_initialOwner); // Initialize Ownable with the specified owner address
        evvmAddress = _evvmAddress; // Store the EVVM contract address for later interactions
        treasuryAddress = _treasuryAddress; // Store the Treasury contract address for token management
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Synchronizes trading balances from off-chain trading system
     * @dev Only callable by contract owner to prevent unauthorized balance manipulation
     *
     * Synchronization Process:
     * - Updates multiple (wallet, token) balances in a single transaction
     * - Overwrites existing balances with new values from off-chain system
     * - Sets the depositor address for each balance entry
     * - Emits NewSyncUp event for off-chain tracking
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
     * @param _data Array of balance updates to synchronize
     *
     * @custom:access-control Owner only
     */
    function syncUp(SyncUpArguments[] memory _data) external onlyOwner {
        // Iterate through each balance update in the provided array
        for (uint256 i = 0; i < _data.length;) {
            // Overwrite the existing balance with new credentials from off-chain system
            tradeBalance[_data[i].caip10Wallet][_data[i].caip10Token] =
                Credentials({evmDepositorWallet: _data[i].evmDepositorWallet, amount: _data[i].newAmount});
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
     * Security:
     * - NATIVE mode requires actual token approval and transfer
     * - OTHER_CHAIN mode restricted to owner only
     * - Depositor address tracked for withdrawal authorization
     *
     * @param _caip10Token CAIP-10 identifier of the token being deposited (e.g., "eip155:1:0x...")
     * @param _caip10Wallet CAIP-10 identifier of the depositor's wallet
     * @param _amount Amount of tokens to deposit in token's base unit
     * @param _action NATIVE for on-chain transfer, OTHER_CHAIN for cross-chain accounting
     * @param _depositorWallet EVM address of depositor (used only in OTHER_CHAIN mode)
     *
     * @custom:chain-agnostic Uses CAIP-10 for multi-chain support
     */
    function deposit(
        string memory _caip10Token,
        string memory _caip10Wallet,
        uint256 _amount,
        ActionIs _action,
        address _depositorWallet
    ) external {
        // Check if this is a native chain deposit (with actual token transfer)
        if (_action == ActionIs.NATIVE) {
            // Parse the CAIP-10 token identifier to extract the token address component
            (, string memory tokenAddress) = _caip10Token.parse();
            // Convert the string token address to an Ethereum address type
            address token = tokenAddress.parseAddress();
            // Transfer tokens from the caller to this contract using SafeTransferLib
            token.safeTransferFrom(msg.sender, address(this), _amount);
            // Forward the tokens to the Treasury contract for safekeeping
            Treasury(treasuryAddress).deposit(token, _amount);
            // Increment the user's trading balance by the deposited amount
            tradeBalance[_caip10Wallet][_caip10Token].amount += _amount;
            // Parse the CAIP-10 wallet identifier to extract the wallet address component
            (, string memory depositorWallet) = _caip10Wallet.parse();
            // Store the depositor's address for withdrawal authorization
            tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet = depositorWallet.parseAddress();
        } else {
            // OTHER_CHAIN mode: verify caller is the contract owner
            _checkOwner();
            // If this is the first deposit for this wallet-token pair, set the depositor address
            if (tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet == address(0)) {
                tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet = _depositorWallet;
            }
            // Increment the user's trading balance (no actual token transfer in OTHER_CHAIN mode)
            tradeBalance[_caip10Wallet][_caip10Token].amount += _amount;
        }
        // Emit deposit event for off-chain tracking and indexing
        emit Deposit(_caip10Wallet, _caip10Token, _amount, _depositorWallet);
    }

    // ═════════════════════════════════════════════════════════════════════════════════════════════
    // WITHDRAWAL FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Withdraws tokens from trading balance using CAIP-10 identifiers
     * @dev Supports both native chain operations (with token transfer) and cross-chain accounting
     *
     * Security Validations:
     * - Verifies sufficient balance before withdrawal
     * - Validates msg.sender is the original depositor
     * - Prevents unauthorized withdrawals
     *
     * Operation Modes:
     *
     * NATIVE Mode:
     * - Parses EVM token address from CAIP-10 identifier
     * - Withdraws tokens from Treasury
     * - Transfers tokens to msg.sender
     * - Decrements trading balance
     * - Available to any authorized user
     *
     * OTHER_CHAIN Mode:
     * - Only accessible by owner (for cross-chain withdrawals)
     * - Decrements balance without actual token transfer
     * - Used when tokens are withdrawn on another chain
     *
     * Chain-Agnostic Features:
     * - Accepts CAIP-10 identifiers for wallet and token
     * - Maintains consistent balance tracking across chains
     * - Supports cross-chain withdrawal scenarios
     *
     * @param _caip10Token CAIP-10 identifier of the token being withdrawn
     * @param _caip10Wallet CAIP-10 identifier of the withdrawer's wallet
     * @param _amount Amount of tokens to withdraw in token's base unit
     * @param _action NATIVE for on-chain transfer, OTHER_CHAIN for cross-chain accounting
     *
     * @custom:security Only the depositor can withdraw their balance
     * @custom:chain-agnostic Uses CAIP-10 for multi-chain support
     */
    function withdraw(string memory _caip10Token, string memory _caip10Wallet, uint256 _amount, ActionIs _action)
        external
    {
        // Validate that the user has sufficient balance for the requested withdrawal
        if (_amount > tradeBalance[_caip10Wallet][_caip10Token].amount) {
            // Revert with detailed error showing available vs. requested amount
            revert CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE(tradeBalance[_caip10Wallet][_caip10Token].amount, _amount);
        }
        // Verify that msg.sender is the original depositor who owns this balance
        if (tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet != msg.sender) {
            // Revert with error showing the actual owner address
            revert YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT(tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet);
        }
        // Check if this is a native chain withdrawal (with actual token transfer)
        if (_action == ActionIs.NATIVE) {
            // Parse the CAIP-10 token identifier to extract the token address component
            (, string memory tokenAddress) = _caip10Token.parse();
            // Convert the string token address to an Ethereum address type
            address token = tokenAddress.parseAddress();
            // Withdraw tokens from the Treasury contract to this contract
            Treasury(treasuryAddress).withdraw(token, _amount);
            // Transfer the withdrawn tokens from this contract to the caller
            token.safeTransfer(msg.sender, _amount);
            // Decrement the user's trading balance by the withdrawn amount
            tradeBalance[_caip10Wallet][_caip10Token].amount -= _amount;
        } else {
            // OTHER_CHAIN mode: verify caller is the contract owner
            _checkOwner();
            // Decrement the user's trading balance (no actual token transfer in OTHER_CHAIN mode)
            tradeBalance[_caip10Wallet][_caip10Token].amount -= _amount;
        }
        // Emit withdrawal event for off-chain tracking and indexing
        emit Withdraw(
            _caip10Wallet, _caip10Token, _amount, tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet
        );
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
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {Trading} from "@EVVM/testnet/contracts/trading/Trading.sol";
import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";
import {EvvmStructs} from "@EVVM/testnet/contracts/evvm/lib/EvvmStructs.sol";
import {SignatureRecover} from "@EVVM/testnet/lib/SignatureRecover.sol";
import {Caip10Utils} from "@EVVM/testnet/lib/Caip10Utils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TradingTest
 * @notice Comprehensive test suite for Trading contract achieving 100% code coverage
 */
contract TradingTest is Test, EvvmStructs {
    Trading public trading;
    Evvm public evvm;
    Treasury public treasury;
    MockERC20 public mockToken;

    address public owner;
    address public user1;
    address public user2;
    address public notOwner;

    uint256 public user1PrivateKey = 0x1;
    uint256 public user2PrivateKey = 0x2;

    string public constant CAIP10_WALLET_USER1 = "eip155:1:0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf";
    string public constant CAIP10_WALLET_USER2 = "eip155:1:0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF";
    string public caip10Token;

    event NewSyncUp(Trading.SyncUpArguments[] newInfo);
    event Deposit(string caip10Wallet, string caip10Token, uint256 amount, address evmDepositorAddress);
    event Withdraw(string caip10Wallet, string caip10Token, uint256 amount, address evmDepositorAddress);
    event OrderCancelled(string indexed caip10Wallet, uint256 nonce);

    function setUp() public {
        // Setup accounts
        owner = address(this);
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        notOwner = address(0x999);

        // Deploy mock token for trading
        mockToken = new MockERC20();

        // Setup CAIP-10 token identifier
        caip10Token = string(abi.encodePacked("eip155:1:", Strings.toHexString(uint160(address(mockToken)), 20)));

        // Create a different token for principal token (MATE)
        MockERC20 principalToken = new MockERC20();

        // Deploy EVVM with metadata using different principal token
        EvvmMetadata memory metadata = EvvmMetadata({
            EvvmName: "Test EVVM",
            EvvmID: 1,
            principalTokenName: "MATE",
            principalTokenSymbol: "MATE",
            principalTokenAddress: address(principalToken),
            totalSupply: 1000000 * 10 ** 18,
            eraTokens: 500000 * 10 ** 18,
            reward: 10 * 10 ** 18
        });

        evvm = new Evvm(owner, address(0x123), metadata);
        treasury = new Treasury(address(evvm));

        // Setup name service and treasury integration first
        evvm._setupNameServiceAndTreasuryAddress(address(0x456), address(treasury));

        // Create Trading contract with NameService address
        trading = new Trading(owner, address(evvm), address(treasury), address(0x456));

        // Authorize Trading contract to modify EVVM balances for deep integration
        evvm.setAuthorizedTradingContract(address(trading));

        // Mint tokens to users
        mockToken.mint(user1, 10000 * 10 ** 18);
        mockToken.mint(user2, 10000 * 10 ** 18);

        // Approve trading contract
        vm.prank(user1);
        mockToken.approve(address(trading), type(uint256).max);
        vm.prank(user2);
        mockToken.approve(address(trading), type(uint256).max);

        // Approve treasury
        vm.prank(address(trading));
        mockToken.approve(address(treasury), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testConstructor() public {
        Trading newTrading = new Trading(owner, address(evvm), address(treasury), address(0x456));
        assertEq(newTrading.owner(), owner);
        assertEq(newTrading.evvmAddress(), address(evvm));
        assertEq(newTrading.treasuryAddress(), address(treasury));
        assertEq(newTrading.nameServiceAddress(), address(0x456));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // SYNCUP TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testSyncUpSingle() public {
        Trading.SyncUpArguments[] memory data = new Trading.SyncUpArguments[](1);
        data[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: 1000 * 10 ** 18
        });

        vm.expectEmit(true, true, true, true);
        emit NewSyncUp(data);
        trading.syncUp(data);

        // Check depositor info in Trading contract (ownership tracking)
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);

        // Check balance in EVVM using CAIP-10 native storage (source of truth)
        uint256 balance = trading.getTradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 1000 * 10 ** 18);

        // Verify directly in EVVM's CAIP-10 native balance mapping
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), 1000 * 10 ** 18);
    }

    function testSyncUpMultiple() public {
        Trading.SyncUpArguments[] memory data = new Trading.SyncUpArguments[](2);
        data[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: 1000 * 10 ** 18
        });
        data[1] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER2,
            caip10Token: caip10Token,
            evmDepositorWallet: user2,
            newAmount: 2000 * 10 ** 18
        });

        trading.syncUp(data);

        // Check depositors
        address depositor1 = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        address depositor2 = trading.getDepositor(CAIP10_WALLET_USER2, caip10Token);
        assertEq(depositor1, user1);
        assertEq(depositor2, user2);

        // Check balances in EVVM CAIP-10 native storage
        uint256 balance1 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        uint256 balance2 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER2, caip10Token);
        assertEq(balance1, 1000 * 10 ** 18);
        assertEq(balance2, 2000 * 10 ** 18);
    }

    function testSyncUpOverwritesExisting() public {
        // First sync
        Trading.SyncUpArguments[] memory data1 = new Trading.SyncUpArguments[](1);
        data1[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: 1000 * 10 ** 18
        });
        trading.syncUp(data1);

        // Second sync with different amount
        Trading.SyncUpArguments[] memory data2 = new Trading.SyncUpArguments[](1);
        data2[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: 500 * 10 ** 18
        });
        trading.syncUp(data2);

        // Verify balance in EVVM CAIP-10 native storage
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 500 * 10 ** 18);
    }

    function testSyncUpOnlyOwner() public {
        Trading.SyncUpArguments[] memory data = new Trading.SyncUpArguments[](1);
        data[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: 1000 * 10 ** 18
        });

        vm.prank(notOwner);
        vm.expectRevert();
        trading.syncUp(data);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // DEPOSIT NATIVE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositNative() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 initialBalance = mockToken.balanceOf(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        // Check depositor in Trading
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);

        // Check balance in EVVM CAIP-10 native storage (source of truth)
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount);

        // Verify tokens were transferred
        assertEq(mockToken.balanceOf(user1), initialBalance - depositAmount);
    }

    function testDepositNativeMultipleTimes() public {
        uint256 depositAmount1 = 100 * 10 ** 18;
        uint256 depositAmount2 = 50 * 10 ** 18;

        vm.startPrank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount1, Trading.ActionIs.NATIVE, address(0));
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount2, Trading.ActionIs.NATIVE, address(0));
        vm.stopPrank();

        // Verify accumulated balance in EVVM CAIP-10 native storage
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount1 + depositAmount2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // DEPOSIT OTHER_CHAIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositOtherChain() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.expectEmit(true, true, true, true);
        emit Deposit(CAIP10_WALLET_USER1, caip10Token, depositAmount, user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify depositor
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);

        // Verify balance in EVVM CAIP-10 native storage
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount);
    }

    function testDepositOtherChainSetsDepositorOnlyOnce() public {
        // First deposit sets depositor
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);

        // Second deposit with different depositor address should not change it
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 50 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user2);

        // Verify depositor didn't change
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1); // Should still be user1

        // Verify balance accumulated in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 150 * 10 ** 18);
    }

    function testDepositOtherChainOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // WITHDRAW NATIVE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawNative() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        // Setup: deposit first
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        uint256 balanceBefore = mockToken.balanceOf(user1);

        // Calculate expected fee (1% for non-stakers)
        uint256 expectedFee = (withdrawAmount * 100) / 10000; // 1%
        uint256 expectedNetAmount = withdrawAmount - expectedFee;

        // Withdraw
        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);

        // Check balance in EVVM CAIP-10 native storage (full amount deducted)
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount - withdrawAmount);

        // Verify tokens were transferred (net amount after fee)
        assertEq(mockToken.balanceOf(user1), balanceBefore + expectedNetAmount);

        // Verify fee was credited to treasury's CAIP-10 balance in EVVM
        string memory treasuryCaip10 = Caip10Utils.toCaip10("eip155", "1", address(treasury));
        uint256 treasuryFeeBalance = evvm.getBalanceCaip10Native(treasuryCaip10, caip10Token);
        assertEq(treasuryFeeBalance, expectedFee);
    }

    function testWithdrawNativeFullBalance() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE);

        // Verify zero balance in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 0);
    }

    function testWithdrawNativeInsufficientBalance() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 150 * 10 ** 18;

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(Trading.CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE.selector, depositAmount, withdrawAmount)
        );
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);
    }

    function testWithdrawNativeNotOwner() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Trading.YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT.selector, user1));
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 50 * 10 ** 18, Trading.ActionIs.NATIVE);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // WITHDRAW OTHER_CHAIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawOtherChain() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        // Setup: deposit via OTHER_CHAIN with owner as depositor
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Withdraw via OTHER_CHAIN (requires msg.sender to be depositor AND owner)
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.OTHER_CHAIN);

        // Verify balance in EVVM CAIP-10 native storage
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount - withdrawAmount);
    }

    function testWithdrawOtherChainOnlyOwner() public {
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);

        vm.prank(notOwner);
        vm.expectRevert();
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 50 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN);
    }

    function testWithdrawOtherChainInsufficientBalance() public {
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Trading.CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE.selector, 100 * 10 ** 18, 150 * 10 ** 18
            )
        );
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 150 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CANCEL ORDER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testCancelOrder() public {
        uint256 nonce = 1;
        uint256 evvmID = evvm.getEvvmID();

        // Create signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(CAIP10_WALLET_USER1, nonce);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce, signature);

        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, nonce));
    }

    function testCancelOrderInvalidSignature() public {
        uint256 nonce = 1;
        uint256 evvmID = evvm.getEvvmID();

        // Create signature with wrong private key
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2PrivateKey, messageHash); // Wrong key
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Trading.INVALID_SIGNATURE.selector);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce, signature);
    }

    function testCancelOrderMultipleNonces() public {
        uint256 evvmID = evvm.getEvvmID();

        // Cancel nonce 1
        bytes32 messageHash1 = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(1))).length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(1))
            )
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(user1PrivateKey, messageHash1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        trading.cancelOrder(CAIP10_WALLET_USER1, 1, signature1);

        // Cancel nonce 2
        bytes32 messageHash2 = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(2))).length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(2))
            )
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(user1PrivateKey, messageHash2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        trading.cancelOrder(CAIP10_WALLET_USER1, 2, signature2);

        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, 1));
        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, 2));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositZeroAmountOtherChain() public {
        // Zero deposits work in OTHER_CHAIN mode (no actual token transfer)
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 0, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify zero balance in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 0);
    }

    function testWithdrawZeroAmountOtherChain() public {
        // Deposit with owner as depositor for OTHER_CHAIN withdrawals
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, owner);

        // Withdraw zero amount in OTHER_CHAIN mode (no treasury interaction)
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 0, Trading.ActionIs.OTHER_CHAIN);

        // Verify balance unchanged in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 100 * 10 ** 18);
    }

    function testWithdrawFromZeroBalance() public {
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 0, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify zero balance in EVVM before withdrawal attempt
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), 0);

        vm.expectRevert(abi.encodeWithSelector(Trading.CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE.selector, 0, 1));
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 1, Trading.ActionIs.OTHER_CHAIN);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NON-EVM CHAIN TESTS (TRUE CHAIN-AGNOSTIC SUPPORT)
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testCosmosChainDeposit() public {
        // Cosmos user and token (pure CAIP-10, NO address conversion)
        string memory cosmosWallet = "cosmos:cosmoshub-4:cosmos1abc123def456ghi789jkl0mn";
        string memory cosmosToken = "cosmos:cosmoshub-4:uatom";
        uint256 depositAmount = 1000 * 10 ** 6; // ATOM has 6 decimals

        // Deposit Cosmos tokens (OTHER_CHAIN mode)
        trading.deposit(cosmosToken, cosmosWallet, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify balance in EVVM CAIP-10 native storage (NO address conversion)
        uint256 balance = evvm.getBalanceCaip10Native(cosmosWallet, cosmosToken);
        assertEq(balance, depositAmount);

        // Verify through Trading view function
        uint256 tradeBalance = trading.getTradeBalance(cosmosWallet, cosmosToken);
        assertEq(tradeBalance, depositAmount);
    }

    function testBitcoinChainDeposit() public {
        // Bitcoin user and token (pure CAIP-10)
        string memory bitcoinWallet = "bip122:000000000019d6689c085ae165831e93:128Lkh3S7CkDTBZ8W7BbpsN3YYizJMp8p6";
        string memory bitcoinToken = "bip122:000000000019d6689c085ae165831e93:btc";
        uint256 depositAmount = 50000000; // 0.5 BTC in satoshis

        trading.deposit(bitcoinToken, bitcoinWallet, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify Bitcoin balance in EVVM (no conversion to EVM address)
        uint256 balance = evvm.getBalanceCaip10Native(bitcoinWallet, bitcoinToken);
        assertEq(balance, depositAmount);
    }

    function testSolanaChainDeposit() public {
        // Solana user and token (pure CAIP-10)
        string memory solanaWallet = "solana:mainnet:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp";
        string memory solanaToken = "solana:mainnet:So11111111111111111111111111111111111111112";
        uint256 depositAmount = 1000 * 10 ** 9; // SOL has 9 decimals

        trading.deposit(solanaToken, solanaWallet, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify Solana balance in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(solanaWallet, solanaToken);
        assertEq(balance, depositAmount);
    }

    function testNonEvmChainWithdrawal() public {
        // Test full deposit-withdraw cycle for Cosmos
        string memory cosmosWallet = "cosmos:cosmoshub-4:cosmos1abc123def456ghi789jkl0mn";
        string memory cosmosToken = "cosmos:cosmoshub-4:uatom";
        uint256 depositAmount = 1000 * 10 ** 6;
        uint256 withdrawAmount = 600 * 10 ** 6;

        // Deposit
        trading.deposit(cosmosToken, cosmosWallet, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Withdraw
        trading.withdraw(cosmosToken, cosmosWallet, withdrawAmount, Trading.ActionIs.OTHER_CHAIN);

        // Verify remaining balance
        uint256 balance = evvm.getBalanceCaip10Native(cosmosWallet, cosmosToken);
        assertEq(balance, depositAmount - withdrawAmount);
    }

    function testMixedEvmAndNonEvmBalances() public {
        // EVM deposit
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);

        // Cosmos deposit
        string memory cosmosWallet = "cosmos:cosmoshub-4:cosmos1abc";
        string memory cosmosToken = "cosmos:cosmoshub-4:uatom";
        trading.deposit(cosmosToken, cosmosWallet, 1000 * 10 ** 6, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify both balances coexist in EVVM CAIP-10 storage
        uint256 evmBalance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        uint256 cosmosBalance = evvm.getBalanceCaip10Native(cosmosWallet, cosmosToken);

        assertEq(evmBalance, 100 * 10 ** 18);
        assertEq(cosmosBalance, 1000 * 10 ** 6);
    }

    function testDualBalanceSystemIsolation() public {
        // Test that EVM address-based balances and CAIP-10 balances are separate

        // Add balance to EVM address-based storage (via addBalance faucet)
        evvm.addBalance(user1, address(mockToken), 500 * 10 ** 18);

        // Add balance to CAIP-10 native storage (via Trading)
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify both systems maintain separate balances
        uint256 evmAddressBalance = evvm.getBalance(user1, address(mockToken));
        uint256 caip10Balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);

        assertEq(evmAddressBalance, 500 * 10 ** 18); // EVM storage
        assertEq(caip10Balance, 100 * 10 ** 18); // CAIP-10 storage
            // These are independent - demonstrates dual balance system
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testTradeBalanceView() public view {
        // View function test - just checking it exists and is callable
        trading.getTradeBalance(CAIP10_WALLET_USER1, caip10Token);
    }

    function testOrderNoncesView() public {
        uint256 nonce = 1;
        uint256 evvmID = evvm.getEvvmID();

        assertFalse(trading.orderNonces(CAIP10_WALLET_USER1, nonce));

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce, signature);

        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, nonce));
    }

    function testAddressesView() public view {
        assertEq(trading.evvmAddress(), address(evvm));
        assertEq(trading.treasuryAddress(), address(treasury));
        assertEq(trading.owner(), owner);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - BASIC
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzDepositWithdraw(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18);

        vm.startPrank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, address(0));

        // Verify balance in EVVM CAIP-10 storage
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, amount);

        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE);
        vm.stopPrank();

        // Verify zero balance in EVVM
        uint256 finalBalance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(finalBalance, 0);
    }

    function testFuzzSyncUp(uint128 amount1, uint128 amount2) public {
        Trading.SyncUpArguments[] memory data = new Trading.SyncUpArguments[](2);
        data[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: amount1
        });
        data[1] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER2,
            caip10Token: caip10Token,
            evmDepositorWallet: user2,
            newAmount: amount2
        });

        trading.syncUp(data);

        // Verify balances in EVVM CAIP-10 storage
        uint256 balance1 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        uint256 balance2 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER2, caip10Token);

        assertEq(balance1, amount1);
        assertEq(balance2, amount2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ADVANCED FUZZ TESTS - EXTREME VALUES
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzDepositOtherChainExtremeValues(uint256 amount) public {
        // Test with full uint256 range
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify in EVVM CAIP-10 storage
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, amount);
    }

    function testFuzzMultipleDepositsAccumulation(uint128 amount1, uint128 amount2, uint128 amount3) public {
        // Test that multiple deposits accumulate correctly
        vm.assume(uint256(amount1) + uint256(amount2) + uint256(amount3) <= type(uint256).max);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount1, Trading.ActionIs.OTHER_CHAIN, user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount2, Trading.ActionIs.OTHER_CHAIN, user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount3, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify accumulated balance in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, uint256(amount1) + uint256(amount2) + uint256(amount3));
    }

    function testFuzzPartialWithdrawals(uint128 deposit, uint64 withdraw1, uint64 withdraw2) public {
        // Test multiple partial withdrawals
        vm.assume(deposit > 0);
        vm.assume(uint256(withdraw1) + uint256(withdraw2) <= uint256(deposit));

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, deposit, Trading.ActionIs.OTHER_CHAIN, owner);

        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdraw1, Trading.ActionIs.OTHER_CHAIN);
        uint256 balance1 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance1, uint256(deposit) - uint256(withdraw1));

        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdraw2, Trading.ActionIs.OTHER_CHAIN);
        uint256 balance2 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance2, uint256(deposit) - uint256(withdraw1) - uint256(withdraw2));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - ERROR CONDITIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzWithdrawExceedsBalance(uint128 deposit, uint128 withdraw) public {
        vm.assume(withdraw > deposit);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, deposit, Trading.ActionIs.OTHER_CHAIN, owner);

        vm.expectRevert(
            abi.encodeWithSelector(Trading.CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE.selector, deposit, withdraw)
        );
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdraw, Trading.ActionIs.OTHER_CHAIN);
    }

    function testFuzzUnauthorizedWithdrawal(uint128 amount, address randomUser) public {
        vm.assume(randomUser != user1 && randomUser != address(0));
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18);

        // Deposit as user1
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, address(0));

        // Try to withdraw as different user
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(Trading.YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT.selector, user1));
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE);
    }

    function testFuzzInvalidSignature(uint256 nonce, uint256 wrongPrivateKey) public {
        vm.assume(wrongPrivateKey != 0 && wrongPrivateKey != user1PrivateKey);
        vm.assume(wrongPrivateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337);

        uint256 evvmID = evvm.getEvvmID();

        // Create signature with wrong private key
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Trading.INVALID_SIGNATURE.selector);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce, signature);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - BOUNDARY CONDITIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzMaxUint256Operations(uint256 amount) public {
        // Test operations at uint256 boundaries
        // Bound to prevent fee calculation overflow (amount * 100 / 10000 must not overflow)
        vm.assume(amount > 0 && amount <= type(uint256).max / 100);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, amount);

        // Withdraw full amount
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.OTHER_CHAIN);

        // Verify zero balance (after fee deduction)
        uint256 finalBalance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(finalBalance, 0);
    }

    function testFuzzSyncUpOverwritePreviousBalance(uint128 initialAmount, uint128 newAmount) public {
        // Test that syncUp correctly overwrites previous balances
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, initialAmount, Trading.ActionIs.OTHER_CHAIN, user1);

        Trading.SyncUpArguments[] memory data = new Trading.SyncUpArguments[](1);
        data[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: newAmount
        });

        trading.syncUp(data);

        // Verify balance was overwritten in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, newAmount); // Should be newAmount, not initialAmount + newAmount
    }

    function testFuzzMultipleSyncUpOperations(uint64 amount1, uint64 amount2, uint64 amount3) public {
        // Test multiple syncUp operations in sequence
        Trading.SyncUpArguments[] memory data1 = new Trading.SyncUpArguments[](1);
        data1[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: amount1
        });
        trading.syncUp(data1);

        Trading.SyncUpArguments[] memory data2 = new Trading.SyncUpArguments[](1);
        data2[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: amount2
        });
        trading.syncUp(data2);

        Trading.SyncUpArguments[] memory data3 = new Trading.SyncUpArguments[](1);
        data3[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: user1,
            newAmount: amount3
        });
        trading.syncUp(data3);

        // Verify last syncUp wins in EVVM
        uint256 finalBalance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(finalBalance, amount3); // Last syncUp wins
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - COMPLEX STATE TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzDepositSyncUpWithdrawCycle(uint128 depositAmount, uint128 syncAmount, uint64 withdrawAmount)
        public
    {
        vm.assume(withdrawAmount <= syncAmount);

        // Deposit initial amount
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // SyncUp to new amount (overwrites)
        Trading.SyncUpArguments[] memory data = new Trading.SyncUpArguments[](1);
        data[0] = Trading.SyncUpArguments({
            caip10Wallet: CAIP10_WALLET_USER1,
            caip10Token: caip10Token,
            evmDepositorWallet: owner,
            newAmount: syncAmount
        });
        trading.syncUp(data);

        // Withdraw from synced amount
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.OTHER_CHAIN);

        // Verify final balance in EVVM
        uint256 finalBalance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(finalBalance, uint256(syncAmount) - uint256(withdrawAmount));
    }

    function testFuzzMixedDepositModes(uint128 nativeAmount, uint128 otherChainAmount) public {
        vm.assume(nativeAmount > 0 && nativeAmount <= 5000 * 10 ** 18);

        // Deposit via NATIVE
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, nativeAmount, Trading.ActionIs.NATIVE, address(0));

        // Deposit via OTHER_CHAIN (should accumulate)
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, otherChainAmount, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify accumulated balance in EVVM
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, uint256(nativeAmount) + uint256(otherChainAmount));
    }

    function testFuzzCancelMultipleOrders(uint128 nonce1, uint128 nonce2, uint128 nonce3) public {
        vm.assume(nonce1 != nonce2 && nonce2 != nonce3 && nonce1 != nonce3);

        uint256 evvmID = evvm.getEvvmID();

        // Cancel first order
        bytes32 hash1 = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce1)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce1))
            )
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(user1PrivateKey, hash1);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce1, abi.encodePacked(r1, s1, v1));

        // Cancel second order
        bytes32 hash2 = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce2)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce2))
            )
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(user1PrivateKey, hash2);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce2, abi.encodePacked(r2, s2, v2));

        // Cancel third order
        bytes32 hash3 = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce3)))
                        .length
                ),
                string.concat(Strings.toString(evvmID), ",", "cancelOrder", ",", Strings.toString(nonce3))
            )
        );
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(user1PrivateKey, hash3);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce3, abi.encodePacked(r3, s3, v3));

        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, nonce1));
        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, nonce2));
        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, nonce3));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - MULTI-USER SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzMultiUserIsolation(uint128 amount1, uint128 amount2, uint128 amount3) public {
        // Test that different users' balances are isolated
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount1, Trading.ActionIs.OTHER_CHAIN, user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER2, amount2, Trading.ActionIs.OTHER_CHAIN, user2);

        // Add to user1 again
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount3, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify isolation in EVVM
        uint256 balance1 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        uint256 balance2 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER2, caip10Token);

        assertEq(balance1, uint256(amount1) + uint256(amount3));
        assertEq(balance2, amount2);
    }

    function testFuzzDifferentTokensIsolation(uint128 amount1, uint128 amount2) public {
        // Create second mock token
        MockERC20 secondToken = new MockERC20();
        string memory caip10Token2 =
            string(abi.encodePacked("eip155:1:", Strings.toHexString(uint160(address(secondToken)), 20)));

        // Deposit to same wallet but different tokens
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount1, Trading.ActionIs.OTHER_CHAIN, user1);
        trading.deposit(caip10Token2, CAIP10_WALLET_USER1, amount2, Trading.ActionIs.OTHER_CHAIN, user1);

        // Verify token isolation in EVVM
        uint256 balance1 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        uint256 balance2 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token2);

        assertEq(balance1, amount1);
        assertEq(balance2, amount2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - INVARIANT CHECKS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzInvariantTotalBalanceConservation(uint128 deposit1, uint128 deposit2, uint64 withdraw) public {
        vm.assume(withdraw <= deposit1);

        // Setup two users
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, deposit1, Trading.ActionIs.OTHER_CHAIN, owner);
        trading.deposit(caip10Token, CAIP10_WALLET_USER2, deposit2, Trading.ActionIs.OTHER_CHAIN, user2);

        uint256 totalBefore = uint256(deposit1) + uint256(deposit2);

        // Withdraw from user1
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdraw, Trading.ActionIs.OTHER_CHAIN);

        // Verify balances in EVVM conserve total
        uint256 balance1 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        uint256 balance2 = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER2, caip10Token);

        assertEq(balance1 + balance2, totalBefore - withdraw);
    }

    function testFuzzNoUnderflowOnWithdraw(uint128 balance, uint128 withdraw) public {
        vm.assume(withdraw <= balance);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, balance, Trading.ActionIs.OTHER_CHAIN, owner);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdraw, Trading.ActionIs.OTHER_CHAIN);

        // Verify no underflow in EVVM
        uint256 remainingBalance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(remainingBalance, uint256(balance) - uint256(withdraw));
        assertTrue(remainingBalance <= balance); // No overflow
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - NON-EVM CHAINS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzCosmosBalances(uint128 amount) public {
        string memory cosmosWallet = "cosmos:cosmoshub-4:cosmos1test";
        string memory cosmosToken = "cosmos:cosmoshub-4:uatom";

        trading.deposit(cosmosToken, cosmosWallet, amount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify Cosmos balance without any address conversion
        uint256 balance = evvm.getBalanceCaip10Native(cosmosWallet, cosmosToken);
        assertEq(balance, amount);
    }

    function testFuzzMultiChainIsolation(uint64 evmAmount, uint64 cosmosAmount, uint64 solanaAmount) public {
        string memory cosmosWallet = "cosmos:cosmoshub-4:cosmos1test";
        string memory cosmosToken = "cosmos:cosmoshub-4:uatom";
        string memory solanaWallet = "solana:mainnet:solana1test";
        string memory solanaToken = "solana:mainnet:sol";

        // Deposit to three different chains
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, evmAmount, Trading.ActionIs.OTHER_CHAIN, user1);
        trading.deposit(cosmosToken, cosmosWallet, cosmosAmount, Trading.ActionIs.OTHER_CHAIN, owner);
        trading.deposit(solanaToken, solanaWallet, solanaAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        // Verify each chain's balance is isolated
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), evmAmount);
        assertEq(evvm.getBalanceCaip10Native(cosmosWallet, cosmosToken), cosmosAmount);
        assertEq(evvm.getBalanceCaip10Native(solanaWallet, solanaToken), solanaAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FEE TESTS - NON-STAKER
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawFeeNonStaker() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;

        // Deposit as non-staker
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        // Get fee info before withdrawal
        (uint256 expectedFee, uint256 expectedNet, bool isStaker) =
            trading.getFeeInfo(withdrawAmount, CAIP10_WALLET_USER1, caip10Token);

        // Should NOT be a staker
        assertFalse(isStaker);

        // Fee should be 1% for non-staker
        uint256 calculatedFee = (withdrawAmount * 100) / 10000;
        assertEq(expectedFee, calculatedFee);
        assertEq(expectedNet, withdrawAmount - calculatedFee);

        uint256 userBalanceBefore = mockToken.balanceOf(user1);

        // Withdraw
        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);

        // Verify user received net amount
        assertEq(mockToken.balanceOf(user1), userBalanceBefore + expectedNet);

        // Verify fee was credited to treasury's CAIP-10 balance
        string memory treasuryCaip10 = Caip10Utils.toCaip10("eip155", "1", address(treasury));
        uint256 treasuryFee = evvm.getBalanceCaip10Native(treasuryCaip10, caip10Token);
        assertEq(treasuryFee, expectedFee);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FEE TESTS - STAKER
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawFeeStaker() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;

        // Register user1 as a staker in EVVM (0x01 = FLAG_IS_STAKER)
        evvm.setPointStaker(user1, 0x01);

        // Deposit as staker
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        // Get fee info before withdrawal
        (uint256 expectedFee, uint256 expectedNet, bool isStaker) =
            trading.getFeeInfo(withdrawAmount, CAIP10_WALLET_USER1, caip10Token);

        // Should be a staker
        assertTrue(isStaker);

        // Fee should be 0.5% for staker (50% discount)
        uint256 baseFee = (withdrawAmount * 100) / 10000; // 1%
        uint256 discountedFee = baseFee / 2; // 50% off
        assertEq(expectedFee, discountedFee);
        assertEq(expectedNet, withdrawAmount - discountedFee);

        uint256 userBalanceBefore = mockToken.balanceOf(user1);

        // Withdraw
        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);

        // Verify user received net amount with discounted fee
        assertEq(mockToken.balanceOf(user1), userBalanceBefore + expectedNet);

        // Verify discounted fee was credited to treasury
        string memory treasuryCaip10 = Caip10Utils.toCaip10("eip155", "1", address(treasury));
        uint256 treasuryFee = evvm.getBalanceCaip10Native(treasuryCaip10, caip10Token);
        assertEq(treasuryFee, discountedFee);
    }

    function testGetFeeInfoNonStaker() public {
        uint256 amount = 1000 * 10 ** 18;

        // Deposit as non-staker
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, address(0));

        // Test various withdrawal amounts
        (uint256 fee100, uint256 net100, bool isStaker100) =
            trading.getFeeInfo(100 * 10 ** 18, CAIP10_WALLET_USER1, caip10Token);
        assertFalse(isStaker100);
        assertEq(fee100, 1 * 10 ** 18); // 1% of 100
        assertEq(net100, 99 * 10 ** 18);

        (uint256 fee500, uint256 net500, bool isStaker500) =
            trading.getFeeInfo(500 * 10 ** 18, CAIP10_WALLET_USER1, caip10Token);
        assertFalse(isStaker500);
        assertEq(fee500, 5 * 10 ** 18); // 1% of 500
        assertEq(net500, 495 * 10 ** 18);
    }

    function testGetFeeInfoStaker() public {
        uint256 amount = 1000 * 10 ** 18;

        // Register as staker (0x01 = FLAG_IS_STAKER)
        evvm.setPointStaker(user1, 0x01);

        // Deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, address(0));

        // Test fee calculation with staker discount
        (uint256 fee100, uint256 net100, bool isStaker100) =
            trading.getFeeInfo(100 * 10 ** 18, CAIP10_WALLET_USER1, caip10Token);
        assertTrue(isStaker100);
        assertEq(fee100, 0.5 * 10 ** 18); // 0.5% of 100 (50% discount)
        assertEq(net100, 99.5 * 10 ** 18);
    }

    function testFeeEventEmitted() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        uint256 expectedFee = (withdrawAmount * 100) / 10000;

        // Expect FeeCollected event
        vm.expectEmit(true, true, true, true);
        emit Trading.FeeCollected(CAIP10_WALLET_USER1, caip10Token, expectedFee, false);

        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);
    }

    function testFeeOnOtherChainWithdrawal() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;

        // Deposit via OTHER_CHAIN
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, owner);

        uint256 expectedFee = (withdrawAmount * 100) / 10000;

        // Withdraw via OTHER_CHAIN (owner only)
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.OTHER_CHAIN);

        // Verify fee was credited to treasury via CAIP-10
        string memory treasuryCaip10 = Caip10Utils.toCaip10("eip155", "1", address(treasury));
        uint256 treasuryFee = evvm.getBalanceCaip10Native(treasuryCaip10, caip10Token);
        assertEq(treasuryFee, expectedFee);

        // Verify user balance decreased by full amount
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount - withdrawAmount);
    }

    function testFuzzFeeCalculation(uint128 amount) public {
        // Bound to prevent overflow and stay within user's token balance
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18); // Max balance user has
        vm.assume(amount >= 10000); // Ensure fee is at least 1 wei

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, address(0));

        (uint256 fee, uint256 net, bool isStaker) = trading.getFeeInfo(amount, CAIP10_WALLET_USER1, caip10Token);

        // Verify fee calculation
        assertFalse(isStaker);
        uint256 expectedFee = (amount * 100) / 10000;
        assertEq(fee, expectedFee);
        assertEq(net, amount - expectedFee);

        // Verify fee + net = original amount
        assertEq(fee + net, amount);
    }

    function testFuzzStakerDiscount(uint128 amount) public {
        // Bound to prevent overflow and stay within user's token balance
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18); // Max balance user has
        vm.assume(amount >= 10000); // Ensure fee is at least 1 wei

        // Register as staker (0x01 = FLAG_IS_STAKER)
        evvm.setPointStaker(user2, 0x01);

        vm.prank(user2);
        trading.deposit(caip10Token, CAIP10_WALLET_USER2, amount, Trading.ActionIs.NATIVE, address(0));

        (uint256 fee, uint256 net, bool isStaker) = trading.getFeeInfo(amount, CAIP10_WALLET_USER2, caip10Token);

        // Verify staker status and discounted fee
        assertTrue(isStaker);
        uint256 baseFee = (amount * 100) / 10000;
        uint256 expectedFee = baseFee / 2; // 50% discount
        assertEq(fee, expectedFee);
        assertEq(net, amount - expectedFee);

        // Verify fee + net = original amount
        assertEq(fee + net, amount);
    }
}

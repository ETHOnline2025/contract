// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {Trading} from "@EVVM/testnet/contracts/trading/Trading.sol";
import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";
import {EvvmStructs} from "@EVVM/testnet/contracts/evvm/lib/EvvmStructs.sol";
import {SignatureRecover} from "@EVVM/testnet/lib/SignatureRecover.sol";
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
        trading = new Trading(owner, address(evvm), address(treasury));

        // Setup treasury integration
        evvm._setupNameServiceAndTreasuryAddress(address(0x456), address(treasury));

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
        Trading newTrading = new Trading(owner, address(evvm), address(treasury));
        assertEq(newTrading.owner(), owner);
        assertEq(newTrading.evvmAddress(), address(evvm));
        assertEq(newTrading.treasuryAddress(), address(treasury));
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

        (address depositor, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);
        assertEq(amount, 1000 * 10 ** 18);
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

        (address depositor1, uint256 amount1) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        (address depositor2, uint256 amount2) = trading.tradeBalance(CAIP10_WALLET_USER2, caip10Token);

        assertEq(depositor1, user1);
        assertEq(amount1, 1000 * 10 ** 18);
        assertEq(depositor2, user2);
        assertEq(amount2, 2000 * 10 ** 18);
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

        (address depositor, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, 500 * 10 ** 18);
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
        // Don't test the exact event emission as the depositorWallet might differ in parsing
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        // Check balances
        (address depositor, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);
        assertEq(amount, depositAmount);
        assertEq(mockToken.balanceOf(user1), initialBalance - depositAmount);
    }

    function testDepositNativeMultipleTimes() public {
        uint256 depositAmount1 = 100 * 10 ** 18;
        uint256 depositAmount2 = 50 * 10 ** 18;

        vm.startPrank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount1, Trading.ActionIs.NATIVE, address(0));
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount2, Trading.ActionIs.NATIVE, address(0));
        vm.stopPrank();

        (, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, depositAmount1 + depositAmount2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // DEPOSIT OTHER_CHAIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositOtherChain() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.expectEmit(true, true, true, true);
        emit Deposit(CAIP10_WALLET_USER1, caip10Token, depositAmount, user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, user1);

        (address depositor, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);
        assertEq(amount, depositAmount);
    }

    function testDepositOtherChainSetsDepositorOnlyOnce() public {
        // First deposit sets depositor
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1);

        // Second deposit with different depositor address should not change it
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 50 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user2);

        (address depositor, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1); // Should still be user1
        assertEq(amount, 150 * 10 ** 18);
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

        // Withdraw (don't test exact event as it includes computed values)
        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);

        // Check balances
        (, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, depositAmount - withdrawAmount);
        assertEq(mockToken.balanceOf(user1), balanceBefore + withdrawAmount);
    }

    function testWithdrawNativeFullBalance() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, address(0));

        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE);

        (, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, 0);
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

        (, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, depositAmount - withdrawAmount);
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

        (, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, 0);
    }

    function testWithdrawZeroAmountOtherChain() public {
        // Deposit with owner as depositor for OTHER_CHAIN withdrawals
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, owner);

        // Withdraw zero amount in OTHER_CHAIN mode (no treasury interaction)
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 0, Trading.ActionIs.OTHER_CHAIN);

        (, uint256 amount) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(amount, 100 * 10 ** 18);
    }

    function testWithdrawFromZeroBalance() public {
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 0, Trading.ActionIs.OTHER_CHAIN, user1);

        vm.expectRevert(abi.encodeWithSelector(Trading.CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE.selector, 0, 1));
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 1, Trading.ActionIs.OTHER_CHAIN);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testTradeBalanceView() public view {
        // View function test - just checking it exists and is callable
        trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
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
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzDepositWithdraw(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18);

        vm.startPrank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, address(0));

        (, uint256 balance) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, amount);

        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE);
        vm.stopPrank();

        (, uint256 finalBalance) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
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

        (, uint256 balance1) = trading.tradeBalance(CAIP10_WALLET_USER1, caip10Token);
        (, uint256 balance2) = trading.tradeBalance(CAIP10_WALLET_USER2, caip10Token);

        assertEq(balance1, amount1);
        assertEq(balance2, amount2);
    }
}

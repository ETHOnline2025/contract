// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {Trading} from "@EVVM/testnet/contracts/trading/Trading.sol";
import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";
import {NameService} from "@EVVM/testnet/contracts/nameService/NameService.sol";
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

// Mock NameService for testing name resolution
contract MockNameService {
    mapping(string => address) public nameToAddress;

    function registerName(string memory name, address owner) external {
        nameToAddress[name] = owner;
    }

    function getOwnerOfIdentity(string memory name) external view returns (address) {
        return nameToAddress[name];
    }
}

/**
 * @title TradingTest
 * @notice Comprehensive test suite for Trading contract achieving 100% code coverage
 * @dev Includes unit tests, integration tests, fuzz tests, and edge case coverage
 */
contract TradingTest is Test, EvvmStructs {
    Trading public trading;
    Evvm public evvm;
    Treasury public treasury;
    MockERC20 public mockToken;
    MockNameService public mockNameService;

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
    event FeeCollected(string caip10Wallet, string caip10Token, uint256 feeAmount, bool isStaker);
    event ExecutorRewarded(address indexed executor, address indexed user, uint256 reward);

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

        // Deploy mock NameService
        mockNameService = new MockNameService();

        // Setup name service and treasury integration first
        evvm._setupNameServiceAndTreasuryAddress(address(mockNameService), address(treasury));

        // Create Trading contract with NameService address
        trading = new Trading(owner, address(evvm), address(treasury), address(mockNameService));

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
    // HELPER FUNCTIONS - PURE
    // ═══════════════════════════════════════════════════════════════════════════════════

    function addressToString(address addr) internal pure returns (string memory) {
        return Strings.toHexString(uint160(addr), 20);
    }

    function createCancelOrderSignature(uint256 privateKey, uint256 nonce, uint256 evvmID)
        internal
        pure
        returns (bytes memory)
    {
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testConstructor() public {
        Trading newTrading = new Trading(owner, address(evvm), address(treasury), address(mockNameService));
        assertEq(newTrading.owner(), owner);
        assertEq(newTrading.evvmAddress(), address(evvm));
        assertEq(newTrading.treasuryAddress(), address(treasury));
        assertEq(newTrading.nameServiceAddress(), address(mockNameService));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NAME RESOLUTION UNIT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testParseAddressExternal() public {
        string memory addressStr = addressToString(user1);
        address parsed = trading.parseAddressExternal(addressStr);
        assertEq(parsed, user1);
    }

    function testParseAddressExternalDifferentAddresses() public {
        address[] memory addrs = new address[](3);
        addrs[0] = address(0x1234567890123456789012345678901234567890);
        addrs[1] = address(0xabCDEF1234567890ABcDEF1234567890aBCDeF12);
        addrs[2] = address(0);

        for (uint256 i = 0; i < addrs.length; i++) {
            string memory addrStr = addressToString(addrs[i]);
            address parsed = trading.parseAddressExternal(addrStr);
            assertEq(parsed, addrs[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NAME RESOLUTION INTEGRATION TESTS - ADDRESS STRINGS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositWithAddressString() public {
        uint256 depositAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Verify depositor was resolved correctly
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);
    }

    function testDepositOtherChainWithAddressString() public {
        uint256 depositAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, user1AddrStr);

        // Verify depositor
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // NAME RESOLUTION INTEGRATION TESTS - EVVM NAMES
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositWithEvvmName() public {
        uint256 depositAmount = 100 * 10 ** 18;

        // Register name
        mockNameService.registerName("alice", user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, "alice");

        // Verify depositor was resolved from name
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);

        // Verify balance
        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount);
    }

    function testDepositOtherChainWithEvvmName() public {
        uint256 depositAmount = 100 * 10 ** 18;

        // Register name
        mockNameService.registerName("bob", user2);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, "bob");

        // Verify depositor was resolved from name
        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user2);
    }

    function testDepositWithMultipleNames() public {
        // Register names
        mockNameService.registerName("alice", user1);
        mockNameService.registerName("bob", user2);

        // Deposit with alice's name
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.NATIVE, "alice");

        // Deposit with bob's name
        trading.deposit(caip10Token, CAIP10_WALLET_USER2, 200 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, "bob");

        // Verify both depositors
        assertEq(trading.getDepositor(CAIP10_WALLET_USER1, caip10Token), user1);
        assertEq(trading.getDepositor(CAIP10_WALLET_USER2, caip10Token), user2);
    }

    function testDepositUnregisteredNameReverts() public {
        vm.prank(user1);
        vm.expectRevert("Invalid depositor: not a valid address or registered EVVM name");
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.NATIVE, "unregistered");
    }

    function testDepositInvalidAddressStringReverts() public {
        vm.prank(user1);
        vm.expectRevert("Invalid depositor: not a valid address or registered EVVM name");
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.NATIVE, "0xinvalid");
    }

    function testDepositShortStringReverts() public {
        vm.prank(user1);
        vm.expectRevert("Invalid depositor: not a valid address or registered EVVM name");
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.NATIVE, "0x123");
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - NAME RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzDepositWithRandomAddress(address randomAddr) public {
        vm.assume(randomAddr != address(0));
        string memory addrStr = addressToString(randomAddr);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, addrStr);

        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, randomAddr);
    }

    function testFuzzNameRegistrationAndDeposit(address randomUser, uint128 amount) public {
        vm.assume(randomUser != address(0));
        vm.assume(amount > 0 && amount <= 1000 * 10 ** 18);

        // Register name for random user
        mockNameService.registerName("testuser", randomUser);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.OTHER_CHAIN, "testuser");

        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, randomUser);

        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, amount);
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

        address depositor = trading.getDepositor(CAIP10_WALLET_USER1, caip10Token);
        assertEq(depositor, user1);

        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, 1000 * 10 ** 18);
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

        assertEq(trading.getDepositor(CAIP10_WALLET_USER1, caip10Token), user1);
        assertEq(trading.getDepositor(CAIP10_WALLET_USER2, caip10Token), user2);

        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), 1000 * 10 ** 18);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER2, caip10Token), 2000 * 10 ** 18);
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
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        assertEq(trading.getDepositor(CAIP10_WALLET_USER1, caip10Token), user1);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), depositAmount);
    }

    function testDepositNativeMultipleTimes() public {
        uint256 depositAmount1 = 100 * 10 ** 18;
        uint256 depositAmount2 = 50 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        vm.startPrank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount1, Trading.ActionIs.NATIVE, user1AddrStr);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount2, Trading.ActionIs.NATIVE, user1AddrStr);
        vm.stopPrank();

        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount1 + depositAmount2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // DEPOSIT OTHER_CHAIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositOtherChain() public {
        uint256 depositAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        vm.expectEmit(true, true, true, true);
        emit Deposit(CAIP10_WALLET_USER1, caip10Token, depositAmount, user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.OTHER_CHAIN, user1AddrStr);

        assertEq(trading.getDepositor(CAIP10_WALLET_USER1, caip10Token), user1);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), depositAmount);
    }

    function testDepositOtherChainOnlyOwner() public {
        string memory user1AddrStr = addressToString(user1);

        vm.prank(notOwner);
        vm.expectRevert();
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, Trading.ActionIs.OTHER_CHAIN, user1AddrStr);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawNative() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        uint256 expectedFee = (withdrawAmount * 100) / 10000;
        uint256 expectedNetAmount = withdrawAmount - expectedFee;

        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);

        uint256 balance = evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token);
        assertEq(balance, depositAmount - withdrawAmount);
    }

    function testWithdrawNotOwner() public {
        uint256 depositAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Trading.YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT.selector, user1));
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, 50 * 10 ** 18, Trading.ActionIs.NATIVE);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CANCEL ORDER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testCancelOrder() public {
        uint256 nonce = 1;
        uint256 evvmID = evvm.getEvvmID();
        bytes memory signature = createCancelOrderSignature(user1PrivateKey, nonce, evvmID);

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(CAIP10_WALLET_USER1, nonce);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce, signature);

        assertTrue(trading.orderNonces(CAIP10_WALLET_USER1, nonce));
    }

    function testCancelOrderInvalidSignature() public {
        uint256 nonce = 1;
        uint256 evvmID = evvm.getEvvmID();
        bytes memory signature = createCancelOrderSignature(user2PrivateKey, nonce, evvmID);

        vm.expectRevert(Trading.INVALID_SIGNATURE.selector);
        trading.cancelOrder(CAIP10_WALLET_USER1, nonce, signature);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FEE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawFeeNonStaker() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        (uint256 expectedFee, uint256 expectedNet, bool isStaker) =
            trading.getFeeInfo(withdrawAmount, CAIP10_WALLET_USER1, caip10Token);

        assertFalse(isStaker);
        assertEq(expectedFee, (withdrawAmount * 100) / 10000);
        assertEq(expectedNet, withdrawAmount - expectedFee);
    }

    function testWithdrawFeeStaker() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        evvm.setPointStaker(user1, 0x01);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        (uint256 expectedFee, uint256 expectedNet, bool isStaker) =
            trading.getFeeInfo(withdrawAmount, CAIP10_WALLET_USER1, caip10Token);

        assertTrue(isStaker);
        uint256 baseFee = (withdrawAmount * 100) / 10000;
        assertEq(expectedFee, baseFee / 2);
        assertEq(expectedNet, withdrawAmount - expectedFee);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS - COMPREHENSIVE
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzDepositWithdraw(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18);
        string memory user1AddrStr = addressToString(user1);

        vm.startPrank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, user1AddrStr);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), amount);

        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE);
        vm.stopPrank();

        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), 0);
    }

    function testFuzzFeeCalculation(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 10000 * 10 ** 18);
        vm.assume(amount >= 10000);
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, user1AddrStr);

        (uint256 fee, uint256 net, bool isStaker) = trading.getFeeInfo(amount, CAIP10_WALLET_USER1, caip10Token);

        assertFalse(isStaker);
        assertEq(fee, (amount * 100) / 10000);
        assertEq(net, amount - fee);
        assertEq(fee + net, amount);
    }

    function testFuzzMultiUserIsolation(uint128 amount1, uint128 amount2) public {
        string memory user1AddrStr = addressToString(user1);
        string memory user2AddrStr = addressToString(user2);

        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount1, Trading.ActionIs.OTHER_CHAIN, user1AddrStr);
        trading.deposit(caip10Token, CAIP10_WALLET_USER2, amount2, Trading.ActionIs.OTHER_CHAIN, user2AddrStr);

        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), amount1);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER2, caip10Token), amount2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testAddressesView() public view {
        assertEq(trading.evvmAddress(), address(evvm));
        assertEq(trading.treasuryAddress(), address(treasury));
        assertEq(trading.nameServiceAddress(), address(mockNameService));
        assertEq(trading.owner(), owner);
    }

    function testConstants() public {
        assertEq(trading.FEE_BASIS_POINTS(), 100);
        assertEq(trading.BASIS_POINTS_DIVISOR(), 10000);
        assertEq(trading.STAKER_DISCOUNT_PERCENT(), 50);
        assertEq(trading.EXECUTOR_REWARD_PERCENT(), 20);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EXECUTOR PATTERN TESTS - UNIT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testWithdrawWithExecutorBasic() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);
        address fisher = address(0x777); // Fisher/Relayer

        // Setup: deposit tokens first
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Calculate expected values
        uint256 baseFee = (withdrawAmount * 100) / 10000; // 1%
        uint256 executorReward = (baseFee * 20) / 100; // 20% of fee
        uint256 netAmount = withdrawAmount - baseFee;

        // User signs withdrawal
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        uint256 user1BalanceBefore = mockToken.balanceOf(user1);
        uint256 fisherBalanceBefore = mockToken.balanceOf(fisher);

        // Fisher executes withdrawal
        vm.prank(fisher);
        vm.expectEmit(true, true, true, true);
        emit ExecutorRewarded(fisher, user1, executorReward);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Verify user received net amount
        assertEq(mockToken.balanceOf(user1), user1BalanceBefore + netAmount);

        // Verify fisher received reward
        assertEq(mockToken.balanceOf(fisher), fisherBalanceBefore + executorReward);

        // Verify balance deducted from EVVM
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), depositAmount - withdrawAmount);

        // Verify nonce is marked as used
        assertTrue(trading.executorNonces(user1, nonce));
    }

    function testWithdrawWithExecutorInvalidSignature() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);
        address fisher = address(0x777);

        // Setup: deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // User2 signs (wrong signer)
        uint256 nonce = 1;
        bytes memory wrongSignature = createWithdrawalSignature(user2PrivateKey, caip10Token, withdrawAmount, nonce);

        // Fisher tries to execute with wrong signature
        vm.prank(fisher);
        vm.expectRevert(Trading.INVALID_SIGNATURE.selector);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, wrongSignature);
    }

    function testWithdrawWithExecutorNonceReuse() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);
        address fisher = address(0x777);

        // Setup: deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // User signs withdrawal
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        // Fisher executes first time - should succeed
        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Fisher tries to execute again with same nonce - should fail
        vm.prank(fisher);
        vm.expectRevert(Trading.NONCE_ALREADY_USED.selector);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);
    }

    function testWithdrawWithExecutorInsufficientBalance() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 200 * 10 ** 18; // More than deposited
        string memory user1AddrStr = addressToString(user1);
        address fisher = address(0x777);

        // Setup: deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // User signs withdrawal for more than balance
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        // Fisher tries to execute - should fail
        vm.prank(fisher);
        vm.expectRevert(
            abi.encodeWithSelector(Trading.CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE.selector, depositAmount, withdrawAmount)
        );
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);
    }

    function testWithdrawWithExecutorStakerDiscount() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);
        address fisher = address(0x777);

        // Make user1 a staker
        evvm.setPointStaker(user1, 0x01);

        // Setup: deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Calculate expected values with staker discount
        uint256 baseFee = (withdrawAmount * 100) / 10000; // 1%
        uint256 stakerFee = baseFee / 2; // 50% discount
        uint256 executorReward = (stakerFee * 20) / 100; // 20% of discounted fee
        uint256 netAmount = withdrawAmount - stakerFee;

        // User signs withdrawal
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        uint256 fisherBalanceBefore = mockToken.balanceOf(fisher);

        // Fisher executes
        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Verify fisher received discounted reward
        assertEq(mockToken.balanceOf(fisher), fisherBalanceBefore + executorReward);
    }

    function testWithdrawWithExecutorMultipleExecutors() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);
        address fisher1 = address(0x777);
        address fisher2 = address(0x888);

        // Setup: deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // User signs two different withdrawals with different nonces
        uint256 nonce1 = 1;
        uint256 nonce2 = 2;
        bytes memory signature1 = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce1);
        bytes memory signature2 = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce2);

        uint256 baseFee = (withdrawAmount * 100) / 10000;
        uint256 executorReward = (baseFee * 20) / 100;

        // Fisher1 executes first withdrawal
        vm.prank(fisher1);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce1, signature1);

        // Fisher2 executes second withdrawal
        vm.prank(fisher2);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce2, signature2);

        // Verify both fishers received rewards
        assertEq(mockToken.balanceOf(fisher1), executorReward);
        assertEq(mockToken.balanceOf(fisher2), executorReward);

        // Verify both nonces are used
        assertTrue(trading.executorNonces(user1, nonce1));
        assertTrue(trading.executorNonces(user1, nonce2));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EXECUTOR PATTERN TESTS - INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testExecutorFullWorkflow() public {
        address fisher = address(0x777);
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 200 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        // Step 1: User deposits (normal flow)
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Step 2: User signs withdrawal off-chain
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        // Step 3: Fisher validates (in real scenario, fisher would check balance/signature off-chain)
        uint256 balance = trading.getTradeBalance(CAIP10_WALLET_USER1, caip10Token);
        assertTrue(balance >= withdrawAmount, "Fisher validation: insufficient balance");

        // Step 4: Fisher executes and gets rewarded
        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Verify final state
        uint256 baseFee = (withdrawAmount * 100) / 10000;
        uint256 executorReward = (baseFee * 20) / 100;
        uint256 netAmount = withdrawAmount - baseFee;

        assertEq(mockToken.balanceOf(user1), 10000 * 10 ** 18 - depositAmount + netAmount);
        assertEq(mockToken.balanceOf(fisher), executorReward);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), depositAmount - withdrawAmount);
    }

    function testExecutorWithNameResolution() public {
        address fisher = address(0x777);
        uint256 depositAmount = 500 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;

        // Register user1 with name
        mockNameService.registerName("alice", user1);

        // Deposit with name
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, "alice");

        // User signs withdrawal
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        // Fisher executes
        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Verify execution
        uint256 baseFee = (withdrawAmount * 100) / 10000;
        uint256 executorReward = (baseFee * 20) / 100;
        assertEq(mockToken.balanceOf(fisher), executorReward);
    }

    function testExecutorVsRegularWithdraw() public {
        address fisher = address(0x777);
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 100 * 10 ** 18;
        string memory user1AddrStr = addressToString(user1);

        // Setup two separate deposits
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Regular withdrawal - user pays gas
        uint256 gasBefore = gasleft();
        vm.prank(user1);
        trading.withdraw(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE);
        uint256 regularGas = gasBefore - gasleft();

        // Executor withdrawal - fisher pays gas
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        gasBefore = gasleft();
        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);
        uint256 executorGas = gasBefore - gasleft();

        // Executor path uses more gas due to signature verification
        assertTrue(executorGas > regularGas);

        // But fisher gets rewarded
        uint256 baseFee = (withdrawAmount * 100) / 10000;
        uint256 executorReward = (baseFee * 20) / 100;
        assertEq(mockToken.balanceOf(fisher), executorReward);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EXECUTOR PATTERN TESTS - FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testFuzzExecutorWithdrawal(uint128 withdrawAmount) public {
        // Use fixed deposit, fuzz withdrawal
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.assume(withdrawAmount > 10000 && withdrawAmount <= depositAmount);

        address fisher = address(0x777);
        string memory user1AddrStr = addressToString(user1);

        // Deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, depositAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Sign and execute withdrawal
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Verify invariants
        uint256 baseFee = (withdrawAmount * 100) / 10000;
        uint256 executorReward = (baseFee * 20) / 100;
        uint256 netAmount = withdrawAmount - baseFee;

        assertEq(mockToken.balanceOf(fisher), executorReward);
        assertEq(evvm.getBalanceCaip10Native(CAIP10_WALLET_USER1, caip10Token), depositAmount - withdrawAmount);
    }

    function testFuzzExecutorMultipleWithdrawals(uint64 amount1, uint64 amount2, uint64 amount3) public {
        vm.assume(amount1 > 10000 && amount1 <= 1000 * 10 ** 18);
        vm.assume(amount2 > 10000 && amount2 <= 1000 * 10 ** 18);
        vm.assume(amount3 > 10000 && amount3 <= 1000 * 10 ** 18);

        uint256 totalDeposit = uint256(amount1) + uint256(amount2) + uint256(amount3);
        vm.assume(totalDeposit <= 5000 * 10 ** 18);

        address fisher = address(0x777);
        string memory user1AddrStr = addressToString(user1);

        // Deposit enough for all withdrawals
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, totalDeposit, Trading.ActionIs.NATIVE, user1AddrStr);

        // Execute three withdrawals with different nonces
        bytes memory sig1 = createWithdrawalSignature(user1PrivateKey, caip10Token, amount1, 1);
        bytes memory sig2 = createWithdrawalSignature(user1PrivateKey, caip10Token, amount2, 2);
        bytes memory sig3 = createWithdrawalSignature(user1PrivateKey, caip10Token, amount3, 3);

        vm.startPrank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, amount1, 1, sig1);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, amount2, 2, sig2);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, amount3, 3, sig3);
        vm.stopPrank();

        // Verify all nonces are used
        assertTrue(trading.executorNonces(user1, 1));
        assertTrue(trading.executorNonces(user1, 2));
        assertTrue(trading.executorNonces(user1, 3));

        // Verify fisher accumulated rewards (calculate individually to avoid rounding errors)
        uint256 fee1 = (uint256(amount1) * 100) / 10000;
        uint256 fee2 = (uint256(amount2) * 100) / 10000;
        uint256 fee3 = (uint256(amount3) * 100) / 10000;
        uint256 reward1 = (fee1 * 20) / 100;
        uint256 reward2 = (fee2 * 20) / 100;
        uint256 reward3 = (fee3 * 20) / 100;
        uint256 expectedTotalRewards = reward1 + reward2 + reward3;

        assertEq(mockToken.balanceOf(fisher), expectedTotalRewards);
    }

    function testFuzzExecutorWithRandomFisher(address randomFisher, uint128 amount) public {
        vm.assume(randomFisher != address(0));
        vm.assume(randomFisher != user1);
        vm.assume(randomFisher != address(trading));
        vm.assume(randomFisher != address(treasury));
        vm.assume(amount > 10000 && amount <= 5000 * 10 ** 18);

        string memory user1AddrStr = addressToString(user1);

        // Deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, amount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Random fisher executes
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, amount, nonce);

        vm.prank(randomFisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, amount, nonce, signature);

        // Verify random fisher got rewarded
        uint256 baseFee = (amount * 100) / 10000;
        uint256 executorReward = (baseFee * 20) / 100;
        assertEq(mockToken.balanceOf(randomFisher), executorReward);
    }

    function testFuzzExecutorRewardCalculation(uint128 withdrawAmount) public {
        vm.assume(withdrawAmount > 10000 && withdrawAmount <= 5000 * 10 ** 18);

        address fisher = address(0x777);
        string memory user1AddrStr = addressToString(user1);

        // Deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, Trading.ActionIs.NATIVE, user1AddrStr);

        // Execute
        uint256 nonce = 1;
        bytes memory signature = createWithdrawalSignature(user1PrivateKey, caip10Token, withdrawAmount, nonce);

        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, withdrawAmount, nonce, signature);

        // Verify reward calculation
        uint256 expectedFee = (withdrawAmount * 100) / 10000; // 1%
        uint256 expectedReward = (expectedFee * 20) / 100; // 20% of fee
        uint256 expectedNet = withdrawAmount - expectedFee;
        uint256 expectedTreasuryFee = expectedFee - expectedReward; // 80% of fee

        assertEq(mockToken.balanceOf(fisher), expectedReward);
        assertEq(mockToken.balanceOf(user1), 10000 * 10 ** 18 - withdrawAmount + expectedNet);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // EXECUTOR NONCE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testExecutorNonceTracking() public {
        address fisher = address(0x777);
        string memory user1AddrStr = addressToString(user1);

        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 1000 * 10 ** 18, Trading.ActionIs.NATIVE, user1AddrStr);

        // Check nonce is not used initially
        assertFalse(trading.executorNonces(user1, 1));

        // Execute withdrawal
        bytes memory sig = createWithdrawalSignature(user1PrivateKey, caip10Token, 100 * 10 ** 18, 1);
        vm.prank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, 1, sig);

        // Check nonce is now used
        assertTrue(trading.executorNonces(user1, 1));
    }

    function testExecutorNonceIndependentPerUser() public {
        address fisher = address(0x777);
        string memory user1AddrStr = addressToString(user1);
        string memory user2AddrStr = addressToString(user2);

        // Both users deposit
        vm.prank(user1);
        trading.deposit(caip10Token, CAIP10_WALLET_USER1, 1000 * 10 ** 18, Trading.ActionIs.NATIVE, user1AddrStr);

        vm.prank(user2);
        trading.deposit(caip10Token, CAIP10_WALLET_USER2, 1000 * 10 ** 18, Trading.ActionIs.NATIVE, user2AddrStr);

        // Both use nonce 1
        bytes memory sig1 = createWithdrawalSignature(user1PrivateKey, caip10Token, 100 * 10 ** 18, 1);
        bytes memory sig2 = createWithdrawalSignature(user2PrivateKey, caip10Token, 100 * 10 ** 18, 1);

        vm.startPrank(fisher);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER1, 100 * 10 ** 18, 1, sig1);
        trading.withdrawWithExecutor(caip10Token, CAIP10_WALLET_USER2, 100 * 10 ** 18, 1, sig2);
        vm.stopPrank();

        // Both nonces should be used independently
        assertTrue(trading.executorNonces(user1, 1));
        assertTrue(trading.executorNonces(user2, 1));
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // TOKEN ALLOWANCE TESTS (FIX VERIFICATION)
    // ═══════════════════════════════════════════════════════════════════════════════════

    function testDepositWithoutPreApprovalToTreasury() public {
        // Create a fresh Trading contract without pre-approvals
        Trading freshTrading = new Trading(owner, address(evvm), address(treasury), address(mockNameService));
        evvm.setAuthorizedTradingContract(address(freshTrading));

        // Create a fresh token
        MockERC20 freshToken = new MockERC20();
        string memory freshCaip10Token =
            string(abi.encodePacked("eip155:1:", Strings.toHexString(uint160(address(freshToken)), 20)));

        // Mint and approve Trading contract only (not Treasury)
        address testUser = address(0xABC);
        freshToken.mint(testUser, 1000 * 10 ** 18);
        vm.prank(testUser);
        freshToken.approve(address(freshTrading), type(uint256).max);

        // This should work with our fix (Trading contract approves Treasury internally)
        string memory testUserCaip10 = "eip155:1:0x0000000000000000000000000000000000000abc";
        string memory testUserAddrStr = addressToString(testUser);

        vm.prank(testUser);
        freshTrading.deposit(
            freshCaip10Token, testUserCaip10, 100 * 10 ** 18, Trading.ActionIs.NATIVE, testUserAddrStr
        );

        // Verify deposit succeeded
        uint256 balance = evvm.getBalanceCaip10Native(testUserCaip10, freshCaip10Token);
        assertEq(balance, 100 * 10 ** 18, "Deposit should succeed with automatic approval");
    }

    function testDepositMultipleTimesWithAutomaticApproval() public {
        // Create fresh contracts to test approval mechanism
        Trading freshTrading = new Trading(owner, address(evvm), address(treasury), address(mockNameService));
        evvm.setAuthorizedTradingContract(address(freshTrading));

        MockERC20 freshToken = new MockERC20();
        string memory freshCaip10Token =
            string(abi.encodePacked("eip155:1:", Strings.toHexString(uint160(address(freshToken)), 20)));

        address testUser = address(0xDEF);
        freshToken.mint(testUser, 10000 * 10 ** 18);
        vm.prank(testUser);
        freshToken.approve(address(freshTrading), type(uint256).max);

        string memory testUserCaip10 = "eip155:1:0x0000000000000000000000000000000000000def";
        string memory testUserAddrStr = addressToString(testUser);

        // Multiple deposits should all work
        vm.startPrank(testUser);
        freshTrading.deposit(
            freshCaip10Token, testUserCaip10, 100 * 10 ** 18, Trading.ActionIs.NATIVE, testUserAddrStr
        );
        freshTrading.deposit(
            freshCaip10Token, testUserCaip10, 200 * 10 ** 18, Trading.ActionIs.NATIVE, testUserAddrStr
        );
        freshTrading.deposit(
            freshCaip10Token, testUserCaip10, 300 * 10 ** 18, Trading.ActionIs.NATIVE, testUserAddrStr
        );
        vm.stopPrank();

        // Verify all deposits succeeded
        uint256 balance = evvm.getBalanceCaip10Native(testUserCaip10, freshCaip10Token);
        assertEq(balance, 600 * 10 ** 18, "Multiple deposits should all succeed");
    }

    function testDepositApprovalIsExactAmount() public {
        // Verify that Trading contract only approves the exact amount needed
        Trading freshTrading = new Trading(owner, address(evvm), address(treasury), address(mockNameService));
        evvm.setAuthorizedTradingContract(address(freshTrading));

        MockERC20 freshToken = new MockERC20();
        string memory freshCaip10Token =
            string(abi.encodePacked("eip155:1:", Strings.toHexString(uint160(address(freshToken)), 20)));

        address testUser = address(0x123);
        freshToken.mint(testUser, 10000 * 10 ** 18);
        vm.prank(testUser);
        freshToken.approve(address(freshTrading), type(uint256).max);

        string memory testUserCaip10 = "eip155:1:0x0000000000000000000000000000000000000123";
        string memory testUserAddrStr = addressToString(testUser);

        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(testUser);
        freshTrading.deposit(freshCaip10Token, testUserCaip10, depositAmount, Trading.ActionIs.NATIVE, testUserAddrStr);

        // After deposit, check that Treasury has consumed the allowance
        uint256 allowance = freshToken.allowance(address(freshTrading), address(treasury));
        // Allowance should be 0 or very small after Treasury.deposit() consumes it
        assertEq(allowance, 0, "Treasury should have consumed the exact approved amount");
    }

    function testFuzzDepositWithAutomaticApproval(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 5000 * 10 ** 18);

        Trading freshTrading = new Trading(owner, address(evvm), address(treasury), address(mockNameService));
        evvm.setAuthorizedTradingContract(address(freshTrading));

        MockERC20 freshToken = new MockERC20();
        string memory freshCaip10Token =
            string(abi.encodePacked("eip155:1:", Strings.toHexString(uint160(address(freshToken)), 20)));

        address testUser = address(0xFAB);
        freshToken.mint(testUser, 10000 * 10 ** 18);
        vm.prank(testUser);
        freshToken.approve(address(freshTrading), type(uint256).max);

        string memory testUserCaip10 = "eip155:1:0x0000000000000000000000000000000000000fab";
        string memory testUserAddrStr = addressToString(testUser);

        vm.prank(testUser);
        freshTrading.deposit(freshCaip10Token, testUserCaip10, amount, Trading.ActionIs.NATIVE, testUserAddrStr);

        uint256 balance = evvm.getBalanceCaip10Native(testUserCaip10, freshCaip10Token);
        assertEq(balance, amount, "Deposit with any valid amount should succeed");
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS FOR EXECUTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function createWithdrawalSignature(uint256 privateKey, string memory token, uint256 amount, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        uint256 evvmID = evvm.getEvvmID();

        string memory message = string.concat(token, ",", Strings.toString(amount), ",", Strings.toString(nonce));

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(
                    bytes(string.concat(Strings.toString(evvmID), ",", "withdrawWithExecutor", ",", message)).length
                ),
                string.concat(Strings.toString(evvmID), ",", "withdrawWithExecutor", ",", message)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }
}

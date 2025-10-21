// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";
import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {EvvmStructs} from "@EVVM/testnet/contracts/evvm/lib/EvvmStructs.sol";
import {Staking} from "@EVVM/testnet/contracts/staking/Staking.sol";
import {NameService} from "@EVVM/testnet/contracts/nameService/NameService.sol";
import {Caip10Utils} from "@EVVM/testnet/lib/Caip10Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
}

contract TreasuryCaip10Test is Test {
    Treasury treasury;
    Evvm evvm;
    Staking staking;
    NameService nameService;
    MockERC20 token;

    address admin = address(1);
    address user1 = address(2);
    address user2 = address(3);

    function setUp() public {
        EvvmStructs.EvvmMetadata memory metadata = EvvmStructs.EvvmMetadata({
            EvvmName: "TestEVVM",
            EvvmID: 1,
            principalTokenName: "TestToken",
            principalTokenSymbol: "TEST",
            principalTokenAddress: address(0xdead),
            totalSupply: 1000000 * 10 ** 18,
            eraTokens: 500000 * 10 ** 18,
            reward: 5 * 10 ** 18
        });

        staking = new Staking(admin, admin);
        evvm = new Evvm(admin, address(staking), metadata);
        nameService = new NameService(address(evvm), admin);
        treasury = new Treasury(address(evvm));

        vm.prank(admin);
        evvm._setupNameServiceAndTreasuryAddress(address(nameService), address(treasury));

        token = new MockERC20();
        token.mint(user1, 1000 * 10 ** 18);
    }

    function testDepositCaip10ETH() public {
        string memory caip10Token = "eip155:1:0x0000000000000000000000000000000000000000";
        uint256 depositAmount = 1 ether;

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        treasury.depositCaip10{value: depositAmount}(caip10Token, depositAmount);

        assertEq(evvm.getBalance(user1, address(0)), depositAmount);
    }

    function testDepositCaip10ERC20() public {
        string memory caip10Token = Caip10Utils.toCaip10("eip155", "1", address(token));
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user1);
        token.approve(address(treasury), depositAmount);
        treasury.depositCaip10(caip10Token, depositAmount);
        vm.stopPrank();

        assertEq(evvm.getBalance(user1, address(token)), depositAmount);
    }

    function testDepositCaip10Arbitrum() public {
        string memory caip10Token = Caip10Utils.toCaip10("eip155", "42161", address(token));
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user1);
        token.approve(address(treasury), depositAmount);
        treasury.depositCaip10(caip10Token, depositAmount);
        vm.stopPrank();

        assertEq(evvm.getBalance(user1, address(token)), depositAmount);
    }

    function testWithdrawCaip10ERC20() public {
        string memory caip10Token = Caip10Utils.toCaip10("eip155", "1", address(token));
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        vm.startPrank(user1);
        token.approve(address(treasury), depositAmount);
        treasury.depositCaip10(caip10Token, depositAmount);

        treasury.withdrawCaip10(caip10Token, withdrawAmount);
        vm.stopPrank();

        assertEq(evvm.getBalance(user1, address(token)), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user1), 1000 * 10 ** 18 - depositAmount + withdrawAmount);
    }

    function testWithdrawCaip10ETH() public {
        string memory caip10Token = "eip155:1:0x0000000000000000000000000000000000000000";
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;

        vm.deal(user1, depositAmount);
        vm.startPrank(user1);
        treasury.depositCaip10{value: depositAmount}(caip10Token, depositAmount);

        treasury.withdrawCaip10(caip10Token, withdrawAmount);
        vm.stopPrank();

        assertEq(evvm.getBalance(user1, address(0)), depositAmount - withdrawAmount);
        assertEq(user1.balance, withdrawAmount);
    }


    function testFuzzDepositWithdrawCaip10(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 * 10 ** 18);

        string memory caip10Token = Caip10Utils.toCaip10("eip155", "1", address(token));

        vm.startPrank(user1);
        token.approve(address(treasury), amount);
        treasury.depositCaip10(caip10Token, amount);

        assertEq(evvm.getBalance(user1, address(token)), amount);

        treasury.withdrawCaip10(caip10Token, amount);
        assertEq(evvm.getBalance(user1, address(token)), 0);
        vm.stopPrank();
    }
}

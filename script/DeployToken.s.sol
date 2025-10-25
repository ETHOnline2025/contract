// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {MockToken} from "../src/contracts/token/MockToken.sol";

contract DeployToken is Script {
    MockToken public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy MockToken
        token = new MockToken();

        vm.stopBroadcast();

        console2.log("MockToken deployed at:", address(token));
        console2.log("Token Name:", token.name());
        console2.log("Token Symbol:", token.symbol());
        console2.log("Initial Supply:", token.totalSupply());
        console2.log("Deployer Balance:", token.balanceOf(msg.sender));
    }
}

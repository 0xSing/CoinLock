// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/test_contracts/FinTestToken.sol";

contract FinTestTokenScript is Script {
    function run() external {
        vm.startBroadcast();

        new FinTestToken(10000);

        vm.stopBroadcast();
    }
}

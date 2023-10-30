// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/FinLockV2.sol";

contract FinLock02Script is Script {
    function run() external {
        vm.startBroadcast();

        new FinLock02();

        vm.stopBroadcast();
    }
}

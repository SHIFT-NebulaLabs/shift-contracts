// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/alpha/ShiftEarlyAccess.sol";

contract DeployShiftEarlyAccess is Script {
    function run() external {
        vm.startBroadcast();

        new ShiftEarlyAccess();

        vm.stopBroadcast();
    }
}
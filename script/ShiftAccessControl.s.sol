// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftAccessControl.sol";

contract DeployShiftAccessControl is Script {
    function run() external {
        vm.startBroadcast();

        address admin = vm.envAddress("ADMIN_EOA");

        new ShiftAccessControl(admin);

        vm.stopBroadcast();
    }
}

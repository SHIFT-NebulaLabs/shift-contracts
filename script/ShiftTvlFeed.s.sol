// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftTvlFeed.sol";

contract DeployShiftTvlFeed is Script {
    function run() external {
        vm.startBroadcast();

        address accessControl = vm.envAddress("ACCESS_CONTROL_CONTRACT");

        new ShiftTvlFeed(accessControl);

        vm.stopBroadcast();
    }
}

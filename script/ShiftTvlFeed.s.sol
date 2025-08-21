// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftTvlFeed.sol";

contract DeployShiftTvlFeed is Script {
    function run() external {

        address accessControl = vm.envAddress("ACCESS_CONTROL_CONTRACT");

        vm.startBroadcast();

        new ShiftTvlFeed(accessControl);

        vm.stopBroadcast();
    }
}

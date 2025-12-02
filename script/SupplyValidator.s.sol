// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/add-on/SupplyValidator.sol";

contract DeploySupplyValidator is Script {
    function run() external {
        vm.startBroadcast();

        address supplyValidator = address(new SupplyValidator());

        vm.stopBroadcast();

        console.log("SupplyValidator deployed at:", supplyValidator);
    }
}

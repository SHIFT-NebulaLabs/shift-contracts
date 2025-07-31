// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftVault.sol";

contract DeployShiftVault is Script {
    function run() external {
        vm.startBroadcast();

        address accessControl = vm.envAddress("ACCESS_CONTROL_CONTRACT");
        address tokenContract = vm.envAddress("TOKEN_CONTRACT");
        address tvlFeed = vm.envAddress("TVL_FEED_CONTRACT");
        address feeCollector = vm.envAddress("FEE_COLLECTOR_EOA");
        string memory shareName = vm.envString("LP_TOKEN_NAME");
        string memory shareSymbol = vm.envString("LP_TOKEN_SYMBOL");
        uint256 minTokenDeposit = vm.envUint("MIN_TOKEN_DEPOSIT");
        uint256 maxTvlAllowance = vm.envUint("MAX_TVL_ALLOWANCE");
        uint32 withdrawalDelay = uint32(vm.envUint("WITHDRAWAL_DELAY"));

        new ShiftVault(
            accessControl, tokenContract, tvlFeed, feeCollector, shareName, shareSymbol, minTokenDeposit, maxTvlAllowance, withdrawalDelay
        );

        vm.stopBroadcast();
    }
}

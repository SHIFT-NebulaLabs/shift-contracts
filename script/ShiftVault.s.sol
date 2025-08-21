// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftVault.sol";
import "../src/utils/Structs.sol";

contract DeployShiftVault is Script {
    function run() external {
        ShiftVaultArgs memory args = ShiftVaultArgs({
            tokenContract: vm.envAddress("TOKEN_CONTRACT"),
            tvlFeedContract: vm.envAddress("TVL_FEED_CONTRACT"),
            shareName: vm.envString("LP_TOKEN_NAME"),
            shareSymbol: vm.envString("LP_TOKEN_SYMBOL"),
            managerArgs: ShiftManagerArgs({
                accessControlContract: vm.envAddress("ACCESS_CONTROL_CONTRACT"),
                feeCollector: vm.envAddress("FEE_COLLECTOR_EOA"),
                executor: vm.envAddress("EXECUTOR_EOA"),
                minDeposit: vm.envUint("MIN_TOKEN_DEPOSIT"),
                maxTvl: vm.envUint("MAX_TVL_ALLOWANCE"),
                timelock: uint32(vm.envUint("WITHDRAWAL_TIMELOCK")),
                freshness: uint16(vm.envUint("FRESHNESS_DURATION")),
                requestValidity: uint16(vm.envUint("REQUEST_VALIDITY"))
            })
        });

        vm.startBroadcast();

        new ShiftVault(args);

        vm.stopBroadcast();
    }
}

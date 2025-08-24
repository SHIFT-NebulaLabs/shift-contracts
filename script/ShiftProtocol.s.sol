// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftVault.sol";
import "../src/ShiftAccessControl.sol";
import "../src/ShiftTvlFeed.sol";
import "../src/mocks/TestToken.sol";
import "../src/utils/Structs.sol";

contract DeployShiftProtocol_Testnet is Script {
    function run() external {
        uint256 initialSupply = 1_000_000 * 1e6;

        vm.startBroadcast();

        address tokenContract = address(new TestToken(initialSupply));
        address accessControl = address(new ShiftAccessControl(vm.envAddress("ADMIN_EOA")));
        address tvlFeed = address(new ShiftTvlFeed(accessControl));

        ShiftVaultArgs memory args = ShiftVaultArgs({
            tokenContract: tokenContract,
            tvlFeedContract: tvlFeed,
            shareName: vm.envString("LP_TOKEN_NAME"),
            shareSymbol: vm.envString("LP_TOKEN_SYMBOL"),
            managerArgs: ShiftManagerArgs({
                accessControlContract: accessControl,
                feeCollector: vm.envAddress("FEE_COLLECTOR_EOA"),
                executor: vm.envAddress("EXECUTOR_EOA"),
                minDeposit: vm.envUint("MIN_TOKEN_DEPOSIT"),
                maxTvl: vm.envUint("MAX_TVL_ALLOWANCE"),
                timelock: uint32(vm.envUint("WITHDRAWAL_TIMELOCK")),
                freshness: uint16(vm.envUint("FRESHNESS_DURATION")),
                requestValidity: uint16(vm.envUint("REQUEST_VALIDITY"))
            })
        });

        new ShiftVault(args);

        // IMPORTANT: The ShiftAccessControl and ShiftTvlFeed contracts must be deployed before the ShiftVault contract.
        // This is because the ShiftVault constructor requires the addresses of these contracts.
        // IMPORTANT: ShiftTvlFeed must be initialized with the Vault address after deployment. <initialize()>
        // IMPORTANT: ShiftVault must set performance and maintenance fees after deployment. Then unpaused <updateMaintenanceFee()> <updatePerformanceFee()> <releasePaused()>
        // IMPORTANT: Oracle & Executor must grant roles after deployment.

        vm.stopBroadcast();
    }
}

contract DeployShiftProtocol_Mainnet is Script {
    function run() external {
        vm.startBroadcast();

        address accessControl = address(new ShiftAccessControl(vm.envAddress("ADMIN_EOA")));
        address tvlFeed = address(new ShiftTvlFeed(accessControl));

        ShiftVaultArgs memory args = ShiftVaultArgs({
            tokenContract: vm.envAddress("TOKEN_CONTRACT"),
            tvlFeedContract: tvlFeed,
            shareName: vm.envString("LP_TOKEN_NAME"),
            shareSymbol: vm.envString("LP_TOKEN_SYMBOL"),
            managerArgs: ShiftManagerArgs({
                accessControlContract: accessControl,
                feeCollector: vm.envAddress("FEE_COLLECTOR_EOA"),
                executor: vm.envAddress("EXECUTOR_EOA"),
                minDeposit: vm.envUint("MIN_TOKEN_DEPOSIT"),
                maxTvl: vm.envUint("MAX_TVL_ALLOWANCE"),
                timelock: uint32(vm.envUint("WITHDRAWAL_TIMELOCK")),
                freshness: uint16(vm.envUint("FRESHNESS_DURATION")),
                requestValidity: uint16(vm.envUint("REQUEST_VALIDITY"))
            })
        });

        new ShiftVault(args);

        // IMPORTANT: The ShiftAccessControl and ShiftTvlFeed contracts must be deployed before the ShiftVault contract.
        // This is because the ShiftVault constructor requires the addresses of these contracts.
        // IMPORTANT: ShiftTvlFeed must be initialized with the Vault address after deployment. <initialize()>
        // IMPORTANT: ShiftVault must set performance and maintenance fees after deployment. Then unpaused <updateMaintenanceFee()> <updatePerformanceFee()> <releasePaused()>
        // IMPORTANT: Oracle & Executor must grant roles after deployment.

        vm.stopBroadcast();
    }
}

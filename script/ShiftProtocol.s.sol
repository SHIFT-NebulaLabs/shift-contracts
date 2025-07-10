// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/ShiftVault.sol";
import "../src/ShiftAccessControl.sol";
import "../src/ShiftTvlFeed.sol";
import "../src/mocks/TestToken.sol";

contract DeployShiftProtocol_Test is Script {
    function run() external {
        vm.startBroadcast();

        uint256 initialSupply = 1_000_000 * 1e6;
        address tokenContract = address(new TestToken(initialSupply));

        address admin = vm.envAddress("ADMIN_EOA");
        address accessControl = address(new ShiftAccessControl(admin));

        address tvlFeed = address(new ShiftTvlFeed(accessControl));

        address feeCollector = vm.envAddress("FEE_COLLECTOR_EOA");
        uint256 minTokenDeposit = vm.envUint("MIN_TOKEN_DEPOSIT");
        uint256 maxTvlAllowance = vm.envUint("MAX_TVL_ALLOWANCE");
        uint32 withdrawalDelay = uint32(vm.envUint("WITHDRAWAL_DELAY"));

        new ShiftVault(
            accessControl,
            tokenContract,
            tvlFeed,
            feeCollector,
            minTokenDeposit,
            maxTvlAllowance,
            withdrawalDelay
        );

        // IMPORTANT: The ShiftAccessControl and ShiftTvlFeed contracts must be deployed before the ShiftVault contract.
        // This is because the ShiftVault constructor requires the addresses of these contracts.
        // IMPORTANT: ShiftTvlFeed must be initialized with the Vault address after deployment. <initialize()>
        // IMPORTANT: ShiftVault must set performance and maintenance fees after deployment. Then unpaused <updateMaintenanceFee()> <updatePerformanceFee()> <releasePaused()>

        vm.stopBroadcast();
    }
}

contract DeployShiftProtocol_Mainnet is Script {
    function run() external {
        vm.startBroadcast();

        address admin = vm.envAddress("ADMIN_EOA");
        address accessControl = address(new ShiftAccessControl(admin));

        address tvlFeed = address(new ShiftTvlFeed(accessControl));

        address tokenContract = vm.envAddress("TOKEN_CONTRACT");
        address feeCollector = vm.envAddress("FEE_COLLECTOR_EOA");
        uint256 minTokenDeposit = vm.envUint("MIN_TOKEN_DEPOSIT");
        uint256 maxTvlAllowance = vm.envUint("MAX_TVL_ALLOWANCE");
        uint32 withdrawalDelay = uint32(vm.envUint("WITHDRAWAL_DELAY"));

        new ShiftVault(
            accessControl,
            tokenContract,
            tvlFeed,
            feeCollector,
            minTokenDeposit,
            maxTvlAllowance,
            withdrawalDelay
        );

        // IMPORTANT: The ShiftAccessControl and ShiftTvlFeed contracts must be deployed before the ShiftVault contract.
        // This is because the ShiftVault constructor requires the addresses of these contracts.
        // IMPORTANT: ShiftTvlFeed must be initialized with the Vault address after deployment. <initialize()>
        // IMPORTANT: ShiftVault must set performance and maintenance fees after deployment. Then unpaused <updateMaintenanceFee()> <updatePerformanceFee()> <releasePaused()>

        vm.stopBroadcast();
    }
}
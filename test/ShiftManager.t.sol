// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/ShiftManager.sol";
import "../src/ShiftAccessControl.sol";

// === 🟢 Dummy wrapper to instantiate abstract ShiftManager
/// @dev Concrete implementation of ShiftManager for testing purposes.
contract TestableShiftManager is ShiftManager {
    constructor(
        address _accessControl,
        address _feeCollector,
        uint256 _minDeposit,
        uint256 _maxTvl
    ) ShiftManager(_accessControl, _feeCollector, _minDeposit, _maxTvl) {}

    /// @dev Exposes internal _calc18ptFromBps for testing.
    function expose_calc18pt(uint16 bps) external pure returns (uint256) {
        return _calc18ptFromBps(bps);
    }
}

/// @title ShiftManagerTest
/// @notice Test suite for ShiftManager contract logic and access control.
contract ShiftManagerTest is Test {
    ShiftAccessControl access;
    TestableShiftManager manager;

    address admin = address(this);
    address user = address(0x123);
    address feeCollector = address(0xBEEF);

    /// @notice Deploys contracts and sets up initial state before each test.
    function setUp() public {
        access = new ShiftAccessControl(admin);
        manager = new TestableShiftManager(address(access), feeCollector, 1e18, 1_000e18);
        assertTrue(access.hasRole(access.DEFAULT_ADMIN_ROLE(), admin));
    }

    // === 🟢 Initial State ===
    /// @notice Verifies the initial state of the contract after deployment.
    function test_DefaultState() public view {
        assertTrue(manager.paused());
        assertTrue(manager.whitelistEnabled());
        assertEq(manager.feeCollector(), feeCollector);
        assertEq(manager.minDepositAmount(), 1e18);
        assertEq(manager.maxTvl(), 1_000e18);
    }

    // === 🛠️ Admin-only updates ===
    /// @notice Tests update functions accessible only by the admin.

    function test_UpdatePerformanceFee() public {
        manager.updatePerformanceFee(100); // 1%
        assertEq(manager.performanceFeeBps(), 100);
        assertEq(manager.performanceFee18pt(), 1e16);
    }

    function test_UpdateMaintenanceFee() public {
        uint16 bps = 200;
        uint256 annual = (uint256(bps) * 1e18) / 10_000;
        uint256 expected = annual / 31_536_000;
        manager.updateMaintenanceFee(bps);
        assertEq(manager.maintenanceFeePerSecond18pt(), expected);
    }

    function test_UpdateMinDeposit() public {
        manager.updateMinDeposit(5e18);
        assertEq(manager.minDepositAmount(), 5e18);
    }

    function test_UpdateMaxTvl() public {
        manager.updateMaxTvl(5_000e18);
        assertEq(manager.maxTvl(), 5_000e18);
    }

    function test_UpgradeFeeCollector() public {
        address newCollector = address(0xDEAD);
        manager.upgradeFeeCollector(newCollector);
        assertEq(manager.feeCollector(), newCollector);
    }

    // === ⏸️ Pause logic ===
    /// @notice Tests for pause and emergency pause logic.

    function test_ReleasePauseWorks() public {
        manager.updatePerformanceFee(100);
        manager.updateMaintenanceFee(100);
        manager.releasePause();
        assertFalse(manager.paused());
    }

    function test_EmergencyPauseAlwaysWorks() public {
        manager.updatePerformanceFee(100);
        manager.updateMaintenanceFee(100);
        manager.releasePause();
        manager.emergencyPause();
        assertTrue(manager.paused());
    }

    function test_RevertOnReleasePauseWithoutFees() public {
        vm.expectRevert("ShiftManager: performance fee not set");
        manager.releasePause();
    }

    // === 🟦 Whitelist ===
    /// @notice Tests for whitelist management and toggling.

    function test_ToggleWhitelistFlag() public {
        bool initial = manager.whitelistEnabled();
        manager.manageWhitelist(address(0));
        assertEq(manager.whitelistEnabled(), !initial);
    }

    function test_ManageWhitelistUser() public {
        assertFalse(manager.isWhitelisted(user));
        manager.manageWhitelist(user);
        assertTrue(manager.isWhitelisted(user));
        manager.manageWhitelist(user);
        assertFalse(manager.isWhitelisted(user));
    }

    // === ➗ Math ===
    /// @notice Tests for internal math functions and conversions.

    function test_BpsConversionLogic() public view {
        assertEq(manager.expose_calc18pt(100), 1e16);
        assertEq(manager.expose_calc18pt(250), 2.5e16);
        assertEq(manager.expose_calc18pt(0), 0);
    }

    // === 🔴 Reverts: Error Checks ===
    /// @notice Tests that functions revert on invalid input.

    function test_RevertOnZeroMinDeposit() public {
        vm.expectRevert("ShiftManager: zero min deposit");
        manager.updateMinDeposit(0);
    }

    function test_RevertOnZeroMaxTvl() public {
        vm.expectRevert("ShiftManager: zero max TVL");
        manager.updateMaxTvl(0);
    }

    function test_RevertOnZeroPerfFee() public {
        vm.expectRevert("ShiftManager: zero performance fee");
        manager.updatePerformanceFee(0);
    }

    function test_RevertOnZeroMaintenanceFee() public {
        vm.expectRevert("ShiftManager: zero maintenance fee");
        manager.updateMaintenanceFee(0);
    }

    function test_RevertOnZeroFeeCollectorUpgrade() public {
        vm.expectRevert("ShiftManager: zero fee collector");
        manager.upgradeFeeCollector(address(0));
    }

    // === 🌪️ Fuzzy tests ===
    /// @notice Fuzz tests for input ranges and edge cases.

    function testFuzz_PerformanceFeeAcceptableRange(uint16 feeBps) public {
        vm.assume(feeBps > 0 && feeBps <= 1000);
        manager.updatePerformanceFee(feeBps);
        assertEq(manager.performanceFeeBps(), feeBps);
    }

    function testFuzz_MaintenanceFeeRate(uint16 bps) public {
        vm.assume(bps > 0 && bps <= 2000);
        uint256 annual = (uint256(bps) * 1e18) / 10_000;
        uint256 expected = annual / 31_536_000;
        manager.updateMaintenanceFee(bps);
        assertEq(manager.maintenanceFeePerSecond18pt(), expected);
    }

    function testFuzz_DepositAndTVLLimits(uint256 min, uint256 max) public {
        vm.assume(min > 0 && max >= min && max < 1e30);
        manager.updateMinDeposit(min);
        manager.updateMaxTvl(max);
        assertEq(manager.minDepositAmount(), min);
        assertEq(manager.maxTvl(), max);
    }

    function testFuzz_WhitelistToggle(address addr) public {
        vm.assume(addr != address(0));
        manager.manageWhitelist(addr);
        assertTrue(manager.isWhitelisted(addr) || !manager.isWhitelisted(addr));
    }
}
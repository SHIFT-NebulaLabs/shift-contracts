// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/ShiftManagerHarness.sol";

contract ShiftManagerTest is Test {
    MockAccessControl access;
    ShiftManagerHarness manager;
    address admin = address(1);
    address feeCollector = address(2);
    address user = address(3);

    /// @notice Sets up the test environment before each test
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, admin);
        vm.prank(admin);
        manager = new ShiftManagerHarness(address(access), feeCollector, 1 ether, 100 ether, 1 days);
    }

    /// @notice Tests the pause and release flow for the contract
    function testPauseAndReleaseFlow() public {
        vm.prank(admin);
        manager.updatePerformanceFee(100);
        vm.prank(admin);
        manager.updateMaintenanceFee(100);
        vm.prank(admin);
        manager.releasePause();
        assertFalse(manager.paused());
        vm.prank(admin);
        manager.emergencyPause();
        assertTrue(manager.paused());
    }

    /// @notice Ensures that only admin can pause the contract
    function testRevertNotAdminPause() public {
        vm.expectRevert();
        manager.emergencyPause();
    }

    /// @notice Tests toggling the whitelist feature
    function testWhitelistToggle() public {
        vm.prank(admin); // Impersonate admin for protected function
        bool before = manager.whitelistEnabled();
        vm.prank(admin);
        manager.manageWhitelist(address(0));
        assertEq(manager.whitelistEnabled(), !before);
    }

    /// @notice Tests adding and removing a user from the whitelist
    function testWhitelistUser() public {
        vm.prank(admin);
        manager.manageWhitelist(user);
        assertTrue(manager.exposed_isWhitelisted(user));
        vm.prank(admin);
        manager.manageWhitelist(user);
        assertFalse(manager.exposed_isWhitelisted(user));
    }

    /// @notice Tests updating fee parameters and checks for expected reverts on invalid values
    function testFeeParamsUpdateAndRevert() public {
        vm.prank(admin);
        manager.updateFeeCollector(address(0xCAFE));
        assertEq(manager.feeCollector(), address(0xCAFE));
        vm.prank(admin);
        manager.updateTimelock(2 days);
        assertEq(manager.timelock(), 2 days);
        vm.prank(admin);
        manager.updatePerformanceFee(250);
        assertEq(manager.performanceFeeBps(), 250);
        vm.prank(admin);
        manager.updateMaintenanceFee(300);
        assertEq(manager.maintenanceFeeBpsAnnual(), 300);
        vm.prank(admin);
        manager.updateMinDeposit(5 ether);
        assertEq(manager.minDepositAmount(), 5 ether);
        vm.prank(admin);
        manager.updateMaxTvl(200 ether);
        assertEq(manager.maxTvl(), 200 ether);

        vm.prank(admin);
        vm.expectRevert();
        manager.updateFeeCollector(address(0));
        vm.prank(admin);
        vm.expectRevert();
        manager.updateTimelock(0);
        vm.prank(admin);
        vm.expectRevert();
        manager.updateTimelock(31 days);
        vm.prank(admin);
        vm.expectRevert();
        manager.updatePerformanceFee(0);
        vm.prank(admin);
        vm.expectRevert();
        manager.updateMaintenanceFee(0);
        vm.prank(admin);
        vm.expectRevert();
        manager.updateMinDeposit(0);
        vm.prank(admin);
        vm.expectRevert();
        manager.updateMaxTvl(0);
    }

    /// @notice Fuzz test for calculating a 18-decimal value from basis points
    function testCalc18ptFromBpsFuzzy(uint16 bps) public view {
        uint256 r = manager.exposed_calc18ptFromBps(bps);
        assertEq(r, uint256(bps) * 1e18 / 10_000);
    }
}
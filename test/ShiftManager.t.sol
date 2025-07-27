// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/ShiftManagerHarness.sol";

contract ShiftManagerTest is Test {
    MockAccessControl access;
    ShiftManagerHarness manager;
    address constant ADMIN = address(1);
    address constant FEE_COLLECTOR = address(2);
    address constant USER = address(3);

    /// @notice Sets up the test environment before each test
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        vm.prank(ADMIN);
        manager = new ShiftManagerHarness(address(access), FEE_COLLECTOR, 1 ether, 100 ether, 1 days);
    }

    /// @notice Tests the pause and release flow for the contract
    function testPauseAndReleaseFlow() public {
        vm.startPrank(ADMIN);
        manager.updatePerformanceFee(100);
        manager.updateMaintenanceFee(100);
        manager.releasePause();
        assertFalse(manager.paused());
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
        vm.startPrank(ADMIN); // Impersonate admin for protected function
        bool before = manager.whitelistEnabled();

        address[] memory users = new address[](1);
        users[0] = address(0);
        manager.manageWhitelist(users);
        assertEq(manager.whitelistEnabled(), !before);
    }

    /// @notice Tests adding and removing a user from the whitelist
    function testWhitelistUser() public {
        vm.startPrank(ADMIN);

        address[] memory users = new address[](1);
        users[0] = USER;
        manager.manageWhitelist(users);
        assertTrue(manager.exposed_isWhitelisted(USER));

        manager.manageWhitelist(users);
        assertFalse(manager.exposed_isWhitelisted(USER));
    }

    /// @notice Tests updating fee parameters and checks for expected reverts on invalid values
    function testFeeParamsUpdateAndRevert() public {
        vm.startPrank(ADMIN);
        manager.updateFeeCollector(address(0xCAFE));
        assertEq(manager.feeCollector(), address(0xCAFE));

        manager.updateTimelock(2 days);
        assertEq(manager.timelock(), 2 days);

        manager.updatePerformanceFee(250);
        assertEq(manager.performanceFeeBps(), 250);

        manager.updateMaintenanceFee(300);
        assertEq(manager.maintenanceFeeBpsAnnual(), 300);

        manager.updateMinDeposit(5 ether);
        assertEq(manager.minDepositAmount(), 5 ether);

        manager.updateMaxTvl(200 ether);
        assertEq(manager.maxTvl(), 200 ether);

        vm.expectRevert();
        manager.updateFeeCollector(address(0));

        vm.expectRevert();
        manager.updateTimelock(0);

        vm.expectRevert();
        manager.updateTimelock(0);

        vm.expectRevert();
        manager.updateTimelock(31 days);

        vm.expectRevert();
        manager.updatePerformanceFee(0);

        vm.expectRevert();
        manager.updateMaintenanceFee(0);

        vm.expectRevert();
        manager.updateMinDeposit(0);

        vm.expectRevert();
        manager.updateMaxTvl(0);
    }

    /// @notice Fuzz test for calculating a 18-decimal value from basis points
    function testCalc18ptFromBpsFuzzy(uint16 bps) public view {
        uint256 r = manager.exposed_calc18ptFromBps(bps);
        assertEq(r, uint256(bps) * 1e18 / 10_000);
    }
}

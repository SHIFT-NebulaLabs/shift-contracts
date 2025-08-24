// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/ShiftManagerHarness.sol";
import {ShiftManagerArgs} from "../src/utils/Structs.sol";

contract ShiftManagerTest is Test {
    MockAccessControl access;
    ShiftManagerHarness manager;
    address constant ADMIN = address(1);
    address constant FEE_COLLECTOR = address(2);
    address constant EXECUTOR = address(3);
    address constant USER = address(4);

    /// @notice Sets up the test environment before each test
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        vm.prank(ADMIN);

        ShiftManagerArgs memory args = ShiftManagerArgs({
            accessControlContract: address(access),
            feeCollector: FEE_COLLECTOR,
            executor: EXECUTOR,
            minDeposit: 1 ether,
            maxTvl: 100 ether,
            timelock: 1 days,
            freshness: 90 minutes,
            requestValidity: 120
        });

        manager = new ShiftManagerHarness(args);
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

        manager.toggleWhitelist();
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

    /// @notice Tests updating the executor address
    function testUpdateExecutor() public {
        vm.startPrank(ADMIN);
        manager.updateExecutor(address(0xBEEF));
        assertEq(manager.executor(), address(0xBEEF));
    }

    /// @notice Tests the updateTimelock function by updating the timelock duration to 2 days.
    function testUpdateTimelock() public {
        vm.startPrank(ADMIN);
        manager.updateTimelock(2 days);
        assertEq(manager.timelock(), 2 days);
    }

    /// @notice Tests updating the freshness duration
    function testUpdatedFreshness() public {
        vm.startPrank(ADMIN);
        manager.updateFreshness(2 hours);
        assertEq(manager.freshness(), 2 hours);
    }

    /// @notice Tests updating the request validity duration
    function testUpdateRequestValidity() public {
        vm.startPrank(ADMIN);
        manager.updateRequestValidity(60);
        assertEq(manager.requestValidity(), 60);
    }

    /// @notice Tests updating fee parameters and checks for expected reverts on invalid values
    function testFeeParamsUpdateAndRevert() public {
        vm.startPrank(ADMIN);
        manager.updateFeeCollector(address(0xCAFE));
        assertEq(manager.feeCollector(), address(0xCAFE));

        manager.updateTimelock(2 days);
        assertEq(manager.timelock(), 2 days);

        manager.updateMinDeposit(5 ether);
        assertEq(manager.minDepositAmount(), 5 ether);

        manager.updateMaxTvl(200 ether);
        assertEq(manager.maxTvl(), 200 ether);

        vm.expectRevert();
        manager.updateFeeCollector(address(0));

        vm.expectRevert();
        manager.updateExecutor(address(0));

        vm.expectRevert();
        manager.updateTimelock(0);

        vm.expectRevert();
        manager.updateFreshness(0);

        vm.expectRevert();
        manager.updateFreshness(0);

        vm.expectRevert();
        manager.updateTimelock(31 days);

        vm.expectRevert();
        manager.updatePerformanceFee(10001);

        vm.expectRevert();
        manager.updateMaintenanceFee(10001);

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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/ShiftTvlFeedHarness.sol";

/// @notice MockVault simulates a vault for test purposes
contract MockVault {
    function allowDeposit(address, uint256) external {}
}

/// @notice Test suite for ShiftTvlFeed
contract ShiftTvlFeedTest is Test {
    MockAccessControl access;
    ShiftTvlFeedHarness tvlFeed;
    MockVault mockVault;
    address admin = address(1);
    address oracle = address(2);

    /// @notice Setup: deploys mocks and initializes the contract under test
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, admin);
        access.grantRole(keccak256("ORACLE_ROLE"), oracle);

        tvlFeed = new ShiftTvlFeedHarness(address(access));
        mockVault = new MockVault();

        vm.prank(admin);
        tvlFeed.initialize(address(mockVault));
    }

    /// @notice Tests that initialize works and cannot be called twice
    function testInitialize() public {
        vm.expectRevert();
        vm.prank(admin);
        tvlFeed.initialize(address(mockVault));
        assertEq(address(tvlFeed.shiftVault()), address(mockVault));
        assertTrue(tvlFeed.init());
    }

    /// @notice Tests that initialize reverts if already initialized
    function testRevertAlreadyInitialized() public {
        vm.expectRevert("ShiftTvlFeed: already initialized");
        vm.prank(admin);
        tvlFeed.initialize(address(mockVault));
    }

    /// @notice Tests that only the oracle can update TVL and data is saved correctly
    function testUpdateTvlOracle() public {
        vm.prank(oracle);
        tvlFeed.updateTvl(123456);
        assertEq(tvlFeed.exposed_tvlHistoryLength(), 1);
        ShiftTvlFeed.TvlData memory d = tvlFeed.exposed_tvlHistoryAt(0);
        assertEq(d.value, 123456);
    }

    /// @notice Tests that anyone except the oracle cannot update the TVL
    function testRevertNotOracleUpdateTvl() public {
        vm.expectRevert();
        tvlFeed.updateTvl(1);
    }

    /// @notice Tests that the oracle can call updateTvlForDeposit
    function testUpdateTvlForDeposit() public {
        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(address(0x99), 123);
        assertEq(tvlFeed.exposed_tvlHistoryLength(), 1);
        ShiftTvlFeed.TvlData memory d = tvlFeed.exposed_tvlHistoryAt(0);
        assertEq(d.value, 123);
    }

    /// @notice Tests that getLastTvlEntries returns the correct last N values
    function testGetLastTvlEntries() public {
        vm.startPrank(oracle);
        for (uint256 i; i < 5; ++i) {
            tvlFeed.updateTvl(i + 100);
        }
        vm.stopPrank();
        ShiftTvlFeed.TvlData[] memory arr = tvlFeed.getLastTvlEntries(3);
        assertEq(arr.length, 3);
        assertEq(arr[0].value, 104);
        assertEq(arr[2].value, 102);
    }

    function testGetTvlEntry() public {
        vm.startPrank(oracle);
        for (uint256 i; i < 5; ++i) {
            tvlFeed.updateTvl(i + 100);
        }
        vm.stopPrank();
        ShiftTvlFeed.TvlData memory entry = tvlFeed.getTvlEntry(2);
        assertEq(entry.value, 102);
    }
}

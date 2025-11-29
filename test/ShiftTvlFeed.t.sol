// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/ShiftTvlFeedHarness.sol";
import "./mocks/MockERC20.sol";

/// @notice MockVault simulates a vault for test purposes
contract MockVault {
    MockERC20 public baseToken;

    constructor(address _baseToken) {
        baseToken = MockERC20(_baseToken);
    }

    function allowDeposit(address, uint256, uint256, uint256) external {}

    function totalSupply() external pure returns (uint256) {
        return 1000; // Mock total supply
    }
}

/// @notice Test suite for ShiftTvlFeed
contract ShiftTvlFeedTest is Test {
    MockAccessControl access;
    ShiftTvlFeedHarness tvlFeed;
    MockVault mockVault;
    MockERC20 baseToken;
    address constant ADMIN = address(1);
    address constant ORACLE = address(2);
    uint8 constant DECIMALS = 6;

    /// @notice Setup: deploys mocks and initializes the contract under test
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        access.grantRole(keccak256("ORACLE_ROLE"), ORACLE);

        tvlFeed = new ShiftTvlFeedHarness(address(access));
        baseToken = new MockERC20(DECIMALS);
        mockVault = new MockVault(address(baseToken));

        vm.prank(ADMIN);
        tvlFeed.initialize(address(mockVault));
    }

    /// @notice Tests that initialize works and cannot be called twice
    function testInitialize() public {
        vm.expectRevert();
        vm.prank(ADMIN);
        tvlFeed.initialize(address(mockVault));
        assertEq(address(tvlFeed.shiftVault()), address(mockVault));
        assertTrue(tvlFeed.init());
    }
    /// @notice Tests that decimals() returns the correct number of decimal places

    function testDecimalPlaces() public view {
        assertEq(tvlFeed.decimals(), DECIMALS);
        assertEq(tvlFeed.decimals(), baseToken.decimals());
    }

    /// @notice Tests that initialize reverts if already initialized
    function testRevertAlreadyInitialized() public {
        vm.expectRevert();
        vm.prank(ADMIN);
        tvlFeed.initialize(address(mockVault));
    }

    /// @notice Tests that only the oracle can update TVL and data is saved correctly
    function testUpdateTvlOracle() public {
        vm.prank(ORACLE);
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
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(address(0x99), 123, 1000);
        assertEq(tvlFeed.exposed_tvlHistoryLength(), 1);
        ShiftTvlFeed.TvlData memory d = tvlFeed.exposed_tvlHistoryAt(0);
        assertEq(d.value, 123);
    }

    /// @notice Tests that getLastTvlEntries returns the correct last N values
    function testGetLastTvlEntries() public {
        vm.startPrank(ORACLE);
        for (uint256 i; i < 5; ++i) {
            tvlFeed.updateTvl(i + 100);
        }
        vm.stopPrank();
        ShiftTvlFeed.TvlData[] memory arr = tvlFeed.getLastTvlEntries(3);
        assertEq(arr.length, 3);
        assertEq(arr[0].value, 104);
        assertEq(arr[2].value, 102);
    }

    /// @notice Tests that getTvlEntry returns the correct value at a given index
    function testGetTvlEntry() public {
        vm.startPrank(ORACLE);
        for (uint256 i; i < 5; ++i) {
            tvlFeed.updateTvl(i + 100);
        }
        vm.stopPrank();
        ShiftTvlFeed.TvlData memory entry = tvlFeed.getTvlEntry(2);
        assertEq(entry.value, 102);
    }

    /// @notice Tests that updateTvlForDeposit works correctly with referenceSupply parameter
    function testUpdateTvlForDepositWithReferenceSupply() public {
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(address(0x99), 500, 1000); // referenceSupply = 1000 (should match mock vault totalSupply)
        
        assertEq(tvlFeed.exposed_tvlHistoryLength(), 1);
        ShiftTvlFeed.TvlData memory d = tvlFeed.exposed_tvlHistoryAt(0);
        assertEq(d.value, 500);
        assertEq(d.supplySnapshot, 1000); // Should match the mock vault totalSupply
    }

    /// @notice Tests that updateTvlForDeposit reverts with zero address
    function testRevertUpdateTvlForDepositZeroAddress() public {
        vm.expectRevert();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(address(0), 500, 1000);
    }

    /// @notice Tests that only oracle can call updateTvlForDeposit
    function testRevertNotOracleUpdateTvlForDeposit() public {
        vm.expectRevert();
        tvlFeed.updateTvlForDeposit(address(0x99), 500, 1000);
    }
}

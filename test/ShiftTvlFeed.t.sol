// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/ShiftVault.sol";
import "../src/ShiftTvlFeed.sol";
import "../src/ShiftAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// === 🟢 Mock base token ===
// Mock ERC20 token used as the base asset for testing
contract MockBaseToken is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

// === 🟢 ShiftTvlFeedTest: Test suite for ShiftTvlFeed contract ===
contract ShiftTvlFeedTest is Test {
    ShiftVault vault;
    ShiftTvlFeed tvlFeed;
    ShiftAccessControl access;
    MockBaseToken baseToken;

    address admin = address(this);
    address oracle = address(0x1);
    address user = address(0x2);
    address feeCollector = address(0xdead);

    uint256 minDeposit = 1000 ether;
    uint256 maxTvl = 10_000_000 ether;

    // === 🟢 Setup: Deploy contracts and prepare initial state ===
    function setUp() public {
        // Deploy access control and grant oracle role
        access = new ShiftAccessControl(admin);
        access.grantRole(access.ORACLE_ROLE(), oracle);

        // Deploy mock base token and contracts under test
        baseToken = new MockBaseToken();
        tvlFeed = new ShiftTvlFeed(address(access));
        vault = new ShiftVault(
            address(access),
            address(baseToken),
            address(tvlFeed),
            feeCollector,
            minDeposit,
            maxTvl
        );

        // Initialize TVL feed with vault address
        tvlFeed.initialize(address(vault));

        // Fund user and approve vault for deposits
        baseToken.transfer(user, 5000 ether);
        vm.startPrank(user);
        baseToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // === 🟢 Initial State: Check correct initialization ===

    /// @notice TVL feed should be initialized and linked to the correct vault
    function test_InitLinksVaultCorrectly() public view {
        assertTrue(tvlFeed.init());
        assertEq(address(tvlFeed.shiftVault()), address(vault));
    }

    // === 🟢 Functional: TVL Updates & Queries ===

    /// @notice updateTvl should store new value and update timestamp
    function test_UpdateTvlStoresNewValue() public {
        vm.prank(oracle);
        tvlFeed.updateTvl(1234);
        ShiftTvlFeed.TvlData memory data = tvlFeed.getLastTvl();
        assertEq(data.value, 1234);
        assertGt(data.timestamp, 0);
    }

    /// @notice updateTvlForDeposit should trigger DepositAllowed event from vault
    function test_UpdateTvlForDepositTriggersVaultEvent() public {
        // Whitelist user and request deposit
        vm.prank(admin);
        vault.manageWhitelist(user);
        vm.prank(user);
        vault.reqDeposit();

        // Record logs and call updateTvlForDeposit
        vm.recordLogs();
        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(user, 2345);

        // Check for DepositAllowed event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        uint256 expirationTime;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DepositAllowed(address,uint256)")) {
                (expirationTime) = abi.decode(logs[i].data, (uint256));
                found = true;
                break;
            }
        }

        assertTrue(found, "DepositAllowed not emitted");
        assertGt(expirationTime, block.timestamp);
    }

    /// @notice decimals() should always return 6
    function test_DecimalsAreFixedToSix() public view {
        assertEq(tvlFeed.decimals(), 6);
    }

    /// @notice getLastTvlEntries should return latest values in correct order (most recent first)
    function test_GetLastTvlEntriesReturnsCorrectOrder() public {
        vm.startPrank(oracle);
        for (uint256 i = 0; i < 3; i++) {
            tvlFeed.updateTvl(5000 + i);
        }
        vm.stopPrank();
        ShiftTvlFeed.TvlData[] memory entries = tvlFeed.getLastTvlEntries(2);
        assertEq(entries.length, 2);
        assertEq(entries[0].value, 5002);
        assertEq(entries[1].value, 5001);
    }

    // === 🟠 Permissions: Only Oracle ===

    /// @notice Only oracle should be able to call updateTvl
    function test_OnlyOracleCanCall_updateTvl() public {
        vm.prank(oracle);
        tvlFeed.updateTvl(12345);
        assertEq(tvlFeed.getLastTvl().value, 12345);

        vm.prank(user);
        vm.expectRevert("Not oracle");
        tvlFeed.updateTvl(67890);
    }

    /// @notice Only oracle should be able to call updateTvlForDeposit
    function test_OnlyOracleCanCall_updateTvlForDeposit() public {
        vm.prank(admin);
        vault.manageWhitelist(user);
        vm.prank(user);
        vault.reqDeposit();

        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(user, 5000);
        assertEq(tvlFeed.getLastTvl().value, 5000);

        vm.prank(user);
        vm.expectRevert("Not oracle");
        tvlFeed.updateTvlForDeposit(user, 9999);
    }

    // === 🔴 Reverts: Error Checks ===

    /// @notice Should revert if initialize is called twice
    function test_RevertIf_DoubleInitialize() public {
        vm.expectRevert("ShiftTvlFeed: already initialized");
        tvlFeed.initialize(address(vault));
    }

    /// @notice Should revert if initialized with zero vault address
    function test_RevertIf_VaultIsZero() public {
        ShiftTvlFeed fresh = new ShiftTvlFeed(address(access));
        vm.expectRevert("ShiftTvlFeed: zero vault address");
        fresh.initialize(address(0));
    }

    /// @notice Should revert if updateTvl is called before initialization
    function test_RevertIf_UpdateWithoutInit() public {
        ShiftTvlFeed fresh = new ShiftTvlFeed(address(access));
        vm.prank(oracle);
        vm.expectRevert("ShiftTvlFeed: not initialized");
        fresh.updateTvl(1);
    }

    /// @notice Should revert if user address is zero in updateTvlForDeposit
    function test_RevertIf_UserIsZeroAddress() public {
        vm.prank(oracle);
        vm.expectRevert("ShiftTvlFeed: zero user address");
        tvlFeed.updateTvlForDeposit(address(0), 123);
    }

    /// @notice Should revert if TVL passed is zero in updateTvlForDeposit
    function test_RevertIf_TvlIsZero() public {
        vm.prank(oracle);
        vm.expectRevert("ShiftTvlFeed: TVL must be positive");
        tvlFeed.updateTvlForDeposit(user, 0);
    }

    /// @notice Should revert if updateTvl is called by non-oracle
    function test_RevertIf_CallerNotOracle() public {
        vm.prank(user);
        vm.expectRevert("Not oracle");
        tvlFeed.updateTvl(9999);
    }

    /// @notice Should revert if zero entries are requested from getLastTvlEntries
    function test_RevertIf_EntryCountIsZero() public {
        vm.expectRevert("ShiftTvlFeed: count must be positive");
        tvlFeed.getLastTvlEntries(0);
    }

    // === 🌪️ Fuzzing ===

    /// @notice Fuzz: updateTvl should accept any large, non-zero value
    function testFuzz_UpdateTvlAcceptsLargeValues(uint256 value) public {
        vm.assume(value > 0);
        vm.prank(oracle);
        tvlFeed.updateTvl(value);
        assertEq(tvlFeed.getLastTvl().value, value);
    }
}

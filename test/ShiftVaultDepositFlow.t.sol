// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/MockERC20.sol";
import "../src/ShiftTvlFeed.sol";
import "./mocks/ShiftVaultHarness.sol";
import {ShiftVaultArgs, ShiftManagerArgs} from "../src/utils/Structs.sol";

/// @title ShiftVaultDepositFlowTest
/// @notice Test suite focused on unique deposit flow scenarios not covered in ShiftVault.t.sol
/// @dev Focuses on: overlapping requests, price changes, expiration handling
contract ShiftVaultDepositFlowTest is Test {
    MockAccessControl access;
    MockERC20 token;
    ShiftTvlFeed tvlFeed;
    ShiftVaultHarness vault;

    address constant ADMIN = address(1);
    address constant EXECUTOR = address(2);
    address constant FEE_COLLECTOR = address(3);
    address constant USER1 = address(4);
    address constant USER2 = address(5);
    address constant ORACLE = address(6);
    address constant CLAIMER = address(7);

    string constant SHARE_NAME = "Shift LP";
    string constant SHARE_SYMBOL = "SLP";

    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");

    uint256 constant MIN_DEPOSIT = 1_000_000; // 1 USDC
    uint8 constant TOKEN_DECIMALS = 6; // USDC decimals

    uint16 constant PERFORMANCE_FEE = 2000;
    uint16 constant MAINTENANCE_FEE = 200;

    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        access.grantRole(EXECUTOR_ROLE, EXECUTOR);
        access.grantRole(ORACLE_ROLE, ORACLE);
        access.grantRole(CLAIMER_ROLE, CLAIMER);
        token = new MockERC20(TOKEN_DECIMALS);
        tvlFeed = new ShiftTvlFeed(address(access));

        ShiftVaultArgs memory args = ShiftVaultArgs({
            tokenContract: address(token),
            tvlFeedContract: address(tvlFeed),
            shareName: SHARE_NAME,
            shareSymbol: SHARE_SYMBOL,
            managerArgs: ShiftManagerArgs({
                accessControlContract: address(access),
                feeCollector: FEE_COLLECTOR,
                executor: EXECUTOR,
                minDeposit: MIN_DEPOSIT,
                maxTvl: 1_000_000_000e6,
                timelock: 1 days,
                freshness: 90 minutes,
                requestValidity: 120
            })
        });

        vault = new ShiftVaultHarness(args);

        vm.startPrank(ADMIN);
        tvlFeed.initialize(address(vault));
        vault.updatePerformanceFee(PERFORMANCE_FEE);
        vault.updateMaintenanceFee(MAINTENANCE_FEE);
        vault.releasePause();

        address[] memory users = new address[](2);
        users[0] = USER1;
        users[1] = USER2;
        vault.manageWhitelist(users);
        vm.stopPrank();

        deal(address(token), USER1, 100e6);
        deal(address(token), USER2, 1e6);
    }

    /// @notice Sequential deposit flow maintaining 1:1 share-to-token ratio
    /// Flow: ReqDeposit1 → Response1 → Deposit1 → ReqDeposit2 → Response2 → Deposit2
    function testSequentialDepositsOneToOneRatio() public {
        // === FIRST DEPOSIT FLOW ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply);

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // === SECOND DEPOSIT FLOW ===
        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        currentSupply = vault.totalSupply();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 100e6, currentSupply);

        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        // Verify 1:1 ratio results
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
        assertEq(vault.totalSupply(), 101e18);
        assertEq(token.balanceOf(EXECUTOR), 101e6);

        uint256 sharePrice = vault.getSharePrice();
        assertEq(sharePrice, 1e6); // 1 USDC per share
    }

    /// @notice Overlapping requests where second response REVERTS due to supply mismatch protection
    /// Flow: ReqDeposit1 → ReqDeposit2 → Response1 → Deposit1 → Response2(REVERT)
    /// This is the CORE test case demonstrating the protection mechanism
    function testOverlappingDepositRequestsRevert() public {
        // === OVERLAPPING REQUEST PHASE ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        // === FIRST RESPONSE AND DEPOSIT ===
        uint256 supplyAtUser1Request = vault.totalSupply(); // 0
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, supplyAtUser1Request);

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // === SECOND RESPONSE (SHOULD REVERT) ===
        // Supply has changed from 0 to 100e18, so User2's request is invalid
        uint256 supplyAtUser2Request = 0; // Supply when User2 made the request

        vm.prank(ORACLE);
        vm.expectRevert(); // Should revert with NoValidRequest()
        tvlFeed.updateTvlForDeposit(USER2, 100e6, supplyAtUser2Request);

        // User2 cannot deposit because their request was invalidated
        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vm.expectRevert();
        vault.deposit(1e6);
        vm.stopPrank();

        // Verify only User1 has shares
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 0);
    }

    /// @notice Recovery flow after supply mismatch - user makes fresh request after expiration
    /// Flow: [Previous overlapping flow] → Wait → ReqDeposit2(new) → Response2 → Deposit2
    function testCorrectFlowAfterSupplyMismatch() public {
        testOverlappingDepositRequestsRevert();

        // Wait for User2's request to expire
        vm.warp(block.timestamp + 121);

        // User2 makes new request with current state
        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply(); // 100e18
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 100e6, currentSupply);

        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        // Verify both users have correct shares
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
        assertEq(vault.totalSupply(), 101e18);
    }

    /// @notice Deposit flow with TVL appreciation - second user gets fewer shares due to price increase
    /// Flow: ReqDeposit1 → Response1 → Deposit1 → ReqDeposit2 → Response2(2x price) → Deposit2
    function testDepositWithTVLAppreciation() public {
        // First deposit
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, 0);

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // Second deposit with appreciated TVL
        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 200e6, currentSupply); // TVL doubled

        deal(address(token), USER2, 2e6);
        vm.startPrank(USER2);
        token.approve(address(vault), 2e6);
        vault.deposit(2e6);
        vm.stopPrank();

        // USER2 gets fewer shares due to price appreciation
        assertEq(vault.balanceOf(USER2), 1e18); // 2 USDC for 1 share
        uint256 sharePrice = vault.getSharePrice();
        assertEq(sharePrice, 2e6); // 2 USDC per share
    }

    /// @notice Deposit flow with TVL depreciation - second user gets more shares due to price decrease
    /// Flow: ReqDeposit1 → Response1 → Deposit1 → ReqDeposit2 → Response2(0.5x price) → Deposit2
    function testDepositWithTVLDepreciation() public {
        // First deposit
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, 0);

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // Second deposit with depreciated TVL
        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 50e6, currentSupply); // TVL halved

        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        // USER2 gets more shares due to price depreciation
        assertEq(vault.balanceOf(USER2), 2e18); // 1 USDC for 2 shares
        uint256 sharePrice = vault.getSharePrice();
        assertEq(sharePrice, 0.5e6); // 0.5 USDC per share
    }

    /// @notice Deposit attempt REVERTS when trying to use expired oracle response
    /// Flow: ReqDeposit1 → Response1 → Wait(expire) → Deposit1(REVERT)
    function testDepositWithExpiredRequestFails() public {
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply);

        // Time passes beyond validity
        vm.warp(block.timestamp + 121);

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vm.expectRevert();
        vault.deposit(100e6);
        vm.stopPrank();
    }

    /// @notice Oracle duplicate response REVERTS - prevents double allowance on same request
    /// Flow: ReqDeposit1 → Response1 → Response1(REVERT)
    function testOracleCannotRespondTwiceToSameRequest() public {
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply();

        // First response succeeds
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply);

        // Second response fails
        vm.prank(ORACLE);
        vm.expectRevert();
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply);
    }

    /// @notice Out-of-order deposit execution - both succeed when approved with same supply
    /// Flow: ReqDeposit1 → ReqDeposit2 → Response1 → Response2 → Deposit2 → Deposit1
    /// This tests out-of-order execution where deposits happen in reverse order of requests
    function testReverseOrderDepositFlow() public {
        // === OVERLAPPING REQUESTS ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        // === RESPONSES IN ORDER ===
        uint256 currentSupply = vault.totalSupply(); // 0

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply); // Response1

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 0, currentSupply); // Response2

        // === DEPOSITS IN REVERSE ORDER ===
        // USER2 deposits first (despite requesting second)
        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        // USER1 deposits second (despite requesting first)
        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // Both should work since both were approved with same supply (0)
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
        assertEq(vault.totalSupply(), 101e18);
    }

    /// @notice Interleaved request/response/deposit pattern - realistic concurrent usage
    /// Flow: ReqDeposit1 → Response1 → ReqDeposit2 → Deposit1 → Response2 → Deposit2
    /// This tests interleaved request/response/deposit pattern
    function testInterleavedDepositFlow() public {
        // === FIRST REQUEST AND RESPONSE ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply(); // 0
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply);

        // === SECOND REQUEST (before first deposit) ===
        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        // === FIRST DEPOSIT ===
        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // === SECOND RESPONSE (after first deposit) ===
        currentSupply = vault.totalSupply(); // 100e18
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 100e6, currentSupply); // TVL = deposits

        // === SECOND DEPOSIT ===
        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        // Verify 1:1 ratio maintained
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
        assertEq(vault.getSharePrice(), 1e6);
    }

    /// @notice Multiple users with batched oracle responses - all succeed with same initial supply
    /// Flow: ReqDeposit1 → ReqDeposit2 → ReqDeposit3 → Response1 → Response2 → Response3 → Deposit1 → Deposit2 → Deposit3
    function testMultipleUsersDelayedResponses() public {
        address USER3 = address(0x123);
        deal(address(token), USER3, 50e6);

        // Add USER3 to whitelist
        vm.prank(ADMIN);
        address[] memory users = new address[](1);
        users[0] = USER3;
        vault.manageWhitelist(users);

        // === ALL REQUESTS FIRST ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        vm.startPrank(USER3);
        vault.reqDeposit();
        vm.stopPrank();

        // === ALL RESPONSES ===
        uint256 currentSupply = vault.totalSupply(); // 0

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, currentSupply);

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 0, currentSupply);

        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER3, 0, currentSupply);

        // === ALL DEPOSITS ===
        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        vm.startPrank(USER3);
        token.approve(address(vault), 50e6);
        vault.deposit(50e6);
        vm.stopPrank();

        // All should work with 1:1 ratio since all approved with supply=0
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
        assertEq(vault.balanceOf(USER3), 50e18);
        assertEq(vault.totalSupply(), 151e18);
    }

    /// @notice Late oracle response REVERTS due to stale supply, requiring fresh request cycle
    /// Flow: ReqDeposit1 → ReqDeposit2 → Response1 → Deposit1 → Response2(REVERT) → NewReq2 → NewResponse2 → Deposit2
    function testLateOracleResponseFlow() public {
        // === REQUESTS ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        // === FIRST RESPONSE AND DEPOSIT ===
        uint256 supplyAtRequest = vault.totalSupply(); // 0
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, supplyAtRequest);

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // === LATE SECOND RESPONSE (should fail due to supply change) ===
        vm.prank(ORACLE);
        vm.expectRevert(); // Supply changed from 0 to 100e18
        tvlFeed.updateTvlForDeposit(USER2, 0, supplyAtRequest); // Using old supply=0

        // === USER2 NEW REQUEST FLOW ===
        vm.warp(block.timestamp + 121); // Wait for expiration

        vm.startPrank(USER2);
        vault.reqDeposit(); // New request
        vm.stopPrank();

        uint256 newSupply = vault.totalSupply(); // 100e18
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 100e6, newSupply); // Correct current state

        vm.startPrank(USER2);
        token.approve(address(vault), 1e6);
        vault.deposit(1e6);
        vm.stopPrank();

        // Final state should be 1:1 ratio
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
    }

    /// @notice Price appreciation between deposits affects share allocation correctly
    /// Flow: ReqDeposit1 → Response1 → PriceChange → Deposit1 → ReqDeposit2 → Response2 → Deposit2
    function testPriceChangeBetweenResponseAndDeposit() public {
        // === FIRST FLOW WITH PRICE CHANGE ===
        vm.startPrank(USER1);
        vault.reqDeposit();
        vm.stopPrank();

        // Oracle responds with initial price
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER1, 0, 0);

        // Simulate external price change by updating TVL directly (if vault supported this)
        // For this test, we assume price stays same during USER1's deposit

        vm.startPrank(USER1);
        token.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // === SECOND FLOW WITH APPRECIATED PRICE ===
        vm.startPrank(USER2);
        vault.reqDeposit();
        vm.stopPrank();

        uint256 currentSupply = vault.totalSupply();
        // Oracle responds with appreciated TVL (e.g., underlying assets gained value)
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(USER2, 200e6, currentSupply); // 2x appreciation

        deal(address(token), USER2, 2e6); // Give USER2 enough tokens
        vm.startPrank(USER2);
        token.approve(address(vault), 2e6);
        vault.deposit(2e6);
        vm.stopPrank();

        // USER1 has 100 shares from 100 USDC at 1:1 ratio
        // USER2 has 1 share from 2 USDC at 2:1 ratio (due to appreciation)
        assertEq(vault.balanceOf(USER1), 100e18);
        assertEq(vault.balanceOf(USER2), 1e18);
        assertEq(vault.getSharePrice(), 2e6); // 2 USDC per share
    }
}

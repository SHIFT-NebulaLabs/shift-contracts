// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/MockERC20.sol";
import "../src/ShiftTvlFeed.sol";
import "./mocks/ShiftVaultHarness.sol";

contract ShiftVaultTest is Test {
    MockAccessControl access;
    MockERC20 token;
    ShiftTvlFeed tvlFeed;
    ShiftVaultHarness vault;

    address constant ADMIN = address(1);
    address constant EXECUTOR = address(2);
    address constant FEE_COLLECTOR = address(3);
    address constant USER = address(4);
    address constant ORACLE = address(5);

    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint256 constant MIN_DEPOSIT = 1_000_000;
    uint256 constant INITIAL_BALANCE = 10_000_000;

    /// @notice Sets up the test environment and deploys all mocks and the vault
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        access.grantRole(EXECUTOR_ROLE, EXECUTOR);
        access.grantRole(ORACLE_ROLE, ORACLE);
        token = new MockERC20(6);
        tvlFeed = new ShiftTvlFeed(address(access));
        vault = new ShiftVaultHarness(
            address(access), address(token), address(tvlFeed), FEE_COLLECTOR, MIN_DEPOSIT, 1_000_000_000e6, 1 days
        );
        tvlFeed.initialize(address(vault));
        vm.prank(ADMIN);
        vault.updatePerformanceFee(100);
        vm.prank(ADMIN);
        vault.updateMaintenanceFee(100);
        vm.prank(ADMIN);
        vault.releasePause();
    }

    /// @dev Helper to whitelist a user, fund them, and approve the vault
    function _setupUser(address user, uint256 amount) internal {
        vm.prank(ADMIN);
        vault.manageWhitelist(user);
        deal(address(token), user, amount);
        vm.startPrank(user);
        vault.reqDeposit();
        vm.stopPrank();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(user, amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
    }

    // --- Deposit & Withdraw Flow Tests ---

    /// @notice Tests the full deposit and withdraw flow for a user
    function testDepositAndWithdrawFlow() public {
        _setupUser(USER, INITIAL_BALANCE);
        vault.deposit(5_000_000);
        assertEq(vault.balanceOf(USER), 5_000_000 * 1e12);
        assertEq(token.balanceOf(address(vault)), 5_000_000);

        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        vault.sendFundsToResolver();
        vault.processWithdraw();
        token.approve(address(vault), 5_000_000);
        vault.resolveWithdraw(5_000_000, 1_000_000);
        vm.stopPrank();

        skip(1 days + 1);

        vm.startPrank(USER);
        uint256 balBefore = token.balanceOf(USER);
        vault.withdraw();
        uint256 balAfter = token.balanceOf(USER);
        assertGt(balAfter, balBefore);
        vm.stopPrank();
    }

    /// @notice Tests that the first deposit mints the correct amount of shares
    function testFirstDepositSharesMatch() public {
        _setupUser(USER, 1_000_000);
        vault.deposit(1_000_000);
        assertEq(vault.balanceOf(USER), 1_000_000 * 1e12);
        vm.stopPrank();
    }

    /// @notice Tests that a double withdraw reverts as expected
    function testDoubleWithdrawReverts() public {
        _setupUser(USER, INITIAL_BALANCE);
        vault.deposit(5_000_000);
        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        vault.sendFundsToResolver();
        vault.processWithdraw();
        token.approve(address(vault), 5_000_000);
        vault.resolveWithdraw(5_000_000, 1_000_000);
        vm.stopPrank();

        skip(1 days + 1);

        vm.startPrank(USER);
        vault.withdraw();
        vm.expectRevert();
        vault.withdraw();
        vm.stopPrank();
    }

    /// @notice Tests that resolving a withdraw twice reverts
    function testResolveWithdrawTwiceReverts() public {
        _setupUser(USER, INITIAL_BALANCE);
        vault.deposit(5_000_000);
        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        vault.sendFundsToResolver();
        vault.processWithdraw();
        token.approve(address(vault), 5_000_000);
        vault.resolveWithdraw(5_000_000, 1_000_000);
        vm.expectRevert();
        vault.resolveWithdraw(5_000_000, 1_000_000);
        vm.stopPrank();
    }

    // --- Calculation Tests ---

    /// @notice Tests calculation of shares from token amount
    function testCalcSharesFromToken() public {
        address otherUser = address(0xBEEF);
        _setupUser(otherUser, 10_000_000);
        vault.deposit(10_000_000);
        vm.stopPrank();

        uint256 amount = 5_000_000;
        uint256 totalSupply = vault.totalSupply();
        uint256 tvl = 10_000_000;
        uint256 expectedShares = (amount * 1e12 * totalSupply) / (tvl * 1e12);

        uint256 shares = vault.exposed_calcSharesFromToken(amount, 0);
        assertEq(shares, expectedShares);
    }

    /// @notice Tests calculation of token amount from shares
    function testCalcTokenFromShares() public {
        address otherUser = address(0xBEEF);
        _setupUser(otherUser, 20_000_000);
        vault.deposit(20_000_000);
        vm.stopPrank();

        uint256 shares = 5e18;
        uint256 totalSupply = vault.totalSupply();
        uint256 tvl = 20_000_000;
        uint256 expectedTokens = (shares * tvl * 1e12) / totalSupply;

        uint256 tokens = vault.exposed_calcTokenFromShares(shares, 1e18);
        assertEq(tokens, expectedTokens);
    }

    /// @notice Tests calculation of token amount from shares with a custom rate
    function testCalcTokenFromSharesWithCustomRate() public {
        address otherUser = address(0xBEEF);
        _setupUser(otherUser, 50_000_000);
        vault.deposit(50_000_000);
        vm.stopPrank();

        uint256 shares = 5e18;
        uint256 rate = 2e18;
        uint256 expectedTokens = (shares * rate) / 1e18;
        assertEq(expectedTokens, 10e18);

        uint256 tokens = vault.exposed_calcTokenFromShares(shares, rate);
        assertEq(tokens, expectedTokens);
    }

    /// @notice Tests calculation of buffer value based on TVL (Total Value Locked).
    function testCalcBufferValue() public {
        // Set a fixed TVL
        vm.prank(ORACLE);
        tvlFeed.updateTvl(100_000_000e6);

        // Set the buffer basis points to 100 (1%)
        vm.prank(ADMIN);
        vault.updateBufferBps(100);

        // Calculate buffer value
        uint256 bufferValue = vault.exposed_calcBufferValue();
        assertEq(bufferValue, 1_000_000e6); // 1% of TVL as buffer
    }

    /// @notice Tests calculation of resolver liquidity based on TVL and buffer value.
    function testCalcResolverLiquidity() public {
        // Set up a deposit to establish TVL
        _setupUser(USER, 100_000_000e6);
        vault.deposit(100_000_000e6);
        vm.stopPrank();

        // Set a fixed TVL
        vm.prank(ORACLE);
        tvlFeed.updateTvl(100_000_000e6);

        // Set the buffer basis points to 100 (1%)
        vm.prank(ADMIN);
        vault.updateBufferBps(100);

        // Calculate buffer value
        uint256 bufferValue = vault.exposed_calcBufferValue();
        assertEq(bufferValue, 1_000_000e6); // 1% of TVL as buffer

        // Calculate resolver liquidity
        uint256 resolverLiquidity = vault.exposed_calcResolverLiquidity(bufferValue);
        assertEq(resolverLiquidity, 99_000_000e6); // 100M - 1M buffer
    }

    /// @notice Fuzz test for shares calculation from token amount
    function testFuzzCalcShares(uint256 _amount, uint256 _tvl) public {
        vm.assume(_amount >= MIN_DEPOSIT && _amount <= 1_000_000e6);
        vm.assume(_tvl >= MIN_DEPOSIT && _tvl <= 200_000_000e6);

        address otherUser = address(0xBEEF);
        _setupUser(otherUser, _tvl);
        vault.deposit(_tvl);
        vm.stopPrank();

        vm.prank(ORACLE);
        tvlFeed.updateTvl(_tvl); // Set a random TVL

        uint256 totalSupply = vault.totalSupply();
        uint256 expectedShares = (_amount * 1e12 * totalSupply) / (_tvl * 1e12);
        uint256 shares = vault.exposed_calcSharesFromToken(_amount, 1);

        assertApproxEqAbs(shares, expectedShares, 1e9); //(0.0000000001 in 18 decimals) due to rounding errors on native solidity compare to UD60x18 math
    }

    /// @notice Fuzz test for token calculation from shares and custom rate
    function testFuzzCalcToken(uint256 _shares) public view {
        vm.assume(_shares >= 1e18 && _shares <= 1_000_000_000e18);
        uint256 rate = 2e18;
        uint256 tokensExpected = (_shares * rate) / 1e18;
        uint256 tokens = vault.exposed_calcTokenFromShares(_shares, rate);
        assertEq(tokens, tokensExpected);
    }

    /// @notice Fuzz test to verify the correct calculation of buffer value based on TVL (Total Value Locked).
    function testFuzzCalcBufferValue(uint256 _tvl) public {
        vm.assume(_tvl >= MIN_DEPOSIT && _tvl <= 1_000_000_000e6);
        vm.prank(ORACLE);
        tvlFeed.updateTvl(_tvl);

        // Set buffer basis points to 100 (1%)
        vm.prank(ADMIN);
        vault.updateBufferBps(100);

        uint256 bufferValue = vault.exposed_calcBufferValue();
        assertEq(bufferValue, _tvl / 100); // 1% of TVL as buffer
    }

    /// @notice Fuzz test for resolver liquidity calculation
    function testFuzzCalcResolverLiquidity(uint256 _tvl) public {
        vm.assume(_tvl >= MIN_DEPOSIT && _tvl <= 200_000_000e6);

        _setupUser(USER, _tvl);
        vault.deposit(_tvl);
        vm.stopPrank();

        vm.prank(ORACLE);
        tvlFeed.updateTvl(_tvl); // Set a random TVL

        vm.prank(ADMIN);
        vault.updateBufferBps(100);

        uint256 bufferValue = vault.exposed_calcBufferValue();
        uint256 resolverLiquidity = vault.exposed_calcResolverLiquidity(bufferValue);

        assertEq(resolverLiquidity, _tvl - (_tvl * 100 / 10_000) - vault.amountReadyForWithdraw());
    }

    // --- Fee Calculation Tests ---

    /// @notice Tests performance fee calculation
    function testPerformanceFee() public view {
        uint256 gross = 10_000_000;
        (uint256 fee, uint256 net) = vault.exposed_calcPerformanceFee(gross);
        assertEq(fee, gross / 100);
        assertEq(net, gross - fee);
    }

    /// @notice Fuzz test for performance fee calculation
    function testFuzzPerformanceFee(uint256 _token) public view {
        vm.assume(_token >= MIN_DEPOSIT && _token < 1_000_000e6);
        (uint256 fee, uint256 net) = vault.exposed_calcPerformanceFee(_token);
        assertEq(fee, _token / 100);
        assertEq(net, _token - fee);
    }

    /// @notice Tests maintenance fee calculation over a day
    function testMaintenanceFee() public {
        uint256 tvl = 100_000_000;
        uint256 lastClaim = block.timestamp;
        skip(1 days);
        vm.prank(ORACLE);
        tvlFeed.updateTvl(tvl);

        uint256 fee = vault.exposed_calcMaintenanceFee(lastClaim);

        uint256 tvl18 = tvl * 1e12;
        uint256 elapsed = 1 days;
        uint256 maintenanceFeeAnnual = 100;
        uint256 secondsInYear = 365 days;
        uint256 maintenanceFeePerSecond18pt = (maintenanceFeeAnnual * 1e18) / 10_000 / secondsInYear;
        uint256 expectedFee = (tvl18 * maintenanceFeePerSecond18pt * elapsed) / 1e18;

        assertEq(fee, expectedFee);
    }

    /// @notice Fuzz test for maintenance fee calculation
    function testFuzzMaintenanceFee(uint256 _tvl, uint256 _elapsed) public {
        vm.assume(_tvl > MIN_DEPOSIT && _tvl < 100_000_000e6);
        vm.assume(_elapsed > 0 && _elapsed < 365 days * 10);

        uint256 lastClaim = block.timestamp;
        skip(_elapsed);
        vm.prank(ORACLE);
        tvlFeed.updateTvl(_tvl);

        uint256 fee = vault.exposed_calcMaintenanceFee(lastClaim);

        uint256 tvl18 = _tvl * 1e12;
        uint256 maintenanceFeeAnnual = 100;
        uint256 secondsInYear = 365 days;
        uint256 maintenanceFeePerSecond18pt = (maintenanceFeeAnnual * 1e18) / 10_000 / secondsInYear;
        uint256 expectedFee = (tvl18 * maintenanceFeePerSecond18pt * _elapsed) / 1e18;

        assertEq(fee, expectedFee);
    }

    // --- Revert/Negative Tests ---

    function testUpdateMaxTvlReverts() public {
        vm.prank(ADMIN);
        vm.expectRevert("ShiftManager: zero max TVL");
        vault.updateMaxTvl(0);
    }

    /// @notice Tests that deposit below minimum reverts
    function testDepositBelowMinReverts() public {
        vm.prank(ADMIN);
        vault.manageWhitelist(USER);
        deal(address(token), USER, MIN_DEPOSIT - 1);
        vm.startPrank(USER);
        vault.reqDeposit();
        vm.stopPrank();
        vm.prank(address(tvlFeed));
        vault.allowDeposit(USER, 1);
        vm.startPrank(USER);
        token.approve(address(vault), MIN_DEPOSIT - 1);
        vm.expectRevert("ShiftVault: deposit below minimum");
        vault.deposit(MIN_DEPOSIT - 1);
        vm.stopPrank();
    }

    /// @notice Tests that deposit request from non-whitelisted user reverts
    function testDepositNotWhitelistedReverts() public {
        deal(address(token), USER, INITIAL_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert("ShiftVault: not whitelisted");
        vault.reqDeposit();
        vm.stopPrank();
    }

    /// @notice Tests that withdraw request without shares reverts
    function testWithdrawWithoutSharesReverts() public {
        vm.prank(ADMIN);
        vault.manageWhitelist(USER);
        deal(address(token), USER, INITIAL_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert("ShiftVault: insufficient shares");
        vault.reqWithdraw(1e18);
        vm.stopPrank();
    }
}

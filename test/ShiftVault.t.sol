// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "forge-std/Test.sol";
import "./mocks/MockAccessControl.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockTvlFeed.sol";
import "./mocks/ShiftVaultHarness.sol";

contract ShiftVaultTest is Test {
    MockAccessControl access;
    MockERC20 token;
    MockTvlFeed tvlFeed;
    ShiftVaultHarness vault;

    address constant ADMIN = address(1);
    address constant EXECUTOR = address(2);
    address constant FEE_COLLECTOR = address(3);
    address constant USER = address(4);

    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    uint256 constant MIN_DEPOSIT = 1_000_000;
    uint256 constant INITIAL_BALANCE = 10_000_000;

    /// @notice Sets up the test environment and deploys all mocks and the vault
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        access.grantRole(EXECUTOR_ROLE, EXECUTOR);
        token = new MockERC20(6);
        tvlFeed = new MockTvlFeed();
        vault = new ShiftVaultHarness(
            address(access),
            address(token),
            address(tvlFeed),
            FEE_COLLECTOR,
            MIN_DEPOSIT,
            1_000_000_000,
            1 days
        );
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
        vm.prank(address(tvlFeed));
        vault.allowDeposit(user);
        vm.startPrank(user);
        token.approve(address(vault), amount);
    }

    // --- Deposit & Withdraw Flow Tests ---

    /// @notice Tests the full deposit and withdraw flow for a user
    function testDepositAndWithdrawFlow() public {
        _setupUser(USER, INITIAL_BALANCE);
        tvlFeed.setLastTvl(10_000_000);
        vault.deposit(5_000_000);
        assertEq(vault.balanceOf(USER), 5_000_000 * 1e12);
        assertEq(token.balanceOf(address(vault)), 5_000_000);

        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        vault.sendFundsToResolver(5_000_000);
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
        tvlFeed.setLastTvl(10_000_000);
        vault.deposit(5_000_000);
        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        vault.sendFundsToResolver(5_000_000);
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
        tvlFeed.setLastTvl(10_000_000);
        vault.deposit(5_000_000);
        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
        vault.sendFundsToResolver(5_000_000);
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
        tvlFeed.setLastTvl(10_000_000);
        address otherUser = address(0xBEEF);
        _setupUser(otherUser, 10_000_000);
        vault.deposit(10_000_000);
        vm.stopPrank();

        uint256 amount = 5_000_000;
        uint256 totalSupply = vault.totalSupply();
        uint256 tvl = 10_000_000;
        uint256 expectedShares = (amount * 1e12 * totalSupply) / (tvl * 1e12);

        uint256 shares = vault.exposed_calcSharesFromToken(amount);
        assertEq(shares, expectedShares);
    }

    /// @notice Tests calculation of token amount from shares
    function testCalcTokenFromShares() public {
        tvlFeed.setLastTvl(20_000_000);
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
        tvlFeed.setLastTvl(100_000_000);
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

    /// @notice Fuzz test for shares calculation from token amount
    function testFuzzCalcShares(uint256 amount) public {
        vm.assume(amount >= MIN_DEPOSIT && amount <= 1_000_000_000);
        tvlFeed.setLastTvl(100_000_000);

        address otherUser = address(0xBEEF);
        _setupUser(otherUser, 10_000_000);
        vault.deposit(10_000_000);
        vm.stopPrank();

        uint256 totalSupply = vault.totalSupply();
        uint256 tvl = 100_000_000;
        uint256 expectedShares = (amount * 1e12 * totalSupply) / (tvl * 1e12);
        uint256 shares = vault.exposed_calcSharesFromToken(amount);

        assertEq(shares, expectedShares);
    }

    /// @notice Fuzz test for token calculation from shares and custom rate
    function testFuzzCalcToken(uint256 shares) public view {
        vm.assume(shares >= 1e18 && shares <= 1_000_000_000e18);
        uint256 rate = 2e18;
        uint256 tokensExpected = (shares * rate) / 1e18;
        uint256 tokens = vault.exposed_calcTokenFromShares(shares, rate);
        assertEq(tokens, tokensExpected);
    }

    // --- Fee Calculation Tests ---

    /// @notice Tests performance fee calculation
    function testPerformanceFee() public view {
        uint256 gross = 10_000_000;
        (uint256 fee, uint256 net) = vault.exposed_calcPerformanceFee(gross);
        assertEq(fee, gross / 100);
        assertEq(net, gross - fee);
    }

    /// @notice Tests maintenance fee calculation over a day
    function testMaintenanceFee() public {
        uint256 tvl = 100_000_000;
        tvlFeed.setLastTvl(tvl);
        uint256 lastClaim = block.timestamp;
        skip(1 days);
        uint256 fee = vault.exposed_calcMaintenanceFee(lastClaim);

        uint256 tvl18 = tvl * 1e12;
        uint256 elapsed = 1 days;
        uint256 maintenanceFeeAnnual = 100;
        uint256 secondsInYear = 365 days;
        uint256 maintenanceFeePerSecond18pt = (maintenanceFeeAnnual * 1e18) / 10_000 / secondsInYear;
        uint256 expectedFee = (tvl18 * maintenanceFeePerSecond18pt * elapsed) / 1e18;

        assertApproxEqAbs(fee, expectedFee, 1);
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
        vault.allowDeposit(USER);
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
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

    string constant SHARE_NAME = "Shift LP";
    string constant SHARE_SYMBOL = "SLP";

    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint256 constant MIN_DEPOSIT = 1_000_000;
    uint256 constant INITIAL_BALANCE = 100e6;

    /// @notice Sets up the test environment and deploys all mocks and the vault
    function setUp() public {
        access = new MockAccessControl();
        access.grantRole(0x00, ADMIN);
        access.grantRole(EXECUTOR_ROLE, EXECUTOR);
        access.grantRole(ORACLE_ROLE, ORACLE);
        token = new MockERC20(6);
        tvlFeed = new ShiftTvlFeed(address(access));
        vault = new ShiftVaultHarness(
            address(access), address(token), address(tvlFeed), FEE_COLLECTOR, EXECUTOR, SHARE_NAME, SHARE_SYMBOL, MIN_DEPOSIT, 1_000_000_000e6, 1 days
        );
        vm.startPrank(ADMIN);
        tvlFeed.initialize(address(vault));
        vault.updatePerformanceFee(2000);
        vault.updateMaintenanceFee(200);
        vault.releasePause();
        vm.stopPrank();
    }

    /// @dev Helper to whitelist a user, fund them, and approve the vault
    function _setupUser(address _user, uint256 _tvl, uint256 _amount) internal {
        vm.startPrank(ADMIN);
        address[] memory users = new address[](1);
        users[0] = _user;

        vault.manageWhitelist(users);
        deal(address(token), _user, _amount);
        vm.stopPrank();

        vm.startPrank(_user);
        vault.reqDeposit();
        vm.stopPrank();
        vm.prank(ORACLE);
        tvlFeed.updateTvlForDeposit(_user, _tvl);
        vm.startPrank(_user);
        token.approve(address(vault), _amount);
    }

    // --- Deposit & Withdraw Flow Tests ---

    /// @notice Tests the full deposit and withdraw flow for a user
    function testDepositAndWithdrawFlow() public {
        _setupUser(USER, 0, INITIAL_BALANCE);
        vault.deposit(5_000_000);
        assertEq(vault.balanceOf(USER), 5_000_000 * 1e12);
        assertEq(token.balanceOf(address(EXECUTOR)), 5_000_000);

        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
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
        _setupUser(USER, 0, 1_000_000);
        vault.deposit(1_000_000);
        assertEq(vault.balanceOf(USER), 1_000_000 * 1e12);
        vm.stopPrank();
    }

    /// @notice Tests that a user can deposit twice and receives correct shares and vault balance updates
    function testDoubleDeposit() public {
        _setupUser(USER, 0, INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE);
        assertEq(vault.balanceOf(USER), INITIAL_BALANCE * 1e12);
        assertEq(token.balanceOf(EXECUTOR), INITIAL_BALANCE);

        address[] memory users = new address[](1);
        users[0] = USER;

        vm.stopPrank();
        vm.prank(ADMIN);
        vault.manageWhitelist(users);

        // Deposit again
        uint256 depositAmount = 500e6;
        _setupUser(USER, INITIAL_BALANCE, depositAmount);
        vault.deposit(depositAmount);
        assertEq(vault.balanceOf(USER), (INITIAL_BALANCE + depositAmount) * 1e12);
        assertEq(token.balanceOf(EXECUTOR), INITIAL_BALANCE + depositAmount);
    }

    /// @notice Tests that a double withdraw reverts as expected
    function testDoubleWithdrawReverts() public {
        _setupUser(USER, 0, INITIAL_BALANCE);
        vault.deposit(5_000_000);
        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
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
        _setupUser(USER, 0, INITIAL_BALANCE);
        vault.deposit(5_000_000);
        uint256 shares = vault.balanceOf(USER);
        vault.reqWithdraw(shares);
        vm.stopPrank();

        vm.startPrank(EXECUTOR);
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
        _setupUser(otherUser, 0, 10_000_000);
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
        _setupUser(otherUser, 0, 20_000_000);
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
        _setupUser(otherUser, 0, 50_000_000);
        vault.deposit(50_000_000);
        vm.stopPrank();

        uint256 shares = 5e18;
        uint256 rate = 2e18;
        uint256 expectedTokens = (shares * rate) / 1e18;
        assertEq(expectedTokens, 10e18);

        uint256 tokens = vault.exposed_calcTokenFromShares(shares, rate);
        assertEq(tokens, expectedTokens);
    }

    /// @notice Tests that getSharePrice returns the correct price per share after deposit and TVL update
    function testGetSharePrice() public {
        uint256 tvl = 100_000_000e6;
        uint256 deposit = 200_000_000e6;
        _setupUser(USER, 0, deposit);
        vault.deposit(deposit);
        vm.stopPrank();

        // Set a fixed TVL
        vm.prank(ORACLE);
        tvlFeed.updateTvl(tvl);

        uint256 priceExpected = (tvl * 1e18) / vault.totalSupply();
        uint256 sharePrice = vault.getSharePrice();
        assertEq(sharePrice, priceExpected ); // Convert to 6 decimals for comparison
    }

    /// @notice Fuzz test for shares calculation from token amount
    function testFuzzCalcShares(uint256 _amount, uint256 _tvl) public {
        vm.assume(_amount >= MIN_DEPOSIT && _amount <= 1_000_000e6);
        vm.assume(_tvl >= MIN_DEPOSIT && _tvl <= 200_000_000e6);

        address otherUser = address(0xBEEF);
        _setupUser(otherUser, 0, _tvl);
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
    function testFuzzCalcToken(uint256 _shares, uint256 _rate) public view {
        vm.assume(_shares >= 1e18 && _shares <= 1_000_000_000e18);
        vm.assume(_rate > 0 && _rate <= 1_000_000_000e18);
        uint256 tokensExpected = (_shares * _rate) / 1e18;
        uint256 tokens = vault.exposed_calcTokenFromShares(_shares, _rate);
        assertEq(tokens, tokensExpected);
    }

    // --- Fee Calculation Tests ---

    /// @notice Tests performance fee calculation
    function testPerformanceFee() public view {
        uint256 tvl = 100_000_000e6;
        uint8 decimals = tvlFeed.decimals();
        (uint256 tvl18pt,) = vault.exposed_normalize(tvl, decimals);

        uint256 fee = vault.exposed_calcPerformanceFee(tvl18pt);

        uint256 perfFeeBps = vault.performanceFeeBps();
        uint256 perfFeeRate = (perfFeeBps * 1e18) / 10_000;

        int256 gain = int256(tvl18pt) - int256(vault.exposed_snapshotTvl18pt())
            + int256(vault.exposed_cumulativeWithdrawn()) - int256(vault.exposed_cumulativeDeposit());

        uint256 expectedFee = gain > 0 ? (uint256(gain) * perfFeeRate) / 1e18 : 0;
        assertEq(fee, expectedFee);
    }

    /// @notice Tests maintenance fee calculation over a day
    function testMaintenanceFee() public {
        uint256 tvl = 100_000_000e6;
        uint256 lastClaim = block.timestamp;
        skip(1 days);
        vm.prank(ORACLE);

        uint8 decimals = tvlFeed.decimals();
        (uint256 tvl18pt,) = vault.exposed_normalize(tvl, decimals);

        uint256 fee = vault.exposed_calcMaintenanceFee(lastClaim, tvl18pt);

        uint256 elapsed = 1 days;
        uint256 maintenanceFeeAnnual = vault.maintenanceFeeBpsAnnual();
        uint256 secondsInYear = 365 days;
        uint256 maintenanceFeePerSecond18pt = (maintenanceFeeAnnual * 1e18) / 10_000 / secondsInYear;
        uint256 expectedFee = (tvl18pt * maintenanceFeePerSecond18pt * elapsed) / 1e18;
        assertEq(fee, expectedFee);
    }

    /// @notice Fuzz test for performance fee calculation
    function testFuzzPerformanceFee(uint256 _tvl) public view {
        vm.assume(_tvl >= MIN_DEPOSIT && _tvl < 1_000_000_000e6);
        uint8 decimals = tvlFeed.decimals();
        (uint256 tvl18pt,) = vault.exposed_normalize(_tvl, decimals);

        uint256 fee = vault.exposed_calcPerformanceFee(tvl18pt);

        uint256 perfFeeBps = vault.performanceFeeBps();
        uint256 perfFeeRate = (perfFeeBps * 1e18) / 10_000;

        int256 gain = int256(tvl18pt) - int256(vault.exposed_snapshotTvl18pt())
            + int256(vault.exposed_cumulativeWithdrawn()) - int256(vault.exposed_cumulativeDeposit());

        uint256 expectedFee = gain > 0 ? (uint256(gain) * perfFeeRate) / 1e18 : 0;
        assertGt(fee, 0);
        assertEq(fee, expectedFee);
    }

    /// @notice Fuzz test for maintenance fee calculation
    function testFuzzMaintenanceFee(uint256 _tvl, uint256 _elapsed) public {
        vm.assume(_tvl > MIN_DEPOSIT && _tvl < 1_000_000_000e6);
        vm.assume(_elapsed > 0 && _elapsed < 365 days);

        uint256 lastClaim = block.timestamp;
        skip(_elapsed);
        uint8 decimals = tvlFeed.decimals();
        (uint256 tvl18pt,) = vault.exposed_normalize(_tvl, decimals);

        uint256 fee = vault.exposed_calcMaintenanceFee(lastClaim, tvl18pt);

        uint256 maintenanceFeeAnnual = vault.maintenanceFeeBpsAnnual();
        uint256 secondsInYear = 365 days;
        uint256 maintenanceFeePerSecond18pt = (maintenanceFeeAnnual * 1e18) / 10_000 / secondsInYear;
        uint256 expectedFee = (tvl18pt * maintenanceFeePerSecond18pt * _elapsed) / 1e18;

        assertGt(fee, 0);
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

        address[] memory users = new address[](1);
        users[0] = USER;
        vault.manageWhitelist(users);
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

        address[] memory users = new address[](1);
        users[0] = USER;
        vault.manageWhitelist(users);
        deal(address(token), USER, INITIAL_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert("ShiftVault: insufficient shares");
        vault.reqWithdraw(1e18);
        vm.stopPrank();
    }
}

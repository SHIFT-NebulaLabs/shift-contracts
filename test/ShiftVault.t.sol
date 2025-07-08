// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/ShiftVault.sol";
import "../src/ShiftTvlFeed.sol";
import "../src/ShiftAccessControl.sol";

// === 🟢 Mock base token ===
// Mock ERC20 token used as the base asset for testing
contract ERC20Mock is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1e12); // Initial supply
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

// === 🟢 ShiftVaultTest: Test suite for ShiftVault contract ===
contract ShiftVaultTest is Test {
    ShiftVault vault;
    ShiftTvlFeed tvlFeed;
    ShiftAccessControl access;
    ERC20Mock baseToken;

    address admin        = address(0xA);
    address feeCollector = address(0xF);
    address user         = address(0x1);
    address oracle       = address(0x2);
    address executor     = address(0x3);

    // === 🟢 Setup: Deploy contracts and prepare initial state ===
    function setUp() public {
        access = new ShiftAccessControl(admin);
        baseToken = new ERC20Mock("MockToken", "MOCK", 6);
        tvlFeed = new ShiftTvlFeed(address(access));
        vault = new ShiftVault(address(access), address(baseToken), address(tvlFeed), feeCollector, 1e6, 1e9);

        vm.prank(oracle);
        tvlFeed.initialize(address(vault));

        vm.startPrank(admin);
        access.grantRole(access.ORACLE_ROLE(), oracle);
        access.grantRole(access.EXECUTOR_ROLE(), executor);
        vault.manageWhitelist(user);
        vault.updatePerformanceFee(50);        // 0.5%
        vault.updateMaintenanceFee(200);       // 2%
        vault.releasePause();
        vault.updateMaxTvl(1e15);                // $1 billion
        vm.stopPrank();

        // Mint tokens (extra supply for safety)
        baseToken.mint(user, 5e8);
        baseToken.mint(executor, 5e8);
        vm.prank(user);
        baseToken.approve(address(vault), type(uint256).max);
        vm.prank(executor);
        baseToken.approve(address(vault), type(uint256).max);
    }

    function testDepositFlow() public {
        vm.prank(user);
        vault.reqDeposit();
        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(user, 5e7);
        vm.prank(user);
        vault.deposit(5e7);
        assertGt(vault.balanceOf(user), 0);
    }

    function testWithdrawFullFlow() public {
        testDepositFlow();
        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        vault.reqWithdraw(shares);
        vm.warp(block.timestamp + 1 days);
        vm.prank(executor);
        vault.processWithdraw();
        vm.prank(executor);
        vault.resolveWithdraw(5e7, 1e6);
        vm.prank(user);
        vault.withdraw();
        assertEq(vault.balanceOf(user), 0);
    }

    function testCancelWithdraw() public {
        testDepositFlow();
        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        vault.reqWithdraw(shares);
        vm.prank(user);
        vault.cancelWithdraw();
        (, uint256 amt,,) = vault.getWithdrawStatus();
        assertEq(amt, 0);
    }

    function testWhitelistToggle() public {
        vm.prank(admin);
        vault.manageWhitelist(address(0));
        vm.prank(user);
        vault.reqDeposit();
    }

    function testRevertInvalidDepositFlow() public {
        vm.expectRevert();
        vm.prank(user);
        vault.deposit(1e6);
    }

    function testRevertWithdrawBeforeTime() public {
        testDepositFlow();
        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        vault.reqWithdraw(shares);
        vm.prank(executor);
        vault.processWithdraw();
        vm.prank(executor);
        vault.resolveWithdraw(5e7, 1e6);
        vm.expectRevert();
        vm.prank(user);
        vault.withdraw();
    }

    function testMaintenanceFeeClaiming() public {
        vm.prank(oracle);
        tvlFeed.updateTvl(5e7);
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        vault.claimMaintenanceFee();
        assertGt(vault.balanceOf(feeCollector), 0);
    }

    function testPerformanceFeeCalculation() public {
        uint256 depositAmount = 100_000_000; // $100
        uint256 expectedFee = (depositAmount * 50) / 10_000; // 0.5%

        // Mint extra token to user and feeCollector
        baseToken.mint(user, 1e9); // safety buffer
        baseToken.mint(feeCollector, 1e9);
        baseToken.mint(executor, 1e9);
        vm.prank(user);
        baseToken.approve(address(vault), type(uint256).max);

        // Deposit flow
        vm.prank(user);
        vault.reqDeposit();
        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(user, depositAmount);
        vm.prank(user);
        vault.deposit(depositAmount);

        // Validate shares assigned
        uint256 shares = vault.balanceOf(user);
        require(shares > 0, "No shares assigned to user");

        // Withdraw flow
        vm.prank(user);
        vault.reqWithdraw(shares);
        vm.warp(block.timestamp + 1 days);
        vm.prank(executor);
        vault.processWithdraw();

        // Calculate rate (1:1)
        uint256 rate = (depositAmount * 1e18) / shares;
        vm.prank(executor);
        vault.resolveWithdraw(depositAmount, rate);

        // Fee transfer check
        uint256 before = baseToken.balanceOf(feeCollector);
        vm.prank(user);
        vault.withdraw();
        uint256 earned = baseToken.balanceOf(feeCollector) - before;

        console.log("Expected performance fee:", expectedFee);
        console.log("Actual fee collected:     ", earned);
        assertEq(earned, expectedFee);
    }


    function testMaintenanceFeeExactCalc() public {
        uint256 tvl = 50_000_000;
        uint256 elapsed = 3600;

        vm.prank(oracle);
        tvlFeed.updateTvl(tvl);
        vm.warp(block.timestamp + elapsed);

        uint256 tvl18 = tvl * 1e12;
        uint256 rate = vault.maintenanceFeePerSecond18pt();
        uint256 expected = (tvl18 * rate * elapsed) / 1e18;

        vm.prank(admin);
        vault.claimMaintenanceFee();
        uint256 actual = vault.balanceOf(feeCollector);
        assertEq(actual, expected);
    }

    function testFuzzMaintenanceFeeGeneration(uint256 rawTvl, uint256 rawTime) public {
        uint256 tvlInput = bound(rawTvl, 1e6, 5e12); // Bound TVL between $1 and $5 million, tvl in 6 decimals
        uint256 durationSeconds = bound(rawTime, 3600, 3 days);

        vm.prank(oracle);
        tvlFeed.updateTvl(tvlInput);
        vm.warp(block.timestamp + durationSeconds);

        vm.prank(admin);
        vault.claimMaintenanceFee();
        assertGt(vault.balanceOf(feeCollector), 0);
    }

    function testFuzzPerformanceFeeCalculation(uint256 rawDeposit) public {
        uint256 depositAmount = bound(rawDeposit, 1e6, 1e12); // Bound deposit between $1 and $1 million
        uint256 expectedFee = (depositAmount * 50) / 10_000; // 0.5%

        // Mint extra token to user and feeCollector
        baseToken.mint(user, 1e12); // safety buffer
        baseToken.mint(feeCollector, 1e12);
        baseToken.mint(executor, 1e12);
        vm.prank(user);
        baseToken.approve(address(vault), type(uint256).max);

        // Deposit flow
        vm.prank(user);
        vault.reqDeposit();
        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(user, depositAmount);
        vm.prank(user);
        vault.deposit(depositAmount);

        // Validate shares assigned
        uint256 shares = vault.balanceOf(user);
        require(shares > 0, "No shares assigned to user");

        // Withdraw flow
        vm.prank(user);
        vault.reqWithdraw(shares);
        vm.warp(block.timestamp + 1 days);
        vm.prank(executor);
        vault.processWithdraw();

        // Calculate rate (1:1)
        uint256 rate = (depositAmount * 1e18) / shares;
        vm.prank(executor);
        vault.resolveWithdraw(depositAmount, rate);

        // Fee transfer check
        uint256 before = baseToken.balanceOf(feeCollector);
        vm.prank(user);
        vault.withdraw();
        uint256 earned = baseToken.balanceOf(feeCollector) - before;

        console.log("Expected performance fee:", expectedFee);
        console.log("Actual fee collected:     ", earned);
        assertEq(earned, expectedFee);
    }

   function testMaintenanceFeeLowTvlShortInterval() public {
        vm.prank(oracle);
        tvlFeed.updateTvl(50e6);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        vault.claimMaintenanceFee();
        uint256 fee = vault.balanceOf(feeCollector);
        assertGt(fee, 0);
    }

    function testRevertWithdrawExcessShares() public {
        testDepositFlow();
        uint256 actualShares = vault.balanceOf(user);
        uint256 excessive = actualShares + 1e6;

        vm.prank(user);
        vm.expectRevert("ShiftVault: insufficient shares");
        vault.reqWithdraw(excessive);
    }

    function testRevertResolveWithdrawUnauthorized() public {
        testDepositFlow();
        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        vault.reqWithdraw(shares);
        vm.warp(block.timestamp + 1 days);
        vm.prank(executor);
        vault.processWithdraw();

        vm.prank(user); // non ha EXECUTOR_ROLE
        vm.expectRevert();
        vault.resolveWithdraw(5e7, 1e6);
    }

    function testRevertDepositWithoutBalance() public {
        uint256 depositAmount = 1e6;

        // Rimuoviamo tutti i token dal wallet utente
        vm.startPrank(user);
        baseToken.transfer(address(0xdead), baseToken.balanceOf(user)); // brucia tutto
        baseToken.approve(address(vault), type(uint256).max);
        vault.reqDeposit();
        vm.stopPrank();

        vm.prank(oracle);
        tvlFeed.updateTvlForDeposit(user, depositAmount);

        vm.expectRevert();
        vm.prank(user);
        vault.deposit(depositAmount);
    }

}
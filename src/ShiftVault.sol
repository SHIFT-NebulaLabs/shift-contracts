// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import { IShiftTvlFeed } from "./interface/IShiftTvlFeed.sol";
import { AccessModifier } from "./utils/AccessModifier.sol";
import { ShiftManager } from "./ShiftManager.sol";
import { VALIDITY_DURATION } from "./utils/Constants.sol";

/// @title ShiftVault
/// @notice Manages liquidity and vault operations for the Shift protocol.
/// @dev Inherits from ShiftManager, ERC20, and ReentrancyGuard.
contract ShiftVault is ShiftManager, ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public immutable baseToken;
    IShiftTvlFeed public immutable tvlFeed;

    uint256 public activeUsers;
    uint256 public amountReadyForWithdraw;
    uint256 internal lastMaintenanceFeeClaimedAt;
    uint256 internal currentBatchId;

    mapping(uint256 => BatchState) internal batchWithdrawStates;
    mapping(address => WithdrawState) internal userWithdrawStates;
    mapping(address => DepositState) internal depositStates;

    event DepositRequested(address indexed user);
    event DepositAllowed(address indexed user, uint256 expirationTime);
    event Deposited(address indexed user, uint256 amount);

    struct DepositState {
        bool isPriceUpdated;
        uint256 expirationTime;
    }

    struct WithdrawState {
        uint256 batchId;
        uint256 requestedAt;
        uint256 sharesAmount;
        uint32 timelock;
    }

    struct BatchState {
        uint256 totalShares;
        uint256 rate;
    }

    constructor(
        address _accessControlContract,
        address _tokenContract,
        address _tvlFeedContract,
        address _feeCollector,
        uint256 _minDeposit,
        uint256 _maxTvl,
        uint32 _timeLock
    )
        ShiftManager(_accessControlContract, _feeCollector, _minDeposit, _maxTvl, _timeLock)
        ERC20("Shift LP", "SLP")
    {
        require(_tokenContract != address(0), "ShiftVault: zero token address");
        require(_tvlFeedContract != address(0), "ShiftVault: zero TVL feed address");

        baseToken = ERC20(_tokenContract);
        tvlFeed = IShiftTvlFeed(_tvlFeedContract);

        currentBatchId = 1;
        lastMaintenanceFeeClaimedAt = block.timestamp;
    }

    /// @notice Request a deposit. Only one active request per user.
    function reqDeposit() external nonReentrant notPaused {
        require(isWhitelisted[msg.sender] || !whitelistEnabled, "ShiftVault: not whitelisted");
        DepositState storage state = depositStates[msg.sender];
        require(!state.isPriceUpdated, "ShiftVault: deposit request already exists");
        require(_isExpired(), "ShiftVault: deposit request still valid");

        state.expirationTime = block.timestamp + uint256(VALIDITY_DURATION);
        emit DepositRequested(msg.sender);
    }

    /// @notice Deposit base tokens after a valid request.
    /// @param _tokenAmount Base token amount to deposit.
    function deposit(uint256 _tokenAmount) external nonReentrant notPaused {
        require(_tokenAmount >= minDepositAmount, "ShiftVault: deposit below minimum");
        require(tvlFeed.getLastTvl().value + _tokenAmount <= maxTvl, "ShiftVault: exceeds max TVL");
        DepositState storage state = depositStates[msg.sender];
        require(state.isPriceUpdated && !_isExpired(), "ShiftVault: no valid deposit request");

        state.isPriceUpdated = false; // Reset after deposit
        baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        uint256 shares;
        if (tvlFeed.getLastTvl().value == 0 || totalSupply() == 0) {
            // First deposit: 1:1 mapping to 18 decimals
            (uint256 baseToken18Decimals, ) = _normalize(_tokenAmount, baseToken.decimals());
            shares = baseToken18Decimals;
        } else {
            shares = _calcSharesFromToken(_tokenAmount);
        }
        _mint(msg.sender, shares);

        if (balanceOf(msg.sender) == shares) {
            unchecked { ++activeUsers; }
        }
        emit Deposited(msg.sender, _tokenAmount);
    }

    /// @notice Request withdrawal of LP shares. Only one active request per user.
    /// @param _shareAmount Amount of LP shares to withdraw.
    function reqWithdraw(uint256 _shareAmount) external nonReentrant notPaused {
        require(_shareAmount > 0, "ShiftVault: zero shares");
        require(balanceOf(msg.sender) >= _shareAmount, "ShiftVault: insufficient shares");

        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount == 0, "ShiftVault: withdraw already requested");

        // Transfer shares to the vault
        _transfer(msg.sender, address(this), _shareAmount);

        BatchState storage batchState = batchWithdrawStates[currentBatchId];
        batchState.totalShares += _shareAmount;

        userState.sharesAmount = _shareAmount;
        userState.batchId = currentBatchId;
        userState.requestedAt = block.timestamp;
        userState.timelock = timelock;
    }

    /// @notice Withdraw tokens after batch resolved and timelock passed.
    function withdraw() external nonReentrant notPaused {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        uint256 shares = userState.sharesAmount;
        require(shares > 0, "ShiftVault: no shares to withdraw");
        require(block.timestamp >= userState.requestedAt + uint256(userState.timelock), "ShiftVault: withdrawal locked");

        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        uint256 rate = batchState.rate;
        require(rate > 0, "ShiftVault: batch not resolved");

        uint256 tokenAmount = _calcTokenFromShares(shares, rate);
        (uint256 feeAmount, uint256 userAmount) = _calcPerformanceFee(tokenAmount);

        // Reset user withdrawal state before external calls
        userState.sharesAmount = 0;
        userState.batchId = 0;
        userState.requestedAt = 0;

        // Update batch state
        amountReadyForWithdraw -= shares;

        // Burn shares from vault
        _burn(address(this), shares);

        // Transfer tokens to user and feeCollector
        if (userAmount > 0) baseToken.safeTransfer(msg.sender, userAmount);
        if (feeAmount > 0) baseToken.safeTransfer(feeCollector, feeAmount);

        if (balanceOf(msg.sender) == 0 && activeUsers > 0) {
            unchecked { --activeUsers; }
        }
    }

    /// @notice Cancel a pending withdrawal request if batch not processed.
    function cancelWithdraw() external nonReentrant {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount > 0, "ShiftVault: no withdrawal request to cancel");

        BatchState storage batchState = batchWithdrawStates[userState.batchId];

        // Check if batch is still pending
        if (currentBatchId != userState.batchId){
            require(batchState.rate != 0, "ShiftVault: cannot cancel, withdrawal is processing");
            amountReadyForWithdraw -= userState.sharesAmount;
        }
        // Update batch state before resetting user state
        batchState.totalShares -= userState.sharesAmount;
        // Transfer shares back to user
        _transfer(address(this), msg.sender, userState.sharesAmount);

        // Reset user state
        userState.sharesAmount = 0;
        userState.batchId = 0;
        userState.requestedAt = 0;
    }

    /// @notice Called by TVL feed to allow user deposit after price update.
    /// @param _user User address allowed to deposit.
    function allowDeposit(address _user) external notPaused {
        require(msg.sender == address(tvlFeed), "ShiftVault: caller is not TVL feed");
        DepositState storage state = depositStates[_user];
        if (state.isPriceUpdated || state.expirationTime <= block.timestamp) return;
        state.isPriceUpdated = true;
        emit DepositAllowed(_user, state.expirationTime);
    }

    /// @notice Claim maintenance fee. Only admin.
    function claimMaintenanceFee() external onlyAdmin {
        uint256 lastClaimed = lastMaintenanceFeeClaimedAt;
        uint256 nowTs = block.timestamp;
        require(nowTs > lastClaimed, "ShiftVault: already claimed for this period");

        uint256 feeAmount = _calcMaintenanceFee(lastClaimed);
        if (feeAmount == 0) return;

        lastMaintenanceFeeClaimedAt = nowTs;
        _mint(feeCollector, feeAmount);
    }

    /// @notice Process current withdrawal batch. Only executor.
    function processWithdraw() external onlyExecutor notPaused {
        BatchState storage batchState = batchWithdrawStates[currentBatchId];
        require(batchState.rate == 0, "ShiftVault: batch already resolved");

        // Move to next batch only if shares to process
        if (batchState.totalShares > 0) {
            ++currentBatchId;
        }
    }

    /// @notice Resolve withdrawal batch by setting rate and transferring tokens in.
    /// @param _tokenAmount Tokens to transfer in for withdrawals.
    /// @param _rate Conversion rate for the batch.
    function resolveWithdraw(uint256 _tokenAmount, uint256 _rate) external onlyExecutor nonReentrant notPaused {
        require(_rate > 0, "ShiftVault: invalid rate");

        uint256 batchId = currentBatchId - 1;
        BatchState storage batchState = batchWithdrawStates[batchId];
        require(batchState.rate == 0, "ShiftVault: batch already resolved");

        uint256 totalShares = batchState.totalShares;
        if (totalShares > 0) {
            amountReadyForWithdraw += totalShares;
            batchState.rate = _rate;
            if (_tokenAmount > 0) {
                baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
            }
        }
    }

    /// @notice Send funds to resolver. Only executor.
    /// @param _tokenAmount Amount of tokens to send.
    function sendFundsToResolver(uint256 _tokenAmount) external onlyExecutor nonReentrant notPaused {
        require(_tokenAmount > 0, "ShiftVault: amount is zero");
        baseToken.safeTransfer(msg.sender, _tokenAmount);
    }

    /// @notice Update the maximum TVL allowed in the vault. Only admin.
    /// @param _amount New maximum TVL value.
    function updateMaxTvl(uint256 _amount) public override onlyAdmin {
        uint256 currentTvl = tvlFeed.getLastTvl().value;
        require(_amount <= currentTvl, "ShiftVault: new max TVL below current TVL");
        super.updateMaxTvl(_amount);
    }

    // =========================
    // View functions
    // =========================

    /// @notice Get user withdrawal request status.
    /// @return status 0: none, 1: pending batch, 2: timelock active, 3: ready
    /// @return shareAmount Shares requested for withdrawal.
    /// @return tokenAmount Tokens to be received.
    /// @return unlockTime Withdrawal unlock timestamp.
    function getWithdrawStatus() external view returns (
        uint8 status,
        uint256 shareAmount,
        uint256 tokenAmount,
        uint256 unlockTime
    ) {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        uint256 shares = userState.sharesAmount;
        if (shares == 0) return (0, 0, 0, 0); // No withdrawal requested

        uint256 batchId = userState.batchId;
        uint256 rate = batchWithdrawStates[batchId].rate;
        uint256 unlkTime = userState.requestedAt + uint256(timelock);

        if (rate == 0) return (1, shares, 0, unlkTime); // Pending batch resolution

        uint256 tkAmount = _calcTokenFromShares(shares, rate);
        if (block.timestamp < unlkTime) return (2, shares, tkAmount, unlkTime); // Timelock active

        return (3, shares, tkAmount, unlkTime); // Ready to process
    }

    /// @notice Get total shares in previous withdrawal batch. Only executor.
    function getBatchWithdrawAmount() external view onlyExecutor returns (uint256) {
        return batchWithdrawStates[currentBatchId - 1].totalShares;
    }

    // =========================
    // Internal/private functions
    // =========================

    /// @notice Calculate shares to mint for given token deposit.
    /// @param _tokenAmount Base tokens deposited.
    function _calcSharesFromToken(uint256 _tokenAmount) internal view returns (uint256) {
        (uint256 baseToken18Decimals, ) = _normalize(_tokenAmount, baseToken.decimals());
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());

        UD60x18 ratio = ud(baseToken18Decimals).div(ud(tvl18Decimals));
        UD60x18 shares = ratio.mul(ud(totalSupply()));
        return shares.unwrap(); // UD60x18 to uint256 (18 decimals)
    }

    /// @notice Calculate tokens to return for share amount and rate.
    /// @param _shareAmount LP shares.
    /// @param _rate Conversion rate (6 decimals).
    function _calcTokenFromShares(uint256 _shareAmount, uint256 _rate) internal view returns (uint256) {
        (, uint8 baseTokenDecimalsTo18) = _normalize(_shareAmount, baseToken.decimals());
        (uint256 rate18Decimals, ) = _normalize(_rate, tvlFeed.decimals());

        UD60x18 ratio = ud(rate18Decimals);
        UD60x18 tokenAmount = ratio.mul(ud(_shareAmount));
        return baseTokenDecimalsTo18 == 0 ? tokenAmount.unwrap() : tokenAmount.unwrap() / 10**baseTokenDecimalsTo18; // UD60x18 to uint256 (token decimals)
    }

    /// @notice Normalize amount to 18 decimals.
    /// @param _amount Amount to normalize.
    /// @param _decimals Token decimals.
    /// @return amount Normalized amount.
    /// @return scaleFactor Decimals scaled.
    function _normalize(uint256 _amount, uint8 _decimals) internal view returns (uint256 amount, uint8 scaleFactor) {
        amount = _decimals == decimals() ? _amount : _amount * 10**(decimals() - _decimals);
        scaleFactor = _decimals < decimals() ? decimals() - _decimals : 0;
    }

    /// @notice Calculate performance fee and user amount.
    /// @param _tokenAmount Total token amount.
    /// @return feeAmount Fee amount.
    /// @return userAmount User amount after fee.
    function _calcPerformanceFee(uint256 _tokenAmount) internal view returns (uint256 feeAmount, uint256 userAmount) {
        UD60x18 fee = ud(_tokenAmount).mul(ud(performanceFee18pt)); // 1% fee
        feeAmount = fee.unwrap(); // UD60x18 to uint256 (18 decimals)
        userAmount = ud(_tokenAmount).sub(fee).unwrap();
    }

    /// @notice Calculate maintenance fee since last claim.
    /// @param _lastClaimTimestamp Last claim timestamp.
    /// @return Maintenance fee to mint.
    function _calcMaintenanceFee(uint256 _lastClaimTimestamp) internal view returns (uint256) {
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());
        uint256 elapsed = block.timestamp - _lastClaimTimestamp;
        return (tvl18Decimals * maintenanceFeePerSecond18pt * elapsed) / 1e18;
    }

    /// @notice Check if user's deposit request expired.
    /// @return True if expired, false otherwise.
    function _isExpired() internal view returns(bool) {
        return depositStates[msg.sender].expirationTime < block.timestamp;
    }
}
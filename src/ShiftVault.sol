// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {IShiftTvlFeed} from "./interface/IShiftTvlFeed.sol";
import {AccessModifier} from "./utils/AccessModifier.sol";
import {ShiftManager} from "./ShiftManager.sol";
import {REQUEST_VALIDITY, FRESHNESS_VALIDITY} from "./utils/Constants.sol";

/// @title ShiftVault
/// @notice Manages liquidity and vault operations for the Shift protocol.
/// @dev Inherits from ShiftManager, ERC20, and ReentrancyGuard.
contract ShiftVault is ShiftManager, ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public immutable baseToken;
    IShiftTvlFeed public immutable tvlFeed;

    uint256 public activeUsers;
    uint256 public availableForWithdraw;
    uint256 internal cumulativeDeposit;
    uint256 internal cumulativeWithdrawn;
    uint256 internal snapshotTvl18pt;
    uint256 internal lastMaintenanceFeeClaimedAt;
    uint256 internal currentBatchId;

    mapping(uint256 => BatchState) internal batchWithdrawStates;
    mapping(address => WithdrawState) internal userWithdrawStates;
    mapping(address => DepositState) internal userDepositStates;

    event DepositRequested(address indexed user);
    event DepositAllowed(address indexed user, uint256 expirationTime);
    event Deposited(address indexed user, uint256 amount);

    struct DepositState {
        bool isPriceUpdated;
        uint256 expirationTime;
        uint256 requestIndex;
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
        string memory _shareName,
        string memory _shareSymbol,
        uint256 _minDeposit,
        uint256 _maxTvl,
        uint32 _timeLock
    ) ShiftManager(_accessControlContract, _feeCollector, _minDeposit, _maxTvl, _timeLock) ERC20(_shareName, _shareSymbol) {
        require(_tokenContract != address(0), "ShiftVault: zero token address");
        require(_tvlFeedContract != address(0), "ShiftVault: zero TVL feed address");

        baseToken = ERC20(_tokenContract);
        tvlFeed = IShiftTvlFeed(_tvlFeedContract);
        require(baseToken.decimals() <= 18, "ShiftVault: base token decimals > 18");
        require(tvlFeed.decimals() <= 18, "ShiftVault: TVL feed decimals > 18");

        batchWithdrawStates[currentBatchId].rate = 1;
        currentBatchId = 1;
        lastMaintenanceFeeClaimedAt = block.timestamp;
    }

    // =========================
    // Write functions
    // =========================

    /// @notice Request a deposit. Only one active request per user.
    function reqDeposit() external nonReentrant notPaused {
        require(isWhitelisted[msg.sender] || !whitelistEnabled, "ShiftVault: not whitelisted");
        DepositState storage state = userDepositStates[msg.sender];
        if (_isExpired()) state.isPriceUpdated = false; // Reset if expired, to allow new request

        require(!state.isPriceUpdated, "ShiftVault: deposit request already exists");
        require(_isExpired(), "ShiftVault: deposit request still valid");

        state.expirationTime = block.timestamp + uint256(REQUEST_VALIDITY);
        emit DepositRequested(msg.sender);
    }

    /// @notice Deposit base tokens after a valid request.
    /// @param _tokenAmount Base token amount to deposit.
    function deposit(uint256 _tokenAmount) external nonReentrant notPaused {
        require(_tokenAmount >= minDepositAmount, "ShiftVault: deposit below minimum");
        DepositState storage state = userDepositStates[msg.sender];
        require(state.isPriceUpdated && !_isExpired(), "ShiftVault: no valid deposit request");

        // Reset state before external call for safety
        state.isPriceUpdated = false;
        state.expirationTime = 0;

        // Handle fee-on-transfer tokens efficiently
        uint256 balanceBefore = baseToken.balanceOf(address(this));
        baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        uint256 actualAmount = baseToken.balanceOf(address(this)) - balanceBefore;
        require(actualAmount > 0, "ShiftVault: zero actual deposit");

        uint256 tvl = tvlFeed.getTvlEntry(state.requestIndex).value;
        // Normalize values once for efficiency
        (uint256 tvl18pt,) = _normalize(tvl, tvlFeed.decimals());
        (uint256 maxTvl18pt,) = _normalize(maxTvl, tvlFeed.decimals());
        (uint256 baseToken18pt,) = _normalize(actualAmount, baseToken.decimals());

        require(tvl18pt + baseToken18pt <= maxTvl18pt, "ShiftVault: exceeds max TVL");

        uint256 shares =  _calcSharesFromToken(actualAmount, state.requestIndex);

        require(shares > 0, "ShiftVault: zero shares calculated");
        _mint(msg.sender, shares);

        cumulativeDeposit += actualAmount;

        // Only increment activeUsers if this is the user's first deposit
        if (balanceOf(msg.sender) == shares) {
            unchecked {
                ++activeUsers;
            }
        }
        emit Deposited(msg.sender, actualAmount);
    }

    /// @notice Request withdrawal of LP shares. Only one active request per user.
    /// @param _shareAmount Amount of LP shares to withdraw.
    function reqWithdraw(uint256 _shareAmount) external nonReentrant notPaused {
        require(_shareAmount > 0, "ShiftVault: zero shares");
        require(isWhitelisted[msg.sender] || !whitelistEnabled, "ShiftVault: not whitelisted");
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

        uint256 unlockTime = userState.requestedAt + uint256(userState.timelock);
        require(block.timestamp >= unlockTime, "ShiftVault: withdrawal locked");

        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        uint256 rate = batchState.rate;
        require(rate > 0, "ShiftVault: batch not resolved");

        uint256 tokenAmount = _calcTokenFromShares(shares, rate);
        require(tokenAmount > 0, "ShiftVault: zero token calculated");

        // Effects: update state before external calls
        userState.sharesAmount = 0;
        userState.batchId = 0;
        userState.requestedAt = 0;

        availableForWithdraw -= tokenAmount;
        cumulativeWithdrawn += tokenAmount;

        _burn(address(this), shares);

        if (balanceOf(msg.sender) == 0 && activeUsers > 0) {
            unchecked {
                --activeUsers;
            }
        }

        // Interactions
        baseToken.safeTransfer(msg.sender, tokenAmount);
    }

    /// @notice Cancel a pending withdrawal request if batch not processed.
    function cancelWithdraw() external nonReentrant notPaused {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount > 0, "ShiftVault: no withdrawal request to cancel");
        require(currentBatchId == userState.batchId, "ShiftVault: batch already processed or ongoing");

        // Update batch state before resetting user state
        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        batchState.totalShares -= userState.sharesAmount;
        // Transfer shares back to user
        _transfer(address(this), msg.sender, userState.sharesAmount);

        // Reset user state
        userState.sharesAmount = 0;
        userState.batchId = 0;
        userState.requestedAt = 0;
    }

    // =========================
    // Admin / Oracle functions
    // =========================

    /// @notice Called by TVL feed to allow user deposit after price update.
    /// @param _user User address allowed to deposit.
    function allowDeposit(address _user, uint256 _tvlIndex) external nonReentrant notPaused {
        require(msg.sender == address(tvlFeed), "ShiftVault: caller is not TVL feed");
        DepositState storage state = userDepositStates[_user];
        require(!state.isPriceUpdated, "ShiftVault: deposit already allowed");
        require(state.expirationTime > block.timestamp, "ShiftVault: deposit request expired");

        state.isPriceUpdated = true;
        state.requestIndex = _tvlIndex;
        emit DepositAllowed(_user, state.expirationTime);
    }

    /// @notice Claim maintenance fee. Only admin.
    function claimMaintenanceFee() public onlyAdmin {
        uint256 lastClaimed = lastMaintenanceFeeClaimedAt;
        uint256 nowTs = block.timestamp;
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        require(nowTs - lastTvl.timestamp < FRESHNESS_VALIDITY, "ShiftVault: stale TVL data");
        if (lastTvl.value == 0 && lastTvl.supplySnapshot == 0) return; // During initial setup

        require(nowTs > lastClaimed, "ShiftVault: already claimed for this period");

        lastMaintenanceFeeClaimedAt = nowTs;
        (uint256 tvl18pt,) = _normalize(lastTvl.value, tvlFeed.decimals());
        uint256 feeAmount = _calcMaintenanceFee(lastClaimed, tvl18pt);
        if (feeAmount == 0) return;

        uint256 share = _calcShare(feeAmount, tvl18pt, lastTvl.supplySnapshot);
        _mint(feeCollector, share);
    }

    /// @notice Claim performance fee. Only admin.
    function claimPerformanceFee() public onlyAdmin {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        require(block.timestamp - lastTvl.timestamp < FRESHNESS_VALIDITY, "ShiftVault: stale TVL data");
        if (lastTvl.value == 0 && lastTvl.supplySnapshot == 0) return; // During initial setup

        (uint256 tvl18pt,) = _normalize(lastTvl.value, tvlFeed.decimals());
        uint256 feeAmount = _calcPerformanceFee(tvl18pt);
        uint256 share = _calcShare(feeAmount, tvl18pt, lastTvl.supplySnapshot);

        snapshotTvl18pt = tvl18pt;
        cumulativeDeposit = 0;
        cumulativeWithdrawn = 0;
        _mint(feeCollector, share);
    }

    // Overridden functions

    /// @notice Update the maximum TVL allowed in the vault. Only admin.
    /// @param _amount New maximum TVL value.
    function updateMaxTvl(uint256 _amount) public override onlyAdmin {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        require(block.timestamp - lastTvl.timestamp < FRESHNESS_VALIDITY, "ShiftVault: stale TVL data");
        require(_amount >= lastTvl.value, "ShiftVault: new max TVL below current TVL");

        super.updateMaxTvl(_amount);
    }

    /// @notice Updates the annual maintenance fee for the vault. Only callable by the admin.
    /// @dev Claims any pending maintenance fees before updating the fee.
    /// @param _annualFeeBps The new annual maintenance fee, expressed in basis points (bps).
    function updateMaintenanceFee(uint16 _annualFeeBps) public override onlyAdmin {
        claimMaintenanceFee();
        super.updateMaintenanceFee(_annualFeeBps);
    }

    /// @notice Updates the performance fee for the vault. Only callable by the admin.
    /// @dev Claims any pending performance fees before updating the fee.
    /// @param _performanceFeeBps The new performance fee, expressed in basis points (bps).
    function updatePerformanceFee(uint16 _performanceFeeBps) public override onlyAdmin {
        claimPerformanceFee();
        super.updatePerformanceFee(_performanceFeeBps);
    }

    // =========================
    // Executor functions
    // =========================

    /// @notice Process current withdrawal batch. Only executor.
    function processWithdraw() external onlyExecutor notPaused {
        require(batchWithdrawStates[currentBatchId - 1].rate != 0, "ShiftVault: previous batch not resolved");

        // Move to next batch only if shares to process
        if (batchWithdrawStates[currentBatchId].totalShares > 0) {
            ++currentBatchId;
        }
    }

    /// @notice Resolve withdrawal batch by setting rate and transferring tokens in.
    /// @param _tokenAmount Tokens to transfer in for withdrawals.
    /// @param _rate Conversion rate for the batch with TVL precision.
    function resolveWithdraw(uint256 _tokenAmount, uint256 _rate) external onlyExecutor nonReentrant notPaused {
        require(_rate > 0, "ShiftVault: invalid rate");

        uint256 batchId = currentBatchId - 1;
        BatchState storage batchState = batchWithdrawStates[batchId];
        require(batchState.rate == 0, "ShiftVault: batch already resolved");

        uint256 requiredTokens = _calcTokenFromShares(batchState.totalShares, _rate);

        uint256 balanceBefore = baseToken.balanceOf(address(this));
        baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        uint256 actualAmount = baseToken.balanceOf(address(this)) - balanceBefore;
        require(actualAmount >= requiredTokens, "ShiftVault: insufficient tokens for batch");

        availableForWithdraw += actualAmount;
        batchState.rate = _rate;
    }

    /// @notice Transfer available liquidity to the executor. Only executor.
    function retrieveLiquidity() external onlyExecutor nonReentrant notPaused {
        uint256 liquidity = _calcResolverLiquidity(_calcBufferValue());
        baseToken.safeTransfer(msg.sender, liquidity);
    }

    // =========================
    // View functions
    // =========================

    /// @notice Get user withdrawal request status.
    /// @return status 0: none, 1: pending batch, 2: timelock active, 3: ready
    /// @return shareAmount Shares requested for withdrawal.
    /// @return tokenAmount Tokens to be received.
    /// @return unlockTime Withdrawal unlock timestamp.
    function getWithdrawStatus()
        external
        view
        returns (uint8 status, uint256 shareAmount, uint256 tokenAmount, uint256 unlockTime)
    {
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

    /// @notice Returns the total shares in the previous withdrawal batch.
    /// @return The total shares in the relevant withdrawal batch.
    function getBatchWithdrawAmount() external view onlyExecutor returns (uint256) {
        if (batchWithdrawStates[currentBatchId - 1].rate == 0) {
            return batchWithdrawStates[currentBatchId - 1].totalShares;
        } else {
            return batchWithdrawStates[currentBatchId].totalShares;
        }
    }

    /// @notice Returns the current resolver liquidity and buffer amount available for withdrawal processing.
    /// @return reqInvest True if there is base token liquidity available for resolver (excluding buffer and pending withdrawals).
    /// @return bufferAmount Amount of base tokens held as buffer.
    function getVaultData() external view onlyExecutor returns (bool reqInvest, uint256 bufferAmount) {
        bufferAmount = _calcBufferValue();
        reqInvest = _calcResolverLiquidity(bufferAmount) > 0;
    }

    /**
     * @notice Calculates and returns the current share price based on the latest TVL data.
     * @return The current share price as a uint256 value, normalized to the TVL decimals.
     */
    function getSharePrice() external view returns (uint256) {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        require(block.timestamp - lastTvl.timestamp < FRESHNESS_VALIDITY, "ShiftVault: stale TVL data");
        (uint256 tvl18pt, uint8 tvlScaleFactor) = _normalize(lastTvl.value, tvlFeed.decimals());

        if (lastTvl.supplySnapshot == 0) return 0;

        UD60x18 sharePrice = ud(tvl18pt).div(ud(lastTvl.supplySnapshot));
        return tvlScaleFactor == 0 ? sharePrice.unwrap() : sharePrice.unwrap() / 10 ** tvlScaleFactor; // UD60x18 to uint256 (tvl decimals)
    }

    // =========================
    // Internal/private functions
    // =========================

    /// @notice Calculate shares to mint for a given token deposit based on TVL at request time.
    /// @param _tokenAmount Amount of base tokens deposited.
    /// @param _tvlIndex TVL feed index at the time of deposit request.
    /// @return Number of shares to mint (18 decimals).
    function _calcSharesFromToken(uint256 _tokenAmount, uint256 _tvlIndex) internal view returns (uint256) {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getTvlEntry(_tvlIndex);
        (uint256 baseToken18pt,) = _normalize(_tokenAmount, baseToken.decimals());
        if (lastTvl.supplySnapshot == 0) {
            return baseToken18pt; // If no supply, return token amount as shares
        }
        (uint256 tvl18pt,) = _normalize(lastTvl.value, tvlFeed.decimals());
        return _calcShare(baseToken18pt, tvl18pt, lastTvl.supplySnapshot);
    }

    /// @notice Calculates shares to mint for a deposit based on TVL at request time.
    /// @dev Uses UD60x18 fixed-point math for precise calculations. The formula is: shares = (depositAmount * totalSupply) / TVL.
    /// @param _amount18pt The amount of base tokens deposited, expressed in 18 decimal places.
    /// @param _tvl18pt The total value locked at the time of deposit, expressed in 18 decimal places.
    /// @return The number of shares to mint, as a uint256 with 18 decimals.
    function _calcShare(uint256 _amount18pt, uint256 _tvl18pt, uint256 _totalSupply) internal pure returns (uint256) {
        require(_tvl18pt > 0, "ShiftVault: TVL must be greater than zero");
        UD60x18 shares = ud(_amount18pt).mul(ud(_totalSupply)).div(ud(_tvl18pt));
        return shares.unwrap(); // UD60x18 to uint256 (18 decimals)
    }

    /// @notice Calculate tokens to return for share amount and rate.
    /// @param _shareAmount LP shares.
    /// @param _rate Conversion rate (6 decimals).
    function _calcTokenFromShares(uint256 _shareAmount, uint256 _rate) internal view returns (uint256) {
        (, uint8 baseTokenScaleFactor) = _normalize(1, baseToken.decimals()); // Only to retrieve missing decimals from base token
        (uint256 rate18pt,) = _normalize(_rate, tvlFeed.decimals());

        UD60x18 tokenAmount = ud(rate18pt).mul(ud(_shareAmount));
        return baseTokenScaleFactor == 0 ? tokenAmount.unwrap() : tokenAmount.unwrap() / 10 ** baseTokenScaleFactor; // UD60x18 to uint256 (token decimals)
    }

    /// @notice Calculates the performance fee based on the latest TVL, all-time deposits, and withdrawals.
    /// @param _tvl18pt The latest TVL value normalized to 18 decimals.
    /// @return feeAmount The calculated performance fee amount (18 decimals).
    function _calcPerformanceFee(uint256 _tvl18pt) internal view returns (uint256) {
        if (performanceFee18pt == 0) return 0; // No fee if zero rate
        (uint256 cumulativeDeposit18pt,) = _normalize(cumulativeDeposit, baseToken.decimals());
        (uint256 cumulativeWithdrawn18pt,) = _normalize(cumulativeWithdrawn, baseToken.decimals());

        int256 gain18pt =
            int256(_tvl18pt) - int256(snapshotTvl18pt) + int256(cumulativeDeposit18pt) - int256(cumulativeWithdrawn18pt);
        require(gain18pt > 0, "ShiftVault: no performance fee to claim");
        UD60x18 feeAmount = ud(uint256(gain18pt)).mul(ud(performanceFee18pt));
        return feeAmount.unwrap();
    }

    /// @notice Calculate maintenance fee since last claim.
    /// @param _lastClaimTimestamp Last claim timestamp.
    /// @return Maintenance fee value.
    function _calcMaintenanceFee(uint256 _lastClaimTimestamp, uint256 _tvl18pt) internal view returns (uint256) {
        if (maintenanceFeePerSecond18pt == 0) return 0; // No fee if zero rate
        uint256 elapsed = block.timestamp - _lastClaimTimestamp;
        return (_tvl18pt * maintenanceFeePerSecond18pt * elapsed) / 1e18;
    }

    /// @notice Calculates the buffer value based on the current TVL and buffer basis points.
    /// @dev Uses normalized TVL and base token decimals to compute the buffer value.
    ///      Returns 0 if bufferBps is zero, otherwise calculates the buffer as a proportion of TVL.
    /// @return The buffer value to mint, adjusted for base token decimals.
    function _calcBufferValue() internal view returns (uint256) {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        require(block.timestamp - lastTvl.timestamp < FRESHNESS_VALIDITY, "ShiftVault: stale TVL data");
        (uint256 tvl18pt,) = _normalize(lastTvl.value, tvlFeed.decimals());
        (, uint8 baseTokenScaleFactor) = _normalize(1, baseToken.decimals()); // Only to retrieve missing decimals from base token

        if (bufferBps == 0) return 0; // No buffer, return TVL only

        UD60x18 buffer = ud(tvl18pt).mul(ud(buffer18pt)).div(ud(1e18));
        return baseTokenScaleFactor == 0 ? buffer.unwrap() : buffer.unwrap() / 10 ** baseTokenScaleFactor;
    }

    /// @notice Calculates the available liquidity for the resolver, excluding the buffer and withdrawable amounts.
    /// @dev Returns zero if the calculated liquidity exceeds the contract's token balance.
    /// @param _bufferAmount The amount to be reserved as a buffer and excluded from liquidity.
    /// @return The amount of liquidity available for the resolver.
    function _calcResolverLiquidity(uint256 _bufferAmount) internal view returns (uint256) {
        uint256 balance = baseToken.balanceOf(address(this));
        uint256 required = availableForWithdraw + _bufferAmount;

        return balance > required ? balance - required : 0;
    }

    /// @notice Check if user's deposit request expired.
    /// @return True if expired, false otherwise.
    function _isExpired() internal view returns (bool) {
        return userDepositStates[msg.sender].expirationTime < block.timestamp;
    }

    /// @notice Normalize amount to 18 decimals.
    /// @param _amount Amount to normalize.
    /// @param _decimals Token decimals.
    /// @return amount Normalized amount.
    /// @return scaleFactor Decimals scaled.
    function _normalize(uint256 _amount, uint8 _decimals) internal view returns (uint256 amount, uint8 scaleFactor) {
        scaleFactor = _decimals < decimals() ? decimals() - _decimals : 0;

        if (scaleFactor > 0) {
            uint256 factor = 10 ** scaleFactor;
            require(_amount <= type(uint256).max / factor, "ShiftVault: overflow on normalization");
            amount = _amount * factor;
        } else {
            // Same decimals, no scaling needed
            amount = _amount;
        }
    }
}

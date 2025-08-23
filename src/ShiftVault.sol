// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {IShiftTvlFeed} from "./interface/IShiftTvlFeed.sol";
import {AccessModifier} from "./utils/AccessModifier.sol";
import {ShiftManager} from "./ShiftManager.sol";
import {ShiftVaultArgs} from "./utils/Structs.sol";
import {
    ZeroAddress,
    MoreThan18Decimals,
    NotWhitelisted,
    AlreadyRequested,
    RequestStillValid,
    DepositBelowMinimum,
    NoValidRequest,
    ZeroToken,
    ExceedsMaxTVL,
    ZeroCalculated,
    NoSharesToWithdraw,
    Locked,
    BatchNotResolved,
    NoValidRequest,
    BatchResolvedOrOngoing,
    NotTVLFeed,
    AlreadyAllowed,
    RequestExpired,
    NoDustToSweep,
    StaleTvlData,
    NewMaxTVLBelowCurrentTVL,
    BatchNotResolved,
    BatchResolved,
    InsufficientTokensForBatch,
    OverflowOnNormalization,
    AlreadyClaimed,
    ParamOutOfBounds
} from "./utils/Errors.sol";
import {MINIMUM_LIQUIDITY, BURN_ADDRESS} from "./utils/Constants.sol";

/// @title ShiftVault
/// @notice Manages liquidity and vault operations for the Shift protocol.
/// @dev Inherits from ShiftManager, ERC20, and ReentrancyGuard.
contract ShiftVault is ShiftManager, ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public immutable baseToken;
    IShiftTvlFeed public immutable tvlFeed;

    int256 public profitValue; // Profit value in tvl decimals
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
    event WithdrawRequested(address indexed user, uint256 shareAmount);
    event Withdrawn(address indexed user, uint256 amount);
    event WithdrawCanceled(address indexed user, uint256 shareAmount);

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

    /**
     * @notice Initializes the ShiftVault contract with protocol parameters and sets up the initial state.
     * @param _args Struct containing initialization parameters:
     *   - tokenContract: Address of the base ERC20 token accepted by the vault.
     *   - tvlFeedContract: Address of the TVL oracle/feed contract.
     *   - shareName: Name of the ERC20 LP share token.
     *   - shareSymbol: Symbol of the ERC20 LP share token.
     *   - managerArgs: Arguments for the ShiftManager base contract.
     */
    constructor(ShiftVaultArgs memory _args)
        ShiftManager(_args.managerArgs)
        ERC20(_args.shareName, _args.shareSymbol)
    {
        require(_args.tokenContract != address(0), ZeroAddress());
        require(_args.tvlFeedContract != address(0), ZeroAddress());

        baseToken = ERC20(_args.tokenContract);
        tvlFeed = IShiftTvlFeed(_args.tvlFeedContract);
        require(baseToken.decimals() <= 18, MoreThan18Decimals());

        batchWithdrawStates[currentBatchId].rate = 1;
        currentBatchId = 1;
        lastMaintenanceFeeClaimedAt = block.timestamp;
    }

    // =========================
    // Write functions
    // =========================

    /// @notice Request a deposit. Only one active request per user.
    function reqDeposit() external nonReentrant notPaused {
        require(isWhitelisted[msg.sender] || !whitelistEnabled, NotWhitelisted());
        DepositState storage state = userDepositStates[msg.sender];
        if (_isExpired()) delete userDepositStates[msg.sender]; // Reset if expired, to allow new request

        require(!state.isPriceUpdated, AlreadyRequested());
        require(_isExpired(), RequestStillValid());

        state.expirationTime = block.timestamp + uint256(requestValidity);
        emit DepositRequested(msg.sender);
    }

    /// @notice Deposit base tokens after a valid request.
    /// @param _tokenAmount Base token amount to deposit.
    function deposit(uint256 _tokenAmount) external nonReentrant notPaused {
        require(_tokenAmount >= minDepositAmount, DepositBelowMinimum());
        DepositState storage state = userDepositStates[msg.sender];
        require(state.isPriceUpdated && !_isExpired(), NoValidRequest());

        // Reset state before external call for safety
        uint256 requestIndex = state.requestIndex;
        delete userDepositStates[msg.sender];

        // Handle fee-on-transfer tokens efficiently
        uint256 balanceBefore = baseToken.balanceOf(executor);
        baseToken.safeTransferFrom(msg.sender, executor, _tokenAmount);
        uint256 actualAmount = baseToken.balanceOf(executor) - balanceBefore;
        require(actualAmount > 0, ZeroToken());

        IShiftTvlFeed.TvlData memory tvl = tvlFeed.getTvlEntry(requestIndex);
        // Normalize values once for efficiency
        (uint256 tvl18pt,) = _normalize(tvl.value, tvlFeed.decimals());
        (uint256 baseToken18pt,) = _normalize(actualAmount, baseToken.decimals());

        require(tvl.value + actualAmount <= maxTvl, ExceedsMaxTVL());

        uint256 shares = _calcSharesFromToken(baseToken18pt, tvl18pt, tvl.supplySnapshot);

        require(shares > 0, ZeroCalculated());

        // Permanently lock a small amount of LP tokens to prevent full pool drain and ratio manipulation.
        if (tvl.supplySnapshot == 0) _mint(BURN_ADDRESS, MINIMUM_LIQUIDITY);

        _mint(msg.sender, shares);

        cumulativeDeposit += actualAmount;

        emit Deposited(msg.sender, actualAmount);
    }

    /// @notice Request withdrawal of LP shares. Only one active request per user.
    /// @param _shareAmount Amount of LP shares to withdraw.
    function reqWithdraw(uint256 _shareAmount) external nonReentrant notPaused {
        require(_shareAmount > 0, ParamOutOfBounds("share amount"));
        require(isWhitelisted[msg.sender] || !whitelistEnabled, NotWhitelisted());

        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount == 0, AlreadyRequested());

        // Transfer shares to the vault
        _transfer(msg.sender, address(this), _shareAmount);

        BatchState storage batchState = batchWithdrawStates[currentBatchId];
        batchState.totalShares += _shareAmount;

        userState.sharesAmount = _shareAmount;
        userState.batchId = currentBatchId;
        userState.requestedAt = block.timestamp;
        userState.timelock = timelock;

        emit WithdrawRequested(msg.sender, _shareAmount);
    }

    /// @notice Withdraw tokens after batch resolved and timelock passed.
    function withdraw() external nonReentrant {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        uint256 shares = userState.sharesAmount;
        require(shares > 0, NoSharesToWithdraw());

        uint256 unlockTime = userState.requestedAt + uint256(userState.timelock);
        require(block.timestamp >= unlockTime, Locked());

        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        uint256 rate = batchState.rate;
        require(rate > 0, BatchNotResolved());

        uint256 tokenAmount = _calcTokenFromShares(shares, rate);
        require(tokenAmount > 0, ZeroCalculated());

        // Effects: update state before external calls
        delete userWithdrawStates[msg.sender];

        availableForWithdraw -= tokenAmount;
        cumulativeWithdrawn += tokenAmount;

        _burn(address(this), shares);

        // Interactions
        baseToken.safeTransfer(msg.sender, tokenAmount);

        emit Withdrawn(msg.sender, tokenAmount);
    }

    /// @notice Cancel a pending withdrawal request if batch not processed.
    function cancelWithdraw() external nonReentrant notPaused {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount > 0, NoValidRequest());
        require(currentBatchId == userState.batchId, BatchResolvedOrOngoing());

        // Update batch state before resetting user state
        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        batchState.totalShares -= userState.sharesAmount;
        // Transfer shares back to user
        _transfer(address(this), msg.sender, userState.sharesAmount);

        // Reset user state
        delete userWithdrawStates[msg.sender];

        emit WithdrawCanceled(msg.sender, userState.sharesAmount);
    }

    // =========================
    // Oracle functions
    // =========================

    /// @notice Called by TVL feed to allow user deposit after price update.
    /// @param _user User address allowed to deposit.
    function allowDeposit(address _user, uint256 _tvlIndex) external nonReentrant notPaused {
        require(msg.sender == address(tvlFeed), NotTVLFeed());
        DepositState storage state = userDepositStates[_user];
        require(!state.isPriceUpdated, AlreadyAllowed());
        require(state.expirationTime > block.timestamp, RequestExpired());

        state.isPriceUpdated = true;
        state.requestIndex = _tvlIndex;
        emit DepositAllowed(_user, state.expirationTime);
    }

    // =========================
    // Claimer functions
    // =========================

    /// @notice Claim maintenance fee. Only claimer.
    function claimMaintenanceFee() external onlyClaimer {
        _claimMaintenanceFee();
    }

    /// @notice Claim performance fee. Only claimer.
    function claimPerformanceFee() external onlyClaimer {
        _claimPerformanceFee();
    }

    /// @notice Sweep any excess base tokens (dust) from the vault to the fee collector. Only claimer.
    /// @dev Transfers any base tokens held by the vault contract that are not reserved for withdrawals
    /// @dev All deposits are directly transferred to the executor
    function sweepDust() public onlyClaimer {
        // Sweep dust (small amounts of tokens) from the vault to the fee collector
        require(baseToken.balanceOf(address(this)) > availableForWithdraw, NoDustToSweep());

        uint256 dustAmount = baseToken.balanceOf(address(this)) - availableForWithdraw;
        baseToken.safeTransfer(feeCollector, dustAmount);
    }

    // =========================
    // Overridden functions
    // =========================

    /// @notice Update the maximum TVL allowed in the vault. Only admin.
    /// @param _amount New maximum TVL value.
    function updateMaxTvl(uint256 _amount) public override onlyAdmin {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        require(block.timestamp - lastTvl.timestamp < freshness, StaleTvlData());
        require(_amount >= lastTvl.value, NewMaxTVLBelowCurrentTVL());

        super.updateMaxTvl(_amount);
    }

    /// @notice Updates the annual maintenance fee for the vault. Only callable by the admin.
    /// @dev Claims any pending maintenance fees before updating the fee.
    /// @param _annualFeeBps The new annual maintenance fee, expressed in basis points (bps).
    function updateMaintenanceFee(uint16 _annualFeeBps) public override onlyAdmin {
        _claimMaintenanceFee();
        super.updateMaintenanceFee(_annualFeeBps);
    }

    /// @notice Updates the performance fee for the vault. Only callable by the admin.
    /// @dev Claims any pending performance fees before updating the fee.
    /// @param _performanceFeeBps The new performance fee, expressed in basis points (bps).
    function updatePerformanceFee(uint16 _performanceFeeBps) public override onlyAdmin {
        _claimPerformanceFee();
        super.updatePerformanceFee(_performanceFeeBps);
    }

    // =========================
    // Executor functions
    // =========================

    /// @notice Process current withdrawal batch. Only executor.
    function processWithdraw() external onlyExecutor notPaused {
        require(batchWithdrawStates[currentBatchId - 1].rate != 0, BatchNotResolved());

        // Move to next batch only if shares to process
        if (batchWithdrawStates[currentBatchId].totalShares > 0) {
            ++currentBatchId;
        }
    }

    /// @notice Resolve withdrawal batch by setting rate and transferring tokens in.
    /// @param _tokenAmount Tokens to transfer in for withdrawals.
    /// @param _rate Conversion rate for the batch with TVL precision.
    function resolveWithdraw(uint256 _tokenAmount, uint256 _rate) external onlyExecutor nonReentrant notPaused {
        require(_rate > 0, ParamOutOfBounds("rate"));

        uint256 batchId = currentBatchId - 1;
        BatchState storage batchState = batchWithdrawStates[batchId];
        require(batchState.rate == 0, BatchResolved());

        uint256 requiredTokens = _calcTokenFromShares(batchState.totalShares, _rate);

        uint256 balanceBefore = baseToken.balanceOf(address(this));
        baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        uint256 actualAmount = baseToken.balanceOf(address(this)) - balanceBefore;
        require(actualAmount >= requiredTokens, InsufficientTokensForBatch());

        availableForWithdraw += actualAmount;
        batchState.rate = _rate;
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
        uint256 unlkTime = userState.requestedAt + userState.timelock;

        if (rate == 0) return (1, shares, 0, unlkTime); // Pending batch resolution

        uint256 tkAmount = _calcTokenFromShares(shares, rate);
        if (block.timestamp < unlkTime) return (2, shares, tkAmount, unlkTime); // Timelock active

        return (3, shares, tkAmount, unlkTime); // Ready to process
    }

    /**
     * @notice Calculates and returns the current share price based on the latest TVL data.
     * @return The current share price as a uint256 value, normalized to the TVL decimals.
     */
    function getSharePrice() external view returns (uint256) {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        if (block.timestamp - lastTvl.timestamp > freshness) return 0; // Return 0 if TVL data is stale

        (uint256 tvl18pt, uint8 tvlScaleFactor) = _normalize(lastTvl.value, tvlFeed.decimals());

        if (lastTvl.supplySnapshot == 0) return 0;

        UD60x18 sharePrice = ud(tvl18pt).div(ud(lastTvl.supplySnapshot));
        return tvlScaleFactor == 0 ? sharePrice.unwrap() : sharePrice.unwrap() / 10 ** tvlScaleFactor; // UD60x18 to uint256 (tvl decimals)
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

    // =========================
    // Internal/private functions
    // =========================

    /// @notice Claim maintenance fee.
    function _claimMaintenanceFee() internal {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        if (lastTvl.value == 0 && lastTvl.supplySnapshot == 0) return; // During initial setup
        uint256 lastClaimed = lastMaintenanceFeeClaimedAt;
        uint256 nowTs = block.timestamp;
        require(nowTs - lastTvl.timestamp < freshness, StaleTvlData());
        require(nowTs > lastClaimed, AlreadyClaimed());

        lastMaintenanceFeeClaimedAt = nowTs;
        (uint256 tvl18pt,) = _normalize(lastTvl.value, tvlFeed.decimals());
        uint256 feeAmount = _calcMaintenanceFee(lastClaimed, tvl18pt);
        if (feeAmount == 0) return;

        uint256 share = _calcShare(feeAmount, tvl18pt, lastTvl.supplySnapshot);
        _mint(feeCollector, share);
    }

    /// @notice Claim performance fee.
    function _claimPerformanceFee() internal {
        IShiftTvlFeed.TvlData memory lastTvl = tvlFeed.getLastTvl();
        if (lastTvl.value == 0 && lastTvl.supplySnapshot == 0) return; // During initial setup
        require(block.timestamp - lastTvl.timestamp < freshness, StaleTvlData());

        (uint256 tvl18pt, uint8 tvlScaleFactor) = _normalize(lastTvl.value, tvlFeed.decimals());
        int256 gain18pt = _calcGain(tvl18pt);
        uint256 feeAmount = _calcPerformanceFee(gain18pt);

        profitValue = tvlScaleFactor == 0 ? gain18pt : gain18pt / int256(10 ** tvlScaleFactor);

        if (feeAmount == 0) return;
        snapshotTvl18pt = tvl18pt;
        cumulativeDeposit = 0;
        cumulativeWithdrawn = 0;

        uint256 share = _calcShare(feeAmount, tvl18pt, lastTvl.supplySnapshot);
        _mint(feeCollector, share);
    }

    /**
     * @notice Calculates the net gain (or loss) of the vault since the last performance fee claim.
     * @param _tvl18pt The latest TVL value, normalized to 18 decimals.
     * @return gain18pt The net gain (or loss) as an int256, normalized to 18 decimals.
     */
    function _calcGain(uint256 _tvl18pt) internal view returns (int256) {
        (uint256 cumulativeDeposit18pt,) = _normalize(cumulativeDeposit, baseToken.decimals());
        (uint256 cumulativeWithdrawn18pt,) = _normalize(cumulativeWithdrawn, baseToken.decimals());

        int256 gain18pt = int256(_tvl18pt)
            - (int256(snapshotTvl18pt) + int256(cumulativeDeposit18pt) - int256(cumulativeWithdrawn18pt));
        return gain18pt;
    }

    /// @notice Calculates the number of shares to mint for a deposit, based on the normalized base token amount, TVL, and supply snapshot at the time of deposit request.
    /// @dev If the vault has no existing supply, returns the normalized token amount as shares (1:1). Otherwise, uses the share calculation formula.
    /// @param _baseToken18pt The deposit amount of base tokens, normalized to 18 decimals.
    /// @param _tvl18pt The TVL at the time of deposit, normalized to 18 decimals.
    /// @param _supplySnapshot The total supply snapshot at the time of deposit.
    /// @return The number of shares to mint (18 decimals).
    function _calcSharesFromToken(uint256 _baseToken18pt, uint256 _tvl18pt, uint256 _supplySnapshot)
        internal
        pure
        returns (uint256)
    {
        return _supplySnapshot > 0 ? _calcShare(_baseToken18pt, _tvl18pt, _supplySnapshot) : _baseToken18pt;
    }

    /// @notice Calculates shares to mint for a deposit based on TVL at request time.
    /// @dev Uses UD60x18 fixed-point math for precise calculations. The formula is: shares = (depositAmount * totalSupply) / TVL.
    /// @param _amount18pt The amount of base tokens deposited, expressed in 18 decimal places.
    /// @param _tvl18pt The total value locked at the time of deposit, expressed in 18 decimal places.
    /// @return The number of shares to mint, as a uint256 with 18 decimals.
    function _calcShare(uint256 _amount18pt, uint256 _tvl18pt, uint256 _totalSupply) internal pure returns (uint256) {
        require(_tvl18pt > 0, ParamOutOfBounds("tvl"));
        UD60x18 shares = ud(_amount18pt).mul(ud(_totalSupply)).div(ud(_tvl18pt));
        return shares.unwrap(); // UD60x18 to uint256 (18 decimals)
    }

    /// @notice Calculate tokens to return for share amount and rate.
    /// @param _shareAmount LP shares.
    /// @param _rate Conversion rate (tvl feed decimals).
    function _calcTokenFromShares(uint256 _shareAmount, uint256 _rate) internal view returns (uint256) {
        (, uint8 baseTokenScaleFactor) = _normalize(1, baseToken.decimals()); // Only to retrieve missing decimals from base token
        (uint256 rate18pt,) = _normalize(_rate, tvlFeed.decimals());

        UD60x18 tokenAmount = ud(rate18pt).mul(ud(_shareAmount));
        return baseTokenScaleFactor == 0 ? tokenAmount.unwrap() : tokenAmount.unwrap() / 10 ** baseTokenScaleFactor; // UD60x18 to uint256 (token decimals)
    }

    /**
     * @notice Calculates the performance fee based on the net gain since the last performance fee claim.
     * @param _gain18pt The net gain since the last claim, normalized to 18 decimals.
     * @return feeAmount The calculated performance fee amount (18 decimals).
     */
    function _calcPerformanceFee(int256 _gain18pt) internal view returns (uint256) {
        if (performanceFee18pt == 0 || _gain18pt < 0) return 0; // No fee if zero rate

        UD60x18 feeAmount = ud(uint256(_gain18pt)).mul(ud(performanceFee18pt));
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
            require(_amount <= type(uint256).max / factor, OverflowOnNormalization());
            amount = _amount * factor;
        } else {
            // Same decimals, no scaling needed
            amount = _amount;
        }
    }
}

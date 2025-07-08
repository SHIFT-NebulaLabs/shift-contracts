// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import { IShiftTvlFeed } from "./interface/IShiftTvlFeed.sol";
import { AccessModifier } from "./utils/AccessModifier.sol";
import { ShiftManager } from "./ShiftManager.sol";
import { VALIDITY_DURATION, TIMELOCK } from "./utils/Constants.sol";

contract ShiftVault is ShiftManager, ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public immutable baseToken;
    IShiftTvlFeed public immutable tvlFeed;

    uint256 public activeUsers;
    uint256 public amountReadyForWithdraw;
    uint256 private lastMaintenanceFeeClaimedAt;
    uint256 private currentBatchId;

    mapping(uint256 => BatchState) private batchWithdrawStates;
    mapping(address => WithdrawState) private userWithdrawStates;
    mapping(address => DepositState) private depositStates;

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
        uint256 _maxTvl
    )
        ShiftManager(_accessControlContract, _feeCollector, _minDeposit, _maxTvl)
        ERC20("Shift LP", "SLP")
    {
        require(_tokenContract != address(0), "ShiftVault: zero token address");
        require(_tvlFeedContract != address(0), "ShiftVault: zero TVL feed address");

        baseToken = ERC20(_tokenContract);
        tvlFeed = IShiftTvlFeed(_tvlFeedContract);

        currentBatchId = 1;
        lastMaintenanceFeeClaimedAt = block.timestamp;
    }


    // Add a time lock to avoid potential DDOS attacks
    function reqDeposit() external nonReentrant {
        require(isWhitelisted[msg.sender] || !whitelistEnabled, "ShiftVault: not whitelisted");
        DepositState storage state = depositStates[msg.sender];
        require(!state.isPriceUpdated, "ShiftVault: deposit request already exists");
        require(_isExpired(), "ShiftVault: deposit request still valid");

        state.expirationTime = block.timestamp + VALIDITY_DURATION;
        emit DepositRequested(msg.sender);
    }


    function deposit(uint256 _tokenAmount) external nonReentrant notPaused {
        require(_tokenAmount >= minDepositAmount, "ShiftVault: deposit below minimum");
        require(tvlFeed.getLastTvl().value + _tokenAmount <= maxTvl, "ShiftVault: exceeds max TVL");
        DepositState storage state = depositStates[msg.sender];
        require(state.isPriceUpdated && !_isExpired(), "ShiftVault: no valid deposit request");

        state.isPriceUpdated = false; // Reset state after deposit
        baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        uint256 shares;
        if (tvlFeed.getLastTvl().value == 0 || totalSupply() == 0) {
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

    function reqWithdraw(uint256 _shareAmount) external nonReentrant {
        require(_shareAmount > 0, "ShiftVault: zero shares");
        require(balanceOf(msg.sender) >= _shareAmount, "ShiftVault: insufficient shares");

        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount == 0, "ShiftVault: withdraw already requested");

        BatchState storage batchState = batchWithdrawStates[currentBatchId];
        batchState.totalShares += _shareAmount;

        userState.sharesAmount = _shareAmount;
        userState.batchId = currentBatchId;
        userState.requestedAt = block.timestamp;
    }


// view rate, is 0 is pending

    function withdraw() external nonReentrant notPaused {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        uint256 shares = userState.sharesAmount;
        require(shares > 0, "ShiftVault: no shares to withdraw");
        require(block.timestamp >= userState.requestedAt + TIMELOCK, "ShiftVault: withdrawal locked");

        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        uint256 rate = batchState.rate;
        require(rate > 0, "ShiftVault: batch not resolved");

        uint256 tokenAmount = _calcTokenFromShares(shares, rate);
        (uint256 feeAmount, uint256 userAmount) = _calcPerformanceFee(tokenAmount);

        // Reset user's withdrawal state before external calls
        userState.sharesAmount = 0;
        userState.batchId = 0;
        userState.requestedAt = 0;

        // Update batch state
        amountReadyForWithdraw -= shares;

        _burn(msg.sender, shares);

        // Transfer base tokens to the user and feeCollector
        if (userAmount > 0) baseToken.safeTransfer(msg.sender, userAmount);
        if (feeAmount > 0) baseToken.safeTransfer(feeCollector, feeAmount);

        if (balanceOf(msg.sender) == 0 && activeUsers > 0) {
            unchecked { --activeUsers; }
        }
    }
    function cancelWithdraw() external nonReentrant {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount > 0, "ShiftVault: no withdrawal request to cancel");
        require(currentBatchId == userState.batchId, "ShiftVault: cannot cancel, withdrawal already processing");
        require(batchWithdrawStates[userState.batchId].rate == 0, "ShiftVault: batch already resolved");

        // Update batch state before resetting user state
        batchWithdrawStates[userState.batchId].totalShares -= userState.sharesAmount;

        // Reset user state
        userState.sharesAmount = 0;
        userState.batchId = 0;
        userState.requestedAt = 0;
    }






    function allowDeposit(address _user) external {
        require(msg.sender == address(tvlFeed), "ShiftVault: caller is not TVL feed");
        DepositState storage state = depositStates[_user];
        if (state.isPriceUpdated || state.expirationTime <= block.timestamp) return;
        state.isPriceUpdated = true;
        emit DepositAllowed(_user, state.expirationTime);
    }



    // Claim Maintenance fee
    function claimMaintenanceFee() external onlyAdmin {
        uint256 lastClaimed = lastMaintenanceFeeClaimedAt;
        uint256 nowTs = block.timestamp;
        require(nowTs > lastClaimed, "ShiftVault: already claimed for this period");

        uint256 feeAmount = _calcMaintenanceFee(lastClaimed);
        if (feeAmount == 0) return;

        lastMaintenanceFeeClaimedAt = nowTs;
        _mint(feeCollector, feeAmount);
    }

    function processWithdraw() external onlyExecutor {
        BatchState storage batchState = batchWithdrawStates[currentBatchId];
        require(batchState.rate == 0, "ShiftVault: batch already resolved");

        // Move to the next batch only if there are shares to process
        if (batchState.totalShares > 0) {
            ++currentBatchId;
        }
    }

    function resolveWithdraw(uint256 _tokenAmount, uint256 _rate) external onlyExecutor notPaused {
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

    //Only Resolver
    function sendFundsToResolver(uint256 _tokenAmount) external onlyExecutor notPaused {
        require(_tokenAmount > 0, "ShiftVault: amount is zero");
        baseToken.safeTransfer(msg.sender, _tokenAmount);
    }



    //View functions
    //Fx return withdraw status
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
        uint256 unlkTime = userState.requestedAt + TIMELOCK;

        if (rate == 0) return (1, shares, 0, unlkTime); // Pending batch resolution

        uint256 tkAmount = _calcTokenFromShares(shares, rate);
        if (block.timestamp < unlkTime) return (2, shares, tkAmount, unlkTime); // Timelock active

        return (3, shares, tkAmount, unlkTime); // Ready to process
    }

    function getBatchWithdrawAmount() external view onlyExecutor returns (uint256) {
        return batchWithdrawStates[currentBatchId - 1].totalShares;
    }


    // Private
    function _calcSharesFromToken(uint256 _tokenAmount) internal view returns (uint256) {
        (uint256 baseToken18Decimals, ) = _normalize(_tokenAmount, baseToken.decimals());
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());

        UD60x18 ratio = ud(baseToken18Decimals).div(ud(tvl18Decimals));
        UD60x18 shares = ratio.mul(ud(totalSupply()));
        return shares.unwrap(); // Convert UD60x18 to uint256 (18 decimals)
    }

    //rate with 6 decimals
    function _calcTokenFromShares(uint256 _shareAmount, uint256 _rate) internal view returns (uint256) {
        (, uint8 baseTokenDecimalsTo18) = _normalize(_shareAmount, baseToken.decimals());
        (uint256 rate18Decimals, ) = _normalize(_rate, tvlFeed.decimals());

        UD60x18 ratio = ud(rate18Decimals);
        UD60x18 tokenAmount = ratio.mul(ud(_shareAmount));
        return baseTokenDecimalsTo18 == 0 ? tokenAmount.unwrap() : tokenAmount.unwrap() / 10**baseTokenDecimalsTo18; // Convert UD60x18 to uint256 (Token decimals)
    }

    function _normalize(uint256 _amount, uint8 _decimals) internal view returns (uint256 amount, uint8 scaleFactor) {
        amount = _decimals == decimals() ? _amount : _amount * 10**(decimals() - _decimals);
        scaleFactor = _decimals < decimals() ? decimals() - _decimals : 0;
    }

    function _calcPerformanceFee(uint256 _tokenAmount) internal view returns (uint256 feeAmount, uint256 userAmount) {
        UD60x18 fee = ud(_tokenAmount).mul(ud(performanceFee18pt)); // 1% fee
        feeAmount = fee.unwrap(); // Convert UD60x18 to uint256 (18 decimals)
        userAmount = ud(_tokenAmount).sub(fee).unwrap();
    }

    function _calcMaintenanceFee(uint256 _lastClaimTimestamp) internal view returns (uint256) {
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());
        uint256 elapsed = block.timestamp - _lastClaimTimestamp;
        return (tvl18Decimals * maintenanceFeePerSecond18pt * elapsed) / 1e18;
    }

    function _isExpired() internal view returns(bool) {
        return depositStates[msg.sender].expirationTime < block.timestamp;
    }
}
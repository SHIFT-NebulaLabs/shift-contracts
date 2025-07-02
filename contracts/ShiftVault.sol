// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import { IShiftTvlFeed } from "./interface/IShiftTvlFeed.sol";
import { ShiftModifier } from "./utils/Modifier.sol";
import { VALIDITY_DURATION, TIMELOCK } from "./utils/Constants.sol";

// ✅ Possibility to deposit ERC20s 
// ✅ 2 step deposit to update TVL first
// ✅ Withdrawal request, with a lock of x days
// ✅ Withdraw after x days
// Possibility to transfer data and tokens with an upgraded contract or using UUPS?
// ✅ TVL from external feed
// ✅ Mint shares based on deposit
// ✅ Share value based on TVL
// ✅ Allocation of shares as a daily "Maintenance" fee for the treasury
// ✅ Withdrawal fee ("Performance") for the treasury
// ✅ access control for the contract to implement
// ✅ Whitelist of users that can deposit
// enable permit ?
// ✅ Send tokens to the resolver after deposit
// Security
// View user entry price?
// Pause contract
// ✅ Max TVL
// ✅ Min deposit
// Fx to modify configuration
// Need to track active users

// Clean code & optimization
// Review require statements
// Comments & Messages

contract ShiftVault is ShiftModifier, ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;



    IAccessControl public immutable accessControlContract;
    ERC20 public immutable baseToken;
    IShiftTvlFeed public immutable tvlFeed;

    // Mapping to track user deposits
    // !!Review visibility
    mapping(address => uint256) public userDeposits;
    mapping(address => DepositState) public depositStates;

    //Configuration
    mapping(address => bool) public isWhitelisted;
    bool public whitelistEnabled;
    
    uint256 public activeUsers;

    uint16 public performanceFee; // 1% = 100, 0.5% = 50, etc. -- (_bps * 1e18) / 10_000;
    uint16 public maintenanceFeePerSecond; // 1% = 100, 0.5% = 50, etc. -- (_bps * 1e18) / 10_000 = Annual fee --> Annual fee / (SECONDS_IN_YEAR * 1e18) = Seconds fee;
    address public treasuryRecipient; // Address to receive performance fees
    uint256 public minDeposit; // Minimum deposit amount
    uint256 public maxTvl; // Maximum TVL limit

    uint256 public lastMaintenanceFeeClaimedAt;


    uint256 public currentBatchId;
    uint256 public tokenToBeWithdrawn; // total tokens to be withdrawn, needed for the oracle to calculate the correct TVL???
    mapping(uint256 => BatchState) public batchWithdrawStates; // total shares per batch
    mapping(address => WithdrawState) public userWithdrawStates; // user withdraw states



    // Events
    event DepositRequested(address indexed user);
    event DepositAllowed(address indexed user, uint256 expirationTime);//To be verify how to identify the event specific request!!

    // Structs
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
        uint256 rate; // rate (baseToken per share) per batch
    }


    constructor(address _accessControlContract, address _tokenContract, address _shiftTvlFeedContract) ERC20("Shift LP", "SLP") ShiftModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        require(_tokenContract != address(0), "Token contract address cannot be zero");
        require(_shiftTvlFeedContract != address(0), "Shift TVL feed contract address cannot be zero");
        accessControlContract = IAccessControl(_accessControlContract);
        baseToken = ERC20(_tokenContract);
        tvlFeed = IShiftTvlFeed(_shiftTvlFeedContract);
        whitelistEnabled = true;
        currentBatchId = 1; // Start with batch ID 1
    }


    //be sure to add a time lock to avoid ddos attacks
    function reqDeposit() external nonReentrant {
        require(isWhitelisted[msg.sender] || !whitelistEnabled, "User is not whitelisted for deposits");
        require(!depositStates[msg.sender].isPriceUpdated, "Deposit request already exists");
        require(_isExpired(), "Deposit request is still valid");

        emit DepositRequested(msg.sender);

        depositStates[msg.sender].expirationTime = block.timestamp + VALIDITY_DURATION;
    }


    function Deposit(uint256 _amount) external nonReentrant {
        require(_amount >= minDeposit, "Deposit amount is below the minimum required");
        require(tvlFeed.getLastTvl().value + _amount <= maxTvl, "Deposit exceeds maximum TVL limit");
        require(depositStates[msg.sender].isPriceUpdated && !_isExpired(), "Deposit request not found or expired");
        //Allowance and balance checks are handled by SafeERC20

        depositStates[msg.sender].isPriceUpdated = false; // Reset state after finalizing deposit
        baseToken.safeTransferFrom(msg.sender, address(this), _amount);
        userDeposits[msg.sender] += _amount;///needed??
        
        if (tvlFeed.getLastTvl().value == 0 || totalSupply() == 0) {
            (, uint8 baseTokenDecimalsTo18) = _normalize(_amount, baseToken.decimals());
            uint256 tokenAmount = baseTokenDecimalsTo18 == 0 ? _amount : _amount / 10**baseTokenDecimalsTo18;
            _mint(msg.sender, _calcSharesFromToken(tokenAmount));
        } else {
            _mint(msg.sender, _calcSharesFromToken(_amount));
            //update TVL after minting shares??
        }
        unchecked {
            ++activeUsers; // Increment active users count
        }
    }

    function reqWithdraw(uint256 _shares) external nonReentrant {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(_shares > 0, "Shares amount must be greater than zero");
        require(balanceOf(msg.sender) >= _shares, "Insufficient shares");
        require(userState.sharesAmount == 0, "Withdrawal already requested");

        batchWithdrawStates[currentBatchId].totalShares += _shares;
        userState.sharesAmount += _shares;
        userState.batchId = currentBatchId;
        userState.requestedAt = block.timestamp;
    }


// view rate, is 0 is pending

    function withdraw() external nonReentrant {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(userState.sharesAmount > 0, "No shares to withdraw");
        require(block.timestamp >= userState.requestedAt + TIMELOCK, "Withdrawal is still locked");

        BatchState storage batchState = batchWithdrawStates[userState.batchId];
        require(batchState.rate > 0, "Batch not resolved yet");

        uint256 tokenAmount = _calcTokenFromShares(userState.sharesAmount, batchState.rate);

        (uint256 feeAmount, uint256 userAmount) = _calcPerformanceFee(tokenAmount);

        // Reset user's withdrawal state
        userState.sharesAmount = 0;

        // Update batch state
        tokenToBeWithdrawn -= userState.sharesAmount;

        _burn(msg.sender, userState.sharesAmount); // Burn shares after withdrawal
        // Transfer base tokens to the user
        baseToken.safeTransfer(msg.sender, userAmount);
        baseToken.safeTransfer(treasuryRecipient, feeAmount); // Transfer fee to the treasury
    }

    function cancelWithdraw() external nonReentrant {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        require(currentBatchId == userState.batchId, "Cannot cancel withdrawal in progress");
        require(batchWithdrawStates[userState.batchId].rate != 0, "Batch already resolved");
        require(userState.sharesAmount > 0, "No request to cancel");

        userState.sharesAmount = 0;

        //not needed ? is already re-initialized on the next request
        userState.batchId = 0;
        userState.requestedAt = 0;

        // Update batch state
        batchWithdrawStates[userState.batchId].totalShares -= userState.sharesAmount;
    }






    function allowDeposit(address _user) external {
        require(msg.sender == address(tvlFeed), "Only TVL feed");
        DepositState storage state = depositStates[_user];
        state.isPriceUpdated = true;
        emit DepositAllowed(_user, state.expirationTime);
    }



    //only admin to be added, to be moved to a specific contract
    function manageWhitelist(address _user) external {
        if (_user == address(0)) {
            whitelistEnabled = !whitelistEnabled;
        }else{
            isWhitelisted[_user] = !isWhitelisted[_user];
        }
    }
    // Only Admin
    // Claim Maintenance fee
    function claimMaintenanceFee() external onlyAdmin {
        require(lastMaintenanceFeeClaimedAt < block.timestamp, "Maintenance fee already claimed for this period");

        uint256 feeAmount = _calcMaintenanceFee(lastMaintenanceFeeClaimedAt);
        lastMaintenanceFeeClaimedAt = block.timestamp;

        _mint(treasuryRecipient, feeAmount);
    }

    //Fx Resolver start withdraw process and change batch id
    //only Resolver to be added
    function processWithdraw() external onlyExecutor {
        require(currentBatchId > 0, "No batch to process");

        BatchState storage batchState = batchWithdrawStates[currentBatchId];
        require(batchState.rate == 0, "Batch already resolved");

        // Increment to the next batch ID
        ++currentBatchId;
    }


    //Fx Resolver to send funds and set rate for the batch
    //only Resolver to be added
    function resolveWithdraw(uint256 _tokenAmount, uint256 _rate) external onlyExecutor {
        require(currentBatchId > 0, "No batch to resolve");
        require(_rate > 0, "Rate must be greater than zero");

        BatchState storage batchState = batchWithdrawStates[currentBatchId - 1];
        require(batchState.rate == 0, "Batch already resolved");

        tokenToBeWithdrawn += batchState.totalShares;

        // Set the rate for the current batch
        batchState.rate = _rate;

        baseToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
    }

    //Only Resolver
    function sendFundsToResolver(uint256 _tokenAmount) external onlyExecutor {
        require(_tokenAmount > 0, "Token amount must be greater than zero");

        // Transfer the specified amount of tokens to the resolver
        baseToken.safeTransfer(msg.sender, _tokenAmount);
    }



    //View functions
    //Fx return withdraw status
    function getWithdrawStatus() external view returns (uint8 status, uint256 shareAmount, uint256 tokenAmount, uint256 unlockTime) {
        WithdrawState storage userState = userWithdrawStates[msg.sender];
        uint256 shares = userState.sharesAmount;
        uint256 unlkTime = userState.requestedAt + TIMELOCK;
        uint256 rate = batchWithdrawStates[userState.batchId].rate;

        if (shares == 0) {
            return (0, 0, 0, 0); // No withdrawal requested
        }
        if (rate == 0) {
            return (1, shares, 0, unlkTime); // Withdrawal is pending
        }
        uint256 tkAmount = _calcTokenFromShares(shares, rate);
        if (block.timestamp < unlkTime) {
            return (2, shares, tkAmount, unlkTime); // Withdrawal is locked
        }
        return (3, shares, tkAmount, unlkTime); // Withdrawal can be processed
    }
    // Need to show for the user the withdraw available
    //Fx deposit status??



    // Private
    function _calcSharesFromToken(uint256 _tokenAmount) private view returns (uint256) {
        (uint256 baseToken18Decimals, ) = _normalize(_tokenAmount, baseToken.decimals());
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());

        UD60x18 ratio = ud(baseToken18Decimals).div(ud(tvl18Decimals));
        UD60x18 shares = ratio.mul(ud(totalSupply()));
        return shares.unwrap(); // Convert UD60x18 to uint256 (18 decimals)
    }

    //rate with 6 decimals
    function _calcTokenFromShares(uint256 _shareAmount, uint256 _rate) private view returns (uint256) {
        (, uint8 baseTokenDecimalsTo18) = _normalize(_shareAmount, baseToken.decimals());
        (uint256 rate18Decimals, ) = _normalize(_rate, tvlFeed.decimals());

        UD60x18 ratio = ud(rate18Decimals);
        UD60x18 tokenAmount = ratio.mul(ud(_shareAmount));
        return baseTokenDecimalsTo18 == 0 ? tokenAmount.unwrap() : tokenAmount.unwrap() / 10**baseTokenDecimalsTo18; // Convert UD60x18 to uint256 (Token decimals)
    }

    function _normalize(uint256 _amount, uint8 _decimals) private view returns (uint256 amount, uint8 decimalsTo18) {
        amount = _decimals == 18 ? _amount : _amount * 10**(decimals() - _decimals);
        decimalsTo18 = _decimals < decimals() ? decimals() - _decimals : 0;
    }

    function _calcPerformanceFee(uint256 _tokenAmount) private view returns (uint256 feeAmount, uint256 userAmount) {
        UD60x18 fee = ud(_tokenAmount).mul(ud(uint256(performanceFee))); // 1% fee
        feeAmount = fee.unwrap(); // Convert UD60x18 to uint256 (18 decimals)
        userAmount = ud(_tokenAmount).sub(fee).unwrap();
    }

    function _calcMaintenanceFee(uint256 _lastClaimTimestamp) private view returns (uint256) {
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());
        uint256 elapsed = block.timestamp - _lastClaimTimestamp;

        UD60x18 feePerSecond = ud(tvl18Decimals).mul(ud(maintenanceFeePerSecond));
        return feePerSecond.mul(ud(elapsed)).unwrap();
    }

    function _isExpired() public view returns(bool) {
        return depositStates[msg.sender].expirationTime < block.timestamp;
    }
}
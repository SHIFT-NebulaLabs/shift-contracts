// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

import { IShiftTvlFeed } from "./interface/IShiftTvlFeed.sol";

// ✅ Possibility to deposit ERC20s 
// ✅ 2 step deposit to update TVL first
// Withdrawal request, with a lock of x days
// Withdraw after x days
// User whitelist
// Possibility to transfer data and tokens with an upgraded contract
// ✅ TVL from external feed
// ✅ Mint shares based on deposit
// ✅ Share value based on TVL
// Allocation of shares as a daily "Maintenance" fee for the treasury
// Withdrawal fee ("Performance") for the treasury
// track how many active users there are
// access control for the contract to implement

// Active user are the ones with the sUSDC balance > 0
// TVL limit

contract ShiftVault is ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    uint256 public constant VALIDITY_DURATION = 10 seconds;

    IAccessControl public immutable accessControlContract;
    ERC20 public immutable baseToken;
    IShiftTvlFeed public immutable tvlFeed;

    // Mapping to track user deposits
    mapping(address => uint256) public userDeposits;

    mapping(address => DepositState) public depositStates;

    // Events
    event DepositRequested(address indexed user);

    // Structs
    struct DepositState {
        bool isPriceUpdated;
        uint256 updatedAt;
        uint256 expirationTime;
    }



    constructor(address _accessControlContract, address _tokenContract, address _shiftTvlFeedContract) ERC20("Shift LP", "SLP") {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        require(_tokenContract != address(0), "Token contract address cannot be zero");
        require(_shiftTvlFeedContract != address(0), "Shift TVL feed contract address cannot be zero");
        accessControlContract = IAccessControl(_accessControlContract);
        baseToken = ERC20(_tokenContract);
        tvlFeed = IShiftTvlFeed(_shiftTvlFeedContract);
    }


    //be sure to add a time lock to avoid ddos attacks
    function reqDeposit() external nonReentrant {
        require(!depositStates[msg.sender].isPriceUpdated, "Deposit request already exists");
        require(_isExpired(), "Deposit request is still valid");

        emit DepositRequested(msg.sender);

        depositStates[msg.sender].expirationTime = block.timestamp + VALIDITY_DURATION;
    }


    function finalizeDeposit(uint256 _amount) external {
        //min based on TVL ??
        require(_amount > 0, "Deposit amount must be greater than zero");
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
    }

    function allowDeposit(address _user) external {
        require(msg.sender == address(tvlFeed), "Only Shift TVL feed can call this function");
        
        depositStates[_user].isPriceUpdated = true;
        depositStates[_user].updatedAt = block.timestamp;
        //Event or function with status update??
    }


    function _calcSharesFromToken(uint256 _tokenAmount) private view returns (uint256) {
        (uint256 baseToken18Decimals, ) = _normalize(_tokenAmount, baseToken.decimals());
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());

        UD60x18 ratio = ud(baseToken18Decimals).div(ud(tvl18Decimals));
        UD60x18 shares = ratio.mul(ud(totalSupply()));
        return shares.unwrap(); // Convert UD60x18 to uint256 (18 decimals)
    }

    function _calcTokenFromShares(uint256 _shareAmount) private view returns (uint256) {
        (, uint8 baseTokenDecimalsTo18) = _normalize(_shareAmount, baseToken.decimals());
        (uint256 tvl18Decimals, ) = _normalize(tvlFeed.getLastTvl().value, tvlFeed.decimals());

        UD60x18 ratio = ud(_shareAmount).div(ud(totalSupply()));
        UD60x18 tokenAmount = ratio.mul(ud(tvl18Decimals));
        return baseTokenDecimalsTo18 == 0 ? tokenAmount.unwrap() : tokenAmount.unwrap() / 10**baseTokenDecimalsTo18; // Convert UD60x18 to uint256 (Token decimals)
    }

    function _normalize(uint256 _amount, uint8 _decimals) private view returns (uint256 amount, uint8 decimalsTo18) {
        amount = _decimals == 18 ? _amount : _amount * 10**(decimals() - _decimals);
        decimalsTo18 = _decimals < decimals() ? decimals() - _decimals : 0;
    }

    function _isExpired() public view returns(bool) {
        return depositStates[msg.sender].expirationTime < block.timestamp;
    }
}
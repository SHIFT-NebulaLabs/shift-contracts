// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { AccessModifier } from "../utils/AccessModifier.sol";
import { SECONDS_IN_YEAR } from "../utils/Constants.sol";


abstract contract ShiftManager is AccessModifier {

    mapping(address => bool) public isWhitelisted;

    address public treasuryRecipient;

    bool public whitelistEnabled;
    bool public paused;

    uint256 public performanceFeeBps;// 1% = 100, 0.5% = 50, etc. -- (_bps * 1e18) / 10_000;
    uint256 public maintenanceFeeBpsPerSecond; // 1% = 100, 0.5% = 50, etc. -- (_bps * 1e18) / 10_000 = Annual fee --> Annual fee / (SECONDS_IN_YEAR * 1e18) = Seconds fee;

    uint256 public minDepositAmount;
    uint256 public maxTvl;

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _accessControlContract, address _tresuryRecipient) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        require(_tresuryRecipient != address(0), "Tresury address cannot be zero");
        treasuryRecipient = _tresuryRecipient;
        whitelistEnabled = true;
        paused = true;
    }

    function emergencyPause() external {
        paused = true;
    }

    function releasePause() external {
        require(condition);
    }


    function manageWhitelist(address _user) external onlyAdmin {
        if (_user == address(0)) {
            whitelistEnabled = !whitelistEnabled;
        }else{
            isWhitelisted[_user] = !isWhitelisted[_user];
        }
    }

    function upgradeTresuryRecipient(address _newTresuryRecipient) external onlyAdmin {
        require(_newTresuryRecipient != address(0), "Tresury address cannot be zero");
        treasuryRecipient = _newTresuryRecipient;
    }


    function updatePerformanceFee(uint16 _feeBps) external onlyAdmin {
        require(_feeBps != 0, "Performance fee cannot be zero");
        performanceFeeBps = _calcFeeFromBps(_feeBps);
    }

    function updateMaintenanceFee(uint16 _annualFeeBps) external onlyAdmin {
        require(_annualFeeBps != 0, "Performance fee cannot be zero");
        uint256 feeAnnual = _calcFeeFromBps(_annualFeeBps);
        maintenanceFeeBpsPerSecond =  feeAnnual / SECONDS_IN_YEAR;
    }

    function updateMinDeposit(uint256 _amount) external onlyAdmin {
        minDepositAmount = _amount;
    }

    function updateMaxTvl(uint256 _amount) external onlyAdmin {
        maxTvl = _amount;
    }

    function _calcFeeFromBps(uint16 _feeBps) internal pure returns (uint256) {
        return (uint256(_feeBps) * 1e18) / 10_000;
    }
}
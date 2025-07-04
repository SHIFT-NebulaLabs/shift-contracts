// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { AccessModifier } from "../utils/AccessModifier.sol";
import { SECONDS_IN_YEAR } from "../utils/Constants.sol";


abstract contract ShiftManager is AccessModifier {

    bool internal whitelistEnabled;
    bool public paused;
    uint256 public performanceFeeBps; // 1% is 100, then performanceFeeBps will be 1e16 (0.01 * 1e18)
    uint256 public maintenanceFeeBpsPerSecond; // 1% is 100, then maintenanceFeeBpsPerSecond will be 1e16 / SECONDS_IN_YEAR
    uint256 public minDepositAmount; //BaseToken Precision
    uint256 public maxTvl; //Tvl precision
    address public feeCollector;

    mapping(address => bool) internal isWhitelisted;

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _accessControlContract, address _feeCollector, uint256 _minDeposit, uint256 _maxTvl) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        require(_feeCollector != address(0), "Fee collector address cannot be zero");
        feeCollector = _feeCollector;
        minDepositAmount = _minDeposit;
        maxTvl = _maxTvl;
        whitelistEnabled = true;
        paused = true;
    }

    function emergencyPause() external {
        paused = true;
    }

    function releasePause() external {
        require(performanceFeeBps != 0, "Performance fee not set");
        require(maintenanceFeeBpsPerSecond != 0, "Maintenance fee not set");
        paused = false;
    }


    function manageWhitelist(address _user) external onlyAdmin {
        if (_user == address(0)) {
            whitelistEnabled = !whitelistEnabled;
        }else{
            isWhitelisted[_user] = !isWhitelisted[_user];
        }
    }

    function upgradeFeeCollector(address _newFeeCollector) external onlyAdmin {
        require(_newFeeCollector != address(0), "Fee collector address cannot be zero");
        feeCollector = _newFeeCollector;
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
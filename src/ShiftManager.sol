// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { AccessModifier } from "./utils/AccessModifier.sol";
import { SECONDS_IN_YEAR } from "./utils/Constants.sol";

abstract contract ShiftManager is AccessModifier {
    bool public whitelistEnabled = true;
    bool public paused = true;

    uint16 public performanceFeeBps; // 1% = 100 bps
    uint16 public maintenanceFeeBpsAnnual; // 1% = 100 bps
    uint256 public performanceFee18pt; // 1% = 0.01 * 10^18
    uint256 public maintenanceFeePerSecond18pt; // 1% = 0.01 * 10^18
    uint256 public minDepositAmount;
    uint256 public maxTvl;
    address public feeCollector;

    mapping(address => bool) public isWhitelisted;

    modifier notPaused() {
        require(!paused, "ShiftManager: paused");
        _;
    }

    constructor(
        address _accessControlContract,
        address _feeCollector,
        uint256 _minDeposit,
        uint256 _maxTvl
    ) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "ShiftManager: zero access control");
        require(_feeCollector != address(0), "ShiftManager: zero fee collector");
        feeCollector = _feeCollector;
        minDepositAmount = _minDeposit;
        maxTvl = _maxTvl;
    }

    function emergencyPause() external onlyAdmin {
        paused = true;
    }

    function releasePause() external onlyAdmin {
        require(performanceFeeBps > 0, "ShiftManager: performance fee not set");
        require(maintenanceFeeBpsAnnual > 0, "ShiftManager: maintenance fee not set");
        paused = false;
    }

    function manageWhitelist(address _user) external onlyAdmin {
        if (_user == address(0)) {
            whitelistEnabled = !whitelistEnabled;
        } else {
            isWhitelisted[_user] = !isWhitelisted[_user];
        }
    }

    function upgradeFeeCollector(address _newFeeCollector) external onlyAdmin {
        require(_newFeeCollector != address(0), "ShiftManager: zero fee collector");
        feeCollector = _newFeeCollector;
    }

    function updatePerformanceFee(uint16 _feeBps) external onlyAdmin {
        require(_feeBps > 0, "ShiftManager: zero performance fee");
        performanceFeeBps = _feeBps;
        performanceFee18pt = _calc18ptFromBps(_feeBps);
    }

    function updateMaintenanceFee(uint16 _annualFeeBps) external onlyAdmin {
        require(_annualFeeBps > 0, "ShiftManager: zero maintenance fee");
        maintenanceFeeBpsAnnual = _annualFeeBps;
        maintenanceFeePerSecond18pt = _calc18ptFromBps(_annualFeeBps) / SECONDS_IN_YEAR;
    }

    function updateMinDeposit(uint256 _amount) external onlyAdmin {
        require(_amount > 0, "ShiftManager: zero min deposit");
        minDepositAmount = _amount;
    }

    function updateMaxTvl(uint256 _amount) external onlyAdmin {
        require(_amount > 0, "ShiftManager: zero max TVL");
        maxTvl = _amount;
    }

    function _calc18ptFromBps(uint16 _feeBps) internal pure returns (uint256) {
        return (uint256(_feeBps) * 1e18) / 10_000;
    }
}
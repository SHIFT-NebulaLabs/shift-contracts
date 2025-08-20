// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessModifier} from "./utils/AccessModifier.sol";
import {SECONDS_IN_YEAR} from "./utils/Constants.sol";

/// @title ShiftManager
/// @notice Shift protocol parameters, fees, and whitelist management.
/// @dev Inherits from AccessModifier for access control.
abstract contract ShiftManager is AccessModifier {
    bool public whitelistEnabled = true;
    bool public paused = true;

    uint32 public timelock;
    uint256 public minDepositAmount;
    uint256 public maxTvl;
    address public feeCollector;
    address public executor;
    uint256 public performanceFee18pt; // 1% = 0.01 * 10^18
    uint256 public maintenanceFeePerSecond18pt; // 1% = 0.01 * 10^18

    mapping(address => bool) internal isWhitelisted;

    event MaxTvlUpdated(uint256 indexed timestamp, uint256 newMaxTvl);

    /// @notice Ensures contract is not paused.
    modifier notPaused() {
        require(!paused, "ShiftManager: paused");
        _;
    }

    /// @notice Contract initialization with required parameters.
    /// @param _accessControlContract Address of access control contract.
    /// @param _feeCollector Address that collects protocol fees.
    /// @param _minDeposit Minimum allowed deposit.
    /// @param _maxTvl Maximum total value locked.
    /// @param _timeLock Timelock duration.
    constructor(
        address _accessControlContract,
        address _feeCollector,
        address _executor,
        uint256 _minDeposit,
        uint256 _maxTvl,
        uint32 _timeLock
    ) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "ShiftManager: zero access control");
        require(_feeCollector != address(0), "ShiftManager: zero fee collector");
        require(_executor != address(0), "ShiftManager: zero executor");
        require(_timeLock > 0, "ShiftManager: zero timelock");
        _validateDepositAndTvl(_minDeposit, _maxTvl);
        feeCollector = _feeCollector;
        executor = _executor;
        minDepositAmount = _minDeposit;
        maxTvl = _maxTvl;
        timelock = _timeLock;
    }

    /// @notice Update maximum total value locked (TVL).
    /// @dev This function will be overridden by child contracts <ShiftVault>.
    /// @dev It is important to ensure that the new TVL cap have the same decimal precision as the tvlFeed.
    /// @param _amount New TVL cap.
    function updateMaxTvl(uint256 _amount) public virtual onlyAdmin {
        _validateDepositAndTvl(minDepositAmount, _amount);
        maxTvl = _amount;
        emit MaxTvlUpdated(block.timestamp, _amount);
    }

    /// @notice Update annual maintenance fee (basis points).
    /// @dev This function will be overridden by child contracts <ShiftVault>.
    /// @param _annualFeeBps New maintenance fee in basis points (1% = 100bps).
    function updateMaintenanceFee(uint16 _annualFeeBps) public virtual onlyAdmin {
        require(_annualFeeBps <= 10_000, "ShiftManager: maintenance fee exceeds 100%");
        maintenanceFeePerSecond18pt = _calc18ptFromBps(_annualFeeBps) / uint256(SECONDS_IN_YEAR);
    }

    /// @notice Update performance fee (basis points).
    /// @dev This function will be overridden by child contracts <ShiftVault>.
    /// @param _feeBps New performance fee in basis points (1% = 100bps).
    function updatePerformanceFee(uint16 _feeBps) public virtual onlyAdmin {
        require(_feeBps <= 10_000, "ShiftManager: performance fee exceeds 100%");
        performanceFee18pt = _calc18ptFromBps(_feeBps);
    }

    /// @notice Emergency pause.
    function emergencyPause() external onlyAdmin {
        paused = true;
    }

    /// @notice Unpause contract, requires all fees set.
    function releasePause() external onlyAdmin {
        paused = false;
    }

    /// @notice Whitelist management or toggle whitelist enabled.
    /// @param _user Address to whitelist/unwhitelist, or zero address to toggle whitelist.
    function manageWhitelist(address[] calldata _user) external onlyAdmin {
        uint256 length = _user.length;
        for (uint256 i = 0; i < length; i++) {
            require(_user[i] != address(0), "ShiftManager: zero address");
            isWhitelisted[_user[i]] = !isWhitelisted[_user[i]];
        }
    }

    /// @notice Toggles the whitelist feature on or off.
    function toggleWhitelist() external onlyAdmin {
        whitelistEnabled = !whitelistEnabled;
    }

    /// @notice Update fee collector address.
    /// @param _newFeeCollector New fee collector address.
    function updateFeeCollector(address _newFeeCollector) external onlyAdmin {
        require(_newFeeCollector != address(0), "ShiftManager: zero fee collector");
        feeCollector = _newFeeCollector;
    }

    function updateExecutor(address _newExecutor) external onlyAdmin {
        require(_newExecutor != address(0), "ShiftManager: zero executor");
        executor = _newExecutor;
    }

    /// @notice Update timelock duration.
    /// @param _newTimelock New timelock value.
    function updateTimelock(uint32 _newTimelock) external onlyAdmin {
        require(_newTimelock > 0 && _newTimelock <= 30 days, "ShiftManager: invalid timelock");
        timelock = _newTimelock;
    }

    /// @notice Update minimum deposit amount.
    /// @param _amount New minimum deposit, token precision.
    function updateMinDeposit(uint256 _amount) external onlyAdmin {
        _validateDepositAndTvl(_amount, maxTvl);
        minDepositAmount = _amount;
    }

    /// @notice Convert basis points to 18-decimal fixed point.
    /// @param _feeBps Fee in basis points.
    /// @return Fee as 18-decimal fixed point.
    function _calc18ptFromBps(uint16 _feeBps) internal pure returns (uint256) {
        return (uint256(_feeBps) * 1e18) / 10_000;
    }

    /// @notice Validates deposit and TVL constraints.
    /// @param _minDeposit The new minimum deposit.
    /// @param _maxTvl The new maximum TVL.
    function _validateDepositAndTvl(uint256 _minDeposit, uint256 _maxTvl) internal pure {
        require(_minDeposit > 0, "ShiftManager: zero min deposit");
        require(_maxTvl > 0, "ShiftManager: zero max TVL");
        require(_minDeposit <= _maxTvl, "ShiftManager: min deposit exceeds max TVL");
    }
}

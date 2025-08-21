// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessModifier} from "./utils/AccessModifier.sol";
import {ShiftManagerArgs} from "./utils/Structs.sol";
import {SECONDS_IN_YEAR} from "./utils/Constants.sol";

/// @title ShiftManager
/// @notice Shift protocol parameters, fees, and whitelist management.
/// @dev Inherits from AccessModifier for access control.
abstract contract ShiftManager is AccessModifier {
    address public feeCollector;
    address public executor;
    uint256 public minDepositAmount;
    uint256 public maxTvl;
    uint256 public performanceFee18pt; // 1% = 0.01 * 10^18
    uint256 public maintenanceFeePerSecond18pt; // 1% = 0.01 * 10^18
    uint32 public timelock;
    uint16 public freshness;
    uint16 public requestValidity;
    bool public whitelistEnabled = true;
    bool public paused = true;

    mapping(address => bool) internal isWhitelisted;

    event MaxTvlUpdated(uint256 oldValue, uint256 newValue);
    event MaintenanceFeeUpdated(uint256 oldValue, uint256 newValue);
    event PerformanceFeeUpdated(uint256 oldValue, uint256 newValue);
    event WhitelistUpdated(address user, bool isWhitelisted);
    event WhitelistToggled(bool enabled);
    event FeeCollectorUpdated(address oldValue, address newValue);
    event ExecutorUpdated(address oldValue, address newValue);
    event TimelockUpdated(uint32 oldValue, uint32 newValue);
    event FreshnessUpdated(uint16 oldValue, uint16 newValue);
    event RequestValidityUpdated(uint16 oldValue, uint16 newValue);
    event MinDepositUpdated(uint256 oldValue, uint256 newValue);

    /// @notice Ensures contract is not paused.
    modifier notPaused() {
        require(!paused, "ShiftManager: paused");
        _;
    }

    /// @notice Initializes the ShiftManager contract with protocol parameters.
    /// @param _args Struct containing initialization parameters:
    ///   - accessControlContract: Address of access control contract.
    ///   - feeCollector: Address that collects protocol fees.
    ///   - executor: Address authorized to execute certain actions.
    ///   - minDeposit: Minimum allowed deposit.
    ///   - maxTvl: Maximum total value locked.
    ///   - timelock: Timelock duration.
    constructor(ShiftManagerArgs memory _args) AccessModifier(_args.accessControlContract) {
        require(_args.accessControlContract != address(0), "ShiftManager: zero access control");
        require(_args.feeCollector != address(0), "ShiftManager: zero fee collector");
        require(_args.executor != address(0), "ShiftManager: zero executor");
        require(_args.timelock > 0, "ShiftManager: zero timelock");
        require(_args.freshness > 0, "ShiftManager: zero freshness");
        require(_args.requestValidity > 0, "ShiftManager: zero request validity");
        _validateDepositAndTvl(_args.minDeposit, _args.maxTvl);
        feeCollector = _args.feeCollector;
        executor = _args.executor;
        minDepositAmount = _args.minDeposit;
        maxTvl = _args.maxTvl;
        timelock = _args.timelock;
        freshness = _args.freshness;
        requestValidity = _args.requestValidity;
    }

    /// @notice Update maximum total value locked (TVL).
    /// @dev This function will be overridden by child contracts <ShiftVault>.
    /// @dev It is important to ensure that the new TVL cap have the same decimal precision as the tvlFeed.
    /// @param _amount New TVL cap.
    function updateMaxTvl(uint256 _amount) public virtual onlyAdmin {
        _validateDepositAndTvl(minDepositAmount, _amount);
        uint256 oldValue = maxTvl;
        maxTvl = _amount;
        emit MaxTvlUpdated(oldValue, _amount);
    }

    /// @notice Update annual maintenance fee (basis points).
    /// @dev This function will be overridden by child contracts <ShiftVault>.
    /// @param _annualFeeBps New maintenance fee in basis points (1% = 100bps).
    function updateMaintenanceFee(uint16 _annualFeeBps) public virtual onlyAdmin {
        require(_annualFeeBps <= 10_000, "ShiftManager: maintenance fee exceeds 100%");
        uint256 oldValue = maintenanceFeePerSecond18pt;
        maintenanceFeePerSecond18pt = _calc18ptFromBps(_annualFeeBps) / uint256(SECONDS_IN_YEAR);
        emit MaintenanceFeeUpdated(oldValue, maintenanceFeePerSecond18pt);
    }

    /// @notice Update performance fee (basis points).
    /// @dev This function will be overridden by child contracts <ShiftVault>.
    /// @param _feeBps New performance fee in basis points (1% = 100bps).
    function updatePerformanceFee(uint16 _feeBps) public virtual onlyAdmin {
        require(_feeBps <= 10_000, "ShiftManager: performance fee exceeds 100%");
        uint256 oldValue = performanceFee18pt;
        performanceFee18pt = _calc18ptFromBps(_feeBps);
        emit PerformanceFeeUpdated(oldValue, performanceFee18pt);
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
            emit WhitelistUpdated(_user[i], isWhitelisted[_user[i]]);
        }
    }

    /// @notice Toggles the whitelist feature on or off.
    function toggleWhitelist() external onlyAdmin {
        whitelistEnabled = !whitelistEnabled;
        emit WhitelistToggled(whitelistEnabled);
    }

    /// @notice Update fee collector address.
    /// @param _newFeeCollector New fee collector address.
    function updateFeeCollector(address _newFeeCollector) external onlyAdmin {
        require(_newFeeCollector != address(0), "ShiftManager: zero fee collector");
        address oldValue = feeCollector;
        feeCollector = _newFeeCollector;
        emit FeeCollectorUpdated(oldValue, _newFeeCollector);
    }

    /// @notice Update executor address.
    /// @param _newExecutor New executor address.
    function updateExecutor(address _newExecutor) external onlyAdmin {
        require(_newExecutor != address(0), "ShiftManager: zero executor");
        address oldValue = executor;
        executor = _newExecutor;
        emit ExecutorUpdated(oldValue, _newExecutor);
    }

    /// @notice Update timelock duration.
    /// @param _newTimelock New timelock value.
    function updateTimelock(uint32 _newTimelock) external onlyAdmin {
        require(_newTimelock > 0 && _newTimelock <= 30 days, "ShiftManager: invalid timelock");
        uint32 oldValue = timelock;
        timelock = _newTimelock;
        emit TimelockUpdated(oldValue, _newTimelock);
    }

    /// @notice Updates the freshness parameter, which determines the data validity.
    /// @param _newFreshness New freshness value.
    function updateFreshness(uint16 _newFreshness) external onlyAdmin {
        require(_newFreshness > 0, "ShiftManager: zero freshness");
        uint16 oldValue = freshness;
        freshness = _newFreshness;
        emit FreshnessUpdated(oldValue, _newFreshness);
    }

    /// @notice Update request validity duration.
    /// @param _newRequestValidity New request validity value.
    function updateRequestValidity(uint16 _newRequestValidity) external onlyAdmin {
        require(_newRequestValidity > 0, "ShiftManager: zero request validity");
        uint16 oldValue = requestValidity;
        requestValidity = _newRequestValidity;
        emit RequestValidityUpdated(oldValue, _newRequestValidity);
    }

    /// @notice Update minimum deposit amount.
    /// @param _amount New minimum deposit, token precision.
    function updateMinDeposit(uint256 _amount) external onlyAdmin {
        _validateDepositAndTvl(_amount, maxTvl);
        uint256 oldValue = minDepositAmount;
        minDepositAmount = _amount;
        emit MinDepositUpdated(oldValue, _amount);
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

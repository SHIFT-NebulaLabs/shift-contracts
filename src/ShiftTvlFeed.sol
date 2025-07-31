// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IShiftVault} from "./interface/IShiftVault.sol";
import {AccessModifier} from "./utils/AccessModifier.sol";

/// @title ShiftTvlFeed
/// @notice TVL (Total Value Locked) feed for Shift protocol.
/// @dev Inherits from AccessModifier for access control.
contract ShiftTvlFeed is AccessModifier {
    IShiftVault public shiftVault;

    struct TvlData {
        uint256 value;
        uint256 timestamp;
    }

    TvlData[] internal tvlHistory;
    bool public init;

    event TvlUpdated(uint256 newValue, uint256 timestamp);

    modifier initialized() {
        require(init, "ShiftTvlFeed: not initialized");
        _;
    }

    constructor(address _accessControlContract) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "ShiftTvlFeed: zero access control address");
    }

    /// @notice Initialize contract with ShiftVault address.
    /// @param _shiftVaultContract Address of ShiftVault contract.
    function initialize(address _shiftVaultContract) external onlyAdmin {
        require(!init, "ShiftTvlFeed: already initialized");
        require(_shiftVaultContract != address(0), "ShiftTvlFeed: zero vault address");
        shiftVault = IShiftVault(_shiftVaultContract);
        init = true;
    }

    /// @notice Update TVL and store in history.
    /// @param _value TVL value to record.
    function updateTvl(uint256 _value) external onlyOracle initialized {
        tvlHistory.push(TvlData({value: _value, timestamp: block.timestamp}));
        emit TvlUpdated(_value, block.timestamp);
    }

    /// @notice Update TVL for a deposit and allow deposit for user.
    /// @param _user User address making the deposit.
    /// @param _value TVL value to record.
    function updateTvlForDeposit(address _user, uint256 _value) external onlyOracle initialized {
        require(_user != address(0), "ShiftTvlFeed: zero user address");
        require(_value > 0, "ShiftTvlFeed: TVL must be positive");
        tvlHistory.push(TvlData({value: _value, timestamp: block.timestamp}));
        shiftVault.allowDeposit(_user, tvlHistory.length - 1);
        emit TvlUpdated(_value, block.timestamp);
    }

    /// @notice Number of decimals for TVL values.
    /// @return Number of decimals (6).
    function decimals() external pure returns (uint8) {
        return 6;
    }

    /// @notice Get last TVL entry.
    /// @return Most recent TvlData struct.
    function getLastTvl() external view returns (TvlData memory) {
        uint256 len = tvlHistory.length;
        if (len == 0) return TvlData({value: 0, timestamp: 0});
        return tvlHistory[len - 1];
    }

    /// @notice Retrieves a specific TVL (Total Value Locked) entry from the history by index.
    /// @dev Reverts if the provided index is out of bounds.
    /// @param _index The index of the TVL entry to retrieve.
    /// @return The TvlData struct at the specified index in the tvlHistory array.
    function getTvlEntry(uint256 _index) external view returns (TvlData memory) {
        require(_index < tvlHistory.length, "ShiftTvlFeed: index out of bounds");
        return tvlHistory[_index];
    }

    /// @notice Get last `_count` TVL entries in reverse chronological order.
    /// @param _count Number of entries to return.
    /// @return Array of TvlData structs.
    function getLastTvlEntries(uint256 _count) external view returns (TvlData[] memory) {
        uint256 len = tvlHistory.length;
        require(_count > 0, "ShiftTvlFeed: count must be positive");
        if (_count > len) _count = len;
        TvlData[] memory result = new TvlData[](_count);
        for (uint256 i = 0; i < _count; i++) {
            result[i] = tvlHistory[len - 1 - i];
        }
        return result;
    }
}

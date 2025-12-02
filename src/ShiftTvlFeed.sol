// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IShiftVault} from "./interface/IShiftVault.sol";
import {AccessModifier} from "./utils/AccessModifier.sol";
import {
    ZeroAddress,
    NotInitialized,
    AlreadyInitialized,
    IndexOutOfBounds,
    CountMustBePositive,
    SupplyMissmatch
} from "./utils/Errors.sol";

/// @title ShiftTvlFeed
/// @notice TVL (Total Value Locked) feed for Shift protocol.
/// @dev Inherits from AccessModifier for access control.
contract ShiftTvlFeed is AccessModifier {
    IShiftVault public shiftVault;

    struct TvlData {
        uint256 value;
        uint256 timestamp;
        uint256 supplySnapshot;
    }

    TvlData[] internal tvlHistory;
    bool public init;

    event TvlUpdated(uint256 newValue, uint256 timestamp);

    modifier initialized() {
        require(init, NotInitialized());
        _;
    }

    constructor(address _accessControlContract) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), ZeroAddress());
    }

    /// @notice Initialize contract with ShiftVault address.
    /// @param _shiftVaultContract Address of ShiftVault contract.
    function initialize(address _shiftVaultContract) external onlyAdmin {
        require(!init, AlreadyInitialized());
        require(_shiftVaultContract != address(0), ZeroAddress());
        shiftVault = IShiftVault(_shiftVaultContract);
        init = true;
    }

    /// @notice Update TVL and store in history.
    /// @param _value TVL value to record.
    function updateTvl(uint256 _value) external onlyOracle initialized {
        tvlHistory.push(TvlData({value: _value, timestamp: block.timestamp, supplySnapshot: shiftVault.totalSupply()}));
        emit TvlUpdated(_value, block.timestamp);
    }

    /**
     * @notice Updates TVL for a deposit request and authorizes the user to deposit
     * @param _user Address to authorize for deposit (must have active request)
     * @param _value TVL value to record in the new snapshot
     * @param _referenceSupply Supply snapshot captured at request time (must match current)
     */
    function updateTvlForDeposit(address _user, uint256 _value, uint256 _referenceSupply)
        external
        onlyOracle
        initialized
    {
        require(_user != address(0), ZeroAddress());
        uint256 totalSupply = shiftVault.totalSupply();
        require(_referenceSupply == totalSupply, SupplyMissmatch());
        tvlHistory.push(TvlData({value: _value, timestamp: block.timestamp, supplySnapshot: totalSupply}));
        shiftVault.allowDeposit(_user, tvlHistory.length - 1);
        emit TvlUpdated(_value, block.timestamp);
    }

    /// @notice Number of decimals for TVL values.
    /// @return Number of decimals.
    function decimals() external view returns (uint8) {
        return shiftVault.baseToken().decimals();
    }

    /// @notice Get last TVL entry.
    /// @return Most recent TvlData struct.
    function getLastTvl() external view returns (TvlData memory) {
        uint256 len = tvlHistory.length;
        if (len == 0) return TvlData({value: 0, timestamp: 0, supplySnapshot: 0});
        return tvlHistory[len - 1];
    }

    /// @notice Retrieves a specific TVL (Total Value Locked) entry from the history by index.
    /// @dev Reverts if the provided index is out of bounds.
    /// @param _index The index of the TVL entry to retrieve.
    /// @return The TvlData struct at the specified index in the tvlHistory array.
    function getTvlEntry(uint256 _index) external view returns (TvlData memory) {
        require(_index < tvlHistory.length, IndexOutOfBounds());
        return tvlHistory[_index];
    }

    /// @notice Get last `_count` TVL entries in reverse chronological order.
    /// @param _count Number of entries to return.
    /// @return Array of TvlData structs.
    function getLastTvlEntries(uint256 _count) external view returns (TvlData[] memory) {
        uint256 len = tvlHistory.length;
        require(_count > 0, CountMustBePositive());
        if (_count > len) _count = len;
        TvlData[] memory result = new TvlData[](_count);
        for (uint256 i = 0; i < _count; i++) {
            result[i] = tvlHistory[len - 1 - i];
        }
        return result;
    }
}

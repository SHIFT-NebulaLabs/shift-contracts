// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IShiftTvlFeed {
    struct TvlData {
        uint256 value;
        uint256 timestamp;
    }

    event TvlUpdated(uint256 newValue);

    function decimals() external view returns (uint8);
    function updateTvl(uint256 _value) external;
    function getLastTvl() external view returns (TvlData memory);
    function getLastTvlEntries(uint256 _count) external view returns (TvlData[] memory);
}
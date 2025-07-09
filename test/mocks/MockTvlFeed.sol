// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../../src/interface/IShiftTvlFeed.sol";

contract MockTvlFeed is IShiftTvlFeed {
    uint256 public lastTvl;
    uint8 public override decimals = 6;

    TvlData[] public history;

    function setLastTvl(uint256 _tvl) external { lastTvl = _tvl; }

    function getLastTvl() external view override returns (TvlData memory) {
        return TvlData({ value: lastTvl, timestamp: block.timestamp });
    }

    function getLastTvlEntries(uint256 _count) external view override returns (TvlData[] memory) {
        TvlData[] memory arr = new TvlData[](_count);
        for (uint256 i = 0; i < _count; ++i) {
            arr[i] = TvlData({ value: lastTvl, timestamp: block.timestamp });
        }
        return arr;
    }

    function updateTvl(uint256) external override {}

    function allowDeposit(address) external {}
    function updateTvlForDeposit(address, uint256) external {}
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/ShiftTvlFeed.sol";

contract ShiftTvlFeedHarness is ShiftTvlFeed {
    constructor(address _access) ShiftTvlFeed(_access) {}

    function exposed_tvlHistoryLength() external view returns (uint256) {
        return tvlHistory.length;
    }

    function exposed_tvlHistoryAt(uint256 _i) external view returns (TvlData memory) {
        return tvlHistory[_i];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IShiftVault } from "./interface/IShiftVault.sol";
import { AccessModifier } from "./utils/AccessModifier.sol";

contract ShiftTvlFeed is AccessModifier {
    IShiftVault public shiftVault;

    struct TvlData {
        uint256 value;
        uint256 timestamp;
    }

    TvlData[] private tvlHistory_;
    bool public init;

    event TvlUpdated(uint256 newValue, uint256 timestamp);

    modifier initialized() {
        require(init, "ShiftTvlFeed: not initialized");
        _;
    }

    constructor(address _accessControlContract) AccessModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "ShiftTvlFeed: zero access control address");
    }

    function initialize(address _shiftVaultContract) external {
        require(!init, "ShiftTvlFeed: already initialized");
        require(_shiftVaultContract != address(0), "ShiftTvlFeed: zero vault address");
        shiftVault = IShiftVault(_shiftVaultContract);
        init = true;
    }

    function updateTvl(uint256 _value) external onlyOracle initialized {
        tvlHistory_.push(TvlData({ value: _value, timestamp: block.timestamp }));
        emit TvlUpdated(_value, block.timestamp);
    }

    function updateTvlForDeposit(address _user, uint256 _value) external onlyOracle initialized {
        require(_user != address(0), "ShiftTvlFeed: zero user address");
        require(_value > 0, "ShiftTvlFeed: TVL must be positive");
        tvlHistory_.push(TvlData({ value: _value, timestamp: block.timestamp }));
        shiftVault.allowDeposit(_user);
        emit TvlUpdated(_value, block.timestamp);
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }

    function getLastTvl() external view returns (TvlData memory) {
        uint256 len = tvlHistory_.length;
        if (len == 0) return TvlData({ value: 0, timestamp: 0 });
        return tvlHistory_[len - 1];
    }

    function getLastTvlEntries(uint256 _count) external view returns (TvlData[] memory) {
        uint256 len = tvlHistory_.length;
        require(_count > 0, "ShiftTvlFeed: count must be positive");
        if (_count > len) _count = len;
        TvlData[] memory result = new TvlData[](_count);
        for (uint256 i = 0; i < _count; i++) {
            result[i] = tvlHistory_[len - 1 - i];
        }
        return result;
    }
}

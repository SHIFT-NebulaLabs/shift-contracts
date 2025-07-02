// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import { IShiftVault } from "./interface/IShiftVault.sol";
import { ShiftModifier } from "./utils/Modifier.sol";

contract ShiftTvlFeed is ShiftModifier {
    IAccessControl public immutable accessControlContract;
    IShiftVault public shiftVault;

    struct TvlData {
        uint256 value;
        uint256 timestamp;
    }

    TvlData[] private tvlHistory_;
    bool public initialized;

    event TvlUpdated(uint256 newValue);

    constructor(address _accessControlContract) ShiftModifier(_accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        accessControlContract = IAccessControl(_accessControlContract);
    }

    function initialize(address _shiftVaultContract) external {
        require(!initialized, "Contract is already initialized");
        require(_shiftVaultContract != address(0), "Shift vault address cannot be zero");
        shiftVault = IShiftVault(_shiftVaultContract);
        initialized = true;
    }

    function updateTvl(uint256 _value) external onlyOracle {
        tvlHistory_.push(TvlData({ value: _value, timestamp: block.timestamp }));
        emit TvlUpdated(_value);
    }

    function updateTvlForDeposit(address _user, uint256 _value) external onlyOracle {
        tvlHistory_.push(TvlData({ value: _value, timestamp: block.timestamp }));
        shiftVault.allowDeposit(_user);
        emit TvlUpdated(_value);
    }


    function decimals() public view virtual returns (uint8) {
        return 6;
    }

    function getLastTvl() external view returns (TvlData memory) {
        uint256 len = tvlHistory_.length;
        if (len == 0) return TvlData({ value: 0, timestamp: 0 });
        return tvlHistory_[len - 1];
    }

    function getLastTvlEntries(uint256 _count) external view returns (TvlData[] memory) {
        uint256 len = tvlHistory_.length;
        if (_count > len) _count = len;
        TvlData[] memory result = new TvlData[](_count);
        for (uint256 i = 0; i < _count; i++) {
            result[i] = tvlHistory_[len - 1 - i];
        }
        return result;
    }
}
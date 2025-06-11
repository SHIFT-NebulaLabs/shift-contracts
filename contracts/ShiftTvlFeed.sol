// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

contract ShiftTvlFeed {
    bytes32 private constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    uint8 public constant DECIMALS = 8;
    IAccessControl public immutable accessControlContract;

    struct TvlData {
        uint256 value;
        uint256 timestamp;
    }

    TvlData[] private tvlHistory;

    event TvlUpdated(uint256 newValue);

    modifier onlyOracle() {
        require(accessControlContract.hasRole(ORACLE_ROLE, msg.sender), "Caller is not an oracle");
        _;
    }

    constructor(address _accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        accessControlContract = IAccessControl(_accessControlContract);
    }

    function updateTvl(uint256 _value) external onlyOracle {
        tvlHistory.push(TvlData({ value: _value, timestamp: block.timestamp }));
        emit TvlUpdated(_value);
    }

    function getLastTvl() external view returns (TvlData memory) {
        uint256 len = tvlHistory.length;
        if (len == 0) return TvlData({ value: 0, timestamp: 0 });
        return tvlHistory[len - 1];
    }

    function getLastTvlEntries(uint256 _count) external view returns (TvlData[] memory) {
        uint256 len = tvlHistory.length;
        if (_count > len) _count = len;
        TvlData[] memory result = new TvlData[](_count);
        for (uint256 i = 0; i < _count; i++) {
            result[i] = tvlHistory[len - 1 - i];
        }
        return result;
    }
}
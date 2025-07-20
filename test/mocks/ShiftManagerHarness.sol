// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../../src/ShiftManager.sol";

contract ShiftManagerHarness is ShiftManager {
    constructor(
        address _access,
        address _feeCollector,
        uint256 _minDeposit,
        uint256 _maxTvl,
        uint32 _timelock
    ) ShiftManager(_access, _feeCollector, _minDeposit, _maxTvl, _timelock) {}

    function exposed_calc18ptFromBps(uint16 _bps) external pure returns (uint256) {
        return _calc18ptFromBps(_bps);
    }
    function exposed_isWhitelisted(address _user) external view returns (bool) {
        return isWhitelisted[_user];
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../../src/ShiftManager.sol";

contract ShiftManagerHarness is ShiftManager {
    constructor(
        address access,
        address feeCollector,
        uint256 minDeposit,
        uint256 maxTvl,
        uint32 timelock
    ) ShiftManager(access, feeCollector, minDeposit, maxTvl, timelock) {}

    function exposed_calc18ptFromBps(uint16 bps) external pure returns (uint256) {
        return _calc18ptFromBps(bps);
    }
    function exposed_isWhitelisted(address user) external view returns (bool) {
        return isWhitelisted[user];
    }
}
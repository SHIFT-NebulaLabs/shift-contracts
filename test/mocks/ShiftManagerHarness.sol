// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/ShiftManager.sol";
import {ShiftManagerArgs} from "../../src/utils/Struct.sol";

contract ShiftManagerHarness is ShiftManager {
    constructor(ShiftManagerArgs memory _args) ShiftManager(_args) {}

    function exposed_calc18ptFromBps(uint16 _bps) external pure returns (uint256) {
        return _calc18ptFromBps(_bps);
    }

    function exposed_isWhitelisted(address _user) external view returns (bool) {
        return isWhitelisted[_user];
    }
}

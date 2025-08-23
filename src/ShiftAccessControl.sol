// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ZeroAddress} from "./utils/Errors.sol";

/// @title ShiftAccessControl
/// @notice Shift protocol parameters, fees, and whitelist management.
/// @dev Inherits from AccessControl for access control.
contract ShiftAccessControl is AccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");

    constructor(address _admin) {
        require(_admin != address(0), ZeroAddress());
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ZeroAddress, Unauthorized} from "./Errors.sol";

abstract contract AccessModifier {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 private constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 private constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");

    IAccessControl public immutable accessControlContract;

    constructor(address _accessControlContract) {
        require(_accessControlContract != address(0), ZeroAddress());
        accessControlContract = IAccessControl(_accessControlContract);
    }

    modifier onlyAdmin() {
        require(accessControlContract.hasRole(DEFAULT_ADMIN_ROLE, msg.sender), Unauthorized("admin"));
        _;
    }

    modifier onlyOracle() {
        require(accessControlContract.hasRole(ORACLE_ROLE, msg.sender), Unauthorized("oracle"));
        _;
    }

    modifier onlyExecutor() {
        require(accessControlContract.hasRole(EXECUTOR_ROLE, msg.sender), Unauthorized("executor"));
        _;
    }

    modifier onlyClaimer() {
        require(accessControlContract.hasRole(CLAIMER_ROLE, msg.sender), Unauthorized("claimer"));
        _;
    }
}

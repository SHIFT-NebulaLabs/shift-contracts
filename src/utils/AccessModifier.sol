// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

abstract contract AccessModifier {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 private constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    IAccessControl public immutable accessControlContract;

    constructor(address _accessControlContract) {
        require(_accessControlContract != address(0), "Zero address");
        accessControlContract = IAccessControl(_accessControlContract);
    }

    modifier onlyAdmin() {
        require(accessControlContract.hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier onlyOracle() {
        require(accessControlContract.hasRole(ORACLE_ROLE, msg.sender), "Not oracle");
        _;
    }

    modifier onlyExecutor() {
        require(accessControlContract.hasRole(EXECUTOR_ROLE, msg.sender), "Not executor");
        _;
    }
}

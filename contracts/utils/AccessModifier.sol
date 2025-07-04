// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

abstract contract AccessModifier {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    IAccessControl public immutable accessControlContract;

    constructor(address _accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        accessControlContract = IAccessControl(_accessControlContract);
    }

    modifier onlyAdmin() {
        require(
            accessControlContract.hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Caller is not an admin"
        );
        _;
    }
    modifier onlyOracle() {
        require(
            accessControlContract.hasRole(keccak256("ORACLE_ROLE"), msg.sender),
            "Caller is not an oracle"
        );
        _;
    }
    modifier onlyExecutor() {
        require(
            accessControlContract.hasRole(keccak256("EXECUTOR_ROLE"), msg.sender),
            "Caller is not an executor"
        );
        _;
    }
}
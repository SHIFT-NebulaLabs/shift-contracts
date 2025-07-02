// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
//Verify origin??
abstract contract ShiftModifier {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    IAccessControl private immutable accessControlContract_;

    constructor(address _accessControlContract) {
        require(_accessControlContract != address(0), "Access control contract address cannot be zero");
        accessControlContract_ = IAccessControl(_accessControlContract);
    }

    modifier onlyAdmin() {
        require(
            accessControlContract_.hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Caller is not an admin"
        );
        _;
    }
    // Modifier to check if the caller has the oracle role
    modifier onlyOracle() {
        require(
            accessControlContract_.hasRole(keccak256("ORACLE_ROLE"), msg.sender),
            "Caller is not an oracle"
        );
        _;
    }

    // Modifier to check if the caller has the executor role
    modifier onlyExecutor() {
        require(
            accessControlContract_.hasRole(keccak256("EXECUTOR_ROLE"), msg.sender),
            "Caller is not an executor"
        );
        _;
    }
}
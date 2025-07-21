// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

contract MockAccessControl is IAccessControl {
    mapping(bytes32 => mapping(address => bool)) public _roles;

    function hasRole(bytes32 _role, address _account) external view override returns (bool) {
        return _roles[_role][_account];
    }

    function grantRole(bytes32 _role, address account) external {
        _roles[_role][account] = true;
    }
    // Dummy implementations for IAccessControl

    function getRoleAdmin(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function revokeRole(bytes32, address) external pure override {}
    function renounceRole(bytes32, address) external pure override {}
}

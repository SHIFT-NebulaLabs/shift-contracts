// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IShiftVault} from "../interface/IShiftVault.sol";
import {SupplyMissmatch} from "../utils/Errors.sol";

/// @title SupplyValidator
/// @notice Validates supply consistency between vault state and reference snapshots
/// @dev Utility contract for applying supply mismatch protection to existing vault systems
///      Prevents MEV attacks by ensuring supply hasn't changed between request and execution
/// @dev For version 1.0.0 of Shift protocol
contract SupplyValidator {
    bool public isToggled;

    event SupplyValidated();

    /// @notice Validates vault's current supply against a reference snapshot and toggles state
    /// @dev Core protection mechanism against price manipulation between request/execution
    ///      Flow: Capture supply → Store as reference → Later validate → Toggle if matching
    ///      ┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
    ///      │ Capture ref │───►│ Store supply │───►│ Validation  │───►│ State toggle │
    ///      │   supply    │    │  reference   │    │   check     │    │ (if valid)   │
    ///      └─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
    /// @param _vault Address of the vault contract to validate supply for
    /// @param _referenceSupply Reference supply value captured at request time
    function validateSupply(address _vault, uint256 _referenceSupply) external {
        uint256 supply = IShiftVault(_vault).totalSupply();
        require(supply == _referenceSupply, SupplyMissmatch());

        isToggled = !isToggled;

        emit SupplyValidated();
    }
}

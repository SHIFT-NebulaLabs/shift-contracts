// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Struct containing arguments required to initialize a Shift Vault.
/// @param tokenContract Address of the ERC20 token contract managed by the vault.
/// @param tvlFeedContract Address of the contract providing TVL (Total Value Locked) data.
/// @param shareName Name of the vault share token.
/// @param shareSymbol Symbol of the vault share token.
/// @param managerArgs Struct containing configuration parameters for the vault manager.
struct ShiftVaultArgs {
    address tokenContract;
    address tvlFeedContract;
    string shareName;
    string shareSymbol;
    ShiftManagerArgs managerArgs;
}

/// @dev Struct containing configuration parameters for the Shift Manager.
/// @param accessControlContract Address of the contract managing access control.
/// @param feeCollector Address designated to collect protocol fees.
/// @param executor Address authorized to execute vault operations.
/// @param minDeposit Minimum deposit amount allowed in the vault.
/// @param maxTvl Maximum total value locked allowed in the vault.
/// @param timelock Timelock duration (in seconds) for sensitive operations.
struct ShiftManagerArgs {
    address accessControlContract;
    address feeCollector;
    address executor;
    uint256 minDeposit;
    uint256 maxTvl;
    uint32 timelock;
}
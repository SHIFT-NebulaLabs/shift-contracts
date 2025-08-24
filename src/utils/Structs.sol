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
/// @param accessControlContract The address of the contract responsible for managing access control and permissions.
/// @param feeCollector The address designated to collect protocol fees accrued by the vault.
/// @param executor The address authorized to execute vault operations and manage vault activities.
/// @param minDeposit The minimum deposit amount (in wei) allowed in the vault.
/// @param maxTvl The maximum total value locked (TVL, in wei) permitted in the vault.
/// @param timelock The timelock duration (in seconds) required for executing sensitive operations.
/// @param freshness The maximum allowed age (in seconds) for data or price feeds to be considered valid.
/// @param requestValidity The duration (in seconds) for which a request remains valid before expiration.
struct ShiftManagerArgs {
    address accessControlContract;
    address feeCollector;
    address executor;
    uint256 minDeposit;
    uint256 maxTvl;
    uint32 timelock;
    uint16 freshness;
    uint16 requestValidity;
}

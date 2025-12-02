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

/// @notice Tracks the state of a user's deposit request
/// @param isPriceUpdated True if the oracle has validated the price for this request
/// @param expirationTime Timestamp after which the request expires
/// @param requestIndex Index of the TVL snapshot used for this deposit
struct DepositState {
    bool isPriceUpdated;
    uint256 expirationTime;
    uint256 requestIndex;
}

/// @notice Tracks the state of a user's withdrawal request
/// @param batchId ID of the withdrawal batch the request belongs to
/// @param requestedAt Timestamp when the withdrawal was requested
/// @param sharesAmount Amount of LP shares requested for withdrawal
/// @param timelock Timelock duration for this withdrawal
struct WithdrawState {
    uint256 batchId;
    uint256 requestedAt;
    uint256 sharesAmount;
    uint32 timelock;
}

/// @notice Tracks the state of a withdrawal batch
/// @param totalShares Total LP shares included in this batch
/// @param rate Conversion rate for the batch (TVL precision)
struct BatchState {
    uint256 totalShares;
    uint256 rate;
}

/// @notice Snapshot of vault performance at the time of fee calculation
/// @param netProfit Net profit (or loss) since last fee claim, normalized to 6 decimals
/// @param tvl TVL (Total Value Locked) at the time of the snapshot
struct PerformanceSnapshot {
    int256 netProfit;
    uint256 tvl;
}

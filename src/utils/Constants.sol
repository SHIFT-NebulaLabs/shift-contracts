// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
/**
 * @dev Collection of tconstants used throughout the contracts.
 *
 * - `VALIDITY_DURATION`: The duration (in seconds) for which a certain operation or signature remains valid.
 * - `TIMELOCK`: The minimum time interval (in seconds) required for timelock operations.
 * - `SECONDS_IN_YEAR`: The number of seconds in a year, calculated as 365 days.
 */
uint8 constant VALIDITY_DURATION = 60 seconds;
uint32 constant SECONDS_IN_YEAR = 365 days;
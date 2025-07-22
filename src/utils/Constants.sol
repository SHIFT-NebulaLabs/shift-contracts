// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
/**
 * @dev Collection of time-related constants used throughout the contracts.
 *
 * - `REQUEST_VALIDITY`: Duration (in seconds) for which a request remains valid.
 * - `FRESHNESS_VALIDITY`: Duration (in seconds) for which data is considered fresh.
 * - `SECONDS_IN_YEAR`: Number of seconds in a year (365 days).
 */

uint8 constant REQUEST_VALIDITY = 120 seconds;
uint32 constant FRESHNESS_VALIDITY = 1 days;
uint32 constant SECONDS_IN_YEAR = 365 days;

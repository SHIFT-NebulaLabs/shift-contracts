// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
/**
 * @dev Collection of commonly used constants throughout the contracts.
 *
 * - `SECONDS_IN_YEAR`: Number of seconds in a year (365 days).
 * - `MINIMUM_LIQUIDITY`: Minimum liquidity threshold (set to 1,000).
 * - `BURN_ADDRESS`: Standard address used for burning tokens.
 */

uint32 constant SECONDS_IN_YEAR = 365 days;
uint256 constant MINIMUM_LIQUIDITY = 10 ** 3;
address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ==== Access Control Errors ====
error Unauthorized(string _role);
error NotWhitelisted();

// ==== Initialization Errors ====
error AlreadyInitialized();
error NotInitialized();

// ==== General Validation Errors ====
error ZeroAddress();
error ZeroToken();
error OverflowOnNormalization();
error MoreThan18Decimals();
error ParamOutOfBounds(string _param);
error IndexOutOfBounds();
error CountMustBePositive();
error SupplyMissmatch();

// ==== Request & Claim Errors ====
error AlreadyAllowed();
error AlreadyClaimed();
error AlreadyRequested();
error NoValidRequest();
error RequestExpired();
error RequestStillValid();

// ==== Pause & Lock Errors ====
error Paused();
error Locked();

// ==== Deposit & TVL Errors ====
error DepositBelowMinimum();
error ExceedsMaxTVL();
error MinDepositExceedsMaxTvl();
error NewMaxTVLBelowCurrentTVL();
error NotTVLFeed();
error StaleTvlData();
error ZeroCalculated();

// ==== Batch & Withdraw Errors ====
error BatchNotResolved();
error BatchResolved();
error BatchResolvedOrOngoing();
error InsufficientTokensForBatch();
error NoDustToSweep();
error NoSharesToWithdraw();

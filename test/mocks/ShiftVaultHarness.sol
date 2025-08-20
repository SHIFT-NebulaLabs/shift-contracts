// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/ShiftVault.sol";
import {IShiftTvlFeed} from "../../src/interface/IShiftTvlFeed.sol";

contract ShiftVaultHarness is ShiftVault {
    constructor(
        address _access,
        address _token,
        address _tvlFeed,
        address _feeCollector,
        address _executor,
        string memory _shareName,
        string memory _shareSymbol,
        uint256 _minDeposit,
        uint256 _maxTvl,
        uint32 _timelock
    ) ShiftVault(_access, _token, _tvlFeed, _feeCollector, _executor, _shareName, _shareSymbol, _minDeposit, _maxTvl, _timelock) {}

    function exposed_calcSharesFromToken(uint256 _amount, uint256 _tvlIndex) external view returns (uint256) {
        return _calcSharesFromToken(_amount, _tvlIndex);
    }

    function exposed_calcTokenFromShares(uint256 _share, uint256 _rate) external view returns (uint256) {
        return _calcTokenFromShares(_share, _rate);
    }

    function exposed_normalize(uint256 _a, uint8 _d) external view returns (uint256, uint8) {
        return _normalize(_a, _d);
    }

    function exposed_calcPerformanceFee(uint256 _a) external view returns (uint256) {
        return _calcPerformanceFee(_a);
    }

    function exposed_calcMaintenanceFee(uint256 _t, uint256 _p) external view returns (uint256) {
        return _calcMaintenanceFee(_t, _p);
    }

    function exposed_isExpired() external view returns (bool) {
        return _isExpired();
    }

    function exposed_cumulativeDeposit() external view returns (uint256) {
        return cumulativeDeposit;
    }

    function exposed_cumulativeWithdrawn() external view returns (uint256) {
        return cumulativeWithdrawn;
    }

    function exposed_snapshotTvl18pt() external view returns (uint256) {
        return snapshotTvl18pt;
    }

    function exposed_depositState(address _user) external view returns (bool, uint256) {
        DepositState storage s = userDepositStates[_user];
        return (s.isPriceUpdated, s.expirationTime);
    }

    function exposed_userWithdrawState(address _user) external view returns (uint256, uint256, uint256) {
        WithdrawState storage ws = userWithdrawStates[_user];
        return (ws.batchId, ws.requestedAt, ws.sharesAmount);
    }

    function exposed_batchState(uint256 _batchId) external view returns (uint256, uint256) {
        BatchState storage bs = batchWithdrawStates[_batchId];
        return (bs.totalShares, bs.rate);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/ShiftVault.sol";

contract ShiftVaultHarness is ShiftVault {
    constructor(
        address _access,
        address _token,
        address _tvlFeed,
        address _feeCollector,
        uint256 _minDeposit,
        uint256 _maxTvl,
        uint32 _timelock
    ) ShiftVault(_access, _token, _tvlFeed, _feeCollector, _minDeposit, _maxTvl, _timelock) {}

    function exposed_calcSharesFromToken(uint256 _amount, uint256 _tvlIndex) external view returns (uint256) {
        return _calcSharesFromToken(_amount, _tvlIndex);
    }

    function exposed_calcTokenFromShares(uint256 _share, uint256 _rate) external view returns (uint256) {
        return _calcTokenFromShares(_share, _rate);
    }

    function exposed_normalize(uint256 _a, uint8 _d) external view returns (uint256, uint8) {
        return _normalize(_a, _d);
    }

    function exposed_calcPerformanceFee(uint256 _a) external view returns (uint256, uint256) {
        return _calcPerformanceFee(_a);
    }

    function exposed_calcMaintenanceFee(uint256 _t) external view returns (uint256) {
        return _calcMaintenanceFee(_t);
    }

    function exposed_calcBufferValue() external view returns (uint256) {
        return _calcBufferValue();
    }

    function exposed_calcResolverLiquidity(uint256 _bufferAmount) external view returns (uint256) {
        return _calcResolverLiquidity(_bufferAmount);
    }

    function exposed_isExpired() external view returns (bool) {
        return _isExpired();
    }

    function exposed_depositState(address _user) external view returns (bool, uint256) {
        DepositState storage s = depositStates[_user];
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

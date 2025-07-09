// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../../src/ShiftVault.sol";

contract ShiftVaultHarness is ShiftVault {
    constructor(
        address access,
        address token,
        address tvlFeed,
        address feeCollector,
        uint256 minDeposit,
        uint256 maxTvl,
        uint32 timelock
    ) ShiftVault(access, token, tvlFeed, feeCollector, minDeposit, maxTvl, timelock) {}

    function exposed_calcSharesFromToken(uint256 amount) external view returns (uint256) {
        return _calcSharesFromToken(amount);
    }
    function exposed_calcTokenFromShares(uint256 share, uint256 rate) external view returns (uint256) {
        return _calcTokenFromShares(share, rate);
    }
    function exposed_normalize(uint256 a, uint8 d) external view returns (uint256, uint8) {
        return _normalize(a, d);
    }
    function exposed_calcPerformanceFee(uint256 a) external view returns (uint256, uint256) {
        return _calcPerformanceFee(a);
    }
    function exposed_calcMaintenanceFee(uint256 t) external view returns (uint256) {
        return _calcMaintenanceFee(t);
    }
    function exposed_isExpired() external view returns (bool) {
        return _isExpired();
    }
    function exposed_depositState(address user) external view returns (bool, uint256) {
        DepositState storage s = depositStates[user];
        return (s.isPriceUpdated, s.expirationTime);
    }
    function exposed_userWithdrawState(address user) external view returns (uint256, uint256, uint256) {
        WithdrawState storage ws = userWithdrawStates[user];
        return (ws.batchId, ws.requestedAt, ws.sharesAmount);
    }
    function exposed_batchState(uint256 batchId) external view returns (uint256, uint256) {
        BatchState storage bs = batchWithdrawStates[batchId];
        return (bs.totalShares, bs.rate);
    }
}
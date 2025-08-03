// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IShiftVault {
    function allowDeposit(address _user, uint256 _tvlIndex) external;
    function totalSupply() external view returns (uint256);
}

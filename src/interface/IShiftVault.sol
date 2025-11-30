// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IShiftVault {
    function allowDeposit(address _user, uint256 _tvlIndex) external;
    function totalSupply() external view returns (uint256);
    function baseToken() external view returns (ERC20);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract ShiftEarlyAccess {

    mapping (address => bool) private earlyAccessUsers;
    uint256 public earlyAccessCount;

    function joinEarlyAccess() external {
        require(!earlyAccessUsers[msg.sender], "Already a member");
        earlyAccessUsers[msg.sender] = true;
        earlyAccessCount++;
    }
}
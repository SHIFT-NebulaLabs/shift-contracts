// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _customDecimals;

    constructor(uint8 customDecimals) ERC20("Mock", "MOCK") {
        _customDecimals = customDecimals;
        _mint(msg.sender, 1_000_000 * (10 ** customDecimals));
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}
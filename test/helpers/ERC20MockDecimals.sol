// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20MockDecimals is ERC20 {
    uint8 private _decimals;

    constructor(string memory _name, string memory _symbol, uint8 _tokenDecimals) ERC20(_name, _symbol) {
        _decimals = _tokenDecimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

contract ERC20MockMintableDecimals is ERC20, IMintableERC20 {
    uint8 private _decimals;

    constructor(string memory _name, string memory _symbol, uint8 _tokenDecimals) ERC20(_name, _symbol) {
        _decimals = _tokenDecimals;
    }

    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override {
        _burn(from, amount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Testnet is ERC20, Ownable {
    uint8 private immutable DECIMALS;

    constructor(string memory symbol, uint8 tokenDecimals, address owner) ERC20(symbol, symbol) Ownable(owner) {
        DECIMALS = tokenDecimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }
}

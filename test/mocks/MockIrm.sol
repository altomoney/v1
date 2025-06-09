// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IIrm} from "../../contracts/lending/interfaces/IIrm.sol";

contract MockIrm is IIrm {
    address private _market;
    uint256 private _borrowRate;
    uint256 private _interest;

    function setMarket(address market) external override {
        _market = market;
    }

    function setBorrowRate(uint256 borrowRate) external {
        _borrowRate = borrowRate;
    }

    function setInterest(uint256 interest) external {
        _interest = interest;
    }

    function updateInterestRate(uint256, uint256) external override returns (uint256, uint256) {
        return (_borrowRate, _interest);
    }

    function updateInterestRateView(uint256, uint256) external view override returns (uint256, uint256) {
        return (_borrowRate, _interest);
    }
}

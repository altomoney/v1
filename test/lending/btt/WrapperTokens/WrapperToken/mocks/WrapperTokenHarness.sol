// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {WrapperToken} from "@alto/lending/wrappedToken/WrapperToken.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

/// @dev Test harness exposing internal state setters for BTT coverage.
contract WrapperTokenHarness is WrapperToken {
    constructor(string memory name, string memory symbol, address underlyingToken, address owner, address rollOverBot)
        WrapperToken(name, symbol, underlyingToken, owner, rollOverBot)
    {}

    function setExchangeRateForTest(uint256 newExchangeRate) external {
        exchangeRate = newExchangeRate;
    }

    function setPausedForTest(bool status) external {
        paused[PAUSE_TYPE] = status;
    }
}

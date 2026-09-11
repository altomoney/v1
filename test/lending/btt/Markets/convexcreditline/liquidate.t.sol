// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketLiquidateTest is ConvexCreditLineCommon {
    function test_RevertWhenPaused() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.liquidate(CREDIT_ACCOUNT, "", "");
    }

    function test_RevertNonLiquidatableWhenActiveOrFrozen() external {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketNonLiquidatable.selector);
        market.liquidate(address(0), hex"1234", hex"5678");

        _pause(FROZEN_TYPE);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketNonLiquidatable.selector);
        market.liquidate(CREDIT_ACCOUNT, "", "");
    }
}

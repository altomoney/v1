// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketLiquidateTest is ConvexCreditLineCommon {
    function test_RevertWhenPaused() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.liquidate(CREDIT_ACCOUNT, "", "");
    }

    function test_RevertNonLiquidatableWhenActiveOrFrozenWithoutSideEffects() external {
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketNonLiquidatable.selector);
        market.liquidate(address(0), hex"1234", hex"5678");

        vm.clearMockedCalls();
        _pause(FROZEN_TYPE);
        _mockIrmUpdateRevert();
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketNonLiquidatable.selector);
        market.liquidate(CREDIT_ACCOUNT, "", "");

        _assertUnchanged(beforeState);
        assertEq(rewardPool.withdrawCalls(), 0);
    }
}

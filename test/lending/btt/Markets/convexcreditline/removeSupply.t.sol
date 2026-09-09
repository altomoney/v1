// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketRemoveSupplyTest is ConvexCreditLineCommon {
    function test_RevertWhenPaused() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.removeSupply(1, 0, USER, RECEIVER);
    }

    function test_RevertUnsupportedWhenActiveOrFrozenWithoutChangingState() external {
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.removeSupply(0, 0, address(0), address(0));

        vm.clearMockedCalls();
        _pause(FROZEN_TYPE);
        _mockIrmUpdateRevert();
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.removeSupply(type(uint256).max, type(uint256).max, USER, RECEIVER);

        _assertUnchanged(beforeState);
    }
}

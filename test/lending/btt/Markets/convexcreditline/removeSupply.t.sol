// SPDX-License-Identifier: GPL-3.0-or-later
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

    function test_RevertUnsupportedWhenActiveOrFrozen() external {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.removeSupply(0, 0, address(0), address(0));

        _pause(FROZEN_TYPE);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.removeSupply(type(uint256).max, type(uint256).max, USER, RECEIVER);
    }
}

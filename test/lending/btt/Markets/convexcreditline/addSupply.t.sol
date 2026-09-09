// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketAddSupplyTest is ConvexCreditLineCommon {
    function test_RevertWhenPausedOrFrozen() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.addSupply(1, 0, USER);

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        _assertPausedRevert(FROZEN_TYPE);
        market.addSupply(1, 0, USER);
    }

    function test_RevertUnsupportedForEveryInputWithoutChangingState() external {
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.addSupply(0, 0, address(0));
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.addSupply(type(uint256).max, type(uint256).max, USER);

        _assertUnchanged(beforeState);
    }
}

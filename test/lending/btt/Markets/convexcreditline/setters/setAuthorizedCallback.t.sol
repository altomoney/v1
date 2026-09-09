// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetAuthorizedCallbackTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setAuthorizedCallback(USER, true);
    }

    function test_RevertUnsupportedForAllInputsAndStates() external {
        _assertUnsupported(address(0), false);
        _assertUnsupported(USER, true);
        _pause(PAUSE_TYPE);
        _assertUnsupported(USER, false);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        _assertUnsupported(USER, true);
        assertFalse(market.authorizedCallbacks(USER));
    }

    function _assertUnsupported(address callback, bool status) private {
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.setAuthorizedCallback(callback, status);
    }
}

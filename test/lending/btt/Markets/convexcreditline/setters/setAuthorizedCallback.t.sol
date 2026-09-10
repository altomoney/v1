// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetAuthorizedCallbackTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setAuthorizedCallback(USER, true);
    }

    function test_RevertUnsupportedForEveryCallbackAndStatus() external {
        _assertUnsupported(address(0), false);
        _assertUnsupported(address(0), true);
        _assertUnsupported(USER, false);
        _assertUnsupported(USER, true);
    }

    function _assertUnsupported(address callback, bool status) private {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.setAuthorizedCallback(callback, status);
    }
}

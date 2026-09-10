// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetAuthorizedLiquidationPeripheryTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setAuthorizedLiquidationPeriphery(USER, true);
    }

    function test_RevertUnsupportedForEveryPeripheryAndStatus() external {
        _assertUnsupported(address(0), false);
        _assertUnsupported(address(0), true);
        _assertUnsupported(USER, false);
        _assertUnsupported(USER, true);
    }

    function _assertUnsupported(address periphery, bool status) private {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.setAuthorizedLiquidationPeriphery(periphery, status);
    }
}

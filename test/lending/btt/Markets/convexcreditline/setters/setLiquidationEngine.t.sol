// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetLiquidationEngineTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setLiquidationEngine(USER);
    }

    function test_RevertUnsupportedForAllInputsAndStates() external {
        _assertUnsupported(address(0));
        _assertUnsupported(USER);
        _pause(PAUSE_TYPE);
        _assertUnsupported(USER);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        _assertUnsupported(USER);
        assertEq(market.liquidationEngine(), address(0));
    }

    function _assertUnsupported(address engine) private {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnsupportedOperation.selector);
        market.setLiquidationEngine(engine);
    }
}

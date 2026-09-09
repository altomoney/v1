// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetAuthorizedLiquidationPeripheryTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setAuthorizedLiquidationPeriphery(USER, true);
    }

    function test_RevertForZeroPeriphery() external {
        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.setAuthorizedLiquidationPeriphery(address(0), true);
    }

    function test_SetsClearsAndEmitsWithoutAccountingSideEffects() external {
        AccountingState memory beforeState = _state();

        vm.expectEmit(address(market));
        emit IMarketEvents.SetAuthorizedLiquidationPeriphery(USER, true);
        vm.prank(OWNER);
        market.setAuthorizedLiquidationPeriphery(USER, true);
        assertTrue(market.authorizedLiquidationPeriphery(USER));

        vm.expectEmit(address(market));
        emit IMarketEvents.SetAuthorizedLiquidationPeriphery(USER, true);
        vm.prank(OWNER);
        market.setAuthorizedLiquidationPeriphery(USER, true);

        vm.expectEmit(address(market));
        emit IMarketEvents.SetAuthorizedLiquidationPeriphery(USER, false);
        vm.prank(OWNER);
        market.setAuthorizedLiquidationPeriphery(USER, false);
        assertFalse(market.authorizedLiquidationPeriphery(USER));
        _assertUnchanged(beforeState);
    }

    function test_RemainsCallableAcrossPauseStatesButCannotEnableLiquidation() external {
        vm.prank(OWNER);
        market.setAuthorizedLiquidationPeriphery(USER, true);

        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketNonLiquidatable.selector);
        market.liquidate(CREDIT_ACCOUNT, "", "");

        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setAuthorizedLiquidationPeriphery(USER, false);

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setAuthorizedLiquidationPeriphery(USER, true);
        assertTrue(market.authorizedLiquidationPeriphery(USER));
    }
}

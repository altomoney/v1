// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactoryCommon} from "./MintCurveConvexPositionFactoryCommon.t.sol";
import {IMintCurveConvexPositionFactoryErrors, IMintCurveConvexPositionFactoryEvents} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";

contract MintCurveConvexPositionFactory_SetMarketRegistry_Test is MintCurveConvexPositionFactoryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        _expectOwnableUnauthorized(NON_OWNER);
        factory.setMarketRegistry(makeAddr("NewRegistry"));
    }

    function test_RevertWhen_MarketRegistryIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryZeroAddress.selector);
        factory.setMarketRegistry(address(0));
    }

    function test_SetMarketRegistry_WhenMarketRegistryIsValid() public {
        MarketRegistry newRegistry = new MarketRegistry(OWNER);

        vm.expectEmit(true, false, false, true);
        emit IMintCurveConvexPositionFactoryEvents.MarketRegistrySet(address(newRegistry));

        vm.prank(OWNER);
        factory.setMarketRegistry(address(newRegistry));

        assertEq(factory.marketRegistry(), address(newRegistry));
    }
}

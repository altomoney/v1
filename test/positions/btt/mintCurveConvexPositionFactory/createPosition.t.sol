// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactoryCommon} from "./MintCurveConvexPositionFactoryCommon.t.sol";
import {IMintCurveConvexPositionFactoryErrors, IMintCurveConvexPositionFactoryEvents} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {IMintCurveConvexPosition} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MintCurveConvexPositionFactory_CreatePosition_Test is MintCurveConvexPositionFactoryCommon {
    function test_RevertWhen_BeaconIsNotSet() public {
        vm.prank(USER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryBeaconNotSet.selector);
        factory.createPosition(MINT_MARKET);
    }

    function test_RevertWhen_MarketIsNotRegisteredMintMarket() public {
        _setBeacon();

        vm.prank(USER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryUnsupportedMarket.selector);
        factory.createPosition(OTHER_MARKET);
    }

    function test_CreatePosition_WhenMarketIsRegisteredMintMarket() public {
        _setBeacon();

        vm.expectEmit(true, false, false, false);
        emit IMintCurveConvexPositionFactoryEvents.PositionCreated(USER, address(0));

        vm.prank(USER);
        address position = factory.createPosition(MINT_MARKET);

        assertNotEq(position, address(0));
        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPosition(position).factory()), address(factory));
        assertEq(address(IMintCurveConvexPosition(position).market()), MINT_MARKET);
        assertEq(IMintCurveConvexPosition(position).version(), 1);
    }
}

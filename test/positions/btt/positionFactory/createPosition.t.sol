// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionFactoryCommon} from "./PositionFactoryCommon.t.sol";
import {IPosition, PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {IPositionFactoryBase, IPositionFactoryErrors, IPositionFactoryEvents} from "@alto/positions/interfaces/IPositionFactory.sol";
import {IMintCurveConvexPositionBase} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PositionFactory_CreatePosition_Test is PositionFactoryCommon {
    function test_RevertWhen_BeaconIsNotSet() public {
        vm.prank(USER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryUnsupportedType.selector);
        factory.createPosition(PositionType.MINT_CURVE_CONVEX, abi.encode(MINT_MARKET));
    }

    function test_RevertWhen_MarketIsNotRegisteredMintMarket() public {
        _setBeacon();

        vm.prank(USER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryUnsupportedMarket.selector);
        factory.createPosition(PositionType.MINT_CURVE_CONVEX, abi.encode(OTHER_MARKET));
    }

    function test_CreatePosition_WhenMarketIsRegisteredMintMarket() public {
        _setBeacon();

        vm.expectEmit(true, false, true, false);
        emit IPositionFactoryEvents.PositionCreated(USER, address(0), PositionType.MINT_CURVE_CONVEX);

        vm.prank(USER);
        address position = factory.createPosition(PositionType.MINT_CURVE_CONVEX, abi.encode(MINT_MARKET));

        assertNotEq(position, address(0));
        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPositionBase(position).factory()), address(factory));
        assertEq(IMintCurveConvexPositionBase(position).market(), MINT_MARKET);
        assertEq(IPosition(position).version(), 1);
        assertEq(uint8(IPosition(position).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));
    }

    function test_RevertWhen_PositionTypeIsUnsupported() public {
        _setBeacon();

        bytes memory callData = abi.encodeWithSelector(
            IPositionFactoryBase.createPosition.selector, uint8(1), abi.encode(MINT_MARKET)
        );

        vm.prank(USER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryUnsupportedType.selector);
        (bool success,) = address(factory).call(callData);
        assertFalse(success);
    }
}

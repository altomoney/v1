// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionFactoryCommon} from "./PositionFactoryCommon.t.sol";
import {PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {IPositionFactoryErrors, IPositionFactoryEvents} from "@alto/positions/interfaces/IPositionFactory.sol";

contract PositionFactory_SetBeacon_Test is PositionFactoryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        _expectOwnableUnauthorized(NON_OWNER);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));
    }

    function test_RevertWhen_BeaconIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryZeroAddress.selector);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(0));
    }

    function test_RevertWhen_BeaconAlreadySet() public {
        _setBeacon();

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryBeaconAlreadySet.selector);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, makeAddr("OtherBeacon"));
    }

    function test_SetBeacon_WhenBeaconIsNotSet() public {
        vm.expectEmit(true, true, false, true);
        emit IPositionFactoryEvents.BeaconSet(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));

        vm.prank(OWNER);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));

        assertEq(factory.beacon(PositionType.MINT_CURVE_CONVEX), address(positionBeacon));
    }
}

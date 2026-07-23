// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactoryCommon} from "./MintCurveConvexPositionFactoryCommon.t.sol";
import {IMintCurveConvexPositionFactoryErrors, IMintCurveConvexPositionFactoryEvents} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";

contract MintCurveConvexPositionFactory_SetBeacon_Test is MintCurveConvexPositionFactoryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        _expectOwnableUnauthorized(NON_OWNER);
        factory.setBeacon(address(positionBeacon));
    }

    function test_RevertWhen_BeaconIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryZeroAddress.selector);
        factory.setBeacon(address(0));
    }

    function test_RevertWhen_BeaconAlreadySet() public {
        _setBeacon();

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryBeaconAlreadySet.selector);
        factory.setBeacon(makeAddr("OtherBeacon"));
    }

    function test_RevertWhen_BeaconImplementationIsZero() public {
        address emptyBeacon = makeAddr("EmptyBeacon");
        vm.mockCall(emptyBeacon, abi.encodeWithSignature("implementation()"), abi.encode(address(0)));

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryInvalidBeacon.selector);
        factory.setBeacon(emptyBeacon);
    }

    function test_RevertWhen_ImplementationVersionIsUnexpected() public {
        address staleBeacon = makeAddr("StaleBeacon");
        address staleImpl = makeAddr("StaleImpl");
        vm.mockCall(staleBeacon, abi.encodeWithSignature("implementation()"), abi.encode(staleImpl));
        vm.mockCall(staleImpl, abi.encodeWithSignature("version()"), abi.encode(uint256(2)));

        vm.prank(OWNER);
        vm.expectRevert(
            IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryInvalidImplementationVersion.selector
        );
        factory.setBeacon(staleBeacon);
    }

    function test_SetBeacon_WhenBeaconIsNotSet() public {
        vm.expectEmit(true, false, false, true);
        emit IMintCurveConvexPositionFactoryEvents.BeaconSet(address(positionBeacon));

        vm.prank(OWNER);
        factory.setBeacon(address(positionBeacon));

        assertEq(factory.beacon(), address(positionBeacon));
    }
}

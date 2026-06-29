// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionsProxyCommon} from "./PositionsProxyCommon.t.sol";
import {MintCurveConvexPositionUpgraded} from "./implementation/MintCurveConvexPositionUpgraded.sol";
import {IPosition, PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {IMintCurveConvexPositionBase} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MintCurveConvexPositionBeaconUpgrade_Test is PositionsProxyCommon {
    address internal immutable OTHER_OWNER = makeAddr("OtherOwner");

    function test_RevertWhen_NonOwnerUpgradesBeacon() public {
        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        positionBeacon.upgradeTo(address(upgradedImpl));
    }

    function test_OwnerUpgradesBeaconAndExistingPositionsUseNewImplementation() public {
        address position = _createPosition(USER);
        address otherPosition = _createPosition(OTHER_USER);

        assertEq(IPosition(position).version(), 1);
        assertEq(IPosition(otherPosition).version(), 1);
        assertEq(uint8(IPosition(position).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));
        assertEq(uint8(IPosition(otherPosition).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        assertEq(positionBeacon.implementation(), address(upgradedImpl));
        assertEq(IPosition(position).version(), 2);
        assertEq(IPosition(otherPosition).version(), 2);
        assertEq(uint8(IPosition(position).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));
        assertEq(uint8(IPosition(otherPosition).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));
    }

    function test_BeaconUpgradePreservesExistingPositionStorage() public {
        address position = _createPosition(USER);

        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPositionBase(position).factory()), address(factory));
        assertEq(IMintCurveConvexPositionBase(position).market(), MINT_MARKET);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(upgradedPosition.factory()), address(factory));
        assertEq(upgradedPosition.market(), MINT_MARKET);
        assertEq(upgradedPosition.upgradeNonce(), 0);
        assertEq(upgradedPosition.otherOwner(), address(0));
    }

    function test_ExistingPositionCanSetOtherOwnerAfterBeaconUpgrade() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        vm.prank(USER);
        upgradedPosition.setOtherOwner(OTHER_OWNER);

        assertEq(upgradedPosition.otherOwner(), OTHER_OWNER);
    }

    function test_OwnerCanMutateNewStorageAfterBeaconUpgrade() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        vm.startPrank(USER);
        upgradedPosition.setOtherOwner(OTHER_OWNER);
        upgradedPosition.setUpgradeNonce(55);
        vm.stopPrank();

        assertEq(upgradedPosition.otherOwner(), OTHER_OWNER);
        assertEq(upgradedPosition.upgradeNonce(), 55);
    }

    function test_NewPositionUsesUpgradedImplementationAfterBeaconUpgrade() public {
        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        address position = _createPosition(USER);

        assertEq(IPosition(position).version(), 2);
        assertEq(uint8(IPosition(position).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));
        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(IMintCurveConvexPositionBase(position).market(), MINT_MARKET);
    }

    function test_RevertWhen_NonOwnerCallsSetOtherOwnerOnUpgradedPosition() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        vm.prank(NON_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER)
        );
        MintCurveConvexPositionUpgraded(position).setOtherOwner(OTHER_OWNER);
    }

    function test_UpgradedFactoryAndBeaconWorkTogether() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedPositionImpl = new MintCurveConvexPositionUpgraded();

        vm.startPrank(OWNER);
        positionBeacon.upgradeTo(address(upgradedPositionImpl));
        vm.stopPrank();

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        vm.prank(USER);
        upgradedPosition.setOtherOwner(OTHER_OWNER);

        assertEq(IPosition(position).version(), 2);
        assertEq(uint8(IPosition(position).positionType()), uint8(PositionType.MINT_CURVE_CONVEX));
        assertEq(upgradedPosition.otherOwner(), OTHER_OWNER);
        assertEq(address(upgradedPosition.factory()), address(factory));
    }
}

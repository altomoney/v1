// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionsProxyCommon} from "./PositionsProxyCommon.t.sol";
import {MintCurveConvexPositionFactoryUpgraded} from "./implementation/MintCurveConvexPositionFactoryUpgraded.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {IMintCurveConvexPosition} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MintCurveConvexPositionFactoryUpgrade_Test is PositionsProxyCommon {
    address internal immutable ADDED_ADMIN = makeAddr("AddedAdmin");

    function test_RevertWhen_NonOwnerUpgradesFactory() public {
        bool success = false;

        if (_shouldUseSafeProxy()) {
            try this.upgradeFactoryProxyExternal(
                NON_OWNER,
                address(factory),
                "MintCurveConvexPositionFactoryUpgraded.sol",
                abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, true))
            ) {
                success = true;
            } catch (bytes memory reason) {
                assertEq(
                    reason, abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER)
                );
            }
        } else {
            MintCurveConvexPositionFactoryUpgraded upgradedImpl = new MintCurveConvexPositionFactoryUpgraded();

            vm.prank(NON_OWNER);
            vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
            UUPSUpgradeable(address(factory)).upgradeToAndCall(address(upgradedImpl), "");
            return;
        }

        assertFalse(success);
    }

    function test_OwnerUpgradesFactoryAndPreservesExistingStorage() public {
        address createdPosition = _createPosition(USER);
        (MintCurveConvexConfig memory configBefore, address registryBefore, address beaconBefore) =
            _factoryConfigSnapshot();
        address[] memory positionsBefore = factory.positionsOf(USER);

        _upgradeFactoryProxy(
            abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (7, ADDED_ADMIN, true))
        );

        MintCurveConvexPositionFactoryUpgraded upgradedFactory =
            MintCurveConvexPositionFactoryUpgraded(address(factory));

        assertEq(upgradedFactory.owner(), OWNER);
        assertEq(upgradedFactory.addedCounter(), 7);
        assertEq(upgradedFactory.addedAdmin(), ADDED_ADMIN);
        assertTrue(upgradedFactory.addedFlag());

        (MintCurveConvexConfig memory configAfter, address registryAfter, address beaconAfter) =
            _factoryConfigSnapshot();
        address[] memory positionsAfter = upgradedFactory.positionsOf(USER);

        assertEq(registryAfter, registryBefore);
        assertEq(beaconAfter, beaconBefore);
        assertEq(configAfter.curvePool, configBefore.curvePool);
        assertEq(configAfter.convexBooster, configBefore.convexBooster);
        assertEq(configAfter.convexRewardPool, configBefore.convexRewardPool);
        assertEq(configAfter.convexPid, configBefore.convexPid);
        assertEq(configAfter.crv, configBefore.crv);
        assertEq(configAfter.cvx, configBefore.cvx);
        assertEq(positionsBefore.length, 1);
        assertEq(positionsBefore[0], createdPosition);
        assertEq(positionsAfter, positionsBefore);

        vm.prank(USER);
        IMintCurveConvexPosition(createdPosition).transferOwnership(OTHER_USER);
        vm.prank(OTHER_USER);
        IMintCurveConvexPosition(createdPosition).acceptOwnership();

        address[] memory previousOwnerPositions = upgradedFactory.positionsOf(USER);
        address[] memory newOwnerPositions = upgradedFactory.positionsOf(OTHER_USER);
        assertEq(previousOwnerPositions.length, 0);
        assertEq(newOwnerPositions.length, 1);
        assertEq(newOwnerPositions[0], createdPosition);
    }

    function test_OwnerCanMutateNewStorageAfterFactoryUpgrade() public {
        _upgradeFactoryProxy(
            abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, false))
        );

        MintCurveConvexPositionFactoryUpgraded upgradedFactory =
            MintCurveConvexPositionFactoryUpgraded(address(factory));

        vm.startPrank(OWNER);
        upgradedFactory.setAddedCounter(99);
        upgradedFactory.setAddedAdmin(makeAddr("NewAddedAdmin"));
        upgradedFactory.setAddedFlag(true);
        vm.stopPrank();

        assertEq(upgradedFactory.addedCounter(), 99);
        assertEq(upgradedFactory.addedAdmin(), makeAddr("NewAddedAdmin"));
        assertTrue(upgradedFactory.addedFlag());
    }

    function test_CreatePositionWorksAfterFactoryUpgrade() public {
        _upgradeFactoryProxy(
            abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (0, ADDED_ADMIN, false))
        );

        address position = _createPosition(USER);

        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPosition(position).factory()), address(factory));
        assertEq(address(IMintCurveConvexPosition(position).market()), MINT_MARKET);
    }

    function test_RevertWhen_NonOwnerCallsInitializeV2OnUpgradedFactory() public {
        _upgradeFactoryProxy("");

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        MintCurveConvexPositionFactoryUpgraded(address(factory)).initializeV2(1, ADDED_ADMIN, true);
    }

    function test_RevertWhen_InitializeV2CalledTwiceOnUpgradedFactory() public {
        vm.startPrank(OWNER);
        if (_shouldUseSafeProxy()) {
            Upgrades.upgradeProxy(
                address(factory),
                "MintCurveConvexPositionFactoryUpgraded.sol",
                abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, true))
            );
        } else {
            UnsafeUpgrades.upgradeProxy(
                address(factory),
                address(new MintCurveConvexPositionFactoryUpgraded()),
                abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, true))
            );
        }

        vm.expectRevert();
        MintCurveConvexPositionFactoryUpgraded(address(factory)).initializeV2(2, ADDED_ADMIN, false);
        vm.stopPrank();
    }

    function test_ImplementationSlotChangesAfterFactoryUpgrade() public {
        address implBefore = UnsafeUpgrades.getImplementationAddress(address(factory));

        _upgradeFactoryProxy(
            abi.encodeCall(MintCurveConvexPositionFactoryUpgraded.initializeV2, (0, ADDED_ADMIN, false))
        );

        address implAfter = UnsafeUpgrades.getImplementationAddress(address(factory));

        assertNotEq(implBefore, implAfter);
    }

    /// @dev A future factory implementation must remain storage-compatible with the live factory.
    /// @dev `validateUpgrade` shells out to the OZ upgrades-core package via ffi, so it is gated behind the
    ///      repo's VERIFY_PROXY flag (run with `VERIFY_PROXY=true`) to keep the default offline run fast.
    function test_FactoryUpgradeIsLayoutSafe() public {
        if (!_shouldUseSafeProxy()) {
            vm.skip(true);
            return;
        }

        Options memory opts;
        Upgrades.validateUpgrade("MintCurveConvexPositionFactoryUpgraded.sol", opts);
    }
}

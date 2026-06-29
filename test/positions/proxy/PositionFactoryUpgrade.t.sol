// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionsProxyCommon} from "./PositionsProxyCommon.t.sol";
import {PositionFactoryUpgraded} from "./implementation/PositionFactoryUpgraded.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IPositionFactory.sol";
import {IMintCurveConvexPositionBase} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PositionFactoryUpgrade_Test is PositionsProxyCommon {
    address internal immutable ADDED_ADMIN = makeAddr("AddedAdmin");

    function test_RevertWhen_NonOwnerUpgradesFactory() public {
        bool success = false;

        if (_shouldUseSafeProxy()) {
            try this.upgradeFactoryProxyExternal(
                address(factory),
                "PositionFactoryUpgraded.sol",
                abi.encodeCall(PositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, true))
            ) {
                success = true;
            } catch (bytes memory reason) {
                assertEq(
                    reason,
                    abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this))
                );
            }
        } else {
            PositionFactoryUpgraded upgradedImpl = new PositionFactoryUpgraded();

            vm.prank(NON_OWNER);
            vm.expectRevert(
                abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER)
            );
            UUPSUpgradeable(address(factory)).upgradeToAndCall(address(upgradedImpl), "");
            return;
        }

        assertFalse(success);
    }

    function test_OwnerUpgradesFactoryAndPreservesExistingStorage() public {
        (MintCurveConvexConfig memory configBefore, address registryBefore, address beaconBefore, bool swapBefore) =
            _factoryConfigSnapshot();

        _upgradeFactoryProxy(abi.encodeCall(PositionFactoryUpgraded.initializeV2, (7, ADDED_ADMIN, true)));

        PositionFactoryUpgraded upgradedFactory = PositionFactoryUpgraded(address(factory));

        assertEq(upgradedFactory.owner(), OWNER);
        assertEq(upgradedFactory.addedCounter(), 7);
        assertEq(upgradedFactory.addedAdmin(), ADDED_ADMIN);
        assertTrue(upgradedFactory.addedFlag());

        (MintCurveConvexConfig memory configAfter, address registryAfter, address beaconAfter, bool swapAfter) =
            _factoryConfigSnapshot();

        assertEq(registryAfter, registryBefore);
        assertEq(beaconAfter, beaconBefore);
        assertEq(swapAfter, swapBefore);
        assertEq(configAfter.frxUsd, configBefore.frxUsd);
        assertEq(configAfter.curvePool, configBefore.curvePool);
        assertEq(configAfter.convexBooster, configBefore.convexBooster);
        assertEq(configAfter.convexRewardPool, configBefore.convexRewardPool);
        assertEq(configAfter.convexPid, configBefore.convexPid);
        assertEq(configAfter.crv, configBefore.crv);
        assertEq(configAfter.cvx, configBefore.cvx);
    }

    function test_OwnerCanMutateNewStorageAfterFactoryUpgrade() public {
        _upgradeFactoryProxy(abi.encodeCall(PositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, false)));

        PositionFactoryUpgraded upgradedFactory = PositionFactoryUpgraded(address(factory));

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
        _upgradeFactoryProxy(abi.encodeCall(PositionFactoryUpgraded.initializeV2, (0, ADDED_ADMIN, false)));

        address position = _createPosition(USER);

        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPositionBase(position).factory()), address(factory));
        assertEq(IMintCurveConvexPositionBase(position).market(), MINT_MARKET);
    }

    function test_RevertWhen_NonOwnerCallsInitializeV2OnUpgradedFactory() public {
        _upgradeFactoryProxy("");

        vm.prank(NON_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER)
        );
        PositionFactoryUpgraded(address(factory)).initializeV2(1, ADDED_ADMIN, true);
    }

    function test_RevertWhen_InitializeV2CalledTwiceOnUpgradedFactory() public {
        vm.startPrank(OWNER);
        if (_shouldUseSafeProxy()) {
            Upgrades.upgradeProxy(
                address(factory),
                "PositionFactoryUpgraded.sol",
                abi.encodeCall(PositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, true))
            );
        } else {
            UnsafeUpgrades.upgradeProxy(
                address(factory),
                address(new PositionFactoryUpgraded()),
                abi.encodeCall(PositionFactoryUpgraded.initializeV2, (1, ADDED_ADMIN, true))
            );
        }

        vm.expectRevert();
        PositionFactoryUpgraded(address(factory)).initializeV2(2, ADDED_ADMIN, false);
        vm.stopPrank();
    }

    function test_ImplementationSlotChangesAfterFactoryUpgrade() public {
        address implBefore = UnsafeUpgrades.getImplementationAddress(address(factory));

        _upgradeFactoryProxy(abi.encodeCall(PositionFactoryUpgraded.initializeV2, (0, ADDED_ADMIN, false)));

        address implAfter = UnsafeUpgrades.getImplementationAddress(address(factory));

        assertNotEq(implBefore, implAfter);
    }
}

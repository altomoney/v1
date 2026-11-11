// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionsProxyCommon} from "./PositionsProxyCommon.t.sol";
import {MintCurveConvexPositionUpgraded} from "./implementation/MintCurveConvexPositionUpgraded.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {IMintCurveConvexPosition} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

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

        assertEq(MintCurveConvexPosition(position).version(), 1);
        assertEq(MintCurveConvexPosition(otherPosition).version(), 1);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        assertEq(positionBeacon.implementation(), address(upgradedImpl));
        assertEq(MintCurveConvexPosition(position).version(), 2);
        assertEq(MintCurveConvexPosition(otherPosition).version(), 2);
    }

    function test_BeaconUpgradePreservesExistingPositionStorage() public {
        address position = _createPosition(USER);

        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPosition(position).factory()), address(factory));
        assertEq(address(IMintCurveConvexPosition(position).market()), MINT_MARKET);
        // Snapshot the config/borrow-token fields that occupy the newly consumed gap slots.
        (address curvePoolBefore,,,,,) = IMintCurveConvexPosition(position).config();
        assertEq(curvePoolBefore, address(curvePool));
        assertEq(IMintCurveConvexPosition(position).borrowToken(), DUSD);
        assertEq(IMintCurveConvexPosition(position).indexOfBorrowTokenInPool(), 0);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(upgradedPosition.factory()), address(factory));
        assertEq(address(upgradedPosition.market()), MINT_MARKET);
        // The strategy config, cached borrow token, and coin index survive the implementation swap.
        (
            address curvePoolAfter,
            address convexBoosterAfter,
            address convexRewardPoolAfter,
            uint256 convexPidAfter,
            address crvAfter,
            address cvxAfter
        ) = upgradedPosition.config();
        assertEq(curvePoolAfter, address(curvePool), "curvePool preserved");
        assertEq(convexBoosterAfter, CONVEX_BOOSTER, "convexBooster preserved");
        assertEq(convexRewardPoolAfter, CONVEX_REWARD_POOL, "convexRewardPool preserved");
        assertEq(convexPidAfter, 1, "convexPid preserved");
        assertEq(crvAfter, CRV, "crv preserved");
        assertEq(cvxAfter, CVX, "cvx preserved");
        assertEq(upgradedPosition.borrowToken(), DUSD, "borrowToken preserved");
        assertEq(upgradedPosition.indexOfBorrowTokenInPool(), 0, "coin index preserved");
        // Newly appended V2 storage reads as zero on the pre-existing proxy.
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

        assertEq(MintCurveConvexPosition(position).version(), 2);
        assertEq(OwnableUpgradeable(position).owner(), USER);
        assertEq(address(IMintCurveConvexPosition(position).market()), MINT_MARKET);
    }

    function test_RevertWhen_NonOwnerCallsSetOtherOwnerOnUpgradedPosition() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        MintCurveConvexPositionUpgraded(position).setOtherOwner(OTHER_OWNER);
    }

    function test_InitializeV2SetsNewStorageAfterBeaconUpgrade() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        vm.prank(USER);
        upgradedPosition.initializeV2(42, OTHER_OWNER);

        assertEq(upgradedPosition.upgradeNonce(), 42);
        assertEq(upgradedPosition.otherOwner(), OTHER_OWNER);
    }

    function test_RevertWhen_NonOwnerCallsInitializeV2() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        MintCurveConvexPositionUpgraded(position).initializeV2(42, OTHER_OWNER);
    }

    function test_RevertWhen_InitializeV2CalledTwice() public {
        address position = _createPosition(USER);

        MintCurveConvexPositionUpgraded upgradedImpl = new MintCurveConvexPositionUpgraded();

        vm.prank(OWNER);
        positionBeacon.upgradeTo(address(upgradedImpl));

        MintCurveConvexPositionUpgraded upgradedPosition = MintCurveConvexPositionUpgraded(position);

        vm.startPrank(USER);
        upgradedPosition.initializeV2(42, OTHER_OWNER);
        vm.expectRevert();
        upgradedPosition.initializeV2(7, USER);
        vm.stopPrank();
    }

    /// @dev A future beacon implementation must remain storage-compatible with the live position.
    /// @dev `validateUpgrade` shells out to the OZ upgrades-core package via ffi, so it is gated behind the
    ///      repo's VERIFY_PROXY flag (run with `VERIFY_PROXY=true`) to keep the default offline run fast.
    function test_PositionBeaconUpgradeIsLayoutSafe() public {
        if (!_shouldUseSafeProxy()) {
            vm.skip(true);
            return;
        }

        Options memory opts;
        Upgrades.validateUpgrade("MintCurveConvexPositionUpgraded.sol", opts);
    }
}

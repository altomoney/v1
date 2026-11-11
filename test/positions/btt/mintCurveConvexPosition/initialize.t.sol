// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {IMintCurveConvexPositionErrors} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {MockConvexBooster} from "../mocks/MockConvexBooster.sol";
import {MockConvexRewardPool} from "../mocks/MockConvexRewardPool.sol";

contract MintCurveConvexPosition_Initialize_Test is MintCurveConvexPositionCommon {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function test_RevertWhen_FactoryIsZeroAddress() public {
        bytes memory initData = abi.encodeCall(
            MintCurveConvexPosition.initialize, (OWNER, address(0), address(mintMarket), _defaultConfig())
        );

        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        new BeaconProxy(address(positionBeacon), initData);
    }

    function test_RevertWhen_MarketIsZeroAddress() public {
        bytes memory initData =
            abi.encodeCall(MintCurveConvexPosition.initialize, (OWNER, address(factory), address(0), _defaultConfig()));

        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        new BeaconProxy(address(positionBeacon), initData);
    }

    function test_RevertWhen_OwnerIsZeroAddress() public {
        bytes memory initData = abi.encodeCall(
            MintCurveConvexPosition.initialize, (address(0), address(factory), address(mintMarket), _defaultConfig())
        );

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        new BeaconProxy(address(positionBeacon), initData);
    }

    function test_Initialize_WhenOwnerFactoryAndMarketAreValid() public {
        MintCurveConvexPosition freshPosition = _createPosition(OWNER);

        assertEq(address(freshPosition.factory()), address(factory));
        assertEq(address(freshPosition.market()), address(mintMarket));
        assertEq(freshPosition.owner(), OWNER);
        assertEq(freshPosition.borrowToken(), address(borrowToken), "borrowToken cached from market");

        (
            address curvePool_,
            address convexBooster_,
            address convexRewardPool_,
            uint256 convexPid_,
            address crv_,
            address cvx_
        ) = freshPosition.config();

        assertEq(curvePool_, address(curvePool), "curvePool");
        assertEq(convexBooster_, address(convexBooster), "convexBooster");
        assertEq(convexRewardPool_, address(convexRewardPool), "convexRewardPool");
        assertEq(convexPid_, 1, "convexPid");
        assertEq(crv_, address(crv), "crv");
        assertEq(cvx_, address(cvx), "cvx");
    }

    function test_Initialize_SetsIndexOfBorrowTokenInPool_WhenBorrowTokenIsCoin0() public {
        MintCurveConvexPosition freshPosition = _createPosition(OWNER);

        assertEq(freshPosition.indexOfBorrowTokenInPool(), 0, "borrow token is coin0");
    }

    function test_Initialize_SetsIndexOfBorrowTokenInPool_WhenBorrowTokenIsCoin1() public {
        MockCurvePool pool1 = new MockCurvePool(address(pairToken), address(borrowToken));
        MockConvexRewardPool rp1 = new MockConvexRewardPool(address(pool1), address(crv), address(cvx), 1);
        MockConvexBooster b1 = new MockConvexBooster(address(rp1), address(pool1));

        MintCurveConvexPosition freshPosition =
            _createPositionWithConfig(_config(address(pool1), address(b1), address(rp1)));

        assertEq(freshPosition.borrowToken(), address(borrowToken), "borrowToken cached from market");
        assertEq(freshPosition.indexOfBorrowTokenInPool(), 1, "borrow token is coin1");
    }

    function test_RevertWhen_BorrowTokenNotInCurvePool() public {
        MockCurvePool invalidPool = new MockCurvePool(address(pairToken), address(crv));
        MintCurveConvexConfig memory cfg =
            _config(address(invalidPool), address(convexBooster), address(convexRewardPool));

        bytes memory initData =
            abi.encodeCall(MintCurveConvexPosition.initialize, (OWNER, address(factory), address(mintMarket), cfg));

        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        new BeaconProxy(address(positionBeacon), initData);
    }

    function test_Initialize_EmitsOwnershipTransferred() public {
        bytes memory initData = abi.encodeCall(
            MintCurveConvexPosition.initialize, (OWNER, address(factory), address(mintMarket), _defaultConfig())
        );

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(0), OWNER);
        new BeaconProxy(address(positionBeacon), initData);
    }

    function test_Initialize_InitializesAuthUpgradeable() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        assertTrue(position.isAuthorized(OWNER, AUTHORIZED_SPENDER));
    }

    function test_RevertWhen_ReInitializing() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        position.initialize(OWNER, address(factory), address(mintMarket), _defaultConfig());
    }

    function _defaultConfig() internal view returns (MintCurveConvexConfig memory) {
        return _config(address(curvePool), address(convexBooster), address(convexRewardPool));
    }
}

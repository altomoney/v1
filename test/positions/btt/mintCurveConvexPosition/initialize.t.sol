// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {
    IMintCurveConvexPositionErrors
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MintCurveConvexPosition_Initialize_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_FactoryIsZeroAddress() public {
        bytes memory initData =
            abi.encodeCall(MintCurveConvexPosition.initialize, (OWNER, address(0), address(mintMarket)));

        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        address proxy = address(new BeaconProxy(address(positionBeacon), initData));
        proxy;
    }

    function test_RevertWhen_MarketIsZeroAddress() public {
        bytes memory initData =
            abi.encodeCall(MintCurveConvexPosition.initialize, (OWNER, address(factory), address(0)));

        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        address proxy = address(new BeaconProxy(address(positionBeacon), initData));
        proxy;
    }

    function test_Initialize_WhenFactoryAndMarketAreValid() public {
        MintCurveConvexPosition freshPosition = _createPosition(OWNER);

        assertEq(address(freshPosition.factory()), address(factory));
        assertEq(freshPosition.market(), address(mintMarket));
        assertEq(freshPosition.owner(), OWNER);
    }

    function test_Initialize_InitializesAuthUpgradeable() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        assertTrue(position.isAuthorized(OWNER, AUTHORIZED_SPENDER));
    }

    function test_RevertWhen_ReInitializing() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        position.initialize(OWNER, address(factory), address(mintMarket));
    }
}

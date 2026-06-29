// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionFactoryCommon} from "./PositionFactoryCommon.t.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {IPositionFactoryErrors, IPositionFactoryEvents, MintCurveConvexConfig} from "@alto/positions/interfaces/IPositionFactory.sol";

contract PositionFactory_SetMintCurveConvexConfig_Test is PositionFactoryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        _expectOwnableUnauthorized(NON_OWNER);
        factory.setMintCurveConvexConfig(_validConfig());
    }

    function test_RevertWhen_FrxUsdIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.frxUsd = address(0);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_RevertWhen_CurvePoolIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.curvePool = address(0);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_RevertWhen_ConvexBoosterIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.convexBooster = address(0);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_RevertWhen_ConvexRewardPoolIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.convexRewardPool = address(0);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_RevertWhen_CrvIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.crv = address(0);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_RevertWhen_CvxIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.cvx = address(0);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_RevertWhen_CurvePoolDoesNotHaveTwoCoins() public {
        MockCurvePool invalidPool = new MockCurvePool(DUSD, FRX_USD);
        invalidPool.setNCoins(3);

        MintCurveConvexConfig memory config = _validConfig();
        config.curvePool = address(invalidPool);

        vm.prank(OWNER);
        vm.expectRevert(IPositionFactoryErrors.PositionFactoryInvalidConfig.selector);
        factory.setMintCurveConvexConfig(config);
    }

    function test_SetMintCurveConvexConfig_WhenConfigIsValid() public {
        MintCurveConvexConfig memory config = _validConfig();

        vm.expectEmit(false, false, false, true);
        emit IPositionFactoryEvents.MintCurveConvexConfigSet(config);

        vm.prank(OWNER);
        factory.setMintCurveConvexConfig(config);

        (
            address frxUsd,
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        ) = factory.mintCurveConvexConfig();

        assertEq(frxUsd, config.frxUsd);
        assertEq(curvePool, config.curvePool);
        assertEq(convexBooster, config.convexBooster);
        assertEq(convexRewardPool, config.convexRewardPool);
        assertEq(convexPid, config.convexPid);
        assertEq(crv, config.crv);
        assertEq(cvx, config.cvx);
    }
}

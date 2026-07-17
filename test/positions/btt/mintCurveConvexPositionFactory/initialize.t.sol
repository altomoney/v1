// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactoryCommon} from "./MintCurveConvexPositionFactoryCommon.t.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {
    IMintCurveConvexPositionFactoryErrors,
    IMintCurveConvexPositionFactoryEvents,
    MintCurveConvexConfig
} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";

contract MintCurveConvexPositionFactory_Initialize_Test is MintCurveConvexPositionFactoryCommon {
    function setUp() public override {
        curvePool = new MockCurvePool(DUSD, FRX_USD);
        registry = new MarketRegistry(OWNER);

        // Config validation checks the reward pool's pid matches convexPid (1).
        vm.mockCall(CONVEX_REWARD_POOL, abi.encodeWithSignature("pid()"), abi.encode(uint256(1)));
    }

    function test_RevertWhen_AdminIsZeroAddress() public {
        MintCurveConvexPositionFactory uninitializedFactory = _deployUninitializedFactory();

        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryZeroAddress.selector);
        uninitializedFactory.initialize(address(0), address(registry), _validConfig());
    }

    function test_RevertWhen_MarketRegistryIsZeroAddress() public {
        MintCurveConvexPositionFactory uninitializedFactory = _deployUninitializedFactory();

        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryZeroAddress.selector);
        uninitializedFactory.initialize(OWNER, address(0), _validConfig());
    }

    function test_RevertWhen_CurvePoolIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.curvePool = address(0);
        _expectInvalidConfigOnInitialize(config);
    }

    function test_RevertWhen_ConvexBoosterIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.convexBooster = address(0);
        _expectInvalidConfigOnInitialize(config);
    }

    function test_RevertWhen_ConvexRewardPoolIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.convexRewardPool = address(0);
        _expectInvalidConfigOnInitialize(config);
    }

    function test_RevertWhen_CrvIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.crv = address(0);
        _expectInvalidConfigOnInitialize(config);
    }

    function test_RevertWhen_CvxIsZeroAddress() public {
        MintCurveConvexConfig memory config = _validConfig();
        config.cvx = address(0);
        _expectInvalidConfigOnInitialize(config);
    }

    function test_RevertWhen_CurvePoolDoesNotHaveTwoCoins() public {
        MockCurvePool invalidPool = new MockCurvePool(DUSD, FRX_USD);
        invalidPool.setNCoins(3);

        MintCurveConvexConfig memory config = _validConfig();
        config.curvePool = address(invalidPool);
        _expectInvalidConfigOnInitialize(config);
    }

    function test_RevertWhen_RewardPoolPidDoesNotMatchConvexPid() public {
        MintCurveConvexConfig memory config = _validConfig();
        vm.mockCall(config.convexRewardPool, abi.encodeWithSignature("pid()"), abi.encode(config.convexPid + 1));
        _expectInvalidConfigOnInitialize(config);
    }

    function test_Initialize_WhenAdminMarketRegistryAndConfigAreValid() public {
        MintCurveConvexPositionFactory uninitializedFactory = _deployUninitializedFactory();
        MintCurveConvexConfig memory config = _validConfig();

        vm.expectEmit(true, false, false, true);
        emit IMintCurveConvexPositionFactoryEvents.MarketRegistrySet(address(registry));
        vm.expectEmit(false, false, false, true);
        emit IMintCurveConvexPositionFactoryEvents.MintCurveConvexConfigSet(config);

        uninitializedFactory.initialize(OWNER, address(registry), config);

        assertEq(uninitializedFactory.marketRegistry(), address(registry));
        assertEq(uninitializedFactory.owner(), OWNER);

        (address curvePool_,,,,,) = uninitializedFactory.config();
        assertEq(curvePool_, config.curvePool, "config stored at initialize");
    }

    function test_RevertWhen_ReInitializing() public {
        MintCurveConvexPositionFactory initializedFactory = _deployInitializedFactory();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        initializedFactory.initialize(OWNER, address(registry), _validConfig());
    }

    function _expectInvalidConfigOnInitialize(MintCurveConvexConfig memory config) internal {
        MintCurveConvexPositionFactory uninitializedFactory = _deployUninitializedFactory();

        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryInvalidConfig.selector);
        uninitializedFactory.initialize(OWNER, address(registry), config);
    }
}

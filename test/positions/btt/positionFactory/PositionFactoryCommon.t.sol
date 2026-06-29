// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PositionFactory} from "@alto/positions/PositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {
    IPositionFactoryErrors,
    IPositionFactoryEvents,
    MintCurveConvexConfig
} from "@alto/positions/interfaces/IPositionFactory.sol";
import {IMintCurveConvexPositionBase} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";

abstract contract PositionFactoryCommon is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");
    address internal immutable USER = makeAddr("User");
    address internal immutable MINT_MARKET = makeAddr("MintMarket");
    address internal immutable OTHER_MARKET = makeAddr("OtherMarket");

    address internal immutable FRX_USD = makeAddr("FrxUsd");
    address internal immutable DUSD = makeAddr("Dusd");
    MockCurvePool internal curvePool;
    address internal immutable CONVEX_BOOSTER = makeAddr("ConvexBooster");
    address internal immutable CONVEX_REWARD_POOL = makeAddr("ConvexRewardPool");
    address internal immutable CRV = makeAddr("Crv");
    address internal immutable CVX = makeAddr("Cvx");

    MarketRegistry internal registry;
    PositionFactory internal factory;
    MintCurveConvexPosition internal positionImplementation;
    PositionBeacon internal positionBeacon;

    function setUp() public virtual {
        curvePool = new MockCurvePool(DUSD, FRX_USD);

        registry = new MarketRegistry(OWNER);

        vm.startPrank(OWNER);
        registry.addMintMarket(MINT_MARKET);
        vm.stopPrank();

        factory = _deployInitializedFactory();
        positionImplementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(positionImplementation), OWNER);
    }

    function _deployUninitializedFactory() internal returns (PositionFactory) {
        return PositionFactory(UnsafeUpgrades.deployUUPSProxy(address(new PositionFactory()), ""));
    }

    function _deployInitializedFactory() internal returns (PositionFactory) {
        PositionFactory deployed = _deployUninitializedFactory();
        deployed.initialize(OWNER, address(registry));
        return deployed;
    }

    function _validConfig() internal view returns (MintCurveConvexConfig memory config) {
        config = MintCurveConvexConfig({
            frxUsd: FRX_USD,
            curvePool: address(curvePool),
            convexBooster: CONVEX_BOOSTER,
            convexRewardPool: CONVEX_REWARD_POOL,
            convexPid: 1,
            crv: CRV,
            cvx: CVX
        });
    }

    function _setBeacon() internal {
        vm.prank(OWNER);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));
    }

    function _expectOwnableUnauthorized(address caller) internal {
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PositionFactory} from "@alto/positions/PositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IPositionFactory.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {PositionFactoryUpgraded} from "./implementation/PositionFactoryUpgraded.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockCurvePool} from "../btt/mocks/MockCurvePool.sol";

abstract contract PositionsProxyCommon is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");
    address internal immutable USER = makeAddr("User");
    address internal immutable OTHER_USER = makeAddr("OtherUser");
    address internal immutable MINT_MARKET = makeAddr("MintMarket");

    address internal immutable FRX_USD = makeAddr("FrxUsd");
    address internal immutable DUSD = makeAddr("Dusd");
    MockCurvePool internal curvePool;
    address internal immutable CONVEX_BOOSTER = makeAddr("ConvexBooster");
    address internal immutable CONVEX_REWARD_POOL = makeAddr("ConvexRewardPool");
    address internal immutable CRV = makeAddr("Crv");
    address internal immutable CVX = makeAddr("Cvx");
    address internal immutable SWAP_TARGET = makeAddr("SwapTarget");

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

        vm.startPrank(OWNER);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));
        factory.setMintCurveConvexConfig(_validConfig());
        factory.setApprovedSwapTarget(SWAP_TARGET, true);
        vm.stopPrank();
    }

    function _deployInitializedFactory() internal returns (PositionFactory) {
        PositionFactory deployed = PositionFactory(
            UnsafeUpgrades.deployUUPSProxy(address(new PositionFactory()), "")
        );
        deployed.initialize(OWNER, address(registry));
        return deployed;
    }

    function _shouldUseSafeProxy() internal view returns (bool) {
        return vm.envOr("VERIFY_PROXY", false);
    }

    function _upgradeFactoryProxy(bytes memory data) internal {
        vm.startPrank(OWNER);
        if (_shouldUseSafeProxy()) {
            Upgrades.upgradeProxy(address(factory), "PositionFactoryUpgraded.sol", data);
        } else {
            UnsafeUpgrades.upgradeProxy(address(factory), address(new PositionFactoryUpgraded()), data);
        }
        vm.stopPrank();
    }

    function upgradeFactoryProxyExternal(address proxy, string memory contractName, bytes memory data) external {
        Upgrades.upgradeProxy(proxy, contractName, data);
    }

    function upgradeFactoryProxyExternalUnsafe(address proxy, address newImpl, bytes memory data) external {
        UnsafeUpgrades.upgradeProxy(proxy, newImpl, data);
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

    function _createPosition(address owner) internal returns (address position) {
        vm.prank(owner);
        position = factory.createPosition(PositionType.MINT_CURVE_CONVEX, abi.encode(MINT_MARKET));
    }

    function _factoryConfigSnapshot()
        internal
        view
        returns (MintCurveConvexConfig memory config, address marketRegistry, address beaconAddr, bool swapApproved)
    {
        marketRegistry = factory.marketRegistry();
        beaconAddr = factory.beacon(PositionType.MINT_CURVE_CONVEX);
        swapApproved = factory.approvedSwapTarget(SWAP_TARGET);
        config = _readFactoryConfig();
    }

    function _readFactoryConfig() internal view returns (MintCurveConvexConfig memory config) {
        (
            config.frxUsd,
            config.curvePool,
            config.convexBooster,
            config.convexRewardPool,
            config.convexPid,
            config.crv,
            config.cvx
        ) = factory.mintCurveConvexConfig();
    }
}

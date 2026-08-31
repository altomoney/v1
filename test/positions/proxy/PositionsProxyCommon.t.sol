// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {MintCurveConvexPositionFactoryUpgraded} from "./implementation/MintCurveConvexPositionFactoryUpgraded.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockCurvePool} from "../btt/mocks/MockCurvePool.sol";

abstract contract PositionsProxyCommon is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");
    address internal immutable USER = makeAddr("User");
    address internal immutable OTHER_USER = makeAddr("OtherUser");
    address internal immutable MINT_MARKET = makeAddr("MintMarket");

    address internal immutable PAIR_TOKEN = makeAddr("PairToken");
    address internal immutable DUSD = makeAddr("Dusd");
    MockCurvePool internal curvePool;
    address internal immutable CONVEX_BOOSTER = makeAddr("ConvexBooster");
    address internal immutable CONVEX_REWARD_POOL = makeAddr("ConvexRewardPool");
    address internal immutable CRV = makeAddr("Crv");
    address internal immutable CVX = makeAddr("Cvx");

    MarketRegistry internal registry;
    MintCurveConvexPositionFactory internal factory;
    MintCurveConvexPosition internal positionImplementation;
    PositionBeacon internal positionBeacon;

    function setUp() public virtual {
        curvePool = new MockCurvePool(DUSD, PAIR_TOKEN);

        registry = new MarketRegistry(OWNER);

        vm.startPrank(OWNER);
        registry.addMintMarket(MINT_MARKET);
        vm.stopPrank();

        // Positions read borrowToken() from the market at initialization; DUSD is coin0 of the pool.
        vm.mockCall(MINT_MARKET, abi.encodeWithSignature("borrowToken()"), abi.encode(DUSD));

        // Config validation checks the reward pool's pid matches convexPid (1).
        vm.mockCall(CONVEX_REWARD_POOL, abi.encodeWithSignature("pid()"), abi.encode(uint256(1)));

        // Config validation binds the booster's poolInfo(pid) to the curve pool and reward pool.
        vm.mockCall(
            CONVEX_BOOSTER,
            abi.encodeWithSignature("poolInfo(uint256)"),
            abi.encode(address(curvePool), address(0), address(0), CONVEX_REWARD_POOL, address(0), false)
        );

        factory = _deployInitializedFactory();
        positionImplementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(positionImplementation), OWNER);

        vm.startPrank(OWNER);
        factory.setBeacon(address(positionBeacon));
        vm.stopPrank();
    }

    function _deployInitializedFactory() internal returns (MintCurveConvexPositionFactory) {
        MintCurveConvexPositionFactory deployed = MintCurveConvexPositionFactory(
            UnsafeUpgrades.deployUUPSProxy(address(new MintCurveConvexPositionFactory()), "")
        );
        deployed.initialize(OWNER, address(registry), _validConfig());
        return deployed;
    }

    function _shouldUseSafeProxy() internal view returns (bool) {
        return vm.envOr("VERIFY_PROXY", false);
    }

    function _upgradeFactoryProxy(bytes memory data) internal {
        vm.startPrank(OWNER);
        if (_shouldUseSafeProxy()) {
            Upgrades.upgradeProxy(address(factory), "MintCurveConvexPositionFactoryUpgraded.sol", data);
        } else {
            UnsafeUpgrades.upgradeProxy(address(factory), address(new MintCurveConvexPositionFactoryUpgraded()), data);
        }
        vm.stopPrank();
    }

    /// @dev Pranks inside this frame so the underlying `upgradeToAndCall` originates with `caller` as msg.sender
    ///      (a plain vm.prank at the test level would not propagate into the OZ upgrade call).
    function upgradeFactoryProxyExternal(address caller, address proxy, string memory contractName, bytes memory data)
        external
    {
        vm.startPrank(caller);
        Upgrades.upgradeProxy(proxy, contractName, data);
        vm.stopPrank();
    }

    function _validConfig() internal view returns (MintCurveConvexConfig memory config) {
        config = MintCurveConvexConfig({
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
        position = factory.createPosition(MINT_MARKET);
    }

    function _factoryConfigSnapshot()
        internal
        view
        returns (MintCurveConvexConfig memory config, address marketRegistry, address beaconAddr)
    {
        marketRegistry = factory.marketRegistry();
        beaconAddr = factory.beacon();
        config = _readFactoryConfig();
    }

    function _readFactoryConfig() internal view returns (MintCurveConvexConfig memory config) {
        (config.curvePool, config.convexBooster, config.convexRewardPool, config.convexPid, config.crv, config.cvx) =
            factory.config();
    }
}

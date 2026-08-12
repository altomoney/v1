// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {
    IMintCurveConvexPositionFactoryErrors,
    IMintCurveConvexPositionFactoryEvents,
    MintCurveConvexConfig
} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";

abstract contract MintCurveConvexPositionFactoryCommon is Test {
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
    MintCurveConvexPositionFactory internal factory;
    MintCurveConvexPosition internal positionImplementation;
    PositionBeacon internal positionBeacon;

    function setUp() public virtual {
        curvePool = new MockCurvePool(DUSD, FRX_USD);

        registry = new MarketRegistry(OWNER);

        vm.startPrank(OWNER);
        registry.addMintMarket(MINT_MARKET);
        vm.stopPrank();

        // Positions read borrowToken() from the market at initialization; DUSD is coin0 of the pool.
        vm.mockCall(MINT_MARKET, abi.encodeWithSignature("borrowToken()"), abi.encode(DUSD));

        // Config validation checks the reward pool's pid matches convexPid (1).
        vm.mockCall(CONVEX_REWARD_POOL, abi.encodeWithSignature("pid()"), abi.encode(uint256(1)));
        vm.mockCall(CONVEX_REWARD_POOL, abi.encodeWithSignature("rewardToken()"), abi.encode(CRV));

        // Config validation binds the booster's poolInfo(pid) to the curve pool and reward pool.
        _mockPoolInfo(CONVEX_BOOSTER, address(curvePool), CONVEX_REWARD_POOL, false);

        factory = _deployInitializedFactory();
        positionImplementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(positionImplementation), OWNER);
    }

    function _deployUninitializedFactory() internal returns (MintCurveConvexPositionFactory) {
        return MintCurveConvexPositionFactory(
            UnsafeUpgrades.deployUUPSProxy(address(new MintCurveConvexPositionFactory()), "")
        );
    }

    function _deployInitializedFactory() internal returns (MintCurveConvexPositionFactory) {
        MintCurveConvexPositionFactory deployed = _deployUninitializedFactory();
        deployed.initialize(OWNER, address(registry), _validConfig());
        return deployed;
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

    function _setBeacon() internal {
        vm.prank(OWNER);
        factory.setBeacon(address(positionBeacon));
    }

    function _expectOwnableUnauthorized(address caller) internal {
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
    }

    /// @dev Mocks a Convex booster's poolInfo(pid) registry entry used by config validation.
    function _mockPoolInfo(address booster, address lptoken, address crvRewards, bool shutdown) internal {
        vm.mockCall(
            booster,
            abi.encodeWithSignature("poolInfo(uint256)"),
            abi.encode(lptoken, address(0), address(0), crvRewards, address(0), shutdown)
        );
    }
}

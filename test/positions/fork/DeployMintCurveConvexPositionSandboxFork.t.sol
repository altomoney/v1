// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {
    MintCurveConvexPositionFactoryBatchReport
} from "@alto/deployments/ethereum-mainnet/MintCurveConvexPositionFactoryBatch.sol";
import {
    CONVEX_BOOSTER_MAINNET,
    CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {
    DeployMintCurveConvexPositionSandboxScript,
    MARKET_REGISTRY_MAINNET
} from "../../../script/DeployMintCurveConvexPositionSandbox.s.sol";

contract DeployMintCurveConvexPositionSandboxForkTest is Test {
    uint256 internal constant FORK_BLOCK = 25537175;
    address internal constant WETH_MINT_MARKET_MAINNET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;

    address internal owner;
    DeployMintCurveConvexPositionSandboxScript internal deployer;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
        owner = makeAddr("SandboxOwner");
        vm.setEnv("OWNER", vm.toString(owner));
        deployer = new DeployMintCurveConvexPositionSandboxScript();
    }

    function test_DeploysWiresAndCreatesOnePosition() public {
        MintCurveConvexPositionFactoryBatchReport memory report = deployer.run();
        MintCurveConvexPositionFactory factory = MintCurveConvexPositionFactory(report.factory);

        assertEq(factory.owner(), owner, "factory owner");
        assertEq(PositionBeacon(report.positionBeacon).owner(), owner, "beacon owner");
        assertEq(factory.beacon(), report.positionBeacon, "factory beacon");
        assertEq(
            IBeacon(report.positionBeacon).implementation(), report.positionImplementation, "beacon implementation"
        );
        assertEq(
            Upgrades.getImplementationAddress(report.factory), report.factoryImplementation, "factory implementation"
        );
        assertEq(factory.marketRegistry(), MARKET_REGISTRY_MAINNET, "market registry");

        (
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        ) = factory.config();
        assertEq(curvePool, FRXUSD_DUSD_CURVE_POOL_MAINNET, "Curve pool");
        assertEq(convexBooster, CONVEX_BOOSTER_MAINNET, "Convex booster");
        assertEq(convexRewardPool, CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET, "Convex reward pool");
        assertEq(convexPid, POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET, "Convex pid");
        assertEq(crv, CRV_TOKEN_MAINNET, "CRV token");
        assertEq(cvx, CVX_TOKEN_MAINNET, "CVX token");

        address user = makeAddr("User");
        vm.prank(user);
        address positionAddress = factory.createPosition(WETH_MINT_MARKET_MAINNET);
        MintCurveConvexPosition position = MintCurveConvexPosition(positionAddress);

        assertEq(position.owner(), user, "position owner");
        assertEq(address(position.factory()), report.factory, "position factory");
        assertEq(address(position.market()), WETH_MINT_MARKET_MAINNET, "position market");

        address[] memory positions = factory.positionsOf(user);
        assertEq(positions.length, 1, "one position created");
        assertEq(positions[0], positionAddress, "position indexed for user");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {
    MintCurveConvexPositionFactoryBatch,
    MintCurveConvexPositionFactoryBatchParams,
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
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";

address constant MARKET_REGISTRY_MAINNET = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;

/// @notice One-time deployment script for a personal mainnet or mainnet-fork frontend stack.
/// @dev This script intentionally does not write to the production deployment output directory.
contract DeployMintCurveConvexPositionSandboxScript is Script {
    function run() external returns (MintCurveConvexPositionFactoryBatchReport memory report) {
        require(block.chainid == 1, "Ethereum mainnet only");

        address owner = vm.envAddress("OWNER");
        require(owner != address(0), "OWNER must not be zero");

        _validateImplementations();

        MintCurveConvexPositionFactoryBatch batch;
        vm.startBroadcast();
        batch = new MintCurveConvexPositionFactoryBatch(
            MintCurveConvexPositionFactoryBatchParams({
                owner: owner, marketRegistry: MARKET_REGISTRY_MAINNET, config: _mainnetConfig()
            })
        );
        vm.stopBroadcast();

        report = batch.getReport();
        _assertDeployment(report, owner);

        console.log("Factory proxy:", report.factory);
        console.log("Factory implementation:", report.factoryImplementation);
        console.log("Position beacon:", report.positionBeacon);
        console.log("Position implementation:", report.positionImplementation);
    }

    /// @dev Validation must execute before the broadcasted batch deployment.
    function _validateImplementations() internal virtual {
        Options memory opts;
        Upgrades.validateImplementation("MintCurveConvexPositionFactory.sol:MintCurveConvexPositionFactory", opts);
        Upgrades.validateImplementation("MintCurveConvexPosition.sol:MintCurveConvexPosition", opts);
    }

    function _mainnetConfig() internal pure returns (MintCurveConvexConfig memory config) {
        config = MintCurveConvexConfig({
            curvePool: FRXUSD_DUSD_CURVE_POOL_MAINNET,
            convexBooster: CONVEX_BOOSTER_MAINNET,
            convexRewardPool: CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
            convexPid: POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
            crv: CRV_TOKEN_MAINNET,
            cvx: CVX_TOKEN_MAINNET
        });
    }

    function _assertDeployment(MintCurveConvexPositionFactoryBatchReport memory report, address owner) internal view {
        MintCurveConvexPositionFactory factory = MintCurveConvexPositionFactory(report.factory);

        require(factory.owner() == owner, "Incorrect factory owner");
        require(PositionBeacon(report.positionBeacon).owner() == owner, "Incorrect beacon owner");
        require(factory.beacon() == report.positionBeacon, "Incorrect factory beacon");
        require(
            IBeacon(report.positionBeacon).implementation() == report.positionImplementation,
            "Incorrect beacon implementation"
        );
        require(
            Upgrades.getImplementationAddress(report.factory) == report.factoryImplementation,
            "Incorrect factory implementation"
        );
        require(factory.marketRegistry() == MARKET_REGISTRY_MAINNET, "Incorrect market registry");

        (
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        ) = factory.config();
        MintCurveConvexConfig memory expected = _mainnetConfig();

        require(curvePool == expected.curvePool, "Incorrect Curve pool");
        require(convexBooster == expected.convexBooster, "Incorrect Convex booster");
        require(convexRewardPool == expected.convexRewardPool, "Incorrect Convex reward pool");
        require(convexPid == expected.convexPid, "Incorrect Convex pid");
        require(crv == expected.crv, "Incorrect CRV token");
        require(cvx == expected.cvx, "Incorrect CVX token");
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import {DeployAltoEthereumMainnet} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeploymentPhase,
    MintCurveConvexPositionContracts
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    CONVEX_BOOSTER_MAINNET,
    CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Mainnet-fork test for the MINT_CURVE_CONVEX_POSITION deployment phase. It drives the deploy
///      through the same DeployAltoEthereumMainnet library the script uses and asserts the resulting
///      strategy stack (factory proxy, position implementation, PositionBeacon) is deployed and wired.
contract MintCurveConvexPositionFactoryBatchForkTest is Test {
    uint256 internal constant FORK_BLOCK = 25537175;

    address internal constant MARKET_REGISTRY_MAINNET = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;
    address internal constant WETH_MINT_MARKET_MAINNET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address internal constant TIMELOCK_MAINNET = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
    }

    function _deployPhase() internal returns (MintCurveConvexPositionContracts memory) {
        AltoEthereumMainnetInput memory input;
        input.contracts.timelock = TIMELOCK_MAINNET;
        input.contracts.marketRegistry = MARKET_REGISTRY_MAINNET;

        AltoEthereumMainnetParams memory params;
        params.phase = DeploymentPhase.MINT_CURVE_CONVEX_POSITION;
        params.useUnsafeUpgrades = true;
        params.deployer = address(this);

        input = DeployAltoEthereumMainnet.deploy(params, input);
        return input.contracts.mintCurveConvexPosition;
    }

    function test_PhaseDeploysAndWiresStack() public {
        MintCurveConvexPositionContracts memory deployed = _deployPhase();

        MintCurveConvexPositionFactory factory = MintCurveConvexPositionFactory(deployed.factory);

        // Factory wiring.
        assertEq(factory.owner(), TIMELOCK_MAINNET, "factory owner should be timelock");
        assertEq(factory.pendingOwner(), address(0), "no pending owner (skip 2-step)");
        assertEq(factory.marketRegistry(), MARKET_REGISTRY_MAINNET, "market registry");
        assertEq(factory.beacon(), deployed.positionBeacon, "beacon wired into factory");

        // Config snapshot (the concrete getter returns the fields as a tuple).
        (
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        ) = factory.config();
        assertEq(curvePool, FRXUSD_DUSD_CURVE_POOL_MAINNET, "curvePool");
        assertEq(convexBooster, CONVEX_BOOSTER_MAINNET, "convexBooster");
        assertEq(convexRewardPool, CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET, "convexRewardPool");
        assertEq(convexPid, POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET, "convexPid");
        assertEq(crv, CRV_TOKEN_MAINNET, "crv");
        assertEq(cvx, CVX_TOKEN_MAINNET, "cvx");

        // Beacon wiring.
        assertEq(PositionBeacon(deployed.positionBeacon).owner(), TIMELOCK_MAINNET, "beacon owner should be timelock");
        assertEq(
            IBeacon(deployed.positionBeacon).implementation(), deployed.positionImplementation, "beacon implementation"
        );
        assertEq(
            MintCurveConvexPosition(deployed.positionImplementation).version(),
            factory.EXPECTED_POSITION_VERSION(),
            "position version matches expected"
        );

        // Factory is usable: a user can create a position against a supported mint market.
        address user = makeAddr("User");
        vm.prank(user);
        address position = factory.createPosition(WETH_MINT_MARKET_MAINNET);
        assertEq(MintCurveConvexPosition(position).owner(), user, "position owner");
    }

    /// @dev The factory/position implementations disable initializers in their constructors, so a
    ///      malicious actor cannot initialize the raw implementations to hijack ownership.
    function test_RevertWhen_InitializingImplementations() public {
        MintCurveConvexPositionContracts memory deployed = _deployPhase();

        address attacker = makeAddr("Attacker");
        MintCurveConvexConfig memory maliciousConfig; // Reverts before config validation, so values are irrelevant.

        // Factory implementation (behind the UUPS proxy) is locked.
        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        MintCurveConvexPositionFactory(deployed.factoryImplementation)
            .initialize(attacker, MARKET_REGISTRY_MAINNET, maliciousConfig);

        // Position implementation (the beacon implementation) is locked.
        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        MintCurveConvexPosition(deployed.positionImplementation)
            .initialize(attacker, deployed.factory, WETH_MINT_MARKET_MAINNET, maliciousConfig);
    }
}

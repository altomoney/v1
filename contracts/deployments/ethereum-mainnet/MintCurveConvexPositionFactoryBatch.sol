// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";

import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

struct MintCurveConvexPositionFactoryBatchParams {
    /// @notice Final owner of the factory and beacon (e.g. the timelock).
    address owner;
    /// @notice Market registry used to validate mint markets.
    address marketRegistry;
    /// @notice Shared Curve/Convex configuration applied to all deployed positions.
    MintCurveConvexConfig config;
}

struct MintCurveConvexPositionFactoryBatchReport {
    /// @notice The MintCurveConvexPositionFactory UUPS proxy (the address users interact with).
    address factory;
    /// @notice The factory implementation behind the proxy.
    address factoryImplementation;
    /// @notice The MintCurveConvexPosition implementation used as the beacon implementation.
    address positionImplementation;
    /// @notice The PositionBeacon wired into the factory.
    address positionBeacon;
}

/// @title MintCurveConvexPositionFactoryBatch
/// @notice Deploys and wires the MintCurveConvexPosition strategy stack in a single transaction.
/// @dev Deploying this contract performs, atomically in its constructor:
///      1. MintCurveConvexPositionFactory UUPS proxy + initialize (batch is temporary owner).
///      2. MintCurveConvexPosition implementation (the beacon implementation, version() == 1).
///      3. PositionBeacon(implementation, owner) owned directly by the final owner.
///      4. factory.setBeacon(beacon) (requires factory ownership -> held by this batch).
///      5. factory.transferOwnershipSkip2Step(owner) to hand the factory to the final owner.
/// @dev The factory initializer validates the Curve/Convex config via on-chain calls, so this
///      batch must be deployed against a chain where those contracts exist (Ethereum mainnet).
/// @dev Upgrade safety must be validated by the calling deployment script before broadcasting.
contract MintCurveConvexPositionFactoryBatch {
    MintCurveConvexPositionFactoryBatchReport public report;

    error InvalidParams();

    constructor(MintCurveConvexPositionFactoryBatchParams memory _params) {
        if (_params.owner == address(0) || _params.marketRegistry == address(0)) {
            revert InvalidParams();
        }

        // 1. Deploy the factory proxy with this batch as the temporary admin so it can call setBeacon.
        bytes memory initData = abi.encodeCall(
            MintCurveConvexPositionFactory.initialize, (address(this), _params.marketRegistry, _params.config)
        );

        address factoryImplementation = address(new MintCurveConvexPositionFactory());
        address factory = UnsafeUpgrades.deployUUPSProxy(factoryImplementation, initData);

        // 2. Deploy the beacon implementation (MintCurveConvexPosition, version() == 1).
        address positionImplementation = address(new MintCurveConvexPosition());

        // 3. Deploy the beacon owned directly by the final owner; the batch never needs beacon ownership.
        address positionBeacon = address(new PositionBeacon(positionImplementation, _params.owner));

        // 4. Wire the beacon into the factory (onlyOwner -> this batch).
        MintCurveConvexPositionFactory(factory).setBeacon(positionBeacon);

        // 5. Hand the factory to the final owner without the 2-step dance (deployment convenience).
        MintCurveConvexPositionFactory(factory).transferOwnershipSkip2Step(_params.owner);

        report = MintCurveConvexPositionFactoryBatchReport({
            factory: factory,
            factoryImplementation: factoryImplementation,
            positionImplementation: positionImplementation,
            positionBeacon: positionBeacon
        });
    }

    function getReport() external view returns (MintCurveConvexPositionFactoryBatchReport memory) {
        return report;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {ProtocolFeeCollectorInitParams} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";

struct ProtocolFeeCollectorBatchParams {
    address timelock;
    address freezer;
    address emergencyController;
    address dusd;
    address marketRegistry;
    address vaultRegistry;
    address usmRegistry;
    address flashMinter;
    address treasury;
    address manualSwapReceiver;
    address[] collateralOperators;
    uint256 rewardsBps;
    uint256 minimumRewardAmount;
}

struct ProtocolFeeCollectorBatchReport {
    address protocolFeeCollector;
    address protocolFeeCollectorImplementation;
}

/// @notice Deploys and configures ProtocolFeeCollector in one transaction.
/// @dev Upgrade safety must be validated by the calling deployment script before broadcasting. The batch is temporary
///      owner only while configuring roles, then hands ownership to the timelock.
contract ProtocolFeeCollectorBatch {
    ProtocolFeeCollectorBatchReport public report;

    error InvalidParams();

    constructor(ProtocolFeeCollectorBatchParams memory params) {
        address implementation = address(new ProtocolFeeCollector());
        bytes memory initData = abi.encodeCall(
            ProtocolFeeCollector.initialize,
            (ProtocolFeeCollectorInitParams({
                    admin: address(this),
                    collateralOperator: params.collateralOperators[0],
                    pauser: params.freezer,
                    dusd: params.dusd,
                    marketRegistry: params.marketRegistry,
                    usmRegistry: params.usmRegistry,
                    flashMinter: params.flashMinter,
                    treasury: params.treasury,
                    manualSwapReceiver: params.manualSwapReceiver,
                    rewardsBps: params.rewardsBps,
                    minimumRewardAmount: params.minimumRewardAmount
                }))
        );
        ProtocolFeeCollector collector = ProtocolFeeCollector(UnsafeUpgrades.deployUUPSProxy(implementation, initData));
        collector.setVaultRegistry(params.vaultRegistry);

        for (uint256 i = 1; i < params.collateralOperators.length; ++i) {
            if (params.collateralOperators[i] == address(0)) revert InvalidParams();
            collector.setCollateralOperator(params.collateralOperators[i], true);
        }

        collector.setPauser(params.emergencyController, PAUSE_TYPE, true);
        collector.setPauser(address(this), PAUSE_TYPE, false);
        collector.transferOwnershipSkip2Step(params.timelock);

        report = ProtocolFeeCollectorBatchReport({
            protocolFeeCollector: address(collector), protocolFeeCollectorImplementation: implementation
        });
    }

    function getReport() external view returns (ProtocolFeeCollectorBatchReport memory) {
        return report;
    }
}

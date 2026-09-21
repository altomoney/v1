// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";

struct SDUSDBatchParams {
    address rewarder;
    address timelock;
    address freezer;
    address emergencyController;
    address dusd;
    uint256 seedShares;
    uint256 depositCap;
    uint256 rewardDuration;
}

struct SDUSDBatchReport {
    address sdusd;
    address sdusdImplementation;
}

/// @notice Deploys and configures SDUSD in one transaction.
/// @dev Upgrade safety must be validated by the calling deployment script before broadcasting. ProtocolFeeCollector is
///      configured as the rewarder during deployment. After this batch is deployed, the deployer must make the normal
///      deployment seed deposit by approving the vault and calling `deposit(seedShares, address(1))` before activation.
contract SDUSDBatch {
    SDUSDBatchReport public report;

    constructor(SDUSDBatchParams memory params) {
        address implementation = address(new SDUSD());
        bytes memory initData = abi.encodeCall(
            SDUSD.initialize,
            (SDUSDInitParams({
                    admin: address(this),
                    pauser: params.freezer,
                    dusd: params.dusd,
                    rewarder: params.rewarder,
                    seedShares: params.seedShares,
                    depositCap: params.depositCap,
                    rewardDuration: params.rewardDuration
                }))
        );
        SDUSD vault = SDUSD(UnsafeUpgrades.deployUUPSProxy(implementation, initData));

        vault.setPauser(params.emergencyController, PAUSE_TYPE, true);
        vault.setPauser(address(this), PAUSE_TYPE, false);
        vault.transferOwnershipSkip2Step(params.timelock);

        report = SDUSDBatchReport({sdusd: address(vault), sdusdImplementation: implementation});
    }

    function getReport() external view returns (SDUSDBatchReport memory) {
        return report;
    }
}

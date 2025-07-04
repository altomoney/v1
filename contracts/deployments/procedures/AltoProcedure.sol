// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {RewardsDistributor} from "@alto/rewards/RewardsDistributor.sol";
import {TWAlto, Bucket} from "@alto/rewards/TWAlto.sol";
import {AltoTokenReport} from "../interfaces/IAltoReport.sol";


abstract contract AltoProcedure {
    function _deployAltoToken(address altoToken, address admin) internal returns (AltoTokenReport memory report) {
        Bucket[] memory buckets = new Bucket[](1);

        buckets[0] = Bucket({
            enabled: true,
            lockEpochDuration: 1, // 1 weeks
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 10_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 10 ether
        });

        report.twAltoStaking = (address(new TWAlto(altoToken, admin, 7 days, buckets)));
        
        report.rewardsDistributor = (address(new RewardsDistributor(address(this), 2 days, bytes32(0), bytes32(0), altoToken)));

        RewardsDistributor(payable(report.rewardsDistributor)).setLockContract(report.twAltoStaking);


        RewardsDistributor(payable(report.rewardsDistributor)).transferOwnership(admin);
        return report;
    }
}

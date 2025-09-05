// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAltoStaking} from "@alto/staking/interfaces/IAltoStaking.sol";
import {AltoStaking} from "@alto/staking/AltoStaking.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

struct TestnetStakingBatchParams {
    address owner;
    address rewardToken;
    uint256 epochDuration;
    uint256 universalRewardsDistributorTimelock;
}

struct TestnetStakingBatchReport {
    address stakingContract;
    address universalRewardsDistributor;
}

/// @title TestnetStakingBatch
/// @notice Deploy testnet staking contract
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TestnetStakingBatch {
    TestnetStakingBatchReport public report;

    constructor(TestnetStakingBatchParams memory _params) {
        Container[] memory containers = new Container[](4);
        containers[0] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 1}),
            decayRate: MinMaxEpochs({min: 1, max: 1}),
            duration: MinMaxEpochs({min: 1, max: 4}),
            maxRateDifferenceEpochs: 2,
            currentDurationEpochs: 0,
            isActive: false
        });
        containers[1] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 1}),
            decayRate: MinMaxEpochs({min: 1, max: 1}),
            duration: MinMaxEpochs({min: 2, max: 6}),
            maxRateDifferenceEpochs: 2,
            currentDurationEpochs: 0,
            isActive: false
        });
        containers[2] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 1}),
            decayRate: MinMaxEpochs({min: 1, max: 1}),
            duration: MinMaxEpochs({min: 3, max: 8}),
            maxRateDifferenceEpochs: 2,
            currentDurationEpochs: 0,
            isActive: false
        });
        containers[3] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 1}),
            decayRate: MinMaxEpochs({min: 1, max: 1}),
            duration: MinMaxEpochs({min: 4, max: 12}),
            maxRateDifferenceEpochs: 2,
            currentDurationEpochs: 0,
            isActive: false
        });

        uint256[] memory multipliers = new uint256[](4);
        multipliers[0] = 0.1 ether;
        multipliers[1] = 0.4 ether;
        multipliers[2] = 0.7 ether;
        multipliers[3] = 1 ether;

        report.stakingContract =
            address(new AltoStaking(_params.rewardToken, address(this), _params.epochDuration, containers, multipliers));

        IAltoStaking(report.stakingContract).activateContainer(1);
        IAltoStaking(report.stakingContract).activateContainer(2);
        IAltoStaking(report.stakingContract).activateContainer(3);
        IAltoStaking(report.stakingContract).activateContainer(4);

        AltoStaking(report.stakingContract).transferOwnership(_params.owner);
    }

    function getStakingContractReport() public view returns (TestnetStakingBatchReport memory) {
        return report;
    }
}

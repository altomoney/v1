// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsDistributor} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";

struct TestnetRewardsBatchParams {
    address owner;
    address rewardToken;
    uint256 merkleRootTimelock;
    address paymentToken;
    uint256 paymentUsdOraclePrice;
    uint256 rewardTokenUsdOraclePrice;
    uint256 lockBonusDiscount;
    address stakingContract;
}

struct TestnetRewardsBatchReport {
    address rewardsDistributor;
    address paymentOracle;
    address rewardOracle;
}

/// @title TestnetRewardsBatch
/// @notice Deploy testnet rewards distributor
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TestnetRewardsBatch {
    TestnetRewardsBatchReport public report;

    constructor(TestnetRewardsBatchParams memory _params) {
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(
            address(new AltoRewardsDistributor(address(this), _params.merkleRootTimelock, _params.rewardToken))
        );

        report.paymentOracle = address(new OracleMock());
        report.rewardOracle = address(new OracleMock());
        OracleMock(report.paymentOracle).setPrice(_params.paymentUsdOraclePrice);
        OracleMock(report.rewardOracle).setPrice(_params.rewardTokenUsdOraclePrice);

        // Setup payment token oracle
        rewardsDistributor.setPaymentToken(_params.paymentToken, report.paymentOracle);

        // Setup reward token USD oracle
        rewardsDistributor.setRewardTokenUsdOracle(report.rewardOracle);

        // Setup lock bonus discount
        rewardsDistributor.setLockBonusDiscount(_params.lockBonusDiscount);
        rewardsDistributor.setLockContract(_params.stakingContract);

        report.rewardsDistributor = address(rewardsDistributor);

        AltoRewardsDistributor(report.rewardsDistributor).transferOwnership(_params.owner);
    }

    function getRewardsDistributorReport() public view returns (TestnetRewardsBatchReport memory) {
        return report;
    }
}

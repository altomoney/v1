// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsDistributor} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";

struct TestnetRewardsBatchParams {
    address owner;
    address rewardToken;
    uint256 merkleRootTimelock;
    address[] paymentTokens;
    uint256[] paymentUsdOraclePrices;
    uint256 rewardTokenUsdOraclePrice;
    uint256 lockBonusDiscount;
    address stakingContract;
}

struct TestnetRewardsBatchReport {
    address rewardsDistributor;
    address[] paymentOracles;
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

        report.paymentOracles = new address[](_params.paymentTokens.length);

        for (uint256 i = 0; i < _params.paymentTokens.length; i++) {
            report.paymentOracles[i] = address(new OracleTestnet(address(this)));
            OracleTestnet(report.paymentOracles[i]).setPrice(_params.paymentUsdOraclePrices[i]);
            OracleTestnet(report.paymentOracles[i]).transferOwnership(_params.owner);
            rewardsDistributor.setPaymentToken(_params.paymentTokens[i], report.paymentOracles[i]);
        }

        report.rewardOracle = address(new OracleTestnet(address(this)));

        OracleTestnet(report.rewardOracle).setPrice(_params.rewardTokenUsdOraclePrice);

        OracleTestnet(report.rewardOracle).transferOwnership(_params.owner);

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

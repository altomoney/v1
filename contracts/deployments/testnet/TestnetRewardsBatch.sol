// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsDistributor} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {getMerkleManagerUpdaters, getMulticallOwnerAddresses} from "@alto/deployments/testnet/Constants.sol";
import {IMerkleRootManager} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";

struct TestnetRewardsBatchParams {
    address owner;
    address rewardToken;
    uint256 merkleRootTimelock;
    address[] paymentTokens;
    uint256[] paymentUsdOraclePrices;
    uint256 rewardTokenUsdOraclePrice;
    uint256 lockBonusDiscount;
    address stakingContract;
    uint256 referralBonusDiscount;
    uint256 referralPaymentTokenShare;
}

struct TestnetRewardsBatchReport {
    address rewardsDistributor;
    address[] paymentOracles;
    address rewardOracle;
    address referralAdapter;
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

        // Setup merkle manager updaters
        address[] memory merkleManagerUpdaters = getMerkleManagerUpdaters();
        for (uint256 i = 0; i < merkleManagerUpdaters.length; i++) {
            IMerkleRootManager(address(rewardsDistributor)).setMerkleRootUpdater(merkleManagerUpdaters[i], true);
        }

        // Deploy referral adapter
        report.referralAdapter =
            address(new AltoReferralWhitelistAdapter(_params.referralBonusDiscount, _params.referralPaymentTokenShare));

        // Setup merkle root updaters for referral adapter (multicall admins)
        address[] memory multicallAdmins = getMulticallOwnerAddresses();
        for (uint256 i = 0; i < multicallAdmins.length; i++) {
            IMerkleRootManager(report.referralAdapter).setMerkleRootUpdater(multicallAdmins[i], true);
        }
        AltoOwnable2Step(report.referralAdapter).transferOwnershipSkip2Step(_params.owner);

        // Whitelist referral adapter in rewards distributor
        rewardsDistributor.whitelistAdapter(report.referralAdapter);

        report.rewardsDistributor = address(rewardsDistributor);

        AltoOwnable2Step(report.rewardsDistributor).transferOwnershipSkip2Step(_params.owner);
    }

    function getRewardsDistributorReport() public view returns (TestnetRewardsBatchReport memory) {
        return report;
    }
}

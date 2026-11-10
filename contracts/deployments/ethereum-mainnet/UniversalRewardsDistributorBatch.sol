// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {UniversalRewardsDistributor} from "@alto/utils/UniversalRewardsDistributor.sol";
import {IMerkleRootManager} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

struct UniversalRewardsDistributorBatchParams {
    address owner;
    address merkleRootUpdater;
    address freezer;
    uint256 initialTimelock;
}

struct UniversalRewardsDistributorBatchReport {
    address universalRewardsDistributor;
}

/// @notice Deploys UniversalRewardsDistributor, configures roles, and transfers ownership to timelock
/// @dev The batch contract is the temporary owner during deployment so it can run all `onlyOwner` calls.
contract UniversalRewardsDistributorBatch {
    UniversalRewardsDistributorBatchReport public report;

    constructor(UniversalRewardsDistributorBatchParams memory _params) {
        address distributor = address(new UniversalRewardsDistributor(address(this), _params.initialTimelock));

        IMerkleRootManager(distributor).setMerkleRootUpdater(_params.merkleRootUpdater, true);
        UniversalRewardsDistributor(distributor).setPauser(_params.freezer, PAUSE_TYPE, true);

        AltoOwnable2Step(distributor).transferOwnershipSkip2Step(_params.owner);

        report = UniversalRewardsDistributorBatchReport({universalRewardsDistributor: distributor});
    }

    function getReport() external view returns (UniversalRewardsDistributorBatchReport memory) {
        return report;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";

struct UsmRegistryBatchParams {
    address timelock;
    address oldUsmRegistry;
}

struct UsmRegistryBatchReport {
    address usmRegistry;
}

/// @title UsmRegistryBatch
/// @notice Deploys an updated UsmRegistry and migrates all USMs from the previous registry.
/// @dev The batch contract is the temporary owner during deployment so it can register USMs and
///      transfer ownership to the timelock in a single transaction.
contract UsmRegistryBatch {
    UsmRegistryBatchReport public report;

    error InvalidParams();

    constructor(UsmRegistryBatchParams memory _params) {
        if (_params.timelock == address(0) || _params.oldUsmRegistry == address(0)) revert InvalidParams();

        UsmRegistry registry = new UsmRegistry(address(this));

        address[] memory usms = IUsmRegistry(_params.oldUsmRegistry).getUsmList();
        for (uint256 i; i < usms.length; ++i) {
            registry.addUsm(usms[i]);
        }

        registry.transferOwnershipSkip2Step(_params.timelock);

        report = UsmRegistryBatchReport({usmRegistry: address(registry)});
    }

    function getReport() external view returns (UsmRegistryBatchReport memory) {
        return report;
    }
}

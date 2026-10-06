// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ERPOutputWriter,
    ERPTransactionPlan,
    ERPTransactionPlanBatch,
    ERPTransactionPlanCall
} from "./ERPOutputWriter.sol";

import {IAltoVault, IAltoVaultBase, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice One state-derived Alto Vault allocator plan.
struct ERPVaultQueuePlan {
    address allocator;
    address vault;
    bytes data;
    bytes reallocateData;
    address[] expectedQueue;
    address[] removedMarkets;
    uint256[] remainingIndexes;
    MarketAllocation[] allocations;
    uint256 expectedWithdrawnAssets;
    uint256 expectedRemainingAffectedAssets;
}

/// @notice Shared queue planning and artifact writing for ERPs that operate Alto Vaults.
library ERPVaultQueue {
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;

    function validateAllocator(address vault, address allocator, string memory reason) internal view {
        require(allocator != address(0) && IAltoVault(vault).isAllocator(allocator), reason);
    }

    function setSupplyQueuePlan(
        address vaultAddress,
        address allocator,
        address[] memory removedMarkets,
        address[] memory replacementMarkets
    ) internal view returns (ERPVaultQueuePlan memory plan) {
        IAltoVault vault = IAltoVault(vaultAddress);
        address[] memory currentQueue = supplyQueue(vault);
        (plan.expectedQueue,) = _without(currentQueue, removedMarkets);

        plan.allocator = allocator;
        plan.vault = vaultAddress;
        plan.removedMarkets = removedMarkets;
        if (plan.expectedQueue.length != currentQueue.length) {
            plan.data = abi.encodeCall(IAltoVaultBase.setSupplyQueue, (plan.expectedQueue));
        }

        (plan.allocations, plan.expectedWithdrawnAssets, plan.expectedRemainingAffectedAssets) =
            _reallocationPlan(vault, removedMarkets, replacementMarkets);
        if (plan.allocations.length != 0) {
            plan.reallocateData = abi.encodeCall(IAltoVaultBase.reallocate, (plan.allocations));
        }
    }

    function updateWithdrawQueuePlan(
        address vaultAddress,
        address allocator,
        address[] memory removedMarkets,
        string memory phase
    ) internal view returns (ERPVaultQueuePlan memory plan) {
        validateAllocator(vaultAddress, allocator, string.concat(phase, ": unauthorized Vault allocator"));

        IAltoVault vault = IAltoVault(vaultAddress);
        address[] memory currentSupplyQueue = supplyQueue(vault);
        for (uint256 i; i < removedMarkets.length; ++i) {
            address market = removedMarkets[i];
            MarketConfig memory config = vault.config(market);
            PendingUint192 memory pendingCap = vault.pendingCap(market);

            require(
                IMarket(market).position(vaultAddress).supplyShares == 0,
                string.concat(phase, ": Vault market supply remains")
            );
            require(vault.quarantinedAssets(market) == 0, string.concat(phase, ": Vault market assets quarantined"));
            require(config.cap == 0, string.concat(phase, ": Vault cap remains"));
            require(config.removableAt == 0, string.concat(phase, ": pending Vault removal remains"));
            require(pendingCap.validAt == 0, string.concat(phase, ": pending Vault cap remains"));
            require(!contains(currentSupplyQueue, market), string.concat(phase, ": market remains in supply queue"));
        }

        address[] memory currentQueue = withdrawQueue(vault);
        (plan.expectedQueue, plan.remainingIndexes) = _without(currentQueue, removedMarkets);
        plan.allocator = allocator;
        plan.vault = vaultAddress;
        plan.removedMarkets = removedMarkets;

        if (plan.expectedQueue.length != currentQueue.length) {
            plan.data = abi.encodeCall(IAltoVaultBase.updateWithdrawQueue, (plan.remainingIndexes));
        }
    }

    function writeOptionalContainmentPlan(
        string memory outputDirectory,
        string memory fileName,
        uint256 sourceBlock,
        ERPVaultQueuePlan memory plan
    ) internal {
        uint256 callCount =
            (plan.data.length == 0 ? 0 : 1) + (plan.reallocateData.length == 0 ? 0 : 1);
        ERPTransactionPlanCall[] memory calls = new ERPTransactionPlanCall[](callCount);
        uint256 callIndex;
        if (plan.data.length != 0) {
            calls[callIndex++] = ERPTransactionPlanCall({
                target: plan.vault,
                data: plan.data,
                functionName: "setSupplyQueue(address[])",
                argumentsJson: string.concat(
                    "{\"newSupplyQueue\":", ERPOutputWriter.addressArrayJson(plan.expectedQueue), "}"
                )
            });
        }
        if (plan.reallocateData.length != 0) {
            calls[callIndex] = ERPTransactionPlanCall({
                target: plan.vault,
                data: plan.reallocateData,
                functionName: "reallocate((address,uint256)[])",
                argumentsJson: string.concat("{\"allocations\":", _allocationsJson(plan.allocations), "}")
            });
        }

        ERPOutputWriter.writeOptionalTransactionPlanBatch(
            outputDirectory,
            fileName,
            sourceBlock,
            ERPTransactionPlanBatch({
                caller: plan.allocator,
                target: plan.vault,
                calls: calls,
                postconditionsJson: string.concat(
                    "{\"expectedSupplyQueue\":",
                    ERPOutputWriter.addressArrayJson(plan.expectedQueue),
                    ",\"affectedMarketsAbsentFromSupplyQueue\":",
                    ERPOutputWriter.addressArrayJson(plan.removedMarkets),
                    ",\"affectedCapsZero\":true,\"expectedWithdrawnAssets\":\"",
                    ERPOutputWriter.uintString(plan.expectedWithdrawnAssets),
                    "\",\"expectedRemainingAffectedAssets\":\"",
                    ERPOutputWriter.uintString(plan.expectedRemainingAffectedAssets),
                    "\",\"expectedAllocations\":",
                    _allocationsJson(plan.allocations),
                    ",\"withdrawnEqualsSupplied\":true}"
                )
            })
        );
    }

    function writeOptionalWithdrawQueuePlan(
        string memory outputDirectory,
        string memory fileName,
        uint256 sourceBlock,
        ERPVaultQueuePlan memory plan
    ) internal {
        ERPOutputWriter.writeOptionalTransactionPlan(
            outputDirectory,
            fileName,
            sourceBlock,
            ERPTransactionPlan({
                caller: plan.allocator,
                target: plan.vault,
                data: plan.data,
                functionName: "updateWithdrawQueue(uint256[])",
                argumentsJson: string.concat(
                    "{\"remainingIndexes\":", ERPOutputWriter.uintArrayJson(plan.remainingIndexes), "}"
                ),
                postconditionsJson: string.concat(
                    "{\"expectedWithdrawQueue\":",
                    ERPOutputWriter.addressArrayJson(plan.expectedQueue),
                    ",\"affectedMarketsAbsentFromBothQueues\":",
                    ERPOutputWriter.addressArrayJson(plan.removedMarkets),
                    ",\"zeroSupplyShares\":true,\"zeroQuarantinedAssets\":true,",
                    "\"disabledConfigs\":true,\"zeroCaps\":true,\"noPendingActions\":true}"
                )
            })
        );
    }

    function supplyQueue(IAltoVaultBase vault) internal view returns (address[] memory queue) {
        queue = new address[](vault.supplyQueueLength());
        for (uint256 i; i < queue.length; ++i) {
            queue[i] = vault.supplyQueue(i);
        }
    }

    function withdrawQueue(IAltoVaultBase vault) internal view returns (address[] memory queue) {
        queue = new address[](vault.withdrawQueueLength());
        for (uint256 i; i < queue.length; ++i) {
            queue[i] = vault.withdrawQueue(i);
        }
    }

    function contains(address[] memory values, address value) internal pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == value) return true;
        }
        return false;
    }

    function _reallocationPlan(IAltoVault vault, address[] memory removedMarkets, address[] memory replacementMarkets)
        private
        view
        returns (MarketAllocation[] memory allocations, uint256 expectedWithdrawn, uint256 expectedRemaining)
    {
        MarketAllocation[] memory planned = new MarketAllocation[](removedMarkets.length + replacementMarkets.length);
        uint256 allocationCount;

        for (uint256 i; i < removedMarkets.length; ++i) {
            address market = removedMarkets[i];
            uint256 supplyShares = IMarket(market).position(address(vault)).supplyShares;
            if (supplyShares == 0) continue;
            require(vault.config(market).enabled, "Batch A: Vault market not enabled");

            (uint256 supplyAssets, uint256 withdrawable) = _supplyAndWithdrawable(market, supplyShares);
            uint256 targetAssets = withdrawable == supplyAssets ? 0 : supplyAssets - withdrawable;
            planned[allocationCount++] = MarketAllocation({market: market, assets: targetAssets});
            expectedWithdrawn += withdrawable;
            expectedRemaining += targetAssets;
        }

        uint256 remainingToSupply = expectedWithdrawn;
        for (uint256 i; i < replacementMarkets.length; ++i) {
            address replacement = replacementMarkets[i];
            (uint256 cap, uint256 capRoom) = _validateReplacement(vault, replacementMarkets, i, removedMarkets);
            if (remainingToSupply == 0 || capRoom == 0) continue;

            if (remainingToSupply <= capRoom) {
                planned[allocationCount++] = MarketAllocation({market: replacement, assets: type(uint256).max});
                remainingToSupply = 0;
            } else {
                planned[allocationCount++] = MarketAllocation({market: replacement, assets: cap});
                remainingToSupply -= capRoom;
            }
        }
        require(remainingToSupply == 0, "Batch A: insufficient replacement capacity");

        allocations = new MarketAllocation[](allocationCount);
        for (uint256 i; i < allocationCount; ++i) {
            allocations[i] = planned[i];
        }
    }

    function _supplyAndWithdrawable(address marketAddress, uint256 supplyShares)
        private
        view
        returns (uint256 supplyAssets, uint256 withdrawable)
    {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets,) =
            marketAddress.expectedMarketBalances();
        supplyAssets = supplyShares.convertToAssetsDown(totalSupplyAssets, totalSupplyShares);
        uint256 accountingLiquidity = totalSupplyAssets > totalBorrowAssets ? totalSupplyAssets - totalBorrowAssets : 0;
        uint256 tokenLiquidity = IERC20(IMarket(marketAddress).borrowToken()).balanceOf(marketAddress);
        withdrawable = _min(supplyAssets, _min(accountingLiquidity, tokenLiquidity));
    }

    function _validateReplacement(
        IAltoVault vault,
        address[] memory replacements,
        uint256 replacementIndex,
        address[] memory removedMarkets
    ) private view returns (uint256 cap, uint256 capRoom) {
        address replacement = replacements[replacementIndex];
        require(replacement != address(0), "Batch A: zero replacement market");
        require(!contains(removedMarkets, replacement), "Batch A: affected market is replacement");
        for (uint256 i; i < replacementIndex; ++i) {
            require(replacements[i] != replacement, "Batch A: duplicate replacement market");
        }
        require(vault.marketRegistry().isBorrowMarket(replacement), "Batch A: replacement market not registered");

        MarketConfig memory config = vault.config(replacement);
        require(config.enabled, "Batch A: replacement market not enabled");
        require(config.cap != 0, "Batch A: replacement market has zero cap");
        require(
            IMarket(replacement).borrowToken() == IERC4626(address(vault)).asset(),
            "Batch A: replacement asset mismatch"
        );
        require(!IPausable(replacement).paused(FROZEN_TYPE), "Batch A: replacement market frozen");
        require(!IPausable(replacement).paused(PAUSE_TYPE), "Batch A: replacement market paused");

        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = replacement.expectedMarketBalances();
        uint256 supplied = uint256(IMarket(replacement).position(address(vault)).supplyShares)
            .convertToAssetsDown(totalSupplyAssets, totalSupplyShares);
        cap = config.cap;
        if (cap > supplied) capRoom = cap - supplied;
    }

    function _allocationsJson(MarketAllocation[] memory allocations) private pure returns (string memory json) {
        json = "[";
        for (uint256 i; i < allocations.length; ++i) {
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                "{\"market\":\"",
                ERPOutputWriter.addressString(allocations[i].market),
                "\",\"assets\":\"",
                ERPOutputWriter.uintString(allocations[i].assets),
                "\"}"
            );
        }
        return string.concat(json, "]");
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _without(address[] memory currentQueue, address[] memory removedMarkets)
        private
        pure
        returns (address[] memory queue, uint256[] memory indexes)
    {
        uint256 keptCount;
        for (uint256 i; i < currentQueue.length; ++i) {
            if (!contains(removedMarkets, currentQueue[i])) ++keptCount;
        }

        queue = new address[](keptCount);
        indexes = new uint256[](keptCount);
        uint256 keptIndex;
        for (uint256 i; i < currentQueue.length; ++i) {
            if (contains(removedMarkets, currentQueue[i])) continue;
            queue[keptIndex] = currentQueue[i];
            indexes[keptIndex++] = i;
        }
    }
}

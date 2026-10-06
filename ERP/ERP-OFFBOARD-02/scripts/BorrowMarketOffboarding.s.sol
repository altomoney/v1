// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {Vm} from "forge-std/Vm.sol";

import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {
    BorrowerList,
    BorrowerSimulationResult,
    BorrowMarketOffboardingIO
} from "../libraries/BorrowMarketOffboardingIO.sol";
import {
    BorrowMarketOffboardingBorrowerMarket,
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingManifest,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingReport,
    BorrowMarketOffboardingSimulationTotals
} from "../IBorrowMarketOffboarding.sol";

/// @notice Loads one approved activation manifest and prepares the requested ERP-OFFBOARD-02 phase.
/// @dev Pass both values at runtime; no incident-specific library or script edits are required.
contract BorrowMarketOffboardingScript is Script {
    using AssetShareConversionMath for uint256;
    using stdStorage for StdStorage;

    StdStorage internal simulationStorage;

    address internal constant SIMULATION_LIQUIDATOR =
        address(uint160(uint256(keccak256("ERP_OFFBOARD_02_LIQUIDATOR"))));
    bytes32 internal constant LIQUIDATION_EVENT_SIG =
        keccak256("Liquidation(address,address,uint256,uint256,uint256,uint256,uint256,uint256)");

    struct LiquidationEventData {
        address liquidator;
        uint256 seizedCollateralAssets;
        uint256 protocolFeeCollateralAssets;
        uint256 repaidBorrowAssets;
        uint256 repaidBorrowShares;
        uint256 badDebtAssets;
        uint256 badDebtShares;
    }

    struct BatchBSimulation {
        BorrowerSimulationResult[] borrowerResults;
        uint256 borrowerCount;
        BorrowMarketOffboardingSimulationTotals[] marketTotals;
        uint256[] vaultLosses;
        bytes32 operationId;
    }

    function run(uint256 phaseId, string calldata manifestPath) external {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase(phaseId);
        BorrowMarketOffboardingManifest memory manifest = BorrowMarketOffboardingIO.loadActivationManifest(manifestPath);
        BorrowMarketOffboardingInput memory input =
            BorrowMarketOffboardingIO.loadCurrentChainInput(manifest.deploymentId);

        if (phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            BorrowerList memory borrowerList = _writeBorrowerList(manifestPath, manifest);
            BatchBSimulation memory simulation = _assertBatchBSimulation(manifest, input, borrowerList);
            _runPhase(phase, manifest, input);
            BorrowMarketOffboardingIO.writeSimulationReport(
                manifest,
                simulation.borrowerResults,
                simulation.borrowerCount,
                simulation.marketTotals,
                simulation.vaultLosses,
                simulation.operationId
            );
        } else {
            _runPhase(phase, manifest, input);
        }
        BorrowMarketOffboardingIO.writeManifestInput(manifestPath, phase, manifest);
    }

    /// @notice Writes the fetched Batch B borrower list to the standard artifact directory.
    function _writeBorrowerList(string memory manifestPath, BorrowMarketOffboardingManifest memory manifest)
        internal
        virtual
        returns (BorrowerList memory)
    {
        return BorrowMarketOffboardingIO.writeBorrowerList(manifestPath, manifest);
    }

    /// @notice Asserts the exact Batch B calls are safe, then restores the fork state.
    function _assertBatchBSimulation(
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input,
        BorrowerList memory borrowerList
    ) internal returns (BatchBSimulation memory simulation) {
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");

        BorrowMarketOffboardingReport memory report =
            BorrowMarketOffboarding.prepareRateAndLtvReduction(manifest, input);
        (BorrowerSimulationResult[] memory results, uint256 resultCount) = _buildBorrowerResults(manifest, borrowerList);
        (bytes memory scheduleData, bytes memory executeData, bytes32 operationId) = ERPOutputWriter.timelockCalldata(
            input.contracts.timelock, report.timelockBatch, report.timelockDelay, report.predecessor
        );

        uint256 snapshotId = vm.snapshotState();
        _callFrom(manifest.timelockSafe, input.contracts.timelock, scheduleData);
        vm.warp(block.timestamp + report.timelockDelay);

        for (uint256 i; i < resultCount; ++i) {
            results[i].liquidatableBefore = _isLiquidatable(results[i].market, results[i].borrower);
        }

        _callFrom(manifest.timelockSafe, input.contracts.timelock, executeData);
        (BorrowMarketOffboardingSimulationTotals[] memory marketTotals, uint256[] memory vaultLosses) =
            _simulateLiquidations(results, resultCount, manifest);

        simulation.borrowerResults = results;
        simulation.borrowerCount = resultCount;
        simulation.marketTotals = marketTotals;
        simulation.vaultLosses = vaultLosses;
        simulation.operationId = operationId;

        require(vm.revertToState(snapshotId), "Simulation: failed to restore fork state");
    }

    function _runPhase(
        BorrowMarketOffboardingPhase phase,
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input
    ) internal returns (BorrowMarketOffboardingInput memory) {
        vm.startBroadcast();
        require(block.number == manifest.sourceBlock, "ERP: fork block does not match manifest");
        input = BorrowMarketOffboarding.runPhase(phase, manifest, input);
        vm.stopBroadcast();

        return input;
    }

    function _buildBorrowerResults(BorrowMarketOffboardingManifest memory manifest, BorrowerList memory borrowerList)
        internal
        view
        returns (BorrowerSimulationResult[] memory results, uint256 resultCount)
    {
        uint256 candidateCount;
        for (uint256 i; i < borrowerList.markets.length; ++i) {
            candidateCount += borrowerList.markets[i].borrowers.length;
        }
        results = new BorrowerSimulationResult[](candidateCount);

        for (uint256 i; i < manifest.markets.length; ++i) {
            address marketAddress = manifest.markets[i].market;
            BorrowMarketOffboardingBorrowerMarket memory borrowerMarket = borrowerList.markets[i];
            require(borrowerMarket.market == marketAddress, "Simulation: borrower market mismatch");

            IMarket market = IMarket(marketAddress);
            LiquidationConfiguration memory configuration =
                IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
            require(!configuration.isEnabledPriorityLiquidation, "Simulation: priority liquidation unsupported");

            uint256 listedBorrowShares;
            for (uint256 j; j < borrowerMarket.borrowers.length; ++j) {
                address borrower = borrowerMarket.borrowers[j];
                Position memory position = market.position(borrower);
                if (position.borrowShares == 0) continue;
                listedBorrowShares += position.borrowShares;
                BorrowerSimulationResult memory result;
                result.market = marketAddress;
                result.borrower = borrower;
                result.borrowShares = position.borrowShares;
                result.collateralAssets = position.collateralAssets;
                results[resultCount++] = result;
            }
            require(listedBorrowShares == market.totalBorrowed().shares, "Simulation: borrower shares do not reconcile");
        }
    }

    function _isLiquidatable(address market, address borrower) internal returns (bool) {
        uint256 snapshotId = vm.snapshotState();
        (bool success,) = _callLiquidation(market, borrower);
        vm.revertToState(snapshotId);
        return success;
    }

    function _simulateLiquidations(
        BorrowerSimulationResult[] memory results,
        uint256 resultCount,
        BorrowMarketOffboardingManifest memory manifest
    ) internal returns (BorrowMarketOffboardingSimulationTotals[] memory marketTotals, uint256[] memory vaultLosses) {
        marketTotals = new BorrowMarketOffboardingSimulationTotals[](manifest.markets.length);
        vaultLosses = new uint256[](manifest.vaults.length);
        Balance[] memory marketSupplyBefore = new Balance[](manifest.markets.length);
        uint256[] memory marketSupplyAssetsAfter = new uint256[](manifest.markets.length);

        for (uint256 i; i < manifest.markets.length; ++i) {
            IMarket market = IMarket(manifest.markets[i].market);
            market.accrueInterest();
            Balance memory supplyBefore = market.totalSupply();
            marketSupplyBefore[i] = supplyBefore;
            uint256 protocolAssetsBefore =
                _supplyAssets(market, market.feeRecipient(), supplyBefore.assets, supplyBefore.shares);

            for (uint256 j; j < resultCount; ++j) {
                if (results[j].market == address(market)) _attemptLiquidation(results[j], marketTotals[i]);
            }

            uint256 supplyAssetsAfter = supplyBefore.assets > marketTotals[i].supplierLossAssets
                ? supplyBefore.assets - marketTotals[i].supplierLossAssets
                : 0;
            marketSupplyAssetsAfter[i] = supplyAssetsAfter;
            uint256 protocolAssetsAfter =
                _supplyAssets(market, market.feeRecipient(), supplyAssetsAfter, supplyBefore.shares);
            marketTotals[i].protocolLossAssets =
                protocolAssetsBefore > protocolAssetsAfter ? protocolAssetsBefore - protocolAssetsAfter : 0;

            BorrowMarketOffboarding.validateSimulationLimits(marketTotals[i], manifest.markets[i]);
        }

        for (uint256 i; i < manifest.vaults.length; ++i) {
            address vault = manifest.vaults[i].vault;
            for (uint256 j; j < manifest.markets.length; ++j) {
                IMarket market = IMarket(manifest.markets[j].market);
                Balance memory supplyBefore = marketSupplyBefore[j];
                uint256 vaultAssetsBefore = _supplyAssets(market, vault, supplyBefore.assets, supplyBefore.shares);
                uint256 vaultAssetsAfter = _supplyAssets(market, vault, marketSupplyAssetsAfter[j], supplyBefore.shares);
                vaultLosses[i] += vaultAssetsBefore > vaultAssetsAfter ? vaultAssetsBefore - vaultAssetsAfter : 0;
            }
            require(vaultLosses[i] <= manifest.vaults[i].maxVaultLossAssets, "Simulation: Vault loss limit exceeded");
        }
    }

    function _attemptLiquidation(
        BorrowerSimulationResult memory result,
        BorrowMarketOffboardingSimulationTotals memory totals
    ) internal {
        uint256 snapshotId = vm.snapshotState();
        vm.recordLogs();
        (bool success, bytes memory returnData) = _callLiquidation(result.market, result.borrower);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        if (!success) {
            bool solvent = _isSolventPositionError(returnData);
            vm.revertToState(snapshotId);
            if (!solvent) _bubbleRevert(returnData);
            result.liquidatableAfter = false;
            return;
        }

        LiquidationEventData memory liquidation = _liquidationEvent(logs, result.market, result.borrower);
        result.liquidatableAfter = true;
        result.repaidBorrowAssets = liquidation.repaidBorrowAssets;
        result.seizedCollateralAssets = liquidation.seizedCollateralAssets;
        result.badDebtAssets = liquidation.badDebtAssets;
        result.supplierLossAssets = liquidation.badDebtAssets;
        totals.liquidationFundingAssets += liquidation.repaidBorrowAssets;
        totals.badDebtAssets += liquidation.badDebtAssets;
        totals.supplierLossAssets += liquidation.badDebtAssets;
        vm.revertToState(snapshotId);
    }

    function _callLiquidation(address market, address borrower)
        internal
        returns (bool success, bytes memory returnData)
    {
        address borrowToken = IMarket(market).borrowToken();
        _dealToken(borrowToken, SIMULATION_LIQUIDATOR, type(uint128).max);
        vm.startPrank(SIMULATION_LIQUIDATOR);
        require(IERC20(borrowToken).approve(market, type(uint256).max), "Simulation: approve failed");
        (success, returnData) = market.call(abi.encodeCall(IMarketBase.liquidate, (borrower, bytes(""), bytes(""))));
        vm.stopPrank();
    }

    function _isSolventPositionError(bytes memory returnData) internal pure returns (bool) {
        return _revertSelector(returnData)
            == IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector;
    }

    function _liquidationEvent(Vm.Log[] memory logs, address market, address borrower)
        internal
        pure
        returns (LiquidationEventData memory liquidation)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == market && logs[i].topics.length == 2 && logs[i].topics[0] == LIQUIDATION_EVENT_SIG
                    && address(uint160(uint256(logs[i].topics[1]))) == borrower
            ) {
                return abi.decode(logs[i].data, (LiquidationEventData));
            }
        }
        revert("Simulation: liquidation event missing");
    }

    function _supplyAssets(IMarket market, address account, uint256 totalSupplyAssets, uint256 totalSupplyShares)
        internal
        view
        returns (uint256)
    {
        return uint256(market.position(account).supplyShares).convertToAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function _callFrom(address caller, address target, bytes memory data) internal {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) _bubbleRevert(returnData);
    }

    function _revertSelector(bytes memory returnData) internal pure returns (bytes4 selector) {
        if (returnData.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returnData, 0x20))
        }
    }

    function _bubbleRevert(bytes memory returnData) internal pure {
        if (returnData.length == 0) revert("Simulation: unexpected empty revert");
        assembly ("memory-safe") {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    function _dealToken(address token, address account, uint256 amount) internal {
        // vm.deal only sets native ETH balances; liquidation funding requires the market's ERC-20 borrow token.
        simulationStorage.target(token).sig(IERC20.balanceOf.selector).with_key(account).checked_write(amount);
    }
}

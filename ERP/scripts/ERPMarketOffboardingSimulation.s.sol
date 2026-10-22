// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {Vm} from "forge-std/Vm.sol";

import {IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ERPOutputWriter} from "../libraries/ERPOutputWriter.sol";

/// @notice Fork-simulation mechanics shared by market offboarding scripts.
abstract contract ERPMarketOffboardingSimulation is Script {
    using stdStorage for StdStorage;

    StdStorage internal simulationStorage;

    bytes32 internal constant LIQUIDATION_EVENT_SIG =
        keccak256("Liquidation(address,address,uint256,uint256,uint256,uint256,uint256,uint256)");

    /// @dev Keep the field order compatible with the existing borrower-list JSON tuples.
    struct BorrowerMarket {
        address[] borrowers;
        address market;
    }

    struct BorrowerPosition {
        address market;
        address borrower;
        uint256 borrowShares;
        uint256 collateralAssets;
    }

    /// @dev Retains the full candidate capacity; only the first resultCount entries are populated.
    function _collectBorrowerPositions(address[] memory markets, BorrowerMarket[] memory borrowerMarkets)
        internal
        view
        returns (BorrowerPosition[] memory results, uint256 resultCount)
    {
        uint256 candidateCount;
        for (uint256 i; i < borrowerMarkets.length; ++i) {
            candidateCount += borrowerMarkets[i].borrowers.length;
        }
        results = new BorrowerPosition[](candidateCount);

        for (uint256 i; i < markets.length; ++i) {
            address marketAddress = markets[i];
            BorrowerMarket memory borrowerMarket = borrowerMarkets[i];
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
                results[resultCount++] = BorrowerPosition({
                    market: marketAddress,
                    borrower: borrower,
                    borrowShares: position.borrowShares,
                    collateralAssets: position.collateralAssets
                });
            }
            require(listedBorrowShares == market.totalBorrowed().shares, "Simulation: borrower shares do not reconcile");
        }
    }

    struct LiquidationOutcome {
        uint256 seizedCollateralAssets;
        uint256 repaidBorrowAssets;
        uint256 badDebtAssets;
    }

    function _simulationLiquidator() internal pure virtual returns (address);

    function _removeBatchBArtifacts(string memory outputDirectory) internal {
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/batch-b-irm-and-ltv-update-schedule.json"));
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/batch-b-irm-and-ltv-update-execute.json"));
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/inputs.json"));
        ERPOutputWriter.removeIfExists(string.concat(outputDirectory, "/simulation-report.json"));
    }

    function _prepareSimulationOperation(
        address timelockAddress,
        address timelockSafe,
        bytes32 operationId,
        bytes memory scheduleData
    ) internal {
        TimelockController timelock = TimelockController(payable(timelockAddress));
        if (!timelock.isOperationPending(operationId)) _callFrom(timelockSafe, timelockAddress, scheduleData);
        if (!timelock.isOperationReady(operationId)) vm.warp(timelock.getTimestamp(operationId));
    }

    function _isLiquidatable(address market, address borrower) internal returns (bool) {
        uint256 snapshotId = vm.snapshotState();
        (bool success,) = _callLiquidation(market, borrower);
        vm.revertToState(snapshotId);
        return success;
    }

    /// @dev Successful attempts remain snapshotted until the caller finishes its accounting.
    /// Solvent failures are restored here; other failures retain their original revert data.
    function _beginLiquidationAttempt(address market, address borrower)
        internal
        returns (bool liquidatable, LiquidationOutcome memory outcome, uint256 snapshotId)
    {
        snapshotId = vm.snapshotState();
        vm.recordLogs();
        (bool success, bytes memory returnData) = _callLiquidation(market, borrower);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (!success) {
            bool solvent = _isSolventPositionError(returnData);
            vm.revertToState(snapshotId);
            if (!solvent) _bubbleRevert(returnData);
            return (false, outcome, snapshotId);
        }
        outcome = _liquidationOutcome(logs, market, borrower);
        return (true, outcome, snapshotId);
    }

    function _callLiquidation(address market, address borrower)
        internal
        returns (bool success, bytes memory returnData)
    {
        address liquidator = _simulationLiquidator();
        address borrowToken = IMarket(market).borrowToken();
        _dealToken(borrowToken, liquidator, type(uint128).max);
        vm.startPrank(liquidator);
        require(IERC20(borrowToken).approve(market, type(uint256).max), "Simulation: approve failed");
        (success, returnData) = market.call(abi.encodeCall(IMarketBase.liquidate, (borrower, bytes(""), bytes(""))));
        vm.stopPrank();
    }

    function _isSolventPositionError(bytes memory returnData) internal pure returns (bool) {
        return _revertSelector(returnData)
            == IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector;
    }

    function _liquidationOutcome(Vm.Log[] memory logs, address market, address borrower)
        internal
        pure
        returns (LiquidationOutcome memory outcome)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == market && logs[i].topics.length == 2 && logs[i].topics[0] == LIQUIDATION_EVENT_SIG
                    && address(uint160(uint256(logs[i].topics[1]))) == borrower
            ) {
                (, outcome.seizedCollateralAssets,, outcome.repaidBorrowAssets,, outcome.badDebtAssets,) =
                    abi.decode(logs[i].data, (address, uint256, uint256, uint256, uint256, uint256, uint256));
                return outcome;
            }
        }
        revert("Simulation: liquidation event missing");
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
        simulationStorage.target(token).sig(IERC20.balanceOf.selector).with_key(account).checked_write(amount);
    }
}

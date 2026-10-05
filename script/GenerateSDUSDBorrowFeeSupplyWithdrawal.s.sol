// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";

struct BorrowFeeSupplyWithdrawalSafeBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

struct BorrowFeeSupplyWithdrawalMarketReport {
    address market;
    uint256 remainingShares;
    uint256 remainingAssets;
}

struct BorrowFeeSupplyWithdrawal {
    uint256 assets;
    uint256 shares;
}

/// @title Generate sDUSD legacy borrow-fee supply withdrawal transactions
/// @notice Generates timelock calldata that withdraws all currently available legacy fee-recipient supply.
/// @dev Generate this calldata only after every borrow market has migrated away from the legacy fee recipient.
///      Liquidity can change before execution, so regenerate the calldata immediately before scheduling it.
///      Reported residual positions are generation-time projections and are not guaranteed execution-time values.
///      Run with:
///      `forge script script/GenerateSDUSDBorrowFeeSupplyWithdrawal.s.sol --rpc-url $MAINNET_RPC_URL`
contract GenerateSDUSDBorrowFeeSupplyWithdrawalScript is Script {
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;

    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;
    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant REPORT_PATH =
        "contracts/deployments/ethereum-mainnet/output/sdusd-borrow-fee-supply-withdrawal-report.json";
    string internal constant SAFE_BATCH_NAME = "sdusd-borrow-fee-supply-withdrawal";

    function run() public {
        require(block.chainid == 1, "Not Ethereum mainnet");

        string memory json = vm.readFile(
            string.concat(
                OUTPUT_DIR,
                "/ethereum-mainnet-",
                vm.toString(block.chainid),
                "-",
                vm.toString(SDUSD_DEPLOYMENT_ID_TO_LOAD),
                "/addresses.json"
            )
        );

        generate(
            vm.parseJsonAddress(json, ".contracts.marketRegistry"),
            vm.parseJsonAddress(json, ".contracts.legacyFeeRecipient")
        );
    }

    function generate(address marketRegistry, address legacyFeeRecipient) public {
        require(marketRegistry != address(0), "Invalid market registry");
        require(legacyFeeRecipient != address(0), "Invalid legacy fee recipient");

        (BorrowFeeSupplyWithdrawalSafeBatch memory batch, BorrowFeeSupplyWithdrawalMarketReport[] memory report) =
            buildBorrowFeeSupplyWithdrawal(marketRegistry, legacyFeeRecipient);

        _writeReport(report);

        if (batch.targets.length == 0) {
            console.log("No withdrawable legacy borrow-fee supply positions");
            return;
        }

        SafeTransactionBuilder.writeTimelockBatch(
            SAFE_BATCH_NAME,
            legacyFeeRecipient,
            batch.targets,
            batch.values,
            batch.payloads,
            TimelockController(payable(legacyFeeRecipient)).getMinDelay()
        );
    }

    /// @notice Builds direct market withdrawals and projected residuals for all registered borrow markets.
    /// @dev Reverts unless every market has migrated away from `legacyFeeRecipient`. Paused markets and positions with
    ///      no available liquidity are included in `report` but omitted from the Safe batch.
    function buildBorrowFeeSupplyWithdrawal(address marketRegistry, address legacyFeeRecipient)
        public
        view
        returns (BorrowFeeSupplyWithdrawalSafeBatch memory batch, BorrowFeeSupplyWithdrawalMarketReport[] memory report)
    {
        address[] memory markets = IMarketRegistry(marketRegistry).getBorrowMarkets();
        BorrowFeeSupplyWithdrawal[] memory withdrawals = new BorrowFeeSupplyWithdrawal[](markets.length);
        report = new BorrowFeeSupplyWithdrawalMarketReport[](markets.length);
        uint256 withdrawalCount;

        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            require(market.feeRecipient() != legacyFeeRecipient, "Legacy fee recipient still configured");

            uint256 supplyShares = market.position(legacyFeeRecipient).supplyShares;
            report[i].market = markets[i];
            report[i].remainingShares = supplyShares;

            (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets,) =
                markets[i].expectedMarketBalances();
            uint256 supplyAssets = supplyShares.convertToAssetsDown(totalSupplyAssets, totalSupplyShares);
            report[i].remainingAssets = supplyAssets;

            if (supplyShares == 0 || supplyAssets == 0 || market.paused(PAUSE_TYPE)) continue;

            uint256 availableLiquidity =
                Math.min(totalSupplyAssets - totalBorrowAssets, IERC20(market.borrowToken()).balanceOf(markets[i]));
            uint256 withdrawableAssets = Math.min(supplyAssets, availableLiquidity);
            if (withdrawableAssets == 0) continue;

            if (withdrawableAssets == supplyAssets) {
                withdrawals[i].shares = supplyShares;
                report[i].remainingShares = 0;
                report[i].remainingAssets = 0;
            } else {
                uint256 withdrawnShares = withdrawableAssets.convertToSharesUp(totalSupplyAssets, totalSupplyShares);
                uint256 remainingShares = supplyShares - withdrawnShares;

                withdrawals[i].assets = withdrawableAssets;
                report[i].remainingShares = remainingShares;
                report[i].remainingAssets = remainingShares.convertToAssetsDown(
                    totalSupplyAssets - withdrawableAssets, totalSupplyShares - withdrawnShares
                );
            }

            ++withdrawalCount;
        }

        if (withdrawalCount == 0) return (_emptyBatch(), report);

        batch.targets = new address[](withdrawalCount);
        batch.values = new uint256[](withdrawalCount);
        batch.payloads = new bytes[](withdrawalCount);

        uint256 index;
        for (uint256 i; i < markets.length; ++i) {
            BorrowFeeSupplyWithdrawal memory withdrawal = withdrawals[i];
            if (withdrawal.assets == 0 && withdrawal.shares == 0) continue;

            bytes memory payload = withdrawal.assets != 0
                ? abi.encodeCall(
                    IMarketBase.removeSupply, (withdrawal.assets, 0, legacyFeeRecipient, legacyFeeRecipient)
                )
                : abi.encodeCall(
                    IMarketBase.removeSupply, (0, withdrawal.shares, legacyFeeRecipient, legacyFeeRecipient)
                );

            _append(batch, index++, markets[i], payload);
        }
        assert(index == withdrawalCount);
    }

    function _writeReport(BorrowFeeSupplyWithdrawalMarketReport[] memory report) private {
        string memory rows;

        console.log("Legacy borrow-fee supply residual report (generation-time projection):");
        for (uint256 i; i < report.length; ++i) {
            console.log("Market:", report[i].market);
            console.log("  Projected remaining shares:", report[i].remainingShares);
            console.log("  Projected remaining assets:", report[i].remainingAssets);

            rows = string.concat(
                rows,
                i == 0 ? "" : ",",
                '{"market":"',
                vm.toString(report[i].market),
                '","remainingShares":"',
                vm.toString(report[i].remainingShares),
                '","remainingAssets":"',
                vm.toString(report[i].remainingAssets),
                '"}'
            );
        }

        vm.writeFile(
            REPORT_PATH, string.concat('{"projectionBlock":"', vm.toString(block.number), '","markets":[', rows, "]}")
        );
        console.log("Residual report written:", REPORT_PATH);
    }

    function _emptyBatch() private pure returns (BorrowFeeSupplyWithdrawalSafeBatch memory batch) {
        batch.targets = new address[](0);
        batch.values = new uint256[](0);
        batch.payloads = new bytes[](0);
    }

    function _append(
        BorrowFeeSupplyWithdrawalSafeBatch memory batch,
        uint256 index,
        address target,
        bytes memory payload
    ) private pure {
        batch.targets[index] = target;
        batch.payloads[index] = payload;
    }
}

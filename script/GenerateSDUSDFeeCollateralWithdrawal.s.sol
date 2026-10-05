// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";

struct LegacyFeeCollateralWithdrawalSafeBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

/// @title Generate sDUSD legacy fee-recipient collateral withdrawal transactions
/// @notice Generates separate timelock batches for legacy borrow- and mint-market fee-recipient collateral positions.
/// @dev IMPORTANT: Generate this calldata only after every registered market's fee recipient has been updated away
///      from its legacy fee recipient. The script enforces that state before writing either batch.
/// @dev Run with:
///      forge script script/GenerateSDUSDFeeCollateralWithdrawal.s.sol:GenerateSDUSDFeeCollateralWithdrawalScript --rpc-url ethereum -vv
contract GenerateSDUSDFeeCollateralWithdrawalScript is Script {
    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;
    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant BORROW_BATCH_NAME = "sdusd-borrow-fee-collateral-withdrawal";
    string internal constant MINT_BATCH_NAME = "sdusd-mint-fee-collateral-withdrawal";

    function run() public {
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
            vm.parseJsonAddress(json, ".contracts.legacyFeeRecipient"),
            vm.parseJsonAddress(json, ".contracts.legacyMintMarketFeeRecipient")
        );
    }

    function generate(address marketRegistry, address legacyFeeRecipient, address legacyMintMarketFeeRecipient) public {
        require(marketRegistry != address(0), "Invalid market registry");
        require(
            legacyFeeRecipient != address(0) && legacyMintMarketFeeRecipient != address(0),
            "Invalid legacy fee recipient"
        );

        IMarketRegistry registry = IMarketRegistry(marketRegistry);
        _writeBatch(
            BORROW_BATCH_NAME,
            legacyFeeRecipient,
            buildCollateralWithdrawal(registry.getBorrowMarkets(), legacyFeeRecipient)
        );
        _writeBatch(
            MINT_BATCH_NAME,
            legacyMintMarketFeeRecipient,
            buildCollateralWithdrawal(registry.getMintMarkets(), legacyMintMarketFeeRecipient)
        );
    }

    /// @notice Builds direct market calls for every nonzero collateral position owned by a legacy fee recipient.
    /// @dev The legacy fee-recipient timelock executes these calls itself, so no adapter authorization is required.
    function buildCollateralWithdrawal(address[] memory markets, address legacyFeeRecipient)
        public
        view
        returns (LegacyFeeCollateralWithdrawalSafeBatch memory batch)
    {
        uint256 marketCount;
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            require(market.feeRecipient() != legacyFeeRecipient, "Market fee recipient not updated");
            if (market.position(legacyFeeRecipient).collateralAssets != 0) ++marketCount;
        }

        if (marketCount == 0) return _emptyBatch();

        batch.targets = new address[](marketCount);
        batch.values = new uint256[](marketCount);
        batch.payloads = new bytes[](marketCount);

        uint256 index;
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            uint256 collateralAssets = market.position(legacyFeeRecipient).collateralAssets;
            if (collateralAssets == 0) continue;

            _append(
                batch,
                index++,
                markets[i],
                abi.encodeCall(
                    IMarketBase.removeCollateral, (collateralAssets, legacyFeeRecipient, legacyFeeRecipient, bytes(""))
                )
            );
        }
        assert(index == marketCount);
    }

    function _writeBatch(
        string memory batchName,
        address legacyFeeRecipient,
        LegacyFeeCollateralWithdrawalSafeBatch memory batch
    ) private {
        if (batch.targets.length == 0) {
            console.log("No legacy fee-recipient collateral positions for", batchName);
            return;
        }

        SafeTransactionBuilder.writeTimelockBatch(
            batchName,
            legacyFeeRecipient,
            batch.targets,
            batch.values,
            batch.payloads,
            TimelockController(payable(legacyFeeRecipient)).getMinDelay()
        );
    }

    function _emptyBatch() private pure returns (LegacyFeeCollateralWithdrawalSafeBatch memory batch) {
        batch.targets = new address[](0);
        batch.values = new uint256[](0);
        batch.payloads = new bytes[](0);
    }

    function _append(
        LegacyFeeCollateralWithdrawalSafeBatch memory batch,
        uint256 index,
        address target,
        bytes memory payload
    ) private pure {
        batch.targets[index] = target;
        batch.payloads[index] = payload;
    }
}

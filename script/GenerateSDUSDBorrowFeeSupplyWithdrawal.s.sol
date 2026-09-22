// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBundler3, Call} from "@morpho-org/bundler3/interfaces/IBundler3.sol";

import {Balance, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";

struct BorrowFeeSupplyWithdrawalSafeBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

/// @title Generate sDUSD legacy borrow-fee supply withdrawal transactions
/// @notice Regenerates timelock calldata for legacy fee-recipient supply positions that are fully liquid.
/// @dev The script supports generation both before and after the legacy fee recipient is replaced.
contract GenerateSDUSDBorrowFeeSupplyWithdrawalScript is Script {
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;

    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;
    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant SAFE_BATCH_NAME = "sdusd-borrow-fee-supply-withdrawal";
    address internal constant OLD_FEE_RECIPIENT = 0xb9F06fEFc4c53dEd77A90Cb798eD08DC068Bb6dd;

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
            vm.parseJsonAddress(json, ".contracts.altoAdapter"),
            OLD_FEE_RECIPIENT
        );
    }

    function generate(address marketRegistry, address adapter, address feeRecipient) public {
        require(marketRegistry != address(0), "Invalid market registry");
        require(adapter != address(0), "Invalid adapter");
        require(feeRecipient != address(0), "Invalid legacy fee recipient");

        BorrowFeeSupplyWithdrawalSafeBatch memory batch =
            buildBorrowFeeSupplyWithdrawal(marketRegistry, adapter, feeRecipient);
        if (batch.targets.length == 0) {
            console.log("No fully liquid legacy borrow-fee supply positions");
            return;
        }

        SafeTransactionBuilder.writeTimelockBatch(
            SAFE_BATCH_NAME,
            feeRecipient,
            batch.targets,
            batch.values,
            batch.payloads,
            TimelockController(payable(feeRecipient)).getMinDelay()
        );
    }

    /// @notice Builds a legacy fee-recipient batch for fully liquid borrow-market supply positions.
    /// @dev Markets whose complete position cannot be withdrawn with the liquidity available during generation are
    ///      omitted. Liquidity can change before execution, so operators must regenerate and verify this batch before
    ///      scheduling it. The adapter dynamically reads and withdraws all shares held at execution time.
    function buildBorrowFeeSupplyWithdrawal(address marketRegistry, address adapter, address feeRecipient)
        public
        view
        returns (BorrowFeeSupplyWithdrawalSafeBatch memory batch)
    {
        address[] memory markets = IMarketRegistry(marketRegistry).getBorrowMarkets();
        uint256 marketCount;

        for (uint256 i; i < markets.length; ++i) {
            if (_canWithdrawFullSupply(IMarket(markets[i]), feeRecipient)) {
                require(
                    AltoAdapter(payable(adapter)).isApprovedContract(markets[i]),
                    "Borrow market not approved in adapter"
                );
                ++marketCount;
            }
        }

        if (marketCount == 0) return _emptyBatch();

        // For each liquid market, authorize AltoAdapter, withdraw all shares in one Bundler3 call, then revoke it.
        uint256 callCount = marketCount * 2 + 1;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);

        uint256 index;
        Call[] memory bundle = new Call[](marketCount);
        uint256 bundleIndex;
        for (uint256 i; i < markets.length; ++i) {
            if (!_canWithdrawFullSupply(IMarket(markets[i]), feeRecipient)) continue;
            _append(batch, index++, markets[i], abi.encodeCall(IAuth.setAuthorization, (adapter, true)));
            bundle[bundleIndex++] = Call({
                to: adapter,
                data: abi.encodeCall(
                    AltoAdapter.marketRemoveSupply, (IMarket(markets[i]), 0, type(uint256).max, 0, feeRecipient)
                ),
                value: 0,
                skipRevert: false,
                callbackHash: bytes32(0)
            });
        }

        _append(batch, index++, AltoAdapter(payable(adapter)).BUNDLER3(), abi.encodeCall(IBundler3.multicall, (bundle)));

        for (uint256 i; i < markets.length; ++i) {
            if (!_canWithdrawFullSupply(IMarket(markets[i]), feeRecipient)) continue;
            _append(batch, index++, markets[i], abi.encodeCall(IAuth.setAuthorization, (adapter, false)));
        }
        assert(bundleIndex == marketCount);
        assert(index == callCount);
    }

    function _canWithdrawFullSupply(IMarket market, address feeRecipient) private view returns (bool) {
        Balance memory storedTotalSupply = market.totalSupply();
        (uint256 expectedTotalSupplyAssets, uint256 expectedTotalSupplyShares, uint256 expectedTotalBorrowAssets,) =
            address(market).expectedMarketBalances();

        uint256 expectedFeeRecipientShares = market.position(feeRecipient).supplyShares;
        if (market.feeRecipient() == feeRecipient) {
            // Before activation, accrueInterest() mints newly projected supply shares to the legacy fee recipient.
            expectedFeeRecipientShares += expectedTotalSupplyShares - storedTotalSupply.shares;
        }
        if (expectedFeeRecipientShares == 0) return false;

        uint256 claimableAssets =
            expectedFeeRecipientShares.convertToAssetsDown(expectedTotalSupplyAssets, expectedTotalSupplyShares);
        uint256 availableLiquidity = Math.min(
            expectedTotalSupplyAssets - expectedTotalBorrowAssets,
            IERC20(market.borrowToken()).balanceOf(address(market))
        );
        return claimableAssets != 0 && claimableAssets <= availableLiquidity;
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

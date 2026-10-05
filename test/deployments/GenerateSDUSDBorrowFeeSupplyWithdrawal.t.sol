// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {GenerateSDUSDBorrowFeeSupplyWithdrawalScript} from "../../script/GenerateSDUSDBorrowFeeSupplyWithdrawal.s.sol";
import {IMarket, IMarketBase, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

struct DecodedBorrowFeeSupplyWithdrawalBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
    bytes32 predecessor;
    bytes32 salt;
}

contract GenerateSDUSDBorrowFeeSupplyWithdrawalForkTest is Test {
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;

    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;

    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant SCHEDULE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-borrow-fee-supply-withdrawal-schedule.json";
    string internal constant EXECUTE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-borrow-fee-supply-withdrawal-execute.json";
    string internal constant REPORT_PATH =
        "contracts/deployments/ethereum-mainnet/output/sdusd-borrow-fee-supply-withdrawal-report.json";

    address internal marketRegistry;
    address internal legacyFeeRecipient;
    address internal dummyFeeRecipient;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        _deleteGeneratedFiles();

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
        marketRegistry = vm.parseJsonAddress(json, ".contracts.marketRegistry");
        legacyFeeRecipient = vm.parseJsonAddress(json, ".contracts.legacyFeeRecipient");
        dummyFeeRecipient = makeAddr("dummyFeeRecipient");
    }

    function testFork_GeneratedBorrowFeeSupplyWithdrawalsMatchJsonReport() public {
        address[] memory markets = IMarketRegistry(marketRegistry).getBorrowMarkets();
        assertGt(markets.length, 0, "no registered borrow markets");

        uint256 legacyShares = _accrueInterestThenMigrateFeeRecipients(markets);
        assertGt(legacyShares, 0, "old fee recipient has no supply shares");

        GenerateSDUSDBorrowFeeSupplyWithdrawalScript generator = new GenerateSDUSDBorrowFeeSupplyWithdrawalScript();
        generator.run();

        assertTrue(vm.exists(SCHEDULE_PATH), "missing schedule file");
        assertTrue(vm.exists(EXECUTE_PATH), "missing execute file");
        assertTrue(vm.exists(REPORT_PATH), "missing residual report");

        string memory reportJson = vm.readFile(REPORT_PATH);

        DecodedBorrowFeeSupplyWithdrawalBatch memory batch = _readExecuteBatch();
        assertGt(batch.targets.length, 0, "no withdrawal calldata generated");
        assertEq(batch.targets.length, batch.values.length, "target/value length mismatch");
        assertEq(batch.targets.length, batch.payloads.length, "target/payload length mismatch");
        assertEq(batch.predecessor, bytes32(0), "unexpected predecessor");
        assertEq(batch.salt, bytes32(0), "unexpected salt");

        _executeGeneratedMarketCalls(batch);
        _assertPositionsMatchReport(markets, reportJson);

        _deleteGeneratedFiles();
    }

    /// @dev Accrual must happen while the old recipient is still configured so all pending fee shares are minted to it.
    function _accrueInterestThenMigrateFeeRecipients(address[] memory markets) private returns (uint256 legacyShares) {
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);

            market.accrueInterest();
            uint256 sharesAfterAccrual = market.position(legacyFeeRecipient).supplyShares;
            legacyShares += sharesAfterAccrual;

            vm.prank(Ownable(markets[i]).owner());
            market.setFeeRecipient(dummyFeeRecipient);

            assertEq(market.feeRecipient(), dummyFeeRecipient, "fee recipient not updated");
            assertEq(
                market.position(legacyFeeRecipient).supplyShares,
                sharesAfterAccrual,
                "legacy shares changed during migration"
            );
        }
    }

    /// @dev Execute the market payloads decoded from the generated Safe JSON immediately, avoiding projection drift
    ///      from the timelock delay while still testing the exact generated calldata.
    function _executeGeneratedMarketCalls(DecodedBorrowFeeSupplyWithdrawalBatch memory batch) private {
        for (uint256 i; i < batch.targets.length; ++i) {
            IMarket market = IMarket(batch.targets[i]);
            (uint256 encodedAssets, uint256 encodedShares,,) = _decodeRemoveSupply(batch.payloads[i]);

            uint256 sharesBefore = market.position(legacyFeeRecipient).supplyShares;
            IERC20 borrowToken = IERC20(market.borrowToken());
            uint256 assetsBefore = borrowToken.balanceOf(legacyFeeRecipient);

            vm.prank(legacyFeeRecipient);
            (bool success, bytes memory result) = batch.targets[i].call(batch.payloads[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }

            (uint256 withdrawnAssets, uint256 withdrawnShares) = abi.decode(result, (uint256, uint256));
            assertEq(
                borrowToken.balanceOf(legacyFeeRecipient) - assetsBefore,
                withdrawnAssets,
                "received assets differ from generated call"
            );
            assertEq(
                sharesBefore - market.position(legacyFeeRecipient).supplyShares,
                withdrawnShares,
                "burned shares differ from generated call"
            );

            if (encodedAssets != 0) {
                assertEq(withdrawnAssets, encodedAssets, "wrong asset withdrawal");
            } else {
                assertEq(withdrawnShares, encodedShares, "wrong share withdrawal");
            }
        }
    }

    function _assertPositionsMatchReport(address[] memory markets, string memory reportJson) private {
        for (uint256 i; i < markets.length; ++i) {
            string memory reportEntry = string.concat(".markets[", vm.toString(i), "]");
            uint256 remainingShares = vm.parseJsonUint(reportJson, string.concat(reportEntry, ".remainingShares"));
            uint256 remainingAssets = vm.parseJsonUint(reportJson, string.concat(reportEntry, ".remainingAssets"));

            IMarket market = IMarket(markets[i]);
            assertEq(
                market.position(legacyFeeRecipient).supplyShares, remainingShares, "actual shares differ from report"
            );

            (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = markets[i].expectedMarketBalances();
            assertEq(
                remainingShares.convertToAssetsDown(totalSupplyAssets, totalSupplyShares),
                remainingAssets,
                "actual assets differ from report"
            );

            if (remainingShares != 0) {
                vm.startPrank(legacyFeeRecipient);
                vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
                market.removeSupply(1, 0, legacyFeeRecipient, legacyFeeRecipient);
                vm.stopPrank();
            }
        }
    }

    function _readExecuteBatch() private view returns (DecodedBorrowFeeSupplyWithdrawalBatch memory batch) {
        string memory json = vm.readFile(EXECUTE_PATH);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), legacyFeeRecipient, "wrong Safe target");

        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(bytes4(data), TimelockController.executeBatch.selector, "wrong execute selector");
        (batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt) =
            abi.decode(_removeSelector(data), (address[], uint256[], bytes[], bytes32, bytes32));
    }

    function _decodeRemoveSupply(bytes memory payload)
        private
        pure
        returns (uint256 assets, uint256 shares, address onBehalf, address receiver)
    {
        assertEq(bytes4(payload), IMarketBase.removeSupply.selector, "wrong market selector");
        return abi.decode(_removeSelector(payload), (uint256, uint256, address, address));
    }

    function _removeSelector(bytes memory data) private pure returns (bytes memory arguments) {
        require(data.length >= 4, "missing selector");
        arguments = new bytes(data.length - 4);
        for (uint256 i; i < arguments.length; ++i) {
            arguments[i] = data[i + 4];
        }
    }

    function _deleteGeneratedFiles() private {
        _deleteIfExists(SCHEDULE_PATH);
        _deleteIfExists(EXECUTE_PATH);
        _deleteIfExists(REPORT_PATH);
    }

    function _deleteIfExists(string memory path) private {
        if (vm.exists(path)) vm.removeFile(path);
    }
}

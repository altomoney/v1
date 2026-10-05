// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    GenerateSDUSDFeeCollateralWithdrawalScript,
    LegacyFeeCollateralWithdrawalSafeBatch
} from "../../script/GenerateSDUSDFeeCollateralWithdrawal.s.sol";
import {IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

interface IOwnedMarket {
    function owner() external view returns (address);
}

contract GenerateSDUSDFeeCollateralWithdrawalForkTest is Test {
    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;

    address internal constant MAINNET_TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;

    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant BORROW_SCHEDULE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-borrow-fee-collateral-withdrawal-schedule.json";
    string internal constant BORROW_EXECUTE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-borrow-fee-collateral-withdrawal-execute.json";
    string internal constant MINT_SCHEDULE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-mint-fee-collateral-withdrawal-schedule.json";
    string internal constant MINT_EXECUTE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-mint-fee-collateral-withdrawal-execute.json";

    address internal marketRegistry;
    address internal legacyFeeRecipient;
    address internal legacyMintMarketFeeRecipient;
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
        legacyMintMarketFeeRecipient = vm.parseJsonAddress(json, ".contracts.legacyMintMarketFeeRecipient");
        dummyFeeRecipient = makeAddr("dummyFeeRecipient");
    }

    function testFork_GenerateAndExecuteLegacyFeeCollateralWithdrawals() public {
        address[] memory borrowMarkets = IMarketRegistry(marketRegistry).getBorrowMarkets();
        address[] memory mintMarkets = IMarketRegistry(marketRegistry).getMintMarkets();

        uint256 borrowCollateralMarketCount = _collateralMarketCount(borrowMarkets, legacyFeeRecipient);
        uint256 mintCollateralMarketCount = _collateralMarketCount(mintMarkets, legacyMintMarketFeeRecipient);
        assertGt(borrowCollateralMarketCount, 0, "no legacy borrow collateral positions");
        assertGt(mintCollateralMarketCount, 0, "no legacy mint collateral positions");

        _setFeeRecipient(borrowMarkets);
        _setFeeRecipient(mintMarkets);

        GenerateSDUSDFeeCollateralWithdrawalScript generator = new GenerateSDUSDFeeCollateralWithdrawalScript();
        LegacyFeeCollateralWithdrawalSafeBatch memory borrowBatch =
            generator.buildCollateralWithdrawal(borrowMarkets, legacyFeeRecipient);
        LegacyFeeCollateralWithdrawalSafeBatch memory mintBatch =
            generator.buildCollateralWithdrawal(mintMarkets, legacyMintMarketFeeRecipient);
        assertEq(borrowBatch.targets.length, borrowCollateralMarketCount, "unexpected borrow call count");
        assertEq(mintBatch.targets.length, mintCollateralMarketCount, "unexpected mint call count");

        _mockCollateralPrices(borrowMarkets, legacyFeeRecipient);
        _mockCollateralPrices(mintMarkets, legacyMintMarketFeeRecipient);

        generator.run();
        assertTrue(vm.exists(BORROW_SCHEDULE_PATH), "missing borrow schedule file");
        assertTrue(vm.exists(BORROW_EXECUTE_PATH), "missing borrow execute file");
        assertTrue(vm.exists(MINT_SCHEDULE_PATH), "missing mint schedule file");
        assertTrue(vm.exists(MINT_EXECUTE_PATH), "missing mint execute file");

        _callTimelock(legacyFeeRecipient, BORROW_SCHEDULE_PATH);
        _callTimelock(legacyMintMarketFeeRecipient, MINT_SCHEDULE_PATH);

        uint256 borrowDelay = TimelockController(payable(legacyFeeRecipient)).getMinDelay();
        uint256 mintDelay = TimelockController(payable(legacyMintMarketFeeRecipient)).getMinDelay();
        vm.warp(block.timestamp + (borrowDelay > mintDelay ? borrowDelay : mintDelay) + 1);

        _callTimelock(legacyFeeRecipient, BORROW_EXECUTE_PATH);
        _callTimelock(legacyMintMarketFeeRecipient, MINT_EXECUTE_PATH);

        _assertNoCollateral(borrowMarkets, legacyFeeRecipient);
        _assertNoCollateral(mintMarkets, legacyMintMarketFeeRecipient);

        _deleteGeneratedFiles();
    }

    function _setFeeRecipient(address[] memory markets) private {
        for (uint256 i; i < markets.length; ++i) {
            address marketOwner = IOwnedMarket(markets[i]).owner();
            vm.prank(marketOwner);
            IMarketBase(markets[i]).setFeeRecipient(dummyFeeRecipient);
            assertEq(IMarket(markets[i]).feeRecipient(), dummyFeeRecipient, "fee recipient not updated");
        }
    }

    function _collateralMarketCount(address[] memory markets, address feeRecipient)
        private
        view
        returns (uint256 count)
    {
        for (uint256 i; i < markets.length; ++i) {
            Position memory position = IMarket(markets[i]).position(feeRecipient);
            if (position.collateralAssets == 0) continue;
            assertEq(position.borrowShares, 0, "legacy fee recipient has debt");
            ++count;
        }
    }

    function _mockCollateralPrices(address[] memory markets, address feeRecipient) private {
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            if (market.position(feeRecipient).collateralAssets == 0) continue;

            address oracle = market.oracle();
            uint256 price = ILendingOracle(oracle).getPrice();
            vm.mockCall(oracle, abi.encodeCall(ILendingOracle.getPrice, ()), abi.encode(price));
        }
    }

    function _assertNoCollateral(address[] memory markets, address feeRecipient) private view {
        for (uint256 i; i < markets.length; ++i) {
            assertEq(IMarket(markets[i]).position(feeRecipient).collateralAssets, 0, "legacy collateral remains");
        }
    }

    function _callTimelock(address timelock, string memory path) private {
        bytes memory data = vm.parseJsonBytes(vm.readFile(path), ".transactions[0].data");
        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool success, bytes memory result) = timelock.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    function _deleteGeneratedFiles() private {
        _deleteIfExists(BORROW_SCHEDULE_PATH);
        _deleteIfExists(BORROW_EXECUTE_PATH);
        _deleteIfExists(MINT_SCHEDULE_PATH);
        _deleteIfExists(MINT_EXECUTE_PATH);
    }

    function _deleteIfExists(string memory path) private {
        if (vm.exists(path)) vm.removeFile(path);
    }
}

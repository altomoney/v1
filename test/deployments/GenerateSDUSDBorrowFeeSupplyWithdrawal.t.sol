// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    BorrowFeeSupplyWithdrawalSafeBatch,
    GenerateSDUSDBorrowFeeSupplyWithdrawalScript
} from "../../script/GenerateSDUSDBorrowFeeSupplyWithdrawal.s.sol";
import {Balance, IMarket, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract GenerateSDUSDBorrowFeeSupplyWithdrawalForkTest is Test {
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;

    uint256 internal constant MAINNET_FORK_BLOCK = 26025105;
    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;

    address internal constant MAINNET_TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address internal constant OLD_FEE_RECIPIENT = 0xb9F06fEFc4c53dEd77A90Cb798eD08DC068Bb6dd;

    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant SCHEDULE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-borrow-fee-supply-withdrawal-schedule.json";
    string internal constant EXECUTE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-borrow-fee-supply-withdrawal-execute.json";

    address internal marketRegistry;
    address internal altoAdapter;
    address internal dusd;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), MAINNET_FORK_BLOCK);

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
        altoAdapter = vm.parseJsonAddress(json, ".contracts.altoAdapter");
        dusd = vm.parseJsonAddress(json, ".contracts.dusd");
    }

    function testFork_GenerateAndExecuteBorrowFeeSupplyWithdrawal() public {
        address[] memory markets = IMarketRegistry(marketRegistry).getBorrowMarkets();
        assertEq(markets.length, 7, "unexpected borrow market count");

        GenerateSDUSDBorrowFeeSupplyWithdrawalScript generator = new GenerateSDUSDBorrowFeeSupplyWithdrawalScript();
        BorrowFeeSupplyWithdrawalSafeBatch memory withdrawalBatch =
            generator.buildBorrowFeeSupplyWithdrawal(marketRegistry, altoAdapter, OLD_FEE_RECIPIENT);
        assertGt(withdrawalBatch.targets.length, 0, "no withdrawal calldata generated");

        uint256[] memory sharesBefore = new uint256[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            Position memory position = market.position(OLD_FEE_RECIPIENT);
            (uint256 claimableAssets, uint256 availableLiquidity) = _claimableAssetsAndLiquidity(market);

            assertGt(position.supplyShares, 0, "old fee recipient has no supply shares");
            sharesBefore[i] = position.supplyShares;

            if (_isIncluded(withdrawalBatch, markets[i])) {
                assertLe(claimableAssets, availableLiquidity, "included market lacks liquidity");
            } else {
                assertGt(claimableAssets, availableLiquidity, "liquid market missing from calldata");
            }
        }

        generator.run();
        _callTimelock(SCHEDULE_PATH);
        vm.warp(block.timestamp + TimelockController(payable(OLD_FEE_RECIPIENT)).getMinDelay() + 1);

        uint256 dusdBefore = IERC20(dusd).balanceOf(OLD_FEE_RECIPIENT);
        _callTimelock(EXECUTE_PATH);

        for (uint256 i; i < markets.length; ++i) {
            uint256 sharesAfter = IMarket(markets[i]).position(OLD_FEE_RECIPIENT).supplyShares;
            if (_isIncluded(withdrawalBatch, markets[i])) {
                assertLt(sharesAfter, sharesBefore[i], "included market did not withdraw shares");
                assertFalse(
                    IAuth(markets[i]).isAuthorized(OLD_FEE_RECIPIENT, altoAdapter),
                    "temporary adapter authorization was not revoked"
                );
            } else {
                assertEq(sharesAfter, sharesBefore[i], "omitted market shares changed");
            }
        }

        assertGt(IERC20(dusd).balanceOf(OLD_FEE_RECIPIENT), dusdBefore, "old fee recipient did not receive DUSD");
    }

    function _isIncluded(BorrowFeeSupplyWithdrawalSafeBatch memory batch, address market) private pure returns (bool) {
        uint256 marketCount = (batch.targets.length - 1) / 2;
        for (uint256 i; i < marketCount; ++i) {
            if (batch.targets[i] == market) return true;
        }
        return false;
    }

    function _claimableAssetsAndLiquidity(IMarket market)
        private
        view
        returns (uint256 claimableAssets, uint256 availableLiquidity)
    {
        Balance memory storedTotalSupply = market.totalSupply();
        (uint256 expectedTotalSupplyAssets, uint256 expectedTotalSupplyShares, uint256 expectedTotalBorrowAssets,) =
            address(market).expectedMarketBalances();

        uint256 expectedShares = market.position(OLD_FEE_RECIPIENT).supplyShares;
        if (market.feeRecipient() == OLD_FEE_RECIPIENT) {
            expectedShares += expectedTotalSupplyShares - storedTotalSupply.shares;
        }

        claimableAssets = expectedShares.convertToAssetsDown(expectedTotalSupplyAssets, expectedTotalSupplyShares);
        availableLiquidity = Math.min(
            expectedTotalSupplyAssets - expectedTotalBorrowAssets,
            IERC20(market.borrowToken()).balanceOf(address(market))
        );
    }

    function _callTimelock(string memory path) private {
        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool success, bytes memory result) =
            OLD_FEE_RECIPIENT.call(vm.parseJsonBytes(vm.readFile(path), ".transactions[0].data"));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }
}

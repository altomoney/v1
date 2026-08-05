// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    GeneratePolLiquidityMigrationTransactionsScript,
    IConvexRewardPool,
    IYearnV2Vault,
    PolMigrationSafeTx
} from "../../script/GeneratePolLiquidityMigrationTransactions.s.sol";

contract GeneratePolLiquidityMigrationTransactionsTest is Test {
    GeneratePolLiquidityMigrationTransactionsScript internal generator;

    function setUp() public {
        generator = new GeneratePolLiquidityMigrationTransactionsScript();
    }

    function test_RequestAmountsMatchExactSplit() public view {
        assertEq(generator.YEARN_AMOUNT(), 215_246 ether);
        assertEq(generator.STAKE_DAO_AMOUNT(), 306_081 ether);
        assertEq(generator.TOTAL_MIGRATION_AMOUNT(), 521_327 ether);
        assertEq(generator.YEARN_AMOUNT() + generator.STAKE_DAO_AMOUNT(), generator.TOTAL_MIGRATION_AMOUNT());
    }

    function test_GetMigrationTransactions_encodesRequestedSafeBatch() public view {
        PolMigrationSafeTx[] memory txs = generator.getMigrationTransactions();

        assertEq(txs.length, 5);
        _assertConvexWithdrawal(txs[0]);
        _assertApproval(txs[1], generator.YEARN_VAULT(), generator.YEARN_AMOUNT());
        _assertDeposit(txs[2], generator.YEARN_VAULT(), generator.YEARN_AMOUNT());
        _assertApproval(txs[3], generator.STAKE_DAO_VAULT(), generator.STAKE_DAO_AMOUNT());
        _assertDeposit(txs[4], generator.STAKE_DAO_VAULT(), generator.STAKE_DAO_AMOUNT());
    }

    function test_BuildSafeBatchJson_writesImportableFiveTransactionBatch() public view {
        PolMigrationSafeTx[] memory txs = generator.getMigrationTransactions();
        string memory json = generator.buildSafeBatchJson(txs);

        assertEq(vm.parseJsonString(json, ".version"), "1.0");
        assertEq(vm.parseJsonString(json, ".chainId"), "1");
        assertEq(vm.parseJsonString(json, ".meta.name"), "Rebalance POL Liquidity");
        assertEq(vm.parseJsonString(json, ".meta.txBuilderVersion"), "1.16.5");

        for (uint256 i = 0; i < txs.length; ++i) {
            string memory path = string.concat(".transactions[", vm.toString(i), "]");
            assertEq(vm.parseJsonAddress(json, string.concat(path, ".to")), txs[i].to);
            assertEq(vm.parseJsonString(json, string.concat(path, ".value")), "0");
            assertEq(vm.parseJsonBytes(json, string.concat(path, ".data")), txs[i].data);
        }
    }

    function test_BuildSafeBatchJson_rejectsIncompleteBatch() public {
        PolMigrationSafeTx[] memory incomplete = new PolMigrationSafeTx[](4);

        vm.expectRevert(bytes("unexpected migration transaction count"));
        generator.buildSafeBatchJson(incomplete);
    }

    function _assertConvexWithdrawal(PolMigrationSafeTx memory transaction) internal view {
        assertEq(transaction.to, generator.CONVEX_REWARD_POOL());
        assertEq(_selector(transaction.data), IConvexRewardPool.withdrawAndUnwrap.selector);
        (uint256 amount, bool claim) = abi.decode(_arguments(transaction.data), (uint256, bool));
        assertEq(amount, generator.TOTAL_MIGRATION_AMOUNT());
        assertFalse(claim, "migration must not claim Convex rewards");
    }

    function _assertApproval(PolMigrationSafeTx memory transaction, address spender, uint256 amount) internal view {
        assertEq(transaction.to, generator.CURVE_LP_TOKEN());
        assertEq(_selector(transaction.data), IERC20.approve.selector);
        (address encodedSpender, uint256 encodedAmount) = abi.decode(_arguments(transaction.data), (address, uint256));
        assertEq(encodedSpender, spender);
        assertEq(encodedAmount, amount);
    }

    function _assertDeposit(PolMigrationSafeTx memory transaction, address vault, uint256 amount) internal view {
        assertEq(transaction.to, vault);
        assertEq(_selector(transaction.data), IERC4626.deposit.selector);
        (uint256 encodedAmount, address recipient) = abi.decode(_arguments(transaction.data), (uint256, address));
        assertEq(encodedAmount, amount);
        assertEq(recipient, generator.TREASURY_SAFE());
    }

    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        require(data.length >= 4, "missing selector");
        assembly ("memory-safe") {
            selector := mload(add(data, 0x20))
        }
    }

    function _arguments(bytes memory data) internal pure returns (bytes memory arguments) {
        require(data.length >= 4, "missing selector");
        arguments = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; ++i) {
            arguments[i - 4] = data[i];
        }
    }
}

contract GeneratePolLiquidityMigrationTransactionsForkTest is Test {
    uint256 internal constant FORK_BLOCK = 25_593_915;

    GeneratePolLiquidityMigrationTransactionsScript internal generator;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);
        generator = new GeneratePolLiquidityMigrationTransactionsScript();
    }

    function test_Fork_mainnetStateMatchesRequestContracts() public view {
        generator.validateMainnetState();
    }

    function test_Fork_fullSafeBatchExecutesAndRevertsSimulationState() public {
        IConvexRewardPool rewardPool = IConvexRewardPool(generator.CONVEX_REWARD_POOL());
        uint256 convexBalanceBefore = rewardPool.balanceOf(generator.TREASURY_SAFE());
        uint256 convexEarnedBefore = rewardPool.earned(generator.TREASURY_SAFE());

        PolMigrationSafeTx[] memory txs = generator.getMigrationTransactions();
        generator.validateAndSimulateMigrationTransactions(txs);

        assertEq(rewardPool.balanceOf(generator.TREASURY_SAFE()), convexBalanceBefore);
        assertEq(rewardPool.earned(generator.TREASURY_SAFE()), convexEarnedBefore);
        assertEq(IERC20(generator.CURVE_LP_TOKEN()).balanceOf(generator.TREASURY_SAFE()), 0);
        assertEq(IYearnV2Vault(generator.YEARN_VAULT()).balanceOf(generator.TREASURY_SAFE()), 0);
        assertEq(IERC4626(generator.STAKE_DAO_VAULT()).balanceOf(generator.TREASURY_SAFE()), 0);
    }
}

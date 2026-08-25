// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboardingPhase} from "../IBorrowMarketOffboarding.sol";

import {BorrowMarketBatch, BorrowMarketBatchParams} from "@alto/deployments/ethereum-mainnet/BorrowMarketBatch.sol";
import {
    KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET,
    NORDSTERN_ROUTER_MAINNET,
    ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET,
    VELORA_AUGUSTUS_MAINNET,
    WETH_MAINNET,
    ZEROX_SWAP_TARGET_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {MarketContracts} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {EthereumMainnetLendingOracleAsset} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IAltoVaultErrors, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchCRecoverTest is BorrowMarketOffboardingTestBase {
    using AltoBalancesLib for address;

    struct RecoveryMarketSnapshot {
        address oracle;
        address irm;
        address liquidationEngine;
        address feeRecipient;
        uint256 maxLtv;
        uint256 borrowOpeningFee;
        uint256 borrowRate;
        bytes32 liquidationConfigurationHash;
        Balance totalSupply;
        address legacyUser;
        Position legacyPosition;
    }

    uint256[] internal livePrices;
    RecoveryMarketSnapshot[] internal recoverySnapshots;

    function setUp() public {
        _setUpManifest();
        if (marketAlreadyFrozen) return;

        for (uint256 i; i < borrowMarkets.length; ++i) {
            livePrices.push(IOracle(IMarketBase(borrowMarkets[i]).oracle()).getPrice());
        }
    }

    function testBatchCRecoverRevertsAgainstCurrentMainnetDebt() public {
        if (marketAlreadyFrozen) return;

        bool debtRemains;
        bool vaultMarketSupplyRemains;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            Balance memory debt = IMarket(borrowMarkets[i]).totalBorrowed();
            debtRemains = debtRemains || debt.assets != 0 || debt.shares != 0;
            vaultMarketSupplyRemains =
                vaultMarketSupplyRemains || IMarket(borrowMarkets[i]).position(address(vault)).supplyShares != 0;
        }

        assertTrue(debtRemains, "current mainnet has no affected-market debt");
        assertTrue(vaultMarketSupplyRemains, "current mainnet Vault has no affected-market supply");
        vm.expectRevert(bytes("Batch C: market debt remains"));
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, input);
    }

    function testBatchCRecoverSucceedsAfterDebtAndVaultMarketSupplyAreZero() public {
        if (marketAlreadyFrozen) return;

        _assertAddressInventoriesComplete();
        uint256 vaultSharesBefore = vaultToken.totalSupply();
        bytes32 holderSharesHashBefore = _vaultHolderSharesHash();
        _executePrerequisitePhases();
        _repayAllBorrowers();

        vm.expectRevert(bytes("Batch C: Vault market supply remains"));
        scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, input);
        vm.stopBroadcast();

        uint256 targetSupplyAssets = _targetMarketSupplyAssets();
        assertGt(targetSupplyAssets, 0, "test requires positive affected-market supply");
        MarketAllocation[] memory exitsWithoutReplacement = _targetExitAllocations(0);
        vm.expectRevert(IAltoVaultErrors.InconsistentReallocation.selector);
        vm.prank(VAULT_ALLOCATOR);
        vault.reallocate(exitsWithoutReplacement);

        address replacement = _approveReplacementBorrowMarket(targetSupplyAssets + 1 ether);
        _reallocateVaultToReplacement(replacement);
        _removeTargetMarketsFromQueues(replacement);
        _assertRecoveryPreconditions(replacement, vaultSharesBefore, holderSharesHashBefore);
        _snapshotUnrelatedMarketState();

        _executeTimelockPhase(BorrowMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);

        _assertRecoveryOutcome(replacement, vaultSharesBefore, holderSharesHashBefore);
        _exerciseVaultDepositAndWithdrawal(replacement, vaultSharesBefore, holderSharesHashBefore);
        _exerciseLegacyExitRoutes();
    }

    function _executePrerequisitePhases() private {
        OwnerFixedRateIrmFactory factory = _ensureFactory();
        assertEq(factory.owner(), address(timelock), "Timelock does not own IRM factory");

        _executeContainmentPrerequisite();
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );
        _assertAllFrozenAndUnpaused();
    }

    function _assertAddressInventoriesComplete() private view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertBorrowerInventoryComplete(i);
        }

        address[] memory holders = _vaultHolders();
        uint256 listedVaultShares;
        for (uint256 i; i < holders.length; ++i) {
            listedVaultShares += vaultToken.balanceOf(holders[i]);
        }
        assertEq(listedVaultShares, vaultToken.totalSupply(), "stale Vault holder list");
    }

    function _repayAllBorrowers() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _repayAllBorrowersForMarket(i);
        }
    }

    function _vaultHolderSharesHash() private view returns (bytes32 hash) {
        address[] memory holders = _vaultHolders();
        for (uint256 i; i < holders.length; ++i) {
            hash = keccak256(abi.encode(hash, holders[i], vaultToken.balanceOf(holders[i])));
        }
    }

    function _targetMarketSupplyAssets() private view returns (uint256 targetSupplyAssets) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            targetSupplyAssets += borrowMarkets[i].expectedSupplyAssets(address(vault));
        }
    }

    function _targetExitAllocations(uint256 extraLength) private view returns (MarketAllocation[] memory allocations) {
        allocations = new MarketAllocation[](borrowMarkets.length + extraLength);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            allocations[i] = MarketAllocation({market: borrowMarkets[i], assets: 0});
        }
    }

    function _deployWethBorrowMarket() private returns (address replacement) {
        MarketContracts memory deployed = BorrowMarketBatch.deploy(_wethBorrowMarketParams());
        replacement = deployed.market;

        assertEq(IMarket(replacement).borrowToken(), vaultToken.asset(), "replacement has wrong borrow token");
        assertEq(IMarket(replacement).collateralToken(), WETH_MAINNET, "replacement has wrong collateral token");
    }

    /// @dev WETH risk values mirror MINT_MARKET_WETH; borrow-only IRM values mirror the production borrow markets.
    function _wethBorrowMarketParams() private view returns (BorrowMarketBatchParams memory params) {
        params.owner = address(timelock);
        params.deployer = address(this);
        params.dusd = vaultToken.asset();
        params.altoAdapter = address(altoAdapter);
        params.feeRecipient = IMarket(borrowMarkets[0]).feeRecipient();
        params.collateralToken = WETH_MAINNET;
        params.oracleAsset = EthereumMainnetLendingOracleAsset.WETH;
        params.irmConfig = AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 4 ether,
            adjustmentSpeed: 50 ether / int256(365 days),
            targetUtilization: 0.9 ether,
            initialRateAtTarget: 0.1 ether / int256(365 days),
            minRateAtTarget: 0.001 ether / int256(365 days),
            maxRateAtTarget: 2 ether / int256(365 days)
        });
        params.maxLtv = 0.8 ether;
        params.initialBorrowOpeningFee = 0.0005 ether;
        params.supplyCapAssets = 0;
        params.liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.85 ether,
            dynamicBonusFeeStart: 0.02 ether,
            ltvForCompleteLiquidation: 0.93 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.005 ether,
            protocolFeePercentage: 0.07 ether,
            isEnabledPriorityLiquidation: false,
            disablePriorityLiquidationAbovePositionLtv: 0,
            priorityLiquidationGracePeriod: 0,
            taggerLiquidationGracePeriod: 0,
            liquidationWindowTag: 0
        });
        params.validSwapTargets = _validSwapTargets();
        params.freezer = FREEZER_SAFE;
    }

    function _validSwapTargets() private pure returns (address[] memory targets) {
        targets = new address[](5);
        targets[0] = ZEROX_SWAP_TARGET_MAINNET;
        targets[1] = ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET;
        targets[2] = KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET;
        targets[3] = VELORA_AUGUSTUS_MAINNET;
        targets[4] = NORDSTERN_ROUTER_MAINNET;
    }

    function _approveReplacementBorrowMarket(uint256 supplyCap) private returns (address replacement) {
        assertTrue(vault.isAllocator(VAULT_ALLOCATOR), "configured allocator is not authorized");
        _assertVaultQueuesContainOnlyAffectedMarkets();
        replacement = _deployWethBorrowMarket();

        vm.startPrank(address(timelock));
        marketRegistry.addBorrowMarket(replacement);
        altoAdapter.approveContract(replacement);
        ILiquidationPeripheryBase(liquidationPeriphery).setSupportedMarket(replacement, true);
        IMarket(replacement).setAuthorizedLiquidationPeriphery(liquidationPeriphery, true);
        vm.stopPrank();

        vm.prank(vault.curator());
        vault.submitCap(replacement, supplyCap);
        vm.warp(vault.pendingCap(replacement).validAt);
        vault.acceptCap(replacement);

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = replacement;
        vm.prank(VAULT_ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);
    }

    function _reallocateVaultToReplacement(address replacement) private {
        MarketAllocation[] memory allocations = _targetExitAllocations(1);
        allocations[borrowMarkets.length] = MarketAllocation({market: replacement, assets: type(uint256).max});

        vm.prank(VAULT_ALLOCATOR);
        vault.reallocate(allocations);
    }

    function _removeTargetMarketsFromQueues(address replacement) private {
        uint256[] memory remainingIndexes = new uint256[](1);
        uint256 replacementIndex = type(uint256).max;
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            if (vault.withdrawQueue(i) == replacement) {
                replacementIndex = i;
                break;
            }
        }
        assertNotEq(replacementIndex, type(uint256).max, "replacement absent from withdraw queue");
        remainingIndexes[0] = replacementIndex;

        vm.prank(VAULT_ALLOCATOR);
        vault.updateWithdrawQueue(remainingIndexes);

        assertEq(vault.supplyQueueLength(), 1, "unexpected Vault supply queue length");
        assertEq(vault.withdrawQueueLength(), 1, "unexpected Vault withdraw queue length");
        assertEq(vault.supplyQueue(0), replacement, "replacement absent from supply queue");
        assertEq(vault.withdrawQueue(0), replacement, "replacement absent from withdraw queue");
    }

    function _assertVaultQueuesContainOnlyAffectedMarkets() private view {
        assertEq(vault.supplyQueueLength(), borrowMarkets.length, "unexpected Vault supply queue length");
        assertEq(vault.withdrawQueueLength(), borrowMarkets.length, "unexpected Vault withdraw queue length");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertTrue(_isAffectedMarket(vault.supplyQueue(i)), "unaffected market in supply queue");
            assertTrue(_isAffectedMarket(vault.withdrawQueue(i)), "unaffected market in withdraw queue");
        }
    }

    function _assertRecoveryPreconditions(
        address replacement,
        uint256 vaultSharesBefore,
        bytes32 holderSharesHashBefore
    ) private view {
        assertEq(vault.supplyQueueLength(), 1, "Vault supply queue precondition failed");
        assertEq(vault.withdrawQueueLength(), 1, "Vault withdraw queue precondition failed");
        assertEq(vault.supplyQueue(0), replacement, "replacement missing from supply queue");
        assertEq(vault.withdrawQueue(0), replacement, "replacement missing from withdraw queue");
        assertEq(vaultToken.totalSupply(), vaultSharesBefore, "Vault ERC4626 supply changed");
        assertEq(_vaultHolderSharesHash(), holderSharesHashBefore, "Vault holder shares changed");
        MarketConfig memory replacementConfig = vault.config(replacement);
        assertTrue(marketRegistry.isBorrowMarket(replacement), "replacement is not registered");
        assertTrue(replacementConfig.enabled, "replacement is not enabled");
        assertGt(replacementConfig.cap, 0, "replacement has no approved cap");
        assertGt(IMarket(replacement).position(address(vault)).supplyShares, 0, "replacement received no Vault supply");
        assertEq(vault.lostAssets(), 0, "ordinary recovery realized a Vault loss");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            Balance memory debt = market.totalBorrowed();
            MarketConfig memory config = vault.config(address(market));
            PendingUint192 memory pendingCap = vault.pendingCap(address(market));

            assertEq(debt.assets, 0, "market borrowed assets precondition failed");
            assertEq(debt.shares, 0, "market borrowed shares precondition failed");
            assertEq(market.position(address(vault)).supplyShares, 0, "Vault market supply shares remain");
            assertEq(vault.quarantinedAssets(address(market)), 0, "Vault market assets were quarantined");
            assertEq(config.cap, 0, "Vault cap precondition failed");
            assertFalse(config.enabled, "Vault market still enabled");
            assertEq(config.removableAt, 0, "Vault removal remains pending");
            assertEq(pendingCap.value, 0, "pending Vault cap value remains");
            assertEq(pendingCap.validAt, 0, "pending Vault cap remains");

            assertTrue(marketRegistry.isBorrowMarket(address(market)), "market already absent from registry");
            assertTrue(altoAdapter.isApprovedContract(address(market)), "market already revoked from adapter");
            assertTrue(AltoLeverage(leverages[i]).supportedMarkets(address(market)), "leverage support already removed");
            assertTrue(market.authorizedCallbacks(leverages[i]), "leverage callback already revoked");
            assertTrue(
                IAltoLeverageSwapper(leverageSwappers[i]).isWhitelisted(leverages[i]),
                "leverage swapper already revoked"
            );
            assertTrue(
                ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(address(market)),
                "liquidation periphery support already removed"
            );
            assertTrue(
                market.authorizedLiquidationPeriphery(liquidationPeriphery), "liquidation periphery already revoked"
            );
            _assertFrozenAndUnpaused(market);
        }
    }

    function _snapshotUnrelatedMarketState() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _snapshotUnrelatedMarketState(i);
        }
    }

    function _snapshotUnrelatedMarketState(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address[] memory borrowers = _borrowers(marketIndex);
        address legacyUser;
        Position memory legacyPosition;
        for (uint256 i; i < borrowers.length; ++i) {
            Position memory candidate = market.position(borrowers[i]);
            if (candidate.supplyShares != 0 && candidate.collateralAssets != 0) {
                legacyUser = borrowers[i];
                legacyPosition = candidate;
                break;
            }
        }
        assertNotEq(legacyUser, address(0), "no representative legacy position");

        address irm = market.irm();
        address liquidationEngine = market.liquidationEngine();
        (uint256 borrowRate,) = FixedRateIrm(irm).irState();
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();

        recoverySnapshots.push(
            RecoveryMarketSnapshot({
                oracle: market.oracle(),
                irm: irm,
                liquidationEngine: liquidationEngine,
                feeRecipient: market.feeRecipient(),
                maxLtv: market.maxLtv(),
                borrowOpeningFee: market.borrowOpeningFee(),
                borrowRate: borrowRate,
                liquidationConfigurationHash: keccak256(abi.encode(liquidationConfiguration)),
                totalSupply: market.totalSupply(),
                legacyUser: legacyUser,
                legacyPosition: legacyPosition
            })
        );
    }

    function _totalVaultQuarantinedAssets() private view returns (uint256 totalAssets) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            totalAssets += vault.quarantinedAssets(borrowMarkets[i]);
        }
    }

    function _assertRecoveryOutcome(address replacement, uint256 vaultSharesBefore, bytes32 holderSharesHashBefore)
        private
        view
    {
        assertEq(vault.supplyQueueLength(), 1, "Vault supply queue changed");
        assertEq(vault.withdrawQueueLength(), 1, "Vault withdraw queue changed");
        assertEq(vault.supplyQueue(0), replacement, "replacement left supply queue");
        assertEq(vault.withdrawQueue(0), replacement, "replacement left withdraw queue");
        assertEq(vaultToken.totalSupply(), vaultSharesBefore, "Vault ERC4626 supply changed");
        assertEq(_vaultHolderSharesHash(), holderSharesHashBefore, "Vault holder shares changed");
        assertEq(_totalVaultQuarantinedAssets(), 0, "Batch C left quarantined Vault assets");
        MarketConfig memory replacementConfig = vault.config(replacement);
        assertTrue(marketRegistry.isBorrowMarket(replacement), "Batch C removed replacement from registry");
        assertTrue(replacementConfig.enabled, "Batch C disabled replacement");
        assertGt(replacementConfig.cap, 0, "Batch C zeroed replacement cap");
        assertGt(IMarket(replacement).position(address(vault)).supplyShares, 0, "replacement Vault supply disappeared");
        assertEq(vault.lostAssets(), 0, "Batch C changed Vault losses");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketRemoved(i);
            _assertUnrelatedMarketStateUnchanged(i);
        }
    }

    function _exerciseVaultDepositAndWithdrawal(
        address replacement,
        uint256 vaultSharesBefore,
        bytes32 holderSharesHashBefore
    ) private {
        address user = makeAddr("replacement-vault-user");
        IERC20 asset = IERC20(vaultToken.asset());
        uint256 assets = 1 ether;
        deal(address(asset), user, assets);

        vm.startPrank(user);
        asset.approve(address(vaultToken), assets);
        uint256 shares = vaultToken.deposit(assets, user);
        assertGt(shares, 0, "Vault deposit minted no shares");
        uint256 withdrawnAssets = vaultToken.redeem(shares, user, user);
        vm.stopPrank();

        assertGt(withdrawnAssets, 0, "Vault redemption withdrew no assets");
        assertEq(vaultToken.balanceOf(user), 0, "test Vault shares remain");
        assertEq(vaultToken.totalSupply(), vaultSharesBefore, "Vault ERC4626 supply changed after route test");
        assertEq(_vaultHolderSharesHash(), holderSharesHashBefore, "existing Vault holder shares changed");
        assertEq(vault.supplyQueueLength(), 1, "Vault supply queue changed during route test");
        assertEq(vault.withdrawQueueLength(), 1, "Vault withdraw queue changed during route test");
        assertEq(vault.supplyQueue(0), replacement, "replacement left supply queue during route test");
        assertEq(vault.withdrawQueue(0), replacement, "replacement left withdraw queue during route test");
    }

    function _assertMarketRemoved(uint256 marketIndex) private view {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        Balance memory debt = market.totalBorrowed();
        MarketConfig memory config = vault.config(address(market));
        PendingUint192 memory pendingCap = vault.pendingCap(address(market));

        assertEq(debt.assets, 0, "market borrowed assets returned");
        assertEq(debt.shares, 0, "market borrowed shares returned");
        assertEq(market.position(address(vault)).supplyShares, 0, "Vault market supply returned");
        assertEq(vault.quarantinedAssets(address(market)), 0, "Vault market assets became quarantined");
        assertEq(config.cap, 0, "Vault cap changed");
        assertFalse(config.enabled, "Vault market re-enabled");
        assertEq(config.removableAt, 0, "Vault removal became pending");
        assertEq(pendingCap.value, 0, "pending Vault cap value changed");
        assertEq(pendingCap.validAt, 0, "pending Vault cap changed");

        assertFalse(marketRegistry.isBorrowMarket(address(market)), "market remains registered");
        assertFalse(altoAdapter.isApprovedContract(address(market)), "market remains adapter-approved");
        assertFalse(AltoLeverage(leverages[marketIndex]).supportedMarkets(address(market)), "leverage support remains");
        assertFalse(market.authorizedCallbacks(leverages[marketIndex]), "leverage callback remains");
        assertFalse(
            IAltoLeverageSwapper(leverageSwappers[marketIndex]).isWhitelisted(leverages[marketIndex]),
            "leverage swapper permission remains"
        );
        assertFalse(
            ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(address(market)),
            "liquidation periphery support remains"
        );
        assertFalse(
            market.authorizedLiquidationPeriphery(liquidationPeriphery), "liquidation periphery remains authorized"
        );
        _assertFrozenAndUnpaused(market);
    }

    function _assertUnrelatedMarketStateUnchanged(uint256 marketIndex) private view {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        RecoveryMarketSnapshot memory beforeState = recoverySnapshots[marketIndex];
        Balance memory supply = market.totalSupply();
        Position memory legacyPosition = market.position(beforeState.legacyUser);
        (uint256 borrowRate,) = FixedRateIrm(beforeState.irm).irState();
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(beforeState.liquidationEngine).liquidationConfiguration();

        assertEq(market.oracle(), beforeState.oracle, "oracle changed");
        assertEq(market.irm(), beforeState.irm, "IRM changed");
        assertEq(market.liquidationEngine(), beforeState.liquidationEngine, "liquidation engine changed");
        assertEq(market.feeRecipient(), beforeState.feeRecipient, "fee recipient changed");
        assertEq(market.maxLtv(), beforeState.maxLtv, "market max LTV changed");
        assertEq(market.borrowOpeningFee(), beforeState.borrowOpeningFee, "borrow opening fee changed");
        assertEq(borrowRate, beforeState.borrowRate, "fixed borrow rate changed");
        assertEq(
            keccak256(abi.encode(liquidationConfiguration)),
            beforeState.liquidationConfigurationHash,
            "liquidation configuration changed"
        );
        assertEq(supply.assets, beforeState.totalSupply.assets, "unrelated market supply assets changed");
        assertEq(supply.shares, beforeState.totalSupply.shares, "unrelated market supply shares changed");
        assertEq(legacyPosition.supplyShares, beforeState.legacyPosition.supplyShares, "legacy supply changed");
        assertEq(legacyPosition.borrowShares, 0, "legacy debt returned");
        assertEq(
            legacyPosition.collateralAssets, beforeState.legacyPosition.collateralAssets, "legacy collateral changed"
        );
    }

    function _exerciseLegacyExitRoutes() private {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            RecoveryMarketSnapshot memory beforeState = recoverySnapshots[i];
            vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(livePrices[i]));

            vm.startPrank(beforeState.legacyUser);
            market.removeSupply(
                0, beforeState.legacyPosition.supplyShares, beforeState.legacyUser, beforeState.legacyUser
            );
            market.removeCollateral(
                beforeState.legacyPosition.collateralAssets, beforeState.legacyUser, beforeState.legacyUser, ""
            );
            vm.stopPrank();

            Position memory afterExit = market.position(beforeState.legacyUser);
            assertEq(afterExit.supplyShares, 0, "legacy removeSupply failed");
            assertEq(afterExit.borrowShares, 0, "legacy debt changed during exit");
            assertEq(afterExit.collateralAssets, 0, "legacy removeCollateral failed");
            _assertFrozenAndUnpaused(market);
        }
    }
}

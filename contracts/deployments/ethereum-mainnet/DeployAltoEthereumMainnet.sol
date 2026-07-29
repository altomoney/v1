// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {AltoTimelockControllerMintMarketFee} from
    "@alto/deployments/ethereum-mainnet/contracts/AltoTimelockControllerMintMarketFee.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {
    BUNDLER3_MAINNET,
    WETH_MAINNET,
    WSTETH_MAINNET,
    RETH_MAINNET,
    METH_MAINNET,
    TBTC_MAINNET,
    WBTC_MAINNET,
    CBBTC_MAINNET,
    SUSDE_MAINNET,
    SYRUPUSDC_MAINNET,
    PAXG_MAINNET,
    USDC_MAINNET,
    FRXUSD_MAINNET,
    LAYERZERO_ENDPOINT_MAINNET,
    ZEROX_SWAP_TARGET_MAINNET,
    ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET,
    KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET,
    VELORA_AUGUSTUS_MAINNET,
    NORDSTERN_ROUTER_MAINNET,
    getMulticallOwnerAddresses
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    EthereumMainnetOracleDeployer,
    EthereumMainnetLendingOracleAsset
} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";

import {MockFeeCollector} from "@alto/deployments/ethereum-mainnet/MockFeeCollector.sol";
import {DUSDBatch, DUSDBatchParams, DUSDBatchReport} from "@alto/deployments/ethereum-mainnet/DUSDBatch.sol";
import {MintMarketBatch, MintMarketBatchParams} from "@alto/deployments/ethereum-mainnet/MintMarketBatch.sol";
import {BorrowMarketBatch, BorrowMarketBatchParams} from "@alto/deployments/ethereum-mainnet/BorrowMarketBatch.sol";
import {
    LeverageSwapperMultiTargetBatch,
    LeverageSwapperMultiTargetBatchParams
} from "@alto/deployments/ethereum-mainnet/LeverageSwapperMultiTargetBatch.sol";
import {
    LiquidationPeripheryBatch,
    LiquidationPeripheryBatchParams
} from "@alto/deployments/ethereum-mainnet/LiquidationPeripheryBatch.sol";
import {
    UniversalRewardsDistributorBatch,
    UniversalRewardsDistributorBatchParams
} from "@alto/deployments/ethereum-mainnet/UniversalRewardsDistributorBatch.sol";
import {
    AdvancedPermissionsUsmBatch,
    AdvancedPermissionsUsmBatchParams,
    AdvancedPermissionsUsmBatchReport,
    AdvancedPermissionsUsmBatchOverriddenFee,
    AdvancedPermissionsUsmBatchOverriddenRole,
    AdvancedPermissionsUsmBatchFeeByRoleHash
} from "@alto/deployments/ethereum-mainnet/AdvancedPermissionsUsmBatch.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {MarketUpgradeBatch, MarketUpgradeBatchReport} from "@alto/deployments/ethereum-mainnet/MarketUpgradeBatch.sol";
import {
    MintCurveConvexPositionFactoryBatch,
    MintCurveConvexPositionFactoryBatchParams,
    MintCurveConvexPositionFactoryBatchReport
} from "@alto/deployments/ethereum-mainnet/MintCurveConvexPositionFactoryBatch.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
    CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
    CONVEX_BOOSTER_MAINNET,
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {UsmBatch, UsmBatchParams, UsmBatchReport} from "@alto/deployments/ethereum-mainnet/UsmBatch.sol";
import {VaultBatch, VaultBatchParams, VaultBatchReport} from "@alto/deployments/ethereum-mainnet/VaultBatch.sol";
import {IMarketRegistry, MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {IUsmRegistry, UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";
import {
    MarketContracts,
    UsmContracts,
    DeploymentPhase,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeployCoreParams,
    DeployDUSDParams,
    DeployMintMarketParams,
    DeployBorrowMarketParams,
    DeployUsmParams,
    UsmFinalizeMode,
    AdvancedPermissionsUsmContracts,
    MintCurveConvexPositionContracts,
    Contracts
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {DirectionAccess} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

library DeployAltoEthereumMainnet {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deploy(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        if (params.phase == DeploymentPhase.CORE) {
            DeployCoreParams memory coreParams =
                DeployCoreParams({owner: params.deployer, bundler3: BUNDLER3_MAINNET, wNative: WETH_MAINNET});
            input = _deployCore(coreParams, params, input);
        } else if (params.phase == DeploymentPhase.REGISTRY) {
            input = _deployRegistries(params, input);
        } else if (params.phase == DeploymentPhase.DUSD) {
            input = _deployDUSD(
                DeployDUSDParams({
                    owner: input.contracts.timelock,
                    lzEndpoint: LAYERZERO_ENDPOINT_MAINNET,
                    feeRecipient: input.contracts.feeRecipient
                }),
                params,
                input
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_WETH) {
            input.contracts.wethMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: WETH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.WETH,
                    irmInterestRate: 0.02 ether / uint256(365 days), // 2%
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 500_000 ether,
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.05 ether, // 5%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_WSTETH) {
            input.contracts.wstethMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: WSTETH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.stETH,
                    irmInterestRate: 0.025 ether / uint256(365 days), // 2.5%
                    maxLtv: 0.78 ether, // 78%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 500_000 ether, // 500,000 DUSD
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.83 ether, // 83%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.91 ether, // 91%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.06 ether, // 6%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_RETH) {
            input.contracts.rethMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: RETH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.rETH,
                    irmInterestRate: 0.025 ether / uint256(365 days), // 2.5%
                    maxLtv: 0.7 ether, // 70%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 200_000 ether, // 200,000 DUSD
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.75 ether, // 75%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.83 ether, // 83%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_METH) {
            input.contracts.methMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: METH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.METH,
                    irmInterestRate: 0.025 ether / uint256(365 days), // 2.5%
                    maxLtv: 0.65 ether, // 65%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 200_000 ether, // 200,000 DUSD
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.72 ether, // 72%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.8 ether, // 80%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.075 ether, // 7.5%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_TBTC) {
            input.contracts.tbtcMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: TBTC_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.tBTC,
                    irmInterestRate: 0.025 ether / uint256(365 days), // 2.5%
                    maxLtv: 0.7 ether, // 70%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 200_000 ether, // 200,000 DUSD
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.77 ether, // 77%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.85 ether, // 85%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.BORROW_MARKET_WBTC) {
            input.contracts.wbtcBorrowMarket = _deployBorrowMarket(
                DeployBorrowMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: WBTC_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.WBTC,
                    irmConfig: AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                        curveSteepness: 4 ether,
                        adjustmentSpeed: 50 ether / int256(365 days),
                        targetUtilization: 0.9 ether, // 90%
                        initialRateAtTarget: 0.1 ether / int256(365 days), // 10%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.75 ether, // 75%
                    initialBorrowOpeningFee: 0.002 ether, // 0.2%
                    supplyCapAssets: 0,
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether, // 80%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.88 ether, // 88%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.BORROW_MARKET_CBBTC) {
            input.contracts.cbbtcBorrowMarket = _deployBorrowMarket(
                DeployBorrowMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: CBBTC_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.cbBTC,
                    irmConfig: AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                        curveSteepness: 4 ether,
                        adjustmentSpeed: 50 ether / int256(365 days),
                        targetUtilization: 0.9 ether, // 90%
                        initialRateAtTarget: 0.1 ether / int256(365 days), // 10%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.75 ether, // 75%
                    initialBorrowOpeningFee: 0.002 ether, // 0.2%
                    supplyCapAssets: 0,
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether, // 80%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.88 ether, // 88%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false, // priority liquidation is not enabled
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.BORROW_MARKET_SUSDE) {
            input.contracts.susdeBorrowMarket = _deployBorrowMarket(
                DeployBorrowMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: SUSDE_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.SUSDE,
                    irmConfig: AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                        curveSteepness: 4 ether,
                        adjustmentSpeed: 50 ether / int256(365 days),
                        targetUtilization: 0.9 ether, // 90%
                        initialRateAtTarget: 0.1 ether / int256(365 days), // 10%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0.002 ether, // 0.2%
                    supplyCapAssets: 0,
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.005 ether, // 0.5%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.06 ether, // 6%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false, // priority liquidation is not enabled
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.PERMISSIONED_USM) {
            input.contracts.permissionedUsm = _deployUsm(
                DeployUsmParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    freezer: params.freezer,
                    buyFee: 0,
                    sellFee: 0,
                    exposureCap: 5_000_000_000 * 10 ** 6, // 5,000,000,000 USDC
                    underlyingAsset: USDC_MAINNET,
                    isPermissioned: true,
                    treasuryMultisig: params.treasuryMultisig,
                    finalizeMode: UsmFinalizeMode.DIRECT,
                    safeBatchName: ""
                }),
                input
            );
        } else if (params.phase == DeploymentPhase.PERMISSIONLESS_USM) {
            input.contracts.permissionlessUsm = _deployUsm(
                DeployUsmParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    freezer: params.freezer,
                    buyFee: 20, // 0.2%
                    sellFee: 20, // 0.2%
                    exposureCap: 5_000_000 * 10 ** 6, // 5,000,000 USDC
                    underlyingAsset: USDC_MAINNET,
                    isPermissioned: false,
                    treasuryMultisig: params.treasuryMultisig,
                    finalizeMode: UsmFinalizeMode.DIRECT,
                    safeBatchName: ""
                }),
                input
            );
        } else if (params.phase == DeploymentPhase.POST) {
            input = _deployPost(params, input);
        } else if (params.phase == DeploymentPhase.REFERRAL_ADAPTER) {
            input = _deployReferralAdapter(params, input);
        } else if (params.phase == DeploymentPhase.BORROW_MARKET_SYRUP_USDC) {
            input.contracts.syrupUsdcBorrowMarket = _deployBorrowMarket(
                DeployBorrowMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: SYRUPUSDC_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.SYRUPUSDC,
                    irmConfig: AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                        curveSteepness: 4 ether,
                        adjustmentSpeed: 50 ether / int256(365 days),
                        targetUtilization: 0.9 ether, // 90%
                        initialRateAtTarget: 0.1 ether / int256(365 days), // 10%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0.002 ether, // 0.2%
                    supplyCapAssets: 0,
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.06 ether, // 6%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.BORROW_MARKET_PAXG) {
            input.contracts.paxgBorrowMarket = _deployBorrowMarket(
                DeployBorrowMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: PAXG_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.PAXG,
                    irmConfig: AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                        curveSteepness: 2 ether,
                        adjustmentSpeed: 25 ether / int256(365 days),
                        targetUtilization: 0.9 ether, // 90%
                        initialRateAtTarget: 0.04 ether / int256(365 days), // 4%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.75 ether, // 75%
                    initialBorrowOpeningFee: 0.002 ether, // 0.2%
                    supplyCapAssets: 0,
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether, // 80%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.05 ether, // 5%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_SUSDE) {
            input.contracts.susdeMintMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: SUSDE_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.SUSDE,
                    irmInterestRate: 0.015 ether / uint256(365 days), // 1.5%
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 250_000 ether, // 250,000 DUSD
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.005 ether, // 0.5%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.04 ether, // 4%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_SYRUPUSDC) {
            input.contracts.syrupUsdcMintMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipientMintMarkets,
                    collateralToken: SYRUPUSDC_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.SYRUPUSDC,
                    irmInterestRate: 0.03 ether / uint256(365 days), // 3%
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0.0005 ether, // 0.05%
                    debtCeiling: 250_000 ether, // 250,000 DUSD
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.005 ether, // 0.5%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.04 ether, // 4%
                        minPenaltyPercentage: 0.005 ether, // 0.5%
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer,
                    validSwapTargets: _validSwapTargets()
                }),
                input,
                params,
                params.useUnsafeUpgrades,
                params.deployerHasOwnership
            );
        } else if (params.phase == DeploymentPhase.DUSD_VAULT) {
            input = _deployDusdVault(params, input);
        } else if (params.phase == DeploymentPhase.VAULT_REGISTRY) {
            input = _deployVaultRegistry(params, input);
        } else if (params.phase == DeploymentPhase.PERMISSIONED_FRXUSD_USM) {
            input.contracts.permissionedFrxusdUsm = _deployUsm(
                DeployUsmParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    freezer: params.freezer,
                    buyFee: 0,
                    sellFee: 0,
                    exposureCap: 5_000_000_000 ether, // 5,000,000,000 frxUSD (18 decimals)
                    underlyingAsset: FRXUSD_MAINNET,
                    isPermissioned: true,
                    treasuryMultisig: params.treasuryMultisig,
                    finalizeMode: UsmFinalizeMode.TIMELOCK_BATCH,
                    safeBatchName: "frxusd-permissioned-usm-registry"
                }),
                input
            );
        } else if (params.phase == DeploymentPhase.PERMISSIONLESS_FRXUSD_USM) {
            input.contracts.permissionlessFrxusdUsm = _deployUsm(
                DeployUsmParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    freezer: params.freezer,
                    buyFee: 5, // 0.05%
                    sellFee: 5, // 0.05%
                    exposureCap: 500_000 ether, // 500,000 frxUSD (18 decimals)
                    underlyingAsset: FRXUSD_MAINNET,
                    isPermissioned: false,
                    treasuryMultisig: params.treasuryMultisig,
                    finalizeMode: UsmFinalizeMode.TIMELOCK_BATCH,
                    safeBatchName: "frxusd-permissionless-usm-registry"
                }),
                input
            );
        } else if (params.phase == DeploymentPhase.ADAPTER) {
            DeployCoreParams memory adapterCoreParams =
                DeployCoreParams({owner: params.deployer, bundler3: BUNDLER3_MAINNET, wNative: WETH_MAINNET});
            input.contracts.altoAdapter = _deployAdapterAndApproval(adapterCoreParams, params, input);
        } else if (params.phase == DeploymentPhase.ALTO_LEVERAGE_SWAPPER_MULTI_TARGET) {
            input = _deployLeverageSwapperMultiTarget(input);
        } else if (params.phase == DeploymentPhase.LIQUIDATION_PERIPHERY) {
            input = _deployLiquidationPeriphery(params, input);
        } else if (params.phase == DeploymentPhase.ADVANCED_PERMISSIONS_FRXUSD_USM) {
            input = _deployAdvancedPermissionsFrxUsdUsm(params, input);
        } else if (params.phase == DeploymentPhase.UPGRADE_MARKETS_LIQUIDATION_PERIPHERY) {
            input = _upgradeMarketsForLiquidationPeriphery(input);
        } else if (params.phase == DeploymentPhase.UNIVERSAL_REWARDS_DISTRIBUTOR) {
            input = _deployUniversalRewardsDistributor(params, input);
        } else if (params.phase == DeploymentPhase.MINT_CURVE_CONVEX_POSITION) {
            input = _deployMintCurveConvexPositionFactory(input);
        } else {
            revert("Invalid phase");
        }

        return input;
    }

    function _deployCore(
        DeployCoreParams memory coreParams,
        AltoEthereumMainnetParams memory params,
        AltoEthereumMainnetInput memory input
    ) internal returns (AltoEthereumMainnetInput memory) {
        // Deploy TimelockController with deployer and multicall addresses as proposers/executors initially
        // Admin will be transferred to multisig in POST phase
        address[] memory multicallAddresses = getMulticallOwnerAddresses();
        address[] memory proposers = new address[](1 + multicallAddresses.length);
        proposers[0] = params.deployer;
        for (uint256 i = 0; i < multicallAddresses.length; i++) {
            proposers[i + 1] = multicallAddresses[i];
        }
        address[] memory executors = new address[](1 + multicallAddresses.length);
        executors[0] = params.deployer;
        for (uint256 i = 0; i < multicallAddresses.length; i++) {
            executors[i + 1] = multicallAddresses[i];
        }
        input.contracts.timelock = address(new AltoTimelockController(0, proposers, executors, params.deployer));

        address[] memory feeRecipientRoleHolders = new address[](1);
        feeRecipientRoleHolders[0] = params.timelockAdmin;

        // Deploy fee collector with timelock admin as owner, proposer, executor and canceller
        input.contracts.feeRecipient = address(
            new AltoTimelockController(
                params.timelockDelay, feeRecipientRoleHolders, feeRecipientRoleHolders, params.timelockAdmin
            )
        );

        // Deploy timelock controller for mint market fee recipients
        input.contracts.feeRecipientMintMarkets = address(
            new AltoTimelockControllerMintMarketFee(
                params.timelockDelay, feeRecipientRoleHolders, feeRecipientRoleHolders, params.timelockAdmin
            )
        );

        // Deploy AltoAdapter with Morpho's Bundler3, WETH, and deployer as owner
        // Owner will be transferred to timelock in POST phase (needed to authorize contracts during deployment)
        input.contracts.altoAdapter = address(new AltoAdapter(coreParams.bundler3, coreParams.wNative, params.deployer));

        return input;
    }

    function _deployRegistries(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        input.contracts.marketRegistry = address(new MarketRegistry(params.deployer));
        input.contracts.usmRegistry = address(new UsmRegistry(params.deployer));
        return input;
    }

    /// @dev Deploys VaultRegistry with the deployer as initial owner, registers any already-deployed
    ///      vaults from `input.contracts`, and transfers ownership to the timelock.
    function _deployVaultRegistry(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(input.contracts.timelock != address(0), "Timelock not deployed");

        VaultRegistry registry = new VaultRegistry(params.deployer);

        if (input.contracts.dusdVault != address(0)) {
            registry.addVault(input.contracts.dusdVault);
        }

        registry.transferOwnershipSkip2Step(input.contracts.timelock);

        input.contracts.vaultRegistry = address(registry);

        return input;
    }

    function _deployDUSD(
        DeployDUSDParams memory dusdParams,
        AltoEthereumMainnetParams memory params,
        AltoEthereumMainnetInput memory input
    ) internal returns (AltoEthereumMainnetInput memory) {
        // Deploy DUSD batch - deploys DUSD and DUSDFlashMinter in single constructor
        DUSDBatch batch = new DUSDBatch(
            DUSDBatchParams({
                timelock: input.contracts.timelock,
                lzEndpoint: dusdParams.lzEndpoint,
                treasury: dusdParams.feeRecipient,
                flashFee: FlashFee({minFlashFee: 0, maxFlashFee: 0}),
                flashMintCeiling: 500_000 ether,
                deployer: params.deployer,
                freezer: params.freezer
            })
        );
        DUSDBatchReport memory report = batch.getReport();

        input.contracts.dusd = report.dusd;
        input.contracts.dusdFlashMinter = report.dusdFlashMinter;

        return input;
    }

    function _deployMintMarket(
        DeployMintMarketParams memory marketParams,
        AltoEthereumMainnetInput memory input,
        AltoEthereumMainnetParams memory params,
        bool useUnsafeUpgrades,
        bool deployerHasOwnership
    ) internal returns (MarketContracts memory) {
        uint256 minterCeiling = marketParams.debtCeiling * 1.05 ether / marketParams.liquidationConfig.maxLiquidationLtv;
        MarketContracts memory report = MintMarketBatch.deploy(
            MintMarketBatchParams({
                owner: marketParams.owner,
                deployer: params.deployer,
                dusd: marketParams.dusd,
                altoAdapter: marketParams.altoAdapter,
                feeRecipient: marketParams.feeRecipient,
                collateralToken: marketParams.collateralToken,
                oracleAsset: marketParams.oracleAsset,
                irmInterestRate: marketParams.irmInterestRate,
                maxLtv: marketParams.maxLtv,
                initialBorrowOpeningFee: marketParams.initialBorrowOpeningFee,
                debtCeiling: marketParams.debtCeiling,
                liquidationConfig: marketParams.liquidationConfig,
                minterCeiling: minterCeiling,
                validSwapTargets: marketParams.validSwapTargets,
                freezer: marketParams.freezer,
                useUnsafeUpgrades: useUnsafeUpgrades
            })
        );

        if (deployerHasOwnership) {
            IDUSD(marketParams.dusd).setMinterStatus(report.market, true);
            IDUSD(marketParams.dusd).setMinterCeiling(report.market, minterCeiling);
            IDUSD(marketParams.dusd).setBurnerStatus(report.market, true);

            IMarketRegistry(input.contracts.marketRegistry).addMintMarket(report.market);
            AltoAdapter(payable(marketParams.altoAdapter)).approveContract(report.market);
        } else {
            address timelock = input.contracts.timelock;
            uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

            address[] memory targets = new address[](5);
            uint256[] memory values = new uint256[](5);
            bytes[] memory payloads = new bytes[](5);

            targets[0] = marketParams.dusd;
            values[0] = 0;
            payloads[0] = abi.encodeCall(IDUSD.setMinterStatus, (report.market, true));

            targets[1] = marketParams.dusd;
            values[1] = 0;
            payloads[1] = abi.encodeCall(IDUSD.setMinterCeiling, (report.market, minterCeiling));

            targets[2] = marketParams.dusd;
            values[2] = 0;
            payloads[2] = abi.encodeCall(IDUSD.setBurnerStatus, (report.market, true));

            targets[3] = input.contracts.marketRegistry;
            values[3] = 0;
            payloads[3] = abi.encodeCall(IMarketRegistry.addMintMarket, (report.market));

            targets[4] = marketParams.altoAdapter;
            values[4] = 0;
            payloads[4] = abi.encodeCall(AdapterContractApproval.approveContract, (report.market));

            _writeSafeTimelockBatchJson("mint-market-registry", timelock, targets, values, payloads, minDelay);
        }

        return report;
    }

    function _deployBorrowMarket(
        DeployBorrowMarketParams memory marketParams,
        AltoEthereumMainnetInput memory input,
        AltoEthereumMainnetParams memory params,
        bool useUnsafeUpgrades,
        bool deployerHasOwnership
    ) internal returns (MarketContracts memory) {
        // Deploy batch - deploys all market components in single constructor (including Oracle and IRM)
        MarketContracts memory report = BorrowMarketBatch.deploy(
            BorrowMarketBatchParams({
                owner: marketParams.owner,
                deployer: params.deployer,
                dusd: marketParams.dusd,
                altoAdapter: marketParams.altoAdapter,
                feeRecipient: marketParams.feeRecipient,
                collateralToken: marketParams.collateralToken,
                oracleAsset: marketParams.oracleAsset,
                irmConfig: marketParams.irmConfig,
                maxLtv: marketParams.maxLtv,
                initialBorrowOpeningFee: marketParams.initialBorrowOpeningFee,
                supplyCapAssets: marketParams.supplyCapAssets,
                liquidationConfig: marketParams.liquidationConfig,
                validSwapTargets: marketParams.validSwapTargets,
                freezer: marketParams.freezer,
                useUnsafeUpgrades: useUnsafeUpgrades
            })
        );

        if (deployerHasOwnership) {
            // Execute directly when deployer has ownership
            IMarketRegistry(input.contracts.marketRegistry).addBorrowMarket(report.market);
            AltoAdapter(payable(marketParams.altoAdapter)).approveContract(report.market);
        } else {
            // Log timelock batch transaction data for multisig submission
            // Multisig must call timelock.scheduleBatch() then timelock.executeBatch() after delay
            address timelock = input.contracts.timelock;
            uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory payloads = new bytes[](2);

            // Transaction 1: Add borrow market to registry
            targets[0] = input.contracts.marketRegistry;
            values[0] = 0;
            payloads[0] = abi.encodeCall(IMarketRegistry.addBorrowMarket, (report.market));

            // Transaction 2: Approve market on AltoAdapter
            targets[1] = marketParams.altoAdapter;
            values[1] = 0;
            payloads[1] = abi.encodeCall(AdapterContractApproval.approveContract, (report.market));

            _writeSafeTimelockBatchJson("borrow-market-registry", timelock, targets, values, payloads, minDelay);
        }

        return report;
    }

    function _deployUsm(DeployUsmParams memory usmParams, AltoEthereumMainnetInput memory input)
        internal
        returns (UsmContracts memory)
    {
        require(usmParams.freezer != address(0), "Freezer must be set");

        UsmBatch batch = new UsmBatch(
            UsmBatchParams({
                owner: usmParams.owner,
                dusd: usmParams.dusd,
                altoAdapter: usmParams.altoAdapter,
                feeRecipient: usmParams.feeRecipient,
                buyFee: usmParams.buyFee,
                sellFee: usmParams.sellFee,
                exposureCap: usmParams.exposureCap,
                freezer: usmParams.freezer,
                underlyingAsset: usmParams.underlyingAsset,
                priceRatio: 1 ether,
                isPermissioned: usmParams.isPermissioned,
                treasuryMultisig: usmParams.treasuryMultisig
            })
        );
        UsmBatchReport memory report = batch.getReport();

        uint256 mintCeiling = _getUsmMintCeiling(usmParams);

        if (usmParams.finalizeMode == UsmFinalizeMode.DIRECT) {
            _finalizeUsmDirect(usmParams, input, report.dusdUsm, mintCeiling);
        } else if (usmParams.finalizeMode == UsmFinalizeMode.TIMELOCK_BATCH) {
            _finalizeUsmViaTimelockBatch(usmParams, input, report.dusdUsm, mintCeiling);
        } else {
            revert("Invalid USM finalize mode");
        }

        return UsmContracts({
            dusdUsm: report.dusdUsm,
            dusdUsmImplementation: report.dusdUsmImplementation,
            fixedPriceStrategy: report.fixedPriceStrategy,
            fixedFeeStrategy: report.fixedFeeStrategy
        });
    }

    function _getUsmMintCeiling(DeployUsmParams memory usmParams) internal view returns (uint256) {
        uint8 underlyingDecimals = IERC20Metadata(usmParams.underlyingAsset).decimals();
        uint256 exposureCap = usmParams.exposureCap;

        if (exposureCap == 0) {
            exposureCap = 5_000_000_000 * 10 ** underlyingDecimals;
        }

        if (underlyingDecimals < 18) {
            return exposureCap * 10 ** (18 - underlyingDecimals);
        }
        if (underlyingDecimals > 18) {
            return exposureCap / 10 ** (underlyingDecimals - 18);
        }

        return exposureCap;
    }

    function _finalizeUsmDirect(
        DeployUsmParams memory usmParams,
        AltoEthereumMainnetInput memory input,
        address usm,
        uint256 mintCeiling
    ) internal {
        IDUSD(usmParams.dusd).setMinterStatus(usm, true);
        IDUSD(usmParams.dusd).setMinterCeiling(usm, mintCeiling);
        IDUSD(usmParams.dusd).setBurnerStatus(usm, true);

        IUsmRegistry(input.contracts.usmRegistry).addUsm(usm);

        // Approve USM on AltoAdapter (requires adapter ownership)
        if (!usmParams.isPermissioned) {
            AltoAdapter(payable(usmParams.altoAdapter)).approveContract(usm);
        }
    }

    function _finalizeUsmViaTimelockBatch(
        DeployUsmParams memory usmParams,
        AltoEthereumMainnetInput memory input,
        address usm,
        uint256 mintCeiling
    ) internal {
        require(bytes(usmParams.safeBatchName).length > 0, "Safe batch name must be set");

        address timelock = input.contracts.timelock;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

        uint256 actionCount = usmParams.isPermissioned ? 4 : 5;
        address[] memory targets = new address[](actionCount);
        uint256[] memory values = new uint256[](actionCount);
        bytes[] memory payloads = new bytes[](actionCount);

        targets[0] = usmParams.dusd;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IDUSD.setMinterStatus, (usm, true));

        targets[1] = usmParams.dusd;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterCeiling, (usm, mintCeiling));

        targets[2] = usmParams.dusd;
        values[2] = 0;
        payloads[2] = abi.encodeCall(IDUSD.setBurnerStatus, (usm, true));

        targets[3] = input.contracts.usmRegistry;
        values[3] = 0;
        payloads[3] = abi.encodeCall(IUsmRegistry.addUsm, (usm));

        if (!usmParams.isPermissioned) {
            targets[4] = usmParams.altoAdapter;
            values[4] = 0;
            payloads[4] = abi.encodeCall(AdapterContractApproval.approveContract, (usm));
        }

        _writeSafeTimelockBatchJson(usmParams.safeBatchName, timelock, targets, values, payloads, minDelay);
    }

    /// @dev Deploys the Alto DUSD Vault and emits a Safe TX bundle for the multisig to
    ///      approve the vault on AltoAdapter via the timelock.
    function _deployDusdVault(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(params.freezer != address(0), "Freezer must be set");
        require(params.timelockAdmin != address(0), "TimelockAdmin must be set");
        require(params.treasuryMultisig != address(0), "TreasuryMultisig must be set");
        require(input.contracts.dusd != address(0), "DUSD not deployed");
        require(input.contracts.timelock != address(0), "Timelock not deployed");
        require(input.contracts.altoAdapter != address(0), "AltoAdapter not deployed");
        require(input.contracts.marketRegistry != address(0), "MarketRegistry not deployed");
        require(input.contracts.feeRecipient != address(0), "FeeRecipient not deployed");

        address[] memory markets = new address[](5);
        markets[0] = input.contracts.syrupUsdcBorrowMarket.market;
        markets[1] = input.contracts.susdeBorrowMarket.market;
        markets[2] = input.contracts.paxgBorrowMarket.market;
        markets[3] = input.contracts.wbtcBorrowMarket.market;
        markets[4] = input.contracts.cbbtcBorrowMarket.market;

        uint256[] memory caps = new uint256[](5);
        caps[0] = 62_000 ether;
        caps[1] = 62_000 ether;
        caps[2] = 62_000 ether;
        caps[3] = 10_000 ether;
        caps[4] = 10_000 ether;

        // supplyQueue == markets ordering already (syrupUSDC -> sUSDe -> PAXG -> WBTC -> cbBTC)
        address[] memory supplyQueue = new address[](5);
        for (uint256 i; i < 5; ++i) {
            require(markets[i] != address(0), "Borrow market not deployed");
            supplyQueue[i] = markets[i];
        }

        VaultBatch batch = new VaultBatch(
            VaultBatchParams({
                timelock: input.contracts.timelock,
                dusd: input.contracts.dusd,
                marketRegistry: input.contracts.marketRegistry,
                curator: params.timelockAdmin,
                allocator: params.updater,
                guardian: params.freezer,
                skimRecipient: params.treasuryMultisig,
                feeRecipient: input.contracts.feeRecipient,
                fee: 0,
                markets: markets,
                caps: caps,
                supplyQueue: supplyQueue,
                finalTimelock: 1 days
            })
        );
        VaultBatchReport memory report = batch.getReport();

        address vault = report.vault;

        // Log Safe TX bundle for the multisig: timelock executes adapter approval.
        address timelock = input.contracts.timelock;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

        uint256 actionCount = 1;
        address[] memory targets = new address[](actionCount);
        uint256[] memory values = new uint256[](actionCount);
        bytes[] memory payloads = new bytes[](actionCount);

        targets[0] = input.contracts.altoAdapter;
        values[0] = 0;
        payloads[0] = abi.encodeCall(AdapterContractApproval.approveContract, (vault));

        _writeSafeTimelockBatchJson("dusd-vault-adapter-approval", timelock, targets, values, payloads, minDelay);

        input.contracts.dusdVault = vault;

        return input;
    }

    function _deployReferralAdapter(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(params.updater != address(0), "Updater must be set");

        // Deploy AltoReferralWhitelistAdapter with 5% bonusDiscount and 5% paymentTokenShare
        // owner at this point is deployer
        AltoReferralWhitelistAdapter adapter = new AltoReferralWhitelistAdapter(
            0.05 ether, // 5% bonusDiscount
            0.05 ether // 5% paymentTokenShare
        );

        // Set the merkle root updater
        adapter.setMerkleRootUpdater(params.updater, true);

        // Transfer ownership from deployer to timelock
        adapter.transferOwnershipSkip2Step(input.contracts.timelock);

        input.contracts.referralAdapter = address(adapter);

        return input;
    }

    function _deployAdapterAndApproval(
        DeployCoreParams memory coreParams,
        AltoEthereumMainnetParams memory params,
        AltoEthereumMainnetInput memory input
    ) internal returns (address) {
        AltoAdapter adapter = new AltoAdapter(coreParams.bundler3, coreParams.wNative, params.deployer);

        adapter.approveContract(input.contracts.wethMarket.market);
        adapter.approveContract(input.contracts.wstethMarket.market);
        adapter.approveContract(input.contracts.rethMarket.market);
        adapter.approveContract(input.contracts.methMarket.market);
        adapter.approveContract(input.contracts.tbtcMarket.market);
        adapter.approveContract(input.contracts.wbtcBorrowMarket.market);
        adapter.approveContract(input.contracts.cbbtcBorrowMarket.market);
        adapter.approveContract(input.contracts.susdeBorrowMarket.market);
        adapter.approveContract(input.contracts.syrupUsdcBorrowMarket.market);
        adapter.approveContract(input.contracts.paxgBorrowMarket.market);
        adapter.approveContract(input.contracts.susdeMintMarket.market);
        adapter.approveContract(input.contracts.syrupUsdcMintMarket.market);
        adapter.approveContract(input.contracts.permissionlessUsm.dusdUsm);

        AltoOwnable2Step(address(adapter)).transferOwnershipSkip2Step(input.contracts.timelock);

        return address(adapter);
    }

    function _transferOwnershipToTimelock(Contracts memory contracts, address timelock) internal {
        // Transfer ownership from DUSD, MarketRegistry, UsmRegistry, and AltoAdapter (which were deployed with deployer as owner)
        // DUSDFlashMinter already has timelock as owner from DUSDBatch deployment
        AltoOwnable2Step(contracts.altoAdapter).transferOwnershipSkip2Step(timelock);
        AltoOwnable2Step(contracts.dusd).transferOwnershipSkip2Step(timelock);
        AltoOwnable2Step(contracts.marketRegistry).transferOwnershipSkip2Step(timelock);
        AltoOwnable2Step(contracts.usmRegistry).transferOwnershipSkip2Step(timelock);
        // All other contracts already have timelock as owner
    }

    function _updateTimelockDelay(address timelock, uint256 delay) internal {
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, delay);
        TimelockController(payable(timelock)).schedule(timelock, 0, updateDelayData, bytes32(0), bytes32(0), 0);
        TimelockController(payable(timelock)).execute(timelock, 0, updateDelayData, bytes32(0), bytes32(0));
    }

    function _grantTimelockRolesToTimelockAdmin(address timelock, AltoEthereumMainnetParams memory params) internal {
        require(params.timelockAdmin != address(0), "TimelockAdmin must be set");
        AltoTimelockController timelockContract = AltoTimelockController(payable(timelock));

        bytes32[] memory roles = new bytes32[](4);
        roles[0] = timelockContract.PROPOSER_ROLE();
        roles[1] = timelockContract.EXECUTOR_ROLE();
        roles[2] = timelockContract.CANCELLER_ROLE();
        roles[3] = timelockContract.DEFAULT_ADMIN_ROLE();

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);

        for (uint256 i = 0; i < 4; i++) {
            targets[i] = address(timelockContract);
            values[i] = 0;
            payloads[i] = abi.encodeWithSelector(AccessControl.grantRole.selector, roles[i], params.timelockAdmin);
        }

        timelockContract.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), 0);
        timelockContract.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));
    }

    function _revokeTimelockRolesFromMulticall(address timelock) internal {
        AltoTimelockController timelockContract = AltoTimelockController(payable(timelock));
        address[] memory owners = getMulticallOwnerAddresses();

        bytes32[] memory roles = new bytes32[](4);
        roles[0] = timelockContract.PROPOSER_ROLE();
        roles[1] = timelockContract.EXECUTOR_ROLE();
        roles[2] = timelockContract.CANCELLER_ROLE();
        roles[3] = timelockContract.DEFAULT_ADMIN_ROLE();

        address[] memory targets = new address[](4 * owners.length);
        uint256[] memory values = new uint256[](4 * owners.length);
        bytes[] memory payloads = new bytes[](4 * owners.length);

        for (uint256 i = 0; i < owners.length; i++) {
            for (uint256 j = 0; j < 4; j++) {
                uint256 idx = 4 * i + j;
                targets[idx] = address(timelockContract);
                values[idx] = 0;
                payloads[idx] = abi.encodeWithSelector(AccessControl.revokeRole.selector, roles[j], owners[i]);
            }
        }

        timelockContract.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), 0);
        timelockContract.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));
    }

    function _revokeTimelockRolesFromDeployer(address timelock, AltoEthereumMainnetParams memory params) internal {
        AltoTimelockController timelockContract = AltoTimelockController(payable(timelock));

        bytes32[] memory roles = new bytes32[](4);
        roles[0] = timelockContract.PROPOSER_ROLE();
        roles[1] = timelockContract.EXECUTOR_ROLE();
        roles[2] = timelockContract.CANCELLER_ROLE();
        roles[3] = timelockContract.DEFAULT_ADMIN_ROLE();

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);

        for (uint256 i = 0; i < 4; i++) {
            targets[i] = address(timelockContract);
            values[i] = 0;
            payloads[i] = abi.encodeWithSelector(AccessControl.revokeRole.selector, roles[i], params.deployer);
        }

        // Note: executeBatch is not called here because it requires waiting for the delay
        timelockContract.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), params.timelockDelay);
    }

    /// @dev Writes Safe Transaction Builder JSON files for a timelock batch transaction
    /// @param name Identifier for the output files (e.g. "borrow-market-registry")
    /// @param timelock The timelock controller address
    /// @param targets Array of target contract addresses
    /// @param values Array of ETH values (typically all zeros)
    /// @param payloads Array of calldata for each target
    /// @param delay The timelock delay (use timelock.getMinDelay())
    function _writeSafeTimelockBatchJson(
        string memory name,
        address timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal {
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        string memory outputDir = "contracts/deployments/ethereum-mainnet/output";

        vm.writeFile(
            string.concat(outputDir, "/safe-tx-", name, "-schedule.json"),
            _buildSafeJson(string.concat(name, " - Schedule"), timelock, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(outputDir, "/safe-tx-", name, "-execute.json"),
            _buildSafeJson(string.concat(name, " - Execute"), timelock, executeBatchData)
        );

        console.log("Safe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json  (propose)", name);
        console.log("  2. safe-tx-%s-execute.json   (execute after delay)", name);
    }

    function _buildSafeJson(string memory name, address to, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '"},"transactions":[{"to":"',
            vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data),
            '"}]}'
        );
    }

    /// @dev Deploys one AltoLeverageSwapperMultiTarget per market leverage contract and logs timelock
    ///      batch transactions to call setSwapper on each AltoLeverage.
    function _deployLeverageSwapperMultiTarget(AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(input.contracts.timelock != address(0), "Timelock not deployed");

        address[] memory leverageContracts = new address[](12);
        leverageContracts[0] = input.contracts.wethMarket.leverage;
        leverageContracts[1] = input.contracts.wstethMarket.leverage;
        leverageContracts[2] = input.contracts.rethMarket.leverage;
        leverageContracts[3] = input.contracts.methMarket.leverage;
        leverageContracts[4] = input.contracts.tbtcMarket.leverage;
        leverageContracts[5] = input.contracts.wbtcBorrowMarket.leverage;
        leverageContracts[6] = input.contracts.cbbtcBorrowMarket.leverage;
        leverageContracts[7] = input.contracts.susdeBorrowMarket.leverage;
        leverageContracts[8] = input.contracts.syrupUsdcBorrowMarket.leverage;
        leverageContracts[9] = input.contracts.paxgBorrowMarket.leverage;
        leverageContracts[10] = input.contracts.susdeMintMarket.leverage;
        leverageContracts[11] = input.contracts.syrupUsdcMintMarket.leverage;

        address[] memory validSwapTargets = _validSwapTargets();

        LeverageSwapperMultiTargetBatch batch = new LeverageSwapperMultiTargetBatch(
            LeverageSwapperMultiTargetBatchParams({
                owner: input.contracts.timelock,
                leverageContracts: leverageContracts,
                validSwapTargets: validSwapTargets
            })
        );

        address[] memory deployedSwappers = batch.getSwappers();

        input.contracts.wethMarket.leverageSwapper = deployedSwappers[0];
        input.contracts.wstethMarket.leverageSwapper = deployedSwappers[1];
        input.contracts.rethMarket.leverageSwapper = deployedSwappers[2];
        input.contracts.methMarket.leverageSwapper = deployedSwappers[3];
        input.contracts.tbtcMarket.leverageSwapper = deployedSwappers[4];
        input.contracts.wbtcBorrowMarket.leverageSwapper = deployedSwappers[5];
        input.contracts.cbbtcBorrowMarket.leverageSwapper = deployedSwappers[6];
        input.contracts.susdeBorrowMarket.leverageSwapper = deployedSwappers[7];
        input.contracts.syrupUsdcBorrowMarket.leverageSwapper = deployedSwappers[8];
        input.contracts.paxgBorrowMarket.leverageSwapper = deployedSwappers[9];
        input.contracts.susdeMintMarket.leverageSwapper = deployedSwappers[10];
        input.contracts.syrupUsdcMintMarket.leverageSwapper = deployedSwappers[11];

        _logSetSwapperTimelockBatch(input, leverageContracts, deployedSwappers);

        return input;
    }

    function _validSwapTargets() internal pure returns (address[] memory validSwapTargets) {
        validSwapTargets = new address[](5);
        validSwapTargets[0] = ZEROX_SWAP_TARGET_MAINNET;
        validSwapTargets[1] = ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET;
        validSwapTargets[2] = KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET;
        validSwapTargets[3] = VELORA_AUGUSTUS_MAINNET;
        validSwapTargets[4] = NORDSTERN_ROUTER_MAINNET;
    }

    /// @dev Logs Safe TX JSON files for timelock batch setSwapper calls on each AltoLeverage contract.
    function _logSetSwapperTimelockBatch(
        AltoEthereumMainnetInput memory input,
        address[] memory leverageContracts,
        address[] memory swappers
    ) internal {
        require(leverageContracts.length == swappers.length, "Leverage/swapper length mismatch");

        address timelock = input.contracts.timelock;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();
        uint256 count = leverageContracts.length;

        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory payloads = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            targets[i] = leverageContracts[i];
            values[i] = 0;
            payloads[i] = abi.encodeCall(AltoLeverage.setSwapper, (IAltoLeverageSwapper(swappers[i])));
        }

        _writeSafeTimelockBatchJson("leverage-swapper-set-swapper", timelock, targets, values, payloads, minDelay);
    }

    /// @dev Deploys LiquidationPeriphery and registers all 12 markets via LiquidationPeripheryBatch.
    function _deployLiquidationPeriphery(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(input.contracts.timelock != address(0), "Timelock not deployed");
        require(input.contracts.dusd != address(0), "DUSD not deployed");
        require(input.contracts.usmRegistry != address(0), "UsmRegistry not deployed");
        require(params.treasuryMultisig != address(0), "TreasuryMultisig must be set");

        address[] memory markets = new address[](12);
        markets[0] = input.contracts.wethMarket.market;
        markets[1] = input.contracts.wstethMarket.market;
        markets[2] = input.contracts.rethMarket.market;
        markets[3] = input.contracts.methMarket.market;
        markets[4] = input.contracts.tbtcMarket.market;
        markets[5] = input.contracts.wbtcBorrowMarket.market;
        markets[6] = input.contracts.cbbtcBorrowMarket.market;
        markets[7] = input.contracts.susdeBorrowMarket.market;
        markets[8] = input.contracts.syrupUsdcBorrowMarket.market;
        markets[9] = input.contracts.paxgBorrowMarket.market;
        markets[10] = input.contracts.susdeMintMarket.market;
        markets[11] = input.contracts.syrupUsdcMintMarket.market;

        for (uint256 i = 0; i < markets.length; i++) {
            require(markets[i] != address(0), "Market not deployed");
        }

        LiquidationPeripheryBatch batch = new LiquidationPeripheryBatch(
            LiquidationPeripheryBatchParams({
                owner: input.contracts.timelock,
                borrowToken: input.contracts.dusd,
                usmRegistry: input.contracts.usmRegistry,
                treasury: params.treasuryMultisig,
                markets: markets
            })
        );

        address periphery = batch.getReport().liquidationPeriphery;

        input.contracts.liquidationPeriphery = periphery;

        return input;
    }

    /// @dev Deploys UniversalRewardsDistributor via UniversalRewardsDistributorBatch.
    function _deployUniversalRewardsDistributor(
        AltoEthereumMainnetParams memory params,
        AltoEthereumMainnetInput memory input
    ) internal returns (AltoEthereumMainnetInput memory) {
        require(input.contracts.timelock != address(0), "Timelock not deployed");
        require(params.updater != address(0), "Updater must be set");
        require(params.freezer != address(0), "Freezer must be set");

        UniversalRewardsDistributorBatch batch = new UniversalRewardsDistributorBatch(
            UniversalRewardsDistributorBatchParams({
                owner: input.contracts.timelock,
                merkleRootUpdater: params.updater,
                freezer: params.freezer,
                initialTimelock: 1 days
            })
        );

        input.contracts.universalRewardsDistributor = batch.getReport().universalRewardsDistributor;

        return input;
    }

    /// @dev Deploys the MintCurveConvexPosition strategy stack (factory proxy, position implementation,
    ///      PositionBeacon) and wires the beacon into the factory via MintCurveConvexPositionFactoryBatch.
    ///      Ownership of the factory and beacon is handed to the timelock inside the batch.
    function _deployMintCurveConvexPositionFactory(AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(input.contracts.timelock != address(0), "Timelock not deployed");
        require(input.contracts.marketRegistry != address(0), "MarketRegistry not deployed");

        MintCurveConvexConfig memory config = MintCurveConvexConfig({
            curvePool: FRXUSD_DUSD_CURVE_POOL_MAINNET,
            convexBooster: CONVEX_BOOSTER_MAINNET,
            convexRewardPool: CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
            convexPid: POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
            crv: CRV_TOKEN_MAINNET,
            cvx: CVX_TOKEN_MAINNET
        });

        MintCurveConvexPositionFactoryBatch batch = new MintCurveConvexPositionFactoryBatch(
            MintCurveConvexPositionFactoryBatchParams({
                owner: input.contracts.timelock, marketRegistry: input.contracts.marketRegistry, config: config
            })
        );

        MintCurveConvexPositionFactoryBatchReport memory report = batch.getReport();

        input.contracts.mintCurveConvexPosition = MintCurveConvexPositionContracts({
            factory: report.factory,
            factoryImplementation: report.factoryImplementation,
            positionImplementation: report.positionImplementation,
            positionBeacon: report.positionBeacon
        });

        return input;
    }

    /// @dev Deploys Advanced Permissions frxUSD USM for liquidation periphery via AdvancedPermissionsUsmBatch.
    function _deployAdvancedPermissionsFrxUsdUsm(
        AltoEthereumMainnetParams memory params,
        AltoEthereumMainnetInput memory input
    ) internal returns (AltoEthereumMainnetInput memory) {
        require(input.contracts.timelock != address(0), "Timelock not deployed");
        require(input.contracts.dusd != address(0), "DUSD not deployed");
        require(input.contracts.usmRegistry != address(0), "UsmRegistry not deployed");
        require(input.contracts.feeRecipient != address(0), "FeeRecipient not deployed");
        require(input.contracts.liquidationPeriphery != address(0), "LiquidationPeriphery not deployed");
        require(params.freezer != address(0), "Freezer must be set");
        require(params.treasuryMultisig != address(0), "TreasuryMultisig must be set");

        uint128 exposureCap = 5_000_000_000 ether;
        uint256 mintCeiling = exposureCap;

        AdvancedPermissionsUsmBatchOverriddenFee[] memory overriddenFees =
            new AdvancedPermissionsUsmBatchOverriddenFee[](1);
        overriddenFees[0] = AdvancedPermissionsUsmBatchOverriddenFee({
            account: input.contracts.liquidationPeriphery,
            fee: IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: 0}),
            isSell: true
        });

        AdvancedPermissionsUsmBatchOverriddenRole[] memory overriddenRoles =
            new AdvancedPermissionsUsmBatchOverriddenRole[](0);

        AdvancedPermissionsUsmBatchFeeByRoleHash[] memory feesByRoleHash =
            new AdvancedPermissionsUsmBatchFeeByRoleHash[](0);

        address[] memory sellSwappers = new address[](1);
        sellSwappers[0] = input.contracts.liquidationPeriphery;

        address[] memory buySwappers = new address[](0);

        AdvancedPermissionsUsmBatch batch = new AdvancedPermissionsUsmBatch(
            AdvancedPermissionsUsmBatchParams({
                owner: input.contracts.timelock,
                dusd: input.contracts.dusd,
                usmRegistry: input.contracts.usmRegistry,
                feeRecipient: input.contracts.feeRecipient,
                freezer: params.freezer,
                treasuryMultisig: params.treasuryMultisig,
                underlyingAsset: FRXUSD_MAINNET,
                priceRatio: 1 ether,
                buyFee: 5, // 0.05%
                sellFee: 0, // sell fee is permissioned and others don't have access to sell except LiquidationPeriphery
                exposureCap: exposureCap,
                mintCeiling: mintCeiling,
                buyAccess: DirectionAccess.PERMISSIONLESS,
                sellAccess: DirectionAccess.PERMISSIONED,
                finalizeDusdAndRegistry: params.deployerHasOwnership,
                sellSwappers: sellSwappers,
                buySwappers: buySwappers,
                overriddenFees: overriddenFees,
                overriddenRoles: overriddenRoles,
                feesByRoleHash: feesByRoleHash
            })
        );

        AdvancedPermissionsUsmBatchReport memory report = batch.getReport();

        input.contracts.advancedPermissionsFrxusdUsm = AdvancedPermissionsUsmContracts({
            dusdUsm: report.dusdUsm,
            dusdUsmImplementation: report.dusdUsmImplementation,
            fixedPriceStrategy: report.fixedPriceStrategy,
            advancedPermissionsFeeStrategy: report.advancedPermissionsFeeStrategy
        });

        if (!params.deployerHasOwnership) {
            _finalizeAdvancedPermissionsUsmViaTimelockBatch(input, report.dusdUsm, mintCeiling);
        }

        return input;
    }

    function _finalizeAdvancedPermissionsUsmViaTimelockBatch(
        AltoEthereumMainnetInput memory input,
        address usm,
        uint256 mintCeiling
    ) internal {
        address timelock = input.contracts.timelock;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);

        targets[0] = input.contracts.dusd;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IDUSD.setMinterStatus, (usm, true));

        targets[1] = input.contracts.dusd;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterCeiling, (usm, mintCeiling));

        targets[2] = input.contracts.dusd;
        values[2] = 0;
        payloads[2] = abi.encodeCall(IDUSD.setBurnerStatus, (usm, true));

        targets[3] = input.contracts.usmRegistry;
        values[3] = 0;
        payloads[3] = abi.encodeCall(IUsmRegistry.addUsm, (usm));

        _writeSafeTimelockBatchJson(
            "frxusd-advanced-permissions-usm-registry", timelock, targets, values, payloads, minDelay
        );
    }

    /// @dev Deploys new market implementations and logs timelock batches to upgrade all 12 markets and
    ///      authorize the liquidation periphery on each market.
    function _upgradeMarketsForLiquidationPeriphery(AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        require(input.contracts.timelock != address(0), "Timelock not deployed");
        require(input.contracts.liquidationPeriphery != address(0), "LiquidationPeriphery not deployed");

        address[] memory markets = _getAllMarkets(input);
        MarketUpgradeBatchReport memory report = (new MarketUpgradeBatch(markets)).getReport();

        _logMarketUpgradeTimelockBatch(input, report);
        _logAuthorizeLiquidationPeripheryTimelockBatch(input, report.markets);

        input = _updateMarketImplementations(input, report);

        return input;
    }

    function _getAllMarkets(AltoEthereumMainnetInput memory input) internal view returns (address[] memory markets) {
        require(input.contracts.marketRegistry != address(0), "MarketRegistry not deployed");

        IMarketRegistry registry = IMarketRegistry(input.contracts.marketRegistry);
        address[] memory mintMarkets = registry.getMintMarkets();
        address[] memory borrowMarkets = registry.getBorrowMarkets();

        uint256 mintCount = mintMarkets.length;
        uint256 borrowCount = borrowMarkets.length;
        markets = new address[](mintCount + borrowCount);

        for (uint256 i = 0; i < mintCount; i++) {
            markets[i] = mintMarkets[i];
        }
        for (uint256 i = 0; i < borrowCount; i++) {
            markets[mintCount + i] = borrowMarkets[i];
        }

        require(markets.length > 0, "No markets in registry");
    }

    function _logMarketUpgradeTimelockBatch(
        AltoEthereumMainnetInput memory input,
        MarketUpgradeBatchReport memory report
    ) internal {
        address timelock = input.contracts.timelock;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();
        uint256 count = report.markets.length;

        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory payloads = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            targets[i] = report.markets[i];
            values[i] = 0;
            payloads[i] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (report.implementations[i], ""));
        }

        _writeSafeTimelockBatchJson(
            "market-upgrade-liquidation-periphery", timelock, targets, values, payloads, minDelay
        );
    }

    function _logAuthorizeLiquidationPeripheryTimelockBatch(
        AltoEthereumMainnetInput memory input,
        address[] memory markets
    ) internal {
        address timelock = input.contracts.timelock;
        address periphery = input.contracts.liquidationPeriphery;
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();
        uint256 count = markets.length;

        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory payloads = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            targets[i] = markets[i];
            values[i] = 0;
            payloads[i] = abi.encodeCall(IMarketBase.setAuthorizedLiquidationPeriphery, (periphery, true));
        }

        _writeSafeTimelockBatchJson(
            "market-authorize-liquidation-periphery", timelock, targets, values, payloads, minDelay
        );
    }

    function _updateMarketImplementations(AltoEthereumMainnetInput memory input, MarketUpgradeBatchReport memory report)
        internal
        pure
        returns (AltoEthereumMainnetInput memory)
    {
        for (uint256 r = 0; r < report.markets.length; r++) {
            address market = report.markets[r];
            address newImplementation = report.implementations[r];

            if (market == input.contracts.wethMarket.market) {
                input.contracts.wethMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.wstethMarket.market) {
                input.contracts.wstethMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.rethMarket.market) {
                input.contracts.rethMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.methMarket.market) {
                input.contracts.methMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.tbtcMarket.market) {
                input.contracts.tbtcMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.wbtcBorrowMarket.market) {
                input.contracts.wbtcBorrowMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.cbbtcBorrowMarket.market) {
                input.contracts.cbbtcBorrowMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.susdeBorrowMarket.market) {
                input.contracts.susdeBorrowMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.syrupUsdcBorrowMarket.market) {
                input.contracts.syrupUsdcBorrowMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.paxgBorrowMarket.market) {
                input.contracts.paxgBorrowMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.susdeMintMarket.market) {
                input.contracts.susdeMintMarket.marketImplementation = newImplementation;
            } else if (market == input.contracts.syrupUsdcMintMarket.market) {
                input.contracts.syrupUsdcMintMarket.marketImplementation = newImplementation;
            }
        }

        return input;
    }

    function _deployPost(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        // Transfer ownership from DUSD and AltoAdapter to timelock
        _transferOwnershipToTimelock(input.contracts, input.contracts.timelock);

        // Configure timelock roles: remove deployer, grant to timelockAdmin
        _grantTimelockRolesToTimelockAdmin(input.contracts.timelock, params);

        // Revoke timelock roles from multicall addresses
        _revokeTimelockRolesFromMulticall(input.contracts.timelock);

        // Update timelock delay
        _updateTimelockDelay(input.contracts.timelock, params.timelockDelay);

        _revokeTimelockRolesFromDeployer(input.contracts.timelock, params);

        return input;
    }
}

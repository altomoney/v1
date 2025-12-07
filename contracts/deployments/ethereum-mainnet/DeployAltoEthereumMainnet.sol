// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
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
    USDC_MAINNET,
    LAYERZERO_ENDPOINT_MAINNET,
    ZEROX_SWAP_TARGET_MAINNET,
    getMulticallOwnerAddresses
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {
    EthereumMainnetOracleDeployer,
    EthereumMainnetLendingOracleAsset
} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";

import {MockFeeCollector} from "@alto/deployments/ethereum-mainnet/MockFeeCollector.sol";
import {DUSDBatch, DUSDBatchParams, DUSDBatchReport} from "@alto/deployments/ethereum-mainnet/DUSDBatch.sol";
import {MintMarketBatch, MintMarketBatchParams} from "@alto/deployments/ethereum-mainnet/MintMarketBatch.sol";
import {BorrowMarketBatch, BorrowMarketBatchParams} from "@alto/deployments/ethereum-mainnet/BorrowMarketBatch.sol";
import {UsmBatch, UsmBatchParams, UsmBatchReport} from "@alto/deployments/ethereum-mainnet/UsmBatch.sol";
import {IMarketRegistry, MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {IUsmRegistry, UsmRegistry} from "@alto/utils/UsmRegistry.sol";
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
    Contracts
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";

library DeployAltoEthereumMainnet {
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
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: WETH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.WETH,
                    irmInterestRate: 0.035 ether / uint256(365 days), // 3.5%
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    debtCeiling: 300_000 ether, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.05 ether, // 5%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_WSTETH) {
            input.contracts.wstethMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: WSTETH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.stETH,
                    irmInterestRate: 0.035 ether / uint256(365 days), // 3.5%
                    maxLtv: 0.78 ether, // 78%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    debtCeiling: 300_000 ether, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.83 ether, // 83%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.91 ether, // 91%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.06 ether, // 6%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_RETH) {
            input.contracts.rethMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: RETH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.rETH,
                    irmInterestRate: 0.04 ether / uint256(365 days), // 4%
                    maxLtv: 0.7 ether, // 70%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    debtCeiling: 300_000 ether, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.75 ether, // 75%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.83 ether, // 83%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_METH) {
            input.contracts.methMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: METH_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.METH,
                    irmInterestRate: 0.04 ether / uint256(365 days), // 4%
                    maxLtv: 0.67 ether, // 67%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    debtCeiling: 300_000 ether, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.72 ether, // 72%
                        dynamicBonusFeeStart: 0.02 ether, // 2%
                        ltvForCompleteLiquidation: 0.8 ether, // 80%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.075 ether, // 7.5%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.MINT_MARKET_TBTC) {
            input.contracts.tbtcMarket = _deployMintMarket(
                DeployMintMarketParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    collateralToken: TBTC_MAINNET,
                    oracleAsset: EthereumMainnetLendingOracleAsset.tBTC,
                    irmInterestRate: 0.01 ether / uint256(365 days), // TODO placeholder value
                    maxLtv: 0.72 ether, // 72%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    debtCeiling: 300_000 ether, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.77 ether, // 77%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.85 ether, // 85%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
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
                        initialRateAtTarget: 0.04 ether / int256(365 days), // 4%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.75 ether, // 75%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    supplyCapAssets: 0, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether, // 80%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.88 ether, // 88%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false,
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
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
                        initialRateAtTarget: 0.04 ether / int256(365 days), // 4%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.75 ether, // 75%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    supplyCapAssets: 0, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether, // 80%
                        dynamicBonusFeeStart: 0.01 ether, // 1%
                        ltvForCompleteLiquidation: 0.88 ether, // 88%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.07 ether, // 7%
                        minPenaltyPercentage: 0, // placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false, // priority liquidation is not enabled
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
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
                        initialRateAtTarget: 0.04 ether / int256(365 days), // 4%
                        minRateAtTarget: 0.001 ether / int256(365 days), // 0.1%
                        maxRateAtTarget: 2 ether / int256(365 days) // 200%
                    }),
                    maxLtv: 0.8 ether, // 80%
                    initialBorrowOpeningFee: 0, // TODO placeholder value
                    supplyCapAssets: 0, // TODO placeholder value
                    liquidationConfig: LiquidationConfiguration({
                        maxLiquidationLtv: 0.85 ether, // 85%
                        dynamicBonusFeeStart: 0.005 ether, // 0.5%
                        ltvForCompleteLiquidation: 0.93 ether, // 93%
                        dynamicBonusFeeDecaySteepness: 5 ether, // 5
                        liquidationBaseFee: 0.06 ether, // 6%
                        minPenaltyPercentage: 0, // TODO placeholder value
                        protocolFeePercentage: 0.07 ether, // 7%
                        isEnabledPriorityLiquidation: false, // priority liquidation is not enabled
                        disablePriorityLiquidationAbovePositionLtv: 0,
                        priorityLiquidationGracePeriod: 0,
                        taggerLiquidationGracePeriod: 0,
                        liquidationWindowTag: 0
                    }),
                    freezer: params.freezer
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.PERMISSIONED_USM) {
            input = _deployUsm(
                DeployUsmParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    freezer: params.freezer,
                    buyFee: 0,
                    sellFee: 0,
                    exposureCap: 0, // TODO placeholder value
                    underlyingAsset: USDC_MAINNET,
                    isPermissioned: true,
                    treasuryMultisig: params.treasuryMultisig
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.PERMISSIONLESS_USM) {
            input = _deployUsm(
                DeployUsmParams({
                    owner: input.contracts.timelock,
                    dusd: input.contracts.dusd,
                    altoAdapter: input.contracts.altoAdapter,
                    feeRecipient: input.contracts.feeRecipient,
                    freezer: params.freezer,
                    buyFee: 1, // TODO placeholder value
                    sellFee: 1, // TODO placeholder value
                    exposureCap: 0, // TODO placeholder value
                    underlyingAsset: USDC_MAINNET,
                    isPermissioned: false,
                    treasuryMultisig: params.treasuryMultisig
                }),
                input,
                params.useUnsafeUpgrades
            );
        } else if (params.phase == DeploymentPhase.POST) {
            input = _deployPost(params, input);
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

        // Deploy fee collector with timelock as owner
        input.contracts.feeRecipient =
            address(new MockFeeCollector(input.contracts.timelock, params.feeReceiverAddress));

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
                flashFee: FlashFee({minFlashFee: 5e14, maxFlashFee: 1e16}), // TODO placeholder value
                flashMintCeiling: 750_000 ether, // TODO placeholder value
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
        bool useUnsafeUpgrades
    ) internal returns (MarketContracts memory) {
        uint256 minterCeiling = marketParams.debtCeiling * 1.05 ether / marketParams.liquidationConfig.maxLiquidationLtv;
        MintMarketBatch batch = new MintMarketBatch(
            MintMarketBatchParams({
                owner: marketParams.owner,
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
                zeroXSwapTarget: ZEROX_SWAP_TARGET_MAINNET,
                freezer: marketParams.freezer,
                useUnsafeUpgrades: useUnsafeUpgrades
            })
        );
        MarketContracts memory report = batch.getReport();

        // Configure DUSD minter permissions for market (requires DUSD ownership)
        // This is done here because DUSD may be owned by the deployment caller, not the batch contract
        IDUSD(marketParams.dusd).setMinterStatus(report.market, true);
        IDUSD(marketParams.dusd).setMinterCeiling(report.market, minterCeiling);
        IDUSD(marketParams.dusd).setBurnerStatus(report.market, true);

        IMarketRegistry(input.contracts.marketRegistry).addMintMarket(report.market);

        // Approve market on AltoAdapter (requires adapter ownership)
        AltoAdapter(payable(marketParams.altoAdapter)).approveContract(report.market);

        return report;
    }

    function _deployBorrowMarket(
        DeployBorrowMarketParams memory marketParams,
        AltoEthereumMainnetInput memory input,
        bool useUnsafeUpgrades
    ) internal returns (MarketContracts memory) {
        // Deploy batch - deploys all market components in single constructor (including Oracle and IRM)
        BorrowMarketBatch batch = new BorrowMarketBatch(
            BorrowMarketBatchParams({
                owner: marketParams.owner,
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
                zeroXSwapTarget: ZEROX_SWAP_TARGET_MAINNET,
                freezer: marketParams.freezer,
                useUnsafeUpgrades: useUnsafeUpgrades
            })
        );
        MarketContracts memory report = batch.getReport();

        IMarketRegistry(input.contracts.marketRegistry).addBorrowMarket(report.market);

        // Approve market on AltoAdapter (requires adapter ownership)
        AltoAdapter(payable(marketParams.altoAdapter)).approveContract(report.market);

        return report;
    }

    function _deployUsm(DeployUsmParams memory usmParams, AltoEthereumMainnetInput memory input, bool useUnsafeUpgrades)
        internal
        returns (AltoEthereumMainnetInput memory)
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
                useUnsafeUpgrades: useUnsafeUpgrades,
                treasuryMultisig: usmParams.treasuryMultisig
            })
        );
        UsmBatchReport memory report = batch.getReport();

        // exposureCap​ is in underlying asset (in this case USDC) this should be transformed to DUSD amount instead
        // USDC is 6 decimals, DUSD is 18 decimals, so 1e12 is the factor to convert USDC to DUSD
        uint256 mintCeiling = usmParams.exposureCap == 0 ? 5_000_000_000 ether : usmParams.exposureCap * 1e12;

        IDUSD(usmParams.dusd).setMinterStatus(report.dusdUsm, true);
        IDUSD(usmParams.dusd).setMinterCeiling(report.dusdUsm, mintCeiling);
        IDUSD(usmParams.dusd).setBurnerStatus(report.dusdUsm, true);

        IUsmRegistry(input.contracts.usmRegistry).addUsm(report.dusdUsm);

        // Approve USM on AltoAdapter (requires adapter ownership)
        AltoAdapter(payable(usmParams.altoAdapter)).approveContract(report.dusdUsm);

        UsmContracts memory usmContract = UsmContracts({
            dusdUsm: report.dusdUsm,
            dusdUsmImplementation: report.dusdUsmImplementation,
            fixedPriceStrategy: report.fixedPriceStrategy,
            fixedFeeStrategy: report.fixedFeeStrategy
        });

        if (usmParams.isPermissioned) {
            input.contracts.permissionedUsm = usmContract;
        } else {
            input.contracts.permissionlessUsm = usmContract;
        }

        return input;
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


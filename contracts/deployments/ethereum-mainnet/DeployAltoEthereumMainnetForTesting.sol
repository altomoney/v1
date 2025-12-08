// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {
    BUNDLER3_MAINNET,
    WETH_MAINNET,
    WBTC_MAINNET,
    USDC_MAINNET,
    LAYERZERO_ENDPOINT_MAINNET,
    ZEROX_SWAP_TARGET_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {EthereumMainnetLendingOracleAsset} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {DUSDBatch, DUSDBatchParams, DUSDBatchReport} from "@alto/deployments/ethereum-mainnet/DUSDBatch.sol";
import {MintMarketBatch, MintMarketBatchParams} from "@alto/deployments/ethereum-mainnet/MintMarketBatch.sol";
import {BorrowMarketBatch, BorrowMarketBatchParams} from "@alto/deployments/ethereum-mainnet/BorrowMarketBatch.sol";
import {IMarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {
    MarketContracts,
    DeploymentPhase,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeployCoreParams,
    DeployDUSDParams,
    DeployMintMarketParams,
    DeployBorrowMarketParams
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {
    INonfungiblePositionManager,
    MintParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";

library DeployAltoEthereumMainnet {
    function deploy(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        if (params.phase == DeploymentPhase.CORE) {
            DeployCoreParams memory coreParams =
                DeployCoreParams({owner: params.deployer, bundler3: BUNDLER3_MAINNET, wNative: WETH_MAINNET});
            input = _deployCore(coreParams, params, input);
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
                    owner: params.deployer,
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
        } else if (params.phase == DeploymentPhase.BORROW_MARKET_WBTC) {
            input.contracts.wbtcBorrowMarket = _deployBorrowMarket(
                DeployBorrowMarketParams({
                    owner: params.deployer,
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
        // Set feeRecipient to deployer for testing (simplified from main deployment)
        input.contracts.feeRecipient = params.deployer;

        // Deploy AltoAdapter with Morpho's Bundler3, WETH, and deployer as owner
        // Owner will be transferred to timelock in POST phase (needed to authorize contracts during deployment)
        input.contracts.altoAdapter = address(new AltoAdapter(coreParams.bundler3, coreParams.wNative, params.deployer));

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
                timelock: params.deployer,
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

    function _deployPost(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        DUSD(input.contracts.dusd).setMinterStatus(params.deployer, true);
        DUSD(input.contracts.dusd).setMinterCeiling(params.deployer, type(uint128).max);

        DUSD(input.contracts.dusd).mint(params.deployer, 1_000_000 ether);

        {
            MintParams memory mintParams = MintParams({
                token0: address(USDC_MAINNET),
                token1: address(input.contracts.dusd),
                fee: 100,
                tickLower: -887272,
                tickUpper: 887272,
                amount0Desired: 1000 * 10 ** 6,
                amount1Desired: 1000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: params.deployer,
                deadline: block.timestamp + 1 days
            });

            // initial price of 1 dusd = 1 USDC
            if (USDC_MAINNET < input.contracts.dusd) {
                input.contracts.uniswapPool = INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(USDC_MAINNET), address(input.contracts.dusd), 100, 79226131514347940073696838322079733
                    );
                mintParams.token0 = address(USDC_MAINNET);
                mintParams.amount0Desired = 1000 * 10 ** 6;
                mintParams.token1 = address(input.contracts.dusd);
                mintParams.amount1Desired = 1000 ether;
            } else {
                input.contracts.uniswapPool = INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.contracts.dusd), address(USDC_MAINNET), 100, 79226398639705836713598
                    );
                mintParams.token0 = address(input.contracts.dusd);
                mintParams.amount0Desired = 1000 ether;
                mintParams.token1 = address(USDC_MAINNET);
                mintParams.amount1Desired = 1000 * 10 ** 6;
            }

            INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager).mint(mintParams);
        }

        return input;
    }
}


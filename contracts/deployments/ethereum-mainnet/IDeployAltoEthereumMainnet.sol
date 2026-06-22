// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {EthereumMainnetLendingOracleAsset} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

enum DeploymentPhase {
    CORE, // Phase 0: Deploy TimelockController, AltoAdapter, and MockFeeCollector
    REGISTRY, // Phase 1: Deploy MarketRegistry and UsmRegistry
    DUSD, // Phase 2: Deploy DUSD and DUSDFlashMinter
    MINT_MARKET_WETH, // Phase 3: Deploy WETH Mint Market
    MINT_MARKET_WSTETH, // Phase 4: Deploy wstETH Mint Market
    MINT_MARKET_RETH, // Phase 5: Deploy rETH Mint Market
    MINT_MARKET_METH, // Phase 6: Deploy mETH Mint Market
    MINT_MARKET_TBTC, // Phase 7: Deploy tBTC Mint Market
    BORROW_MARKET_WBTC, // Phase 8: Deploy WBTC Borrow Market
    BORROW_MARKET_CBBTC, // Phase 9: Deploy cbBTC Borrow Market
    BORROW_MARKET_SUSDE, // Phase 10: Deploy sUSDe Borrow Market
    PERMISSIONED_USM, // Phase 11: Deploy Permissioned DUSD/USDC Peg Stability Module
    PERMISSIONLESS_USM, // Phase 12: Deploy Permissionless DUSD/USDC Peg Stability Module
    POST, // Phase 13: Configure TimelockController and transfer ownership
    REFERRAL_ADAPTER, // Phase 14: Deploy AltoReferralWhitelistAdapter
    BORROW_MARKET_SYRUP_USDC, // Phase 15: Deploy syrupUSDC Borrow Market
    BORROW_MARKET_PAXG, // Phase 16: Deploy PAXG Borrow Market
    MINT_MARKET_SUSDE, // Phase 17: Deploy sUSDe Mint Market
    MINT_MARKET_SYRUPUSDC, // Phase 18: Deploy syrupUSDC Mint Market
    PERMISSIONED_FRXUSD_USM, // Phase 19: Deploy Permissioned DUSD/FRXUSD Peg Stability Module
    ADAPTER, // Phase 20: Deploy AltoAdapter
    DUSD_VAULT, // Phase 21: Deploy DUSD ERC4626 Vault (`Alto DUSD Vault`, aDUSD)
    VAULT_REGISTRY, // Phase 22: Deploy VaultRegistry, register existing vaults, transfer to timelock
    PERMISSIONLESS_FRXUSD_USM, // Phase 23: Deploy Permissionless DUSD/FRXUSD Peg Stability Module
    ALTO_LEVERAGE_SWAPPER_MULTI_TARGET // Phase 24: Deploy AltoLeverageSwapperMultiTarget for each market
}

enum UsmFinalizeMode {
    DIRECT,
    TIMELOCK_BATCH
}

struct MarketContracts {
    address market;
    address marketImplementation;
    address marketIrm;
    address marketOracle;
    address liquidationEngine;
    address leverageSwapper;
    address leverage;
}

struct UsmContracts {
    address dusdUsm;
    address dusdUsmImplementation;
    address fixedPriceStrategy;
    address fixedFeeStrategy;
}

struct AltoEthereumMainnetInput {
    Contracts contracts;
}

struct Contracts {
    address timelock;
    address altoAdapter;
    address feeRecipient; // Timelock controller for fee recipients
    address feeRecipientMintMarkets; // Timelock controller for mint market fee recipients
    address dusd;
    address dusdFlashMinter;
    address marketRegistry;
    address usmRegistry;
    address vaultRegistry;
    address referralAdapter;
    MarketContracts wethMarket;
    MarketContracts wstethMarket;
    MarketContracts rethMarket;
    MarketContracts methMarket;
    MarketContracts tbtcMarket;
    MarketContracts wbtcBorrowMarket;
    MarketContracts cbbtcBorrowMarket;
    MarketContracts susdeBorrowMarket;
    MarketContracts syrupUsdcBorrowMarket;
    MarketContracts paxgBorrowMarket;
    MarketContracts susdeMintMarket;
    MarketContracts syrupUsdcMintMarket;
    UsmContracts permissionedUsm;
    UsmContracts permissionlessUsm;
    UsmContracts permissionedFrxusdUsm;
    UsmContracts permissionlessFrxusdUsm;
    address dusdVault;
}

// PARAMETERS FOR THE DEPLOYMENT

struct AltoEthereumMainnetParams {
    address timelockAdmin;
    uint256 timelockDelay;
    address freezer;
    address deployer;
    DeploymentPhase phase;
    bool useUnsafeUpgrades;
    address treasuryMultisig;
    address updater;
    bool deployerHasOwnership;
}

struct DeployCoreParams {
    address owner;
    address bundler3; // Bundler3 address (currently BUNDLER3_MAINNET constant)
    address wNative; // Wrapped native token address (currently WETH_MAINNET constant)
}

struct DeployDUSDParams {
    address owner;
    address lzEndpoint; // LayerZero endpoint address
    address feeRecipient; // Fee recipient address (treasury) from previous CORE phase
}

struct DeployBorrowMarketParams {
    address owner;
    address dusd; // From previous DUSD phase
    address altoAdapter; // From previous CORE phase
    address feeRecipient; // From previous CORE phase
    address collateralToken; // WBTC_MAINNET, CBBTC_MAINNET, SUSDE_MAINNET, etc.
    EthereumMainnetLendingOracleAsset oracleAsset; // Oracle asset type
    AdaptiveCurveIrm.AdaptiveCurveIrmConfig irmConfig; // AdaptiveCurveIrm configuration
    uint256 maxLtv; // Maximum loan-to-value ratio
    uint256 initialBorrowOpeningFee; // Initial borrow opening fee
    uint128 supplyCapAssets; // Supply cap in assets
    LiquidationConfiguration liquidationConfig; // Liquidation configuration
    address freezer; // Pauser/Freezer Multisig address
    address swapRouter; // swap router address
}

struct DeployUsmParams {
    address owner;
    address dusd; // From previous DUSD phase
    address underlyingAsset; // Underlying asset address (USDC_MAINNET, etc.)
    address altoAdapter; // From previous CORE phase
    address feeRecipient; // From previous CORE phase
    address freezer; // Pauser/Freezer Multisig address
    uint256 buyFee; // Buy fee for USM
    uint256 sellFee; // Sell fee for USM
    uint256 exposureCap; // Exposure cap for USM
    bool isPermissioned; // Whether the USM is permissioned
    address treasuryMultisig; // Treasury multisig address
    UsmFinalizeMode finalizeMode; // Whether to finalize directly or via timelock batch
    string safeBatchName; // Safe batch name for delayed finalization
}

struct DeployMintMarketParams {
    address owner;
    address dusd; // From previous DUSD phase
    address altoAdapter; // From previous CORE phase
    address feeRecipient; // From previous CORE phase
    address collateralToken; // WETH_MAINNET, WSTETH_MAINNET, etc.
    EthereumMainnetLendingOracleAsset oracleAsset; // Oracle asset type
    uint256 irmInterestRate; // Interest rate for FixedRateIrm (annual rate)
    uint256 maxLtv; // Maximum loan-to-value ratio
    uint256 initialBorrowOpeningFee; // Initial borrow opening fee
    uint256 debtCeiling; // Debt ceiling
    LiquidationConfiguration liquidationConfig; // Liquidation configuration
    address freezer; // Pauser/Freezer Multisig address
    address swapRouter; // swap router address
}

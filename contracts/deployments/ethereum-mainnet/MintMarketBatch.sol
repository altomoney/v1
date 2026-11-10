// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {MintMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    EthereumMainnetOracleDeployer,
    EthereumMainnetLendingOracleAsset
} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {ALTO_MINT_MARKET_IMPL} from "@alto/deployments/ethereum-mainnet/Constants.sol";

import {MarketContracts} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";

struct MintMarketBatchParams {
    address owner;
    address deployer;
    address dusd;
    address altoAdapter;
    address feeRecipient;
    address collateralToken;
    EthereumMainnetLendingOracleAsset oracleAsset;
    uint256 irmInterestRate;
    uint256 maxLtv;
    uint256 initialBorrowOpeningFee;
    uint256 debtCeiling;
    LiquidationConfiguration liquidationConfig;
    uint256 minterCeiling;
    address[] validSwapTargets;
    address freezer;
    address emergencyController;
}

/// @notice Deploys all mint market components in a single transaction
/// @dev Upgrade safety must be validated by the calling deployment script before broadcasting.
library MintMarketBatch {
    function deploy(MintMarketBatchParams memory _params) internal returns (MarketContracts memory) {
        // Deploy Oracle and IRM first (deployed directly with _params.owner as owner)
        address marketOracle = EthereumMainnetOracleDeployer.deployOracle(_params.oracleAsset, _params.owner);
        address marketIrm = address(new FixedRateIrm(_params.irmInterestRate, _params.owner));

        // Deploy Liquidation Engine with deployer as owner temporarily to allow configuration
        // owner will be transferred to _params.owner after configuration
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(_params.deployer));

        // Deploy Market Proxy
        bytes memory initData = abi.encodeCall(
            AltoMintMarket.initialize,
            (MintMarketInitParams({
                    baseMarketInitParams: BaseMarketInitParams({
                        borrowToken: _params.dusd,
                        collateralToken: _params.collateralToken,
                        irm: marketIrm,
                        owner: _params.deployer,
                        emergencyAdmin: _params.freezer,
                        oracle: marketOracle,
                        maxLtv: _params.maxLtv,
                        feeRecipient: _params.feeRecipient,
                        liquidationEngine: liquidationEngine
                    }),
                    debtCeiling: _params.debtCeiling,
                    initialBorrowOpeningFee: _params.initialBorrowOpeningFee
                }))
        );
        address marketImplementation = ALTO_MINT_MARKET_IMPL;
        address marketProxy = UnsafeUpgrades.deployUUPSProxy(marketImplementation, initData);

        // Set liquidation configuration (requires ownership and market to be set)
        // Market initialization calls setMarketOnce on liquidation engine, so market must be initialized first
        DlbDcfPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_params.liquidationConfig);

        // Transfer liquidation engine ownership to _params.owner
        AltoOwnable2Step(liquidationEngine).transferOwnershipSkip2Step(_params.owner);

        // The initializer grants the freezer roles; authorize the emergency controller as well.
        IPausable(marketProxy).setPauser(_params.emergencyController, PAUSE_TYPE, true);
        IPausable(marketProxy).setPauser(_params.emergencyController, FROZEN_TYPE, true);

        // Deploy leverage components with deployer as owner temporarily to allow configuration
        // owner will be transferred to _params.owner after configuration
        address leverageSwapper =
            address(new AltoLeverageSwapperMultiTarget(_params.deployer, _params.validSwapTargets));
        address leverage = address(new AltoLeverage(leverageSwapper, _params.deployer));

        // Configure leverage components (requires ownership)
        AltoLeverage(leverage).setMarket(marketProxy, true);
        AltoLeverageSwapperMultiTarget(leverageSwapper).setWhitelisted(leverage, true);

        // Configure market to authorize leverage callback (requires market ownership)
        IMarket(marketProxy).setAuthorizedCallback(leverage, true);

        // Transfer leverage components ownership to _params.owner
        Ownable(leverageSwapper).transferOwnership(_params.owner);
        AltoOwnable2Step(leverage).transferOwnershipSkip2Step(_params.owner);

        // Transfer market ownership to _params.owner
        AltoOwnable2StepUpgradeable(marketProxy).transferOwnershipSkip2Step(_params.owner);

        return MarketContracts({
            market: marketProxy,
            marketImplementation: marketImplementation,
            marketIrm: marketIrm,
            marketOracle: marketOracle,
            liquidationEngine: liquidationEngine,
            leverageSwapper: leverageSwapper,
            leverage: leverage
        });
    }
}

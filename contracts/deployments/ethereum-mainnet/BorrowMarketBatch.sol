// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {BorrowMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    EthereumMainnetOracleDeployer,
    EthereumMainnetLendingOracleAsset
} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {ALTO_BORROW_MARKET_IMPL} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {MarketContracts} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";

struct BorrowMarketBatchParams {
    address owner;
    address deployer;
    address dusd;
    address altoAdapter;
    address feeRecipient;
    address collateralToken;
    EthereumMainnetLendingOracleAsset oracleAsset;
    AdaptiveCurveIrm.AdaptiveCurveIrmConfig irmConfig;
    uint256 maxLtv;
    uint256 initialBorrowOpeningFee;
    uint128 supplyCapAssets;
    LiquidationConfiguration liquidationConfig;
    address[] validSwapTargets;
    address freezer;
    bool useUnsafeUpgrades;
}

/// @notice Deploys all borrow market components in a single transaction
library BorrowMarketBatch {
    function deploy(BorrowMarketBatchParams memory _params) internal returns (MarketContracts memory) {
        // Deploy Oracle and IRM first (deployed directly with _params.owner as owner)
        address marketOracle = EthereumMainnetOracleDeployer.deployOracle(_params.oracleAsset, _params.owner);
        address marketIrm = address(new AdaptiveCurveIrm(_params.irmConfig, _params.owner));

        // Deploy Liquidation Engine with deployer as owner temporarily to allow configuration
        // owner will be transferred to _params.owner after configuration
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(_params.deployer));

        // Deploy Market Proxy
        bytes memory initData = abi.encodeCall(
            AltoBorrowMarket.initialize,
            (
                BorrowMarketInitParams({
                    baseMarketInitParams: BaseMarketInitParams({
                        borrowToken: _params.dusd,
                        collateralToken: _params.collateralToken,
                        irm: marketIrm,
                        owner: _params.deployer, // ownership of market is temporarily set to deployer
                        oracle: marketOracle,
                        maxLtv: _params.maxLtv,
                        feeRecipient: _params.feeRecipient,
                        liquidationEngine: liquidationEngine
                    }),
                    initialBorrowOpeningFee: _params.initialBorrowOpeningFee,
                    supplyCapAssets: _params.supplyCapAssets,
                    initialInterestFee: 0
                })
            )
        );
        address marketProxy;
        address marketImplementation = ALTO_BORROW_MARKET_IMPL;
        if (_params.useUnsafeUpgrades) {
            marketProxy = UnsafeUpgrades.deployUUPSProxy(marketImplementation, initData);
        } else {
            marketProxy = Upgrades.deployUUPSProxy("AltoBorrowMarket.sol:AltoBorrowMarket", initData);
            marketImplementation = Upgrades.getImplementationAddress(marketProxy);
        }

        // Set liquidation configuration (requires ownership)
        DlbDcfPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_params.liquidationConfig);

        // Transfer liquidation engine ownership to _params.owner
        AltoOwnable2Step(liquidationEngine).transferOwnershipSkip2Step(_params.owner);

        // Set freezer as pauser for PAUSE_TYPE and FROZEN_TYPE (requires market ownership)
        IPausable(marketProxy).setPauser(_params.freezer, PAUSE_TYPE, true);
        IPausable(marketProxy).setPauser(_params.freezer, FROZEN_TYPE, true);
        IPausable(marketProxy).setPauser(_params.deployer, PAUSE_TYPE, false);
        IPausable(marketProxy).setPauser(_params.deployer, FROZEN_TYPE, false);

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

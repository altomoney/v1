// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {MintMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    EthereumMainnetOracleDeployer,
    EthereumMainnetLendingOracleAsset
} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {MarketContracts} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";

struct MintMarketBatchParams {
    address owner;
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
    address zeroXSwapTarget;
    address freezer;
    bool useUnsafeUpgrades;
}

/// @notice Deploys all mint market components in a single transaction
library MintMarketBatch {
    function deploy(MintMarketBatchParams memory _params) internal returns (MarketContracts memory) {
        // Deploy Oracle and IRM first (deployed directly with _params.owner as owner)
        address marketOracle = EthereumMainnetOracleDeployer.deployOracle(_params.oracleAsset, _params.owner);
        address marketIrm = address(new FixedRateIrm(_params.irmInterestRate, _params.owner));

        // Deploy Liquidation Engine with batch contract as owner temporarily to allow configuration
        // owner will be transferred to _params.owner after configuration
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(msg.sender));

        // Deploy Market Proxy
        bytes memory initData = abi.encodeCall(
            AltoMintMarket.initialize,
            (MintMarketInitParams({
                    baseMarketInitParams: BaseMarketInitParams({
                        borrowToken: _params.dusd,
                        collateralToken: _params.collateralToken,
                        irm: marketIrm,
                        owner: msg.sender,
                        oracle: marketOracle,
                        maxLtv: _params.maxLtv,
                        feeRecipient: _params.feeRecipient,
                        liquidationEngine: liquidationEngine
                    }),
                    debtCeiling: _params.debtCeiling,
                    initialBorrowOpeningFee: _params.initialBorrowOpeningFee
                }))
        );
        address marketProxy;
        address marketImplementation;
        if (_params.useUnsafeUpgrades) {
            marketImplementation = address(new AltoMintMarket());
            marketProxy = UnsafeUpgrades.deployUUPSProxy(marketImplementation, initData);
        } else {
            marketProxy = Upgrades.deployUUPSProxy("AltoMintMarket.sol:AltoMintMarket", initData);
            marketImplementation = Upgrades.getImplementationAddress(marketProxy);
        }

        // Set liquidation configuration (requires ownership)
        DlbDcfPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_params.liquidationConfig);

        // Transfer liquidation engine ownership to _params.owner
        AltoOwnable2Step(liquidationEngine).transferOwnershipSkip2Step(_params.owner);

        // Set freezer as pauser for PAUSE_TYPE and FROZEN_TYPE (requires market ownership)
        IPausable(marketProxy).setPauser(_params.freezer, PAUSE_TYPE, true);
        IPausable(marketProxy).setPauser(_params.freezer, FROZEN_TYPE, true);

        // Deploy leverage components with batch contract as owner temporarily to allow configuration
        // owner will be transferred to _params.owner after configuration
        address leverageSwapper = address(new AltoLeverageSwapper(msg.sender, _params.zeroXSwapTarget));
        address leverage = address(new AltoLeverage(leverageSwapper, msg.sender));

        // Configure leverage components (requires ownership)
        AltoLeverage(leverage).setMarket(marketProxy, true);
        AltoLeverageSwapper(leverageSwapper).setWhitelisted(leverage, true);

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


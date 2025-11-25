// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {BorrowMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {ITestnetMarketBatch, TestnetMarketBatchReport} from "./ITestnetMarketBatch.sol";
import {AltoLiquidationEngine} from "@alto/lending/AltoLiquidationEngine.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

struct TestnetBorrowMarketBatchParams {
    address owner;
    address collateralToken;
    address borrowToken;
    uint256 marketOraclePrice;
    uint256 maxLtv;
    uint128 supplyCapAssets;
}

int256 constant YEAR = int256(365 days);

/// @title TestnetBorrowMarketBatch
/// @notice Deploy testnet market
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TestnetBorrowMarketBatch is ITestnetMarketBatch {
    TestnetMarketBatchReport public report;

    constructor(TestnetBorrowMarketBatchParams memory _params) {
        address marketOracle = address(new OracleTestnet(address(this)));
        OracleTestnet(marketOracle).setPrice(_params.marketOraclePrice);
        OracleTestnet(marketOracle).transferOwnership(_params.owner);

        address marketIrm = address(
            new AdaptiveCurveIrm(
                AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                    curveSteepness: 4 ether,
                    adjustmentSpeed: 50 ether / YEAR,
                    targetUtilization: 0.8 ether,
                    initialRateAtTarget: 0.04 ether / YEAR,
                    minRateAtTarget: 0.001e18 / YEAR,
                    maxRateAtTarget: 2 ether / YEAR
                }),
                _params.owner
            )
        );

        address market = address(new AltoBorrowMarket());

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        // Create liquidation engine before market initialization
        // Use address(this) as owner so we can set the configuration before transferring ownership
        address liquidationEngine = address(new AltoLiquidationEngine(address(this)));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: _params.borrowToken,
            collateralToken: _params.collateralToken,
            irm: marketIrm,
            owner: _params.owner,
            oracle: marketOracle,
            maxLtv: _params.maxLtv,
            feeRecipient: _params.owner,
            liquidationEngine: liquidationEngine
        });

        BorrowMarketInitParams memory initParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            initialBorrowOpeningFee: 0.005 ether,
            supplyCapAssets: _params.supplyCapAssets
        });

        address marketProxy =
            UnsafeUpgrades.deployUUPSProxy(address(market), abi.encodeCall(AltoBorrowMarket.initialize, (initParams)));

        // Now set liquidation configuration
        AltoLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

        // Transfer ownership to the actual owner (initiate two-step transfer)
        Ownable2Step(liquidationEngine).transferOwnership(_params.owner);

        report = TestnetMarketBatchReport({
            marketImplementation: market,
            market: marketProxy,
            marketIrm: marketIrm,
            marketOracle: marketOracle,
            liquidationEngine: liquidationEngine
        });
    }

    function getMarketReport() public view returns (TestnetMarketBatchReport memory) {
        return report;
    }
}

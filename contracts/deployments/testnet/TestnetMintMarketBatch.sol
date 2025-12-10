// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {MintMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {ITestnetMarketBatch, TestnetMarketBatchReport} from "./ITestnetMarketBatch.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";

struct TestnetMintMarketBatchParams {
    address owner;
    address collateralToken;
    address borrowToken;
    uint256 marketOraclePrice;
    uint256 maxLtv;
    uint256 debtCeiling;
    uint256 fixedRateIrmInterestRate;
    address leverageAddress;
}

int256 constant YEAR = int256(365 days);

/// @title TestnetMintMarketBatch
/// @notice Deploy testnet market
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TestnetMintMarketBatch is ITestnetMarketBatch {
    TestnetMarketBatchReport public report;

    constructor(TestnetMintMarketBatchParams memory _params) {
        address marketOracle = address(new OracleTestnet(address(this)));
        OracleTestnet(marketOracle).setPrice(_params.marketOraclePrice);
        OracleTestnet(marketOracle).transferOwnership(_params.owner);

        address marketIrm;

        if (_params.fixedRateIrmInterestRate > 0) {
            marketIrm = address(new FixedRateIrm(_params.fixedRateIrmInterestRate, _params.owner));
        } else {
            marketIrm = address(
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
        }

        address market = address(new AltoMintMarket());

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
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(address(this)));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: _params.borrowToken,
            collateralToken: _params.collateralToken,
            irm: marketIrm,
            owner: address(this),
            oracle: marketOracle,
            maxLtv: _params.maxLtv,
            feeRecipient: _params.owner,
            liquidationEngine: liquidationEngine
        });

        MintMarketInitParams memory initParams = MintMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            debtCeiling: _params.debtCeiling,
            initialBorrowOpeningFee: 0.005 ether
        });

        address marketProxy =
            UnsafeUpgrades.deployUUPSProxy(address(market), abi.encodeCall(AltoMintMarket.initialize, (initParams)));

        // Now set liquidation configuration
        DlbDcfPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

        // Transfer ownership to the actual owner (initiate two-step transfer)
        AltoOwnable2Step(liquidationEngine).transferOwnershipSkip2Step(_params.owner);

        IMarket(marketProxy).setAuthorizedCallback(_params.leverageAddress, true);
        AltoOwnable2Step(marketProxy).transferOwnershipSkip2Step(_params.owner);

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

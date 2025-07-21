// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LendingReport} from "../interfaces/IAltoReport.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";

abstract contract LendingProcedure {
    function _deployBorrowMarket(
        address owner,
        address collateralToken,
        address borrowToken,
        address irm,
        address oracle
    ) internal returns (address) {
        return MarketDeployer.deployBorrowMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            0.005 ether,
            owner,
            LiquidationConfiguration({
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
            })
        );
    }

    function _deployMintMarket(address owner, address collateralToken, address borrowToken, address irm, address oracle)
        internal
        returns (address)
    {
        return MarketDeployer.deployMintMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            3_000_000 ether,
            owner,
            0.005 ether,
            LiquidationConfiguration({
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
            })
        );
    }
}

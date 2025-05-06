// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoBorrowMarket} from "@alto-monorepo/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto-monorepo/lending/AltoMintMarket.sol";
import {LendingReport} from "../interfaces/IAltoReport.sol";
import {ORACLE_PRICE_PRECISION} from "@alto-monorepo/lending/interfaces/IOracle.sol";
import {LiquidationConfiguration} from "@alto-monorepo/lending/AltoBorrowMarket.sol";

abstract contract LendingProcedure {
    function _deployLending(
        address owner,
        address collateralTokenBorrowMarket,
        address collateralTokenMintMarket,
        address borrowToken,
        address borrowIrm,
        address borrowOracle,
        address mintIrm,
        address mintOracle
    ) internal returns (LendingReport memory report) {
        report.borrowMarket = address(
            new AltoBorrowMarket(
                address(borrowToken),
                address(collateralTokenBorrowMarket),
                address(borrowIrm),
                owner,
                address(borrowOracle),
                0.75 ether,
                LiquidationConfiguration({
                    maxLiquidationLtv: 0.8 ether,
                    dynamicBonusFeeStart: 0.03 ether,
                    ltvForCompleteLiquidation: 0.9 ether,
                    dynamicBonusFeeDecaySteepness: 5 ether,
                    liquidationBaseFee: 0.05 ether,
                    minPenaltyPercentage: 0.01 ether
                })
            )
        );
        report.mintMarket = address(
            new AltoMintMarket(
                address(borrowToken),
                address(collateralTokenMintMarket),
                address(mintIrm),
                owner,
                address(mintOracle),
                0.75 ether,
                3_000_000 ether,
                owner,
                LiquidationConfiguration({
                    maxLiquidationLtv: 0.8 ether,
                    dynamicBonusFeeStart: 0.03 ether,
                    ltvForCompleteLiquidation: 0.9 ether,
                    dynamicBonusFeeDecaySteepness: 5 ether,
                    liquidationBaseFee: 0.05 ether,
                    minPenaltyPercentage: 0.01 ether
                })
            )
        );
    }
}

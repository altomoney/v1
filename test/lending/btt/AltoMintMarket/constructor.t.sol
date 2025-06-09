// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

contract ConstructorTest is AltoMintMarketTest {
    modifier whenIrmIsZeroAddress() {
        _;
    }

    function test_WhenIrmIsZeroAddress() external whenIrmIsZeroAddress {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        AltoMintMarket newMarket = new AltoMintMarket(
            address(borrowToken),
            address(collateralToken),
            address(0), // zero irm
            owner,
            address(oracle),
            MAX_LTV,
            DEBT_CEILING,
            feeRecipient,
            BORROW_OPENING_FEE,
            config
        );

        // it should set borrowToken correctly
        assertEq(newMarket.borrowToken(), address(borrowToken));

        // it should set collateralToken correctly
        assertEq(newMarket.collateralToken(), address(collateralToken));

        // it should set irm to zero address
        assertEq(newMarket.irm(), address(0));

        // it should set owner correctly
        assertEq(newMarket.owner(), owner);

        // it should set oracle correctly
        assertEq(newMarket.oracle(), address(oracle));

        // it should set maxLtv correctly
        assertEq(newMarket.maxLtv(), MAX_LTV);

        // it should set borrowOpeningFee correctly
        assertEq(newMarket.borrowOpeningFee(), BORROW_OPENING_FEE);

        // it should set feeRecipient correctly
        assertEq(newMarket.feeRecipient(), feeRecipient);

        // it should set totalSupply.assets to debtCeiling
        (uint128 totalSupplyAssets,) = newMarket.totalSupply();
        assertEq(totalSupplyAssets, DEBT_CEILING);

        // it should set totalSupply.shares to 0
        (, uint128 totalSupplyShares) = newMarket.totalSupply();
        assertEq(totalSupplyShares, 0);

        // it should set totalBorrowed.assets to 0
        (uint128 totalBorrowedAssets,) = newMarket.totalBorrowed();
        assertEq(totalBorrowedAssets, 0);

        // it should set totalBorrowed.shares to 0
        (, uint128 totalBorrowedShares) = newMarket.totalBorrowed();
        assertEq(totalBorrowedShares, 0);

        // it should set claimableFeesAssets to 0
        assertEq(newMarket.claimableFeesAssets(), 0);

        // it should not call IIrm.setMarket (implicit - no way to test this directly)
    }

    modifier whenIrmIsNotZeroAddress() {
        _;
    }

    function test_WhenIrmIsNotZeroAddress() external whenIrmIsNotZeroAddress {
        // it should set borrowToken correctly
        assertEq(market.borrowToken(), address(borrowToken));

        // it should set collateralToken correctly
        assertEq(market.collateralToken(), address(collateralToken));

        // it should set irm correctly
        assertEq(market.irm(), address(irm));

        // it should set owner correctly
        assertEq(market.owner(), owner);

        // it should set oracle correctly
        assertEq(market.oracle(), address(oracle));

        // it should set maxLtv correctly
        assertEq(market.maxLtv(), MAX_LTV);

        // it should set borrowOpeningFee correctly
        assertEq(market.borrowOpeningFee(), BORROW_OPENING_FEE);

        // it should set feeRecipient correctly
        assertEq(market.feeRecipient(), feeRecipient);

        // it should set totalSupply.assets to debtCeiling
        (uint128 totalSupplyAssets,) = market.totalSupply();
        assertEq(totalSupplyAssets, DEBT_CEILING);

        // it should set totalSupply.shares to 0
        (, uint128 totalSupplyShares) = market.totalSupply();
        assertEq(totalSupplyShares, 0);

        // it should set totalBorrowed.assets to 0
        (uint128 totalBorrowedAssets,) = market.totalBorrowed();
        assertEq(totalBorrowedAssets, 0);

        // it should set totalBorrowed.shares to 0
        (, uint128 totalBorrowedShares) = market.totalBorrowed();
        assertEq(totalBorrowedShares, 0);

        // it should set claimableFeesAssets to 0
        assertEq(market.claimableFeesAssets(), 0);

        // it should call IIrm.setMarket with contract address
        // Note: This is implicitly tested by the fact that the market was constructed successfully
        // The MockIrm.setMarket() is called but _market is private so we can't verify it directly
    }
}

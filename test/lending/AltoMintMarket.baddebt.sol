// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MarketCommon, MarketType} from "../lending/btt/Markets/MarketCommon.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    IDcfDlbPriorityLiquidationEngine
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract MintBadDebtPoC is MarketCommon {
    AltoMintMarket internal mintMarket;
    IMintableERC20 internal mintToken;

    uint256 internal constant HIGH_PRICE = 1000 * LENDING_ORACLE_PRICE_PRECISION; // 1000 borrow tokens per collateral
    uint256 internal constant BORROW_AMOUNT = 750 ether;
    uint256 internal constant SMALL_COLLATERAL = 1 ether;
    uint256 internal constant DEBT_CEILING = 1000 ether;

    constructor() MarketCommon(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
        mintToken = IMintableERC20(mintMarket.borrowToken());

        vm.prank(OWNER);
        mintMarket.setDebtCeiling(DEBT_CEILING);

        // Fund actors with collateral and approvals for convenience
        deal(address(collateralToken), USER, SMALL_COLLATERAL);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);

        deal(address(collateralToken), USER_2, SMALL_COLLATERAL);
        vm.prank(USER_2);
        collateralToken.approve(address(market), type(uint256).max);
    }

    /// @dev Verifies that bad debt is tracked and incorporated into the debt ceiling check,
    /// preventing reminting beyond the effective capacity after a bad debt write-off.
    /// The fix adds a badDebtAssets accumulator that reduces available borrowing capacity.
    function test_BadDebtWriteOffReducesDebtCeilingCapacity() external {
        // Inflate oracle price so a tiny collateral position can draw a large mint
        vm.prank(OWNER);
        oracle.setPrice(HIGH_PRICE);

        vm.prank(USER);
        market.addCollateral(SMALL_COLLATERAL, USER);

        vm.prank(USER);
        market.borrow(BORROW_AMOUNT, 0, USER, USER, "");

        uint256 supplyAfterBorrow = mintToken.totalSupply();
        assertEq(supplyAfterBorrow, BORROW_AMOUNT, "initial mint supply");

        // Crash price to make the position hopelessly undercollateralized
        vm.prank(OWNER);
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        // Hand the liquidator a single token to cover the small repay amount liquidation will ask for
        vm.prank(USER);
        mintToken.transfer(LIQUIDATOR, 1 ether);
        vm.prank(LIQUIDATOR);
        mintToken.approve(address(market), type(uint256).max);

        // Tag the position for liquidation and wait out the grace window
        address liquidationEngine = mintMarket.liquidationEngine();
        vm.prank(LIQUIDATOR);
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).tagLiquidablePosition(USER, LIQUIDATOR);
        vm.warp(block.timestamp + 6 minutes);

        // Liquidation seizes all collateral and writes off the remaining debt as bad debt
        // Check that BadDebtAccrued event is emitted (value will be verified after)
        vm.expectEmit(true, false, false, false);
        emit AltoMintMarket.BadDebtAccrued(0); // Asserts that bad debt is accrued and event is emitted

        vm.prank(LIQUIDATOR);
        mintMarket.liquidate(USER, "", "");

        uint256 supplyAfterBadDebt = mintToken.totalSupply();
        (uint128 totalBorrowedAfter,) = mintMarket.totalBorrowed();
        uint128 badDebt = mintMarket.badDebtAssets();

        // Verify bad debt was accrued and event was emitted with correct value
        assertGt(badDebt, 0, "bad debt should be greater than 0");

        // Borrowed accounting is wiped while minted tokens remain outstanding
        assertEq(totalBorrowedAfter, 0, "bad debt removed from totalBorrowed");
        assertGt(supplyAfterBadDebt, 0, "orphaned minted supply persists");

        // Setup second user to attempt borrowing
        vm.prank(OWNER);
        oracle.setPrice(HIGH_PRICE);

        vm.prank(USER_2);
        market.addCollateral(SMALL_COLLATERAL, USER_2);

        // Second borrow should revert because badDebtAssets + BORROW_AMOUNT > DEBT_CEILING
        // The effective capacity is reduced by the bad debt from the first default
        vm.prank(USER_2);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(BORROW_AMOUNT, 0, USER_2, USER_2, "");

        // Verify total minted supply did not increase (second borrow was blocked)
        uint256 supplyAfterFailedBorrow = mintToken.totalSupply();
        assertEq(supplyAfterFailedBorrow, supplyAfterBadDebt, "no new tokens minted after failed borrow");

        // User can only borrow up to the remaining capacity (debtCeiling - badDebt)
        uint256 remainingCapacity = DEBT_CEILING - badDebt;
        vm.prank(USER_2);
        market.borrow(remainingCapacity, 0, USER_2, USER_2, "");

        uint256 finalSupply = mintToken.totalSupply();
        // Final supply should be: orphaned tokens from bad debt + new borrow within remaining capacity
        assertEq(finalSupply, supplyAfterBadDebt + remainingCapacity, "supply respects effective ceiling");
        assertLe(finalSupply, DEBT_CEILING, "total supply does not exceed debt ceiling");
    }
}

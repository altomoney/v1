// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoMarketBorrow} from "../borrow.t.sol";
import {MarketType} from "../MarketCommon.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

contract BorrowTestMint is AltoMarketBorrow {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    AltoMintMarket public mintMarket;

    constructor() AltoMarketBorrow(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function test_WhenOpeningFeeIsGreaterThan0()
        external
        givenValidInputs
        whenTotalBorrowedAssetsIsLessThanOrEqualToTotalSupplyAssets
    {
        uint256 openingFee = 0.05 ether;

        vm.prank(OWNER);
        AltoMintMarket(address(market)).setBorrowOpeningFee(openingFee);

        market.addCollateral(20 ether, USER);

        uint256 userBalanceBefore = borrowToken.balanceOf(USER);
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        Position memory positionBefore = market.position(USER);
        Balance memory totalBorrowedBefore = market.totalBorrowed();
        Balance memory totalSupplyBefore = market.totalSupply();

        Position memory positionBeforeFeeRecipient = market.position(FEE_RECIPIENT);

        // it should calculate shares and opening fee from assets
        uint256 expectedOpeningFeeAssets = INITIAL_BORROWED_ASSETS.multiplyWithPrecision(openingFee);
        uint256 openingFeeShares =
            expectedOpeningFeeAssets.convertToSharesUp(totalSupplyBefore.assets, totalSupplyBefore.shares);
        uint256 expectedSharesToBorrow = (INITIAL_BORROWED_ASSETS + expectedOpeningFeeAssets)
        .convertToSharesUp(totalBorrowedBefore.assets, totalBorrowedBefore.shares);

        vm.startPrank(USER);
        // it should emit Borrow event
        vm.expectEmit();
        emit IMarketEvents.Borrow(
            USER, USER, USER, INITIAL_BORROWED_ASSETS, expectedSharesToBorrow, expectedOpeningFeeAssets, 0
        );
        (uint256 addedAssets, uint256 addedShares, uint256 openingFeeAssets) =
            market.borrow(INITIAL_BORROWED_ASSETS, 0, USER, USER, "");
        vm.stopPrank();

        // it should return assets shares openingFeeAssets
        assertEq(addedAssets, INITIAL_BORROWED_ASSETS + expectedOpeningFeeAssets);
        assertEq(addedShares, expectedSharesToBorrow);
        assertEq(openingFeeAssets, expectedOpeningFeeAssets);

        Position memory positionAfter = market.position(USER);

        // it should update totalBorrowed and position
        assertEq(
            market.totalBorrowed().assets,
            totalBorrowedBefore.assets + INITIAL_BORROWED_ASSETS + expectedOpeningFeeAssets
        );
        assertEq(market.totalBorrowed().shares, totalBorrowedBefore.shares + expectedSharesToBorrow);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares + expectedSharesToBorrow);

        // it should send assets minus fee to receiver
        assertEq(borrowToken.balanceOf(USER), userBalanceBefore + INITIAL_BORROWED_ASSETS);
        assertEq(borrowToken.balanceOf(address(market)), marketBalanceBefore);

        // it should NOT update totalSupply
        assertEq(market.totalSupply().assets, totalSupplyBefore.assets);
        assertEq(market.totalSupply().shares, totalSupplyBefore.shares);

        // it should not update position
        assertEq(market.position(FEE_RECIPIENT).supplyShares, positionBeforeFeeRecipient.supplyShares);

        // it should update claimableFeesAssets
        assertEq(AltoMintMarket(address(market)).claimableFeesAssets(), expectedOpeningFeeAssets);
    }
}

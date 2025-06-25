// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

contract AltoMintMarketClaimInterest is MarketCommon {
    constructor() MarketCommon(MarketType.MINT) {}

    AltoMintMarket internal mintMarket;

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        mintMarket.claimInterest();
    }

    function test_RevertWhen_FeeRecipientIsZeroAddress() external {
        vm.startPrank(OWNER);
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        mintMarket.setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0));
        mintMarket.setFeeRecipient(address(0));
        vm.stopPrank();

        // it should revert
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        mintMarket.claimInterest();
    }

    modifier whenMarketIsNotPaused() {
        _;
    }

    function test_WhenClaimableFeesIsZero() external whenMarketIsNotPaused {
        uint256 claimableFeesAssets = mintMarket.claimableFeesAssets();

        assertEq(claimableFeesAssets, 0);

        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        uint256 claimed = mintMarket.claimInterest();

        // it should not transfer tokens
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore);

        // it should not update claimableFeesAssets
        assertEq(mintMarket.claimableFeesAssets(), 0);

        // it should return zero
        assertEq(claimed, 0);
    }

    function test_WhenClaimableFeesIsGreaterThanZero() external whenMarketIsNotPaused {
        // generate interest and fees
        deal(address(collateralToken), address(this), 100 ether);

        market.addCollateral(100 ether, USER);

        vm.prank(OWNER);
        mintMarket.setDebtCeiling(100 ether);

        mintMarket.borrow(70 ether, 0, USER, USER, "");

        vm.warp(block.timestamp + 365 days);

        market.accrueInterest();

        uint256 claimableFeesAssetsBefore = mintMarket.claimableFeesAssets();

        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        uint256 claimed = mintMarket.claimInterest();

        // it should mint tokens to fee recipient and set claimableFeesAssets to zero
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesAssetsBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);

        // it should return the amount of interest claimed
        assertEq(claimed, claimableFeesAssetsBefore);
    }
}

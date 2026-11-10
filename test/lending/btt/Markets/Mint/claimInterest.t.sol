// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";

contract AltoMintMarketClaimInterest is MarketCommon {
    constructor() MarketCommon(MarketType.MINT) {}

    AltoMintMarket internal mintMarket;

    modifier whenMarketIsPaused() {
        vm.prank(PAUSER);
        market.pause(PAUSE_TYPE, true);
        _;
    }

    modifier whenMarketIsNotPaused() {
        _;
    }

    modifier whenFeeRecipientIsZero() {
        vm.startPrank(OWNER);
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0), false);
        mintMarket.setFeeRecipient(address(0));
        vm.stopPrank();
        _;
    }

    modifier whenInterestIsGreaterThanClaimableFees() {
        _generateClaimableFees();
        _;
    }

    modifier whenInterestPassedInIsZero() {
        _generateClaimableFees();
        _;
    }

    modifier whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees() {
        _generateClaimableFees();
        _;
    }

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function _generateClaimableFees() internal {
        deal(address(collateralToken), address(this), 100 ether);
        market.addCollateral(100 ether, USER);

        vm.prank(OWNER);
        mintMarket.setDebtCeiling(100 ether);

        mintMarket.borrow(70 ether, 0, USER, USER, "");

        vm.warp(block.timestamp + 365 days);
        market.accrueInterest();
    }

    function test_RevertWhen_MarketIsPaused() external whenMarketIsPaused {
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        mintMarket.claimInterest(0);
    }

    function test_RevertWhen_FeeRecipientIsZero() external whenFeeRecipientIsZero {
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        mintMarket.claimInterest(0);
    }

    function test_RevertWhen_InterestIsGreaterThanClaimableFees() external whenInterestIsGreaterThanClaimableFees {
        uint256 claimableFees = mintMarket.claimableFeesAssets();
        uint256 excessiveInterest = claimableFees + 1;

        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        mintMarket.claimInterest(excessiveInterest);
    }

    function test_WhenInterestPassedInIsZero() external whenMarketIsNotPaused whenInterestPassedInIsZero {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore);

        uint256 claimed = mintMarket.claimInterest(0);

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2;
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(interestToClaim);

        uint256 claimed = mintMarket.claimInterest(interestToClaim);

        assertGt(interestToClaim, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + interestToClaim);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestEqualsClaimableFees()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore);

        uint256 claimed = mintMarket.claimInterest(claimableFeesBefore);

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }
}

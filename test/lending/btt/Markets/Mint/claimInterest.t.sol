// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors, InterestFeeConfig} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {AltoLiquidationEngine} from "@alto/lending/AltoLiquidationEngine.sol";
import {IPriorityLiquidationEngine} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract AltoMintMarketClaimInterest is MarketCommon {
    using FixedPointMath for uint256;

    constructor() MarketCommon(MarketType.MINT) {}

    AltoMintMarket internal mintMarket;

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    modifier whenCallerIsFeeRecipient() {
        vm.startPrank(FEE_RECIPIENT);
        _;
        vm.stopPrank();
    }

    modifier whenCallerIsNotOwnerNorFeeRecipient() {
        vm.startPrank(USER);
        _;
        vm.stopPrank();
    }

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
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        AltoLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0), false);
        mintMarket.setFeeRecipient(address(0));
        vm.stopPrank();
        _;
    }

    modifier whenInterestIsGreaterThanClaimableFees() {
        // Generate some claimable fees first
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

    modifier givenInterestFeeFeeIsZero() {
        vm.startPrank(OWNER);
        market.setInterestFeeConfig(InterestFeeConfig({recipient: address(0), fee: 0}));
        vm.stopPrank();
        _;
    }

    modifier givenInterestFeeFeeIsNonZero() {
        address interestFeeRecipient = makeAddr("InterestFeeRecipient");
        vm.startPrank(OWNER);
        market.setInterestFeeConfig(InterestFeeConfig({recipient: interestFeeRecipient, fee: 0.1 ether})); // 10% fee
        vm.stopPrank();
        _;
    }

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function _generateClaimableFees() internal {
        // Generate interest and fees by borrowing and letting time pass
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
        vm.startPrank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        mintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_RevertWhen_InterestIsGreaterThanClaimableFees() external whenInterestIsGreaterThanClaimableFees {
        uint256 claimableFees = mintMarket.claimableFeesAssets();
        uint256 excessiveInterest = claimableFees + 1;

        vm.startPrank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        mintMarket.claimInterest(excessiveInterest);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotOwnerNorFeeRecipient() external whenMarketIsNotPaused {
        vm.startPrank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        mintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_WhenInterestPassedInIsZero_GivenInterestFeeFeeIsZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, 0);

        vm.startPrank(OWNER);
        uint256 claimed = mintMarket.claimInterest(0);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestPassedInIsZero_GivenInterestFeeFeeIsZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, 0);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = mintMarket.claimInterest(0);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestPassedInIsZero_GivenInterestFeeFeeIsNonZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeFeeIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = claimableFeesBefore.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = claimableFeesBefore - expectedFeeAmount;

        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, expectedFeeAmount);

        vm.startPrank(OWNER);
        uint256 claimed = mintMarket.claimInterest(0);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertGt(expectedFeeAmount, 0);
        assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), feeRecipientBalanceBefore + expectedRemainingAmount);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestPassedInIsZero_GivenInterestFeeFeeIsNonZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeFeeIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = claimableFeesBefore.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = claimableFeesBefore - expectedFeeAmount;

        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, expectedFeeAmount);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = mintMarket.claimInterest(0);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertGt(expectedFeeAmount, 0);
        assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), feeRecipientBalanceBefore + expectedRemainingAmount);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees_GivenInterestFeeFeeIsZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2; // Claim half
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(interestToClaim, 0);

        vm.startPrank(OWNER);
        uint256 claimed = mintMarket.claimInterest(interestToClaim);
        vm.stopPrank();

        assertGt(interestToClaim, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + interestToClaim);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees_GivenInterestFeeFeeIsZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2; // Claim half
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(interestToClaim, 0);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = mintMarket.claimInterest(interestToClaim);
        vm.stopPrank();

        assertGt(interestToClaim, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + interestToClaim);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees_GivenInterestFeeFeeIsNonZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2; // Claim half
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = interestToClaim.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = interestToClaim - expectedFeeAmount;

        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(interestToClaim, expectedFeeAmount);

        vm.startPrank(OWNER);
        uint256 claimed = mintMarket.claimInterest(interestToClaim);
        vm.stopPrank();

        assertGt(interestToClaim, 0);
        assertGt(expectedFeeAmount, 0);
        assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), feeRecipientBalanceBefore + expectedRemainingAmount);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees_GivenInterestFeeFeeIsNonZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2; // Claim half
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = interestToClaim.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = interestToClaim - expectedFeeAmount;

        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(interestToClaim, expectedFeeAmount);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = mintMarket.claimInterest(interestToClaim);
        vm.stopPrank();

        assertGt(interestToClaim, 0);
        assertGt(expectedFeeAmount, 0);
        assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), feeRecipientBalanceBefore + expectedRemainingAmount);
        assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestEqualsClaimableFees_GivenInterestFeeFeeIsZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, 0);

        vm.startPrank(OWNER);
        uint256 claimed = mintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestEqualsClaimableFees_GivenInterestFeeFeeIsZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, 0);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = mintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestEqualsClaimableFees_GivenInterestFeeFeeIsNonZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = claimableFeesBefore.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = claimableFeesBefore - expectedFeeAmount;

        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, expectedFeeAmount);

        vm.startPrank(OWNER);
        uint256 claimed = mintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertGt(expectedFeeAmount, 0);
        assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), feeRecipientBalanceBefore + expectedRemainingAmount);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestEqualsClaimableFees_GivenInterestFeeFeeIsNonZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
        givenInterestFeeFeeIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = claimableFeesBefore.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = claimableFeesBefore - expectedFeeAmount;

        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.InterestClaimed(claimableFeesBefore, expectedFeeAmount);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = mintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertGt(expectedFeeAmount, 0);
        assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), feeRecipientBalanceBefore + expectedRemainingAmount);
        assertEq(mintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }
}

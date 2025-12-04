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

    modifier whenInterestPassedInIsNonZeroAndLessThanClaimableFees() {
        _generateClaimableFees();
        _;
    }

    modifier whenFeeRecipientIsZeroAndInterestFeeRecipientIsZero() {
        _generateClaimableFees();
        vm.startPrank(OWNER);
        LiquidationConfiguration memory liquidationConfiguration =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        AltoLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0), true);
        mintMarket.setFeeRecipient(address(0));
        market.setInterestFeeConfig(InterestFeeConfig({recipient: address(0), fee: 0}));
        vm.stopPrank();
        _;
    }

    modifier whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero() {
        _generateClaimableFees();
        address interestFeeRecipient = makeAddr("InterestFeeRecipient");
        vm.startPrank(OWNER);
        LiquidationConfiguration memory liquidationConfiguration =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        AltoLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0), true);
        mintMarket.setFeeRecipient(address(0));
        market.setInterestFeeConfig(InterestFeeConfig({recipient: interestFeeRecipient, fee: 0.1 ether})); // 10% fee
        vm.stopPrank();
        _;
    }

    modifier whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZeroButFeeIsZero() {
        _generateClaimableFees();
        address interestFeeRecipient = makeAddr("InterestFeeRecipient");
        vm.startPrank(OWNER);
        LiquidationConfiguration memory liquidationConfiguration =
            IPriorityLiquidationEngine(market.liquidationEngine()).liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        AltoLiquidationEngine(market.liquidationEngine()).setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0), true);
        mintMarket.setFeeRecipient(address(0));
        market.setInterestFeeConfig(InterestFeeConfig({recipient: interestFeeRecipient, fee: 0})); // fee is zero but recipient is set
        vm.stopPrank();
        _;
    }

    modifier givenInterestFeeIsZero() {
        vm.startPrank(OWNER);
        market.setInterestFeeConfig(InterestFeeConfig({recipient: address(0), fee: 0}));
        vm.stopPrank();
        _;
    }

    modifier givenInterestFeeIsNonZero() {
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

    function test_RevertWhen_ClaimableFeesAssetsIsZero() external {
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

    function test_RevertWhen_FeeRecipientIsZeroAndInterestFeeRecipientIsZero()
        external
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsZero
    {
        vm.startPrank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        mintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_RevertWhen_FeeRecipientIsNonZero_CallerIsNotOwnerNorFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
    {
        vm.startPrank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        mintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_WhenFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeIsZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeIsZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeIsZero_WhenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeIsZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeIsNonZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeIsNonZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeFeeIsNonZero_WhenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
        givenInterestFeeIsNonZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeIsZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanClaimableFees
        givenInterestFeeIsZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeIsZero_WhenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanClaimableFees
        givenInterestFeeIsZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeIsNonZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanClaimableFees
        givenInterestFeeIsNonZero
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

    function test_WhenFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeFeeIsNonZero_WhenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanClaimableFees
        givenInterestFeeIsNonZero
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

    // Tests for when feeRecipient is zero and interestFee.recipient is non-zero
    function test_RevertWhen_FeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_CallerIsNotOwnerNorInterestFeeRecipient()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero
    {
        vm.startPrank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        mintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeFeeIsNonZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = claimableFeesBefore.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = claimableFeesBefore - expectedFeeAmount;

        // When feeRecipient is zero and there's a remaining amount, contract will try to mint to address(0) and revert
        if (expectedRemainingAmount > 0) {
            vm.startPrank(OWNER);
            vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
            mintMarket.claimInterest(0);
            vm.stopPrank();
        } else {
            // If fee is 100%, no remaining amount, so it should succeed
            uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);
            vm.startPrank(OWNER);
            uint256 claimed = mintMarket.claimInterest(0);
            vm.stopPrank();

            assertGt(claimableFeesBefore, 0);
            assertGt(expectedFeeAmount, 0);
            assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
            assertEq(mintMarket.claimableFeesAssets(), 0);
            assertEq(claimed, claimableFeesBefore);
        }
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeFeeIsNonZero_WhenCallerIsInterestFeeRecipient()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = claimableFeesBefore.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = claimableFeesBefore - expectedFeeAmount;

        // When feeRecipient is zero and there's a remaining amount, contract will try to mint to address(0) and revert
        if (expectedRemainingAmount > 0) {
            vm.startPrank(interestFeeRecipient);
            vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
            mintMarket.claimInterest(claimableFeesBefore);
            vm.stopPrank();
        } else {
            // If fee is 100%, no remaining amount, so it should succeed
            uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);
            vm.startPrank(interestFeeRecipient);
            uint256 claimed = mintMarket.claimInterest(claimableFeesBefore);
            vm.stopPrank();

            assertGt(claimableFeesBefore, 0);
            assertGt(expectedFeeAmount, 0);
            assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
            assertEq(mintMarket.claimableFeesAssets(), 0);
            assertEq(claimed, claimableFeesBefore);
        }
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeFeeIsNonZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2;
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = interestToClaim.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = interestToClaim - expectedFeeAmount;

        // When feeRecipient is zero and there's a remaining amount, contract will try to mint to address(0) and revert
        if (expectedRemainingAmount > 0) {
            vm.startPrank(OWNER);
            vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
            mintMarket.claimInterest(interestToClaim);
            vm.stopPrank();
        } else {
            // If fee is 100%, no remaining amount, so it should succeed
            uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);
            vm.startPrank(OWNER);
            uint256 claimed = mintMarket.claimInterest(interestToClaim);
            vm.stopPrank();

            assertGt(interestToClaim, 0);
            assertGt(expectedFeeAmount, 0);
            assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
            assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
            assertEq(claimed, interestToClaim);
        }
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeFeeIsNonZero_WhenCallerIsInterestFeeRecipient()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2;
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRate = market.interestFee().fee;
        uint256 expectedFeeAmount = interestToClaim.multiplyWithPrecision(feeRate);
        uint256 expectedRemainingAmount = interestToClaim - expectedFeeAmount;

        // When feeRecipient is zero and there's a remaining amount, contract will try to mint to address(0) and revert
        if (expectedRemainingAmount > 0) {
            vm.startPrank(interestFeeRecipient);
            vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
            mintMarket.claimInterest(interestToClaim);
            vm.stopPrank();
        } else {
            // If fee is 100%, no remaining amount, so it should succeed
            uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);
            vm.startPrank(interestFeeRecipient);
            uint256 claimed = mintMarket.claimInterest(interestToClaim);
            vm.stopPrank();

            assertGt(interestToClaim, 0);
            assertGt(expectedFeeAmount, 0);
            assertEq(borrowToken.balanceOf(interestFeeRecipient), interestFeeRecipientBalanceBefore + expectedFeeAmount);
            assertEq(mintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
            assertEq(claimed, interestToClaim);
        }
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeFeeIsZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZeroButFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        // When feeRecipient is zero and interestFee.fee is zero, contract will try to mint to address(0) and revert
        vm.startPrank(OWNER);
        vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
        mintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestPassedInIsZeroOrEqualsClaimableFees_GivenInterestFeeFeeIsZero_WhenCallerIsInterestFeeRecipient()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZeroButFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        // When feeRecipient is zero and interestFee.fee is zero, contract will try to mint to address(0) and revert
        vm.startPrank(interestFeeRecipient);
        vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
        mintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeFeeIsZero_WhenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZeroButFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2;
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        // When feeRecipient is zero and interestFee.fee is zero, contract will try to mint to address(0) and revert
        vm.startPrank(OWNER);
        vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
        mintMarket.claimInterest(interestToClaim);
        vm.stopPrank();
    }

    function test_WhenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZero_WhenInterestIsNonZeroAndLessThanClaimableFees_GivenInterestFeeFeeIsZero_WhenCallerIsInterestFeeRecipient()
        external
        whenMarketIsNotPaused
        whenFeeRecipientIsZeroAndInterestFeeRecipientIsNonZeroButFeeIsZero
    {
        uint256 claimableFeesBefore = mintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2;
        address interestFeeRecipient = market.interestFee().recipient;
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 interestFeeRecipientBalanceBefore = borrowToken.balanceOf(interestFeeRecipient);

        // When feeRecipient is zero and interestFee.fee is zero, contract will try to mint to address(0) and revert
        vm.startPrank(interestFeeRecipient);
        vm.expectRevert(); // ERC20InvalidReceiver when trying to mint to address(0)
        mintMarket.claimInterest(interestToClaim);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../MarketCommon.t.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";
import {IMarketErrors, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

contract ClaimInterestTestDaoMint is MarketCommon {
    constructor() MarketCommon(MarketType.DAO_MINT) {}

    AltoDaoMintMarket public daoMintMarket;

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
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        daoMintMarket.setLiquidationConfiguration(liquidationConfiguration);
        daoMintMarket.setBorrowOpeningFee(0);
        daoMintMarket.setIrm(address(0), false);
        daoMintMarket.setFeeRecipient(address(0));
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

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setPublicAccessEnabled(true);
        vm.stopPrank();
    }

    function _generateClaimableFees() internal {
        // Generate interest and fees by borrowing and letting time pass
        deal(address(collateralToken), address(this), 100 ether);
        market.addCollateral(100 ether, USER);

        vm.prank(OWNER);
        daoMintMarket.setDebtCeiling(100 ether);

        daoMintMarket.borrow(70 ether, 0, USER, USER, "");

        vm.warp(block.timestamp + 365 days);
        market.accrueInterest();
    }

    function test_RevertWhen_MarketIsPaused() external whenMarketIsPaused {
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        daoMintMarket.claimInterest(0);
    }

    function test_RevertWhen_FeeRecipientIsZero() external whenFeeRecipientIsZero {
        vm.startPrank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        daoMintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_RevertWhen_InterestIsGreaterThanClaimableFees() external whenInterestIsGreaterThanClaimableFees {
        uint256 claimableFees = daoMintMarket.claimableFeesAssets();
        uint256 excessiveInterest = claimableFees + 1;

        vm.startPrank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        daoMintMarket.claimInterest(excessiveInterest);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotOwnerNorFeeRecipient() external whenMarketIsNotPaused {
        vm.startPrank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        daoMintMarket.claimInterest(0);
        vm.stopPrank();
    }

    function test_WhenInterestPassedInIsZero_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
    {
        uint256 claimableFeesBefore = daoMintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.InterestClaimed(claimableFeesBefore);

        vm.startPrank(OWNER);
        uint256 claimed = daoMintMarket.claimInterest(0);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(daoMintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestPassedInIsZero_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsZero
    {
        uint256 claimableFeesBefore = daoMintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.InterestClaimed(claimableFeesBefore);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = daoMintMarket.claimInterest(0);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(daoMintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
    {
        uint256 claimableFeesBefore = daoMintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2; // Claim half
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.InterestClaimed(interestToClaim);

        vm.startPrank(OWNER);
        uint256 claimed = daoMintMarket.claimInterest(interestToClaim);
        vm.stopPrank();

        assertGt(interestToClaim, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + interestToClaim);
        assertEq(daoMintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestIsNonZeroAndLessThanOrEqualClaimableFees_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
    {
        uint256 claimableFeesBefore = daoMintMarket.claimableFeesAssets();
        uint256 interestToClaim = claimableFeesBefore / 2; // Claim half
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.InterestClaimed(interestToClaim);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = daoMintMarket.claimInterest(interestToClaim);
        vm.stopPrank();

        assertGt(interestToClaim, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + interestToClaim);
        assertEq(daoMintMarket.claimableFeesAssets(), claimableFeesBefore - interestToClaim);
        assertEq(claimed, interestToClaim);
    }

    function test_WhenInterestEqualsClaimableFees_GivenCallerIsOwner()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
    {
        uint256 claimableFeesBefore = daoMintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.InterestClaimed(claimableFeesBefore);

        vm.startPrank(OWNER);
        uint256 claimed = daoMintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(daoMintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }

    function test_WhenInterestEqualsClaimableFees_GivenCallerIsFeeRecipient()
        external
        whenMarketIsNotPaused
        whenInterestPassedInIsNonZeroAndLessThanOrEqualClaimableFees
    {
        uint256 claimableFeesBefore = daoMintMarket.claimableFeesAssets();
        uint256 balanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);

        vm.expectEmit(true, true, true, true);
        emit AltoDaoMintMarket.InterestClaimed(claimableFeesBefore);

        vm.startPrank(FEE_RECIPIENT);
        uint256 claimed = daoMintMarket.claimInterest(claimableFeesBefore);
        vm.stopPrank();

        assertGt(claimableFeesBefore, 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), balanceBefore + claimableFeesBefore);
        assertEq(daoMintMarket.claimableFeesAssets(), 0);
        assertEq(claimed, claimableFeesBefore);
    }
}

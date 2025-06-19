// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";

contract RepayTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xCCC);
    address owner = address(this);
    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new AltoBorrowMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            0,
            owner,
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            })
        );

        // Set owner as pauser for PAUSED_MARKET
        market.setPauser(owner, PAUSED_MARKET, true);

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(borrowToken), charlie, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), charlie, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Add initial supply and set up borrowing position
        vm.startPrank(alice);
        market.addSupply(5000 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1000 ether, bob);
        market.borrow(200 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.repay(100 ether, 0, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_BothAssetsAndSharesProvided() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(100 ether, 50 ether, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(100 ether, 0, address(0));
        vm.stopPrank();
    }

    modifier givenAssetsIsProvided() {
        _;
    }

    function test_RevertWhen_AssetsIsZero() public givenAssetsIsProvided {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(0, 0, bob);
        vm.stopPrank();
    }

    modifier whenAssetsIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_UserHasInsufficientBalance() public givenAssetsIsProvided whenAssetsIsGreaterThanZero {
        vm.startPrank(charlie);
        borrowToken.transfer(alice, INITIAL_AMOUNT); // Transfer all tokens away
        vm.expectRevert();
        market.repay(100 ether, 0, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_UserHasNoBorrowPosition() public givenAssetsIsProvided whenAssetsIsGreaterThanZero {
        vm.startPrank(charlie);
        vm.expectRevert();
        market.repay(100 ether, 0, charlie);
        vm.stopPrank();
    }

    function test_RevertWhen_RepayingMoreThanBorrowed() public givenAssetsIsProvided whenAssetsIsGreaterThanZero {
        vm.startPrank(bob);
        vm.expectRevert();
        market.repay(500 ether, 0, bob); // More than the 200 ether borrowed
        vm.stopPrank();
    }

    modifier whenUserHasSufficientBalanceAndBorrowPosition() {
        _;
    }

    function test_RepayValidAmountWithAssets()
        public
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
        whenUserHasSufficientBalanceAndBorrowPosition
    {
        uint256 repayAmount = 50 ether;

        vm.startPrank(bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);
        (uint128 supplySharesBefore, uint128 borrowSharesBefore, uint128 collateralAssetsBefore) = market.position(bob);
        (uint128 totalBorrowedAssetsBefore, uint128 totalBorrowedSharesBefore) = market.totalBorrowed();

        // Repay with assets
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(repayAmount, 0, bob);

        // Verify assets were transferred from borrower
        assertEq(borrowToken.balanceOf(bob), initialBalance - repaidAssets);

        // Verify borrow position was reduced
        (uint128 supplySharesAfter, uint128 borrowSharesAfter, uint128 collateralAssetsAfter) = market.position(bob);
        assertEq(borrowSharesAfter, borrowSharesBefore - uint128(repaidShares));
        assertEq(collateralAssetsAfter, collateralAssetsBefore); // Collateral unchanged

        // Verify total borrowed was reduced
        (uint128 totalBorrowedAssetsAfter, uint128 totalBorrowedSharesAfter) = market.totalBorrowed();
        assertEq(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore - uint128(repaidAssets));
        assertEq(totalBorrowedSharesAfter, totalBorrowedSharesBefore - uint128(repaidShares));

        vm.stopPrank();
    }

    modifier givenSharesIsProvided() {
        _;
    }

    function test_RevertWhen_SharesIsZero() public givenSharesIsProvided {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.repay(0, 0, bob);
        vm.stopPrank();
    }

    modifier whenSharesIsGreaterThanZero() {
        _;
    }

    function test_RepayValidAmountWithShares() public givenSharesIsProvided whenSharesIsGreaterThanZero {
        uint256 shareAmount = 50 ether;

        vm.startPrank(bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);
        (uint128 supplySharesBefore, uint128 borrowSharesBefore, uint128 collateralAssetsBefore) = market.position(bob);
        (uint128 totalBorrowedAssetsBefore, uint128 totalBorrowedSharesBefore) = market.totalBorrowed();

        // Repay with shares
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(0, shareAmount, bob);

        // Verify assets were transferred from borrower
        assertEq(borrowToken.balanceOf(bob), initialBalance - repaidAssets);

        // Verify borrow position was reduced
        (uint128 supplySharesAfter, uint128 borrowSharesAfter, uint128 collateralAssetsAfter) = market.position(bob);
        assertEq(borrowSharesAfter, borrowSharesBefore - uint128(repaidShares));
        assertEq(collateralAssetsAfter, collateralAssetsBefore); // Collateral unchanged

        // Verify total borrowed was reduced
        (uint128 totalBorrowedAssetsAfter, uint128 totalBorrowedSharesAfter) = market.totalBorrowed();
        assertEq(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore - uint128(repaidAssets));
        assertEq(totalBorrowedSharesAfter, totalBorrowedSharesBefore - uint128(repaidShares));

        vm.stopPrank();
    }

    function test_RepayFullPosition() public {
        vm.startPrank(bob);

        // Get current borrow position
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);

        // Repay full position with shares
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(0, borrowShares, bob);

        // Verify position is cleared
        (uint128 supplySharesAfter, uint128 borrowSharesAfter, uint128 collateralAssetsAfter) = market.position(bob);
        assertEq(borrowSharesAfter, 0);
        assertEq(collateralAssetsAfter, collateralAssets); // Collateral remains

        vm.stopPrank();
    }
}

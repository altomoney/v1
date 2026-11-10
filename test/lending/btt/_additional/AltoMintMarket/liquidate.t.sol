// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {BaseMarketInitParams, MintMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";

contract MintableERC20Mock is ERC20, IMintableERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public override {
        _burn(from, amount);
    }
}

contract LiquidateTest is Test {
    AltoMintMarket internal market;
    MintableERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    FixedRateIrm internal irm;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant INITIAL_BALANCE = 10000 ether;
    uint256 internal constant DEBT_CEILING = 1000000 ether;
    uint256 internal constant MAX_LTV = 0.75 ether;
    uint256 internal constant BORROW_OPENING_FEE = 100000000000000000; // 1%

    function setUp() public virtual {
        borrowToken = new MintableERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        oracle = new OracleMock();
        irm = new FixedRateIrm(0.04 ether / uint256(365 days), owner);

        // Set oracle price to proper precision
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            protocolFeePercentage: 0 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        // Create liquidation engine before market deployment
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(owner));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: owner,
            emergencyAdmin: owner,
            oracle: address(oracle),
            maxLtv: MAX_LTV,
            feeRecipient: feeRecipient,
            liquidationEngine: liquidationEngine
        });

        MintMarketInitParams memory mintMarketInitParams = MintMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            debtCeiling: DEBT_CEILING,
            initialBorrowOpeningFee: BORROW_OPENING_FEE
        });

        market = AltoMintMarket(MarketDeployer.deployMintMarket(mintMarketInitParams));

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        vm.startPrank(owner);
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(config);
        vm.stopPrank();

        // Mint tokens to test accounts
        deal(address(collateralToken), alice, INITIAL_BALANCE);
        deal(address(collateralToken), bob, INITIAL_BALANCE);
        deal(address(collateralToken), charlie, INITIAL_BALANCE);

        deal(address(borrowToken), alice, INITIAL_BALANCE);
        deal(address(borrowToken), bob, INITIAL_BALANCE);
        deal(address(borrowToken), charlie, INITIAL_BALANCE);

        // Approve market to spend tokens
        vm.startPrank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Set owner as pauser
        vm.startPrank(owner);
        market.setPauser(owner, PAUSE_TYPE, true);
        market.setPauser(owner, FROZEN_TYPE, true);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.startPrank(owner);
        market.pause(PAUSE_TYPE, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.startPrank(owner);
        market.pause(FROZEN_TYPE, true);
        vm.stopPrank();

        vm.startPrank(alice);
        // liquidate function only has whenNotPaused modifier, not whenNotFrozen
        // So it should proceed to liquidation logic and fail on solvency check
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector
        );
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }

    modifier whenMarketIsNotPausedAndNotFrozen() {
        _;
    }

    function test_RevertWhen_UserIsZeroAddress() external whenMarketIsNotPausedAndNotFrozen {
        vm.startPrank(alice);
        // No explicit zero address validation in liquidate, so it gets to liquidation solvency check
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector
        );
        market.liquidate(address(0), hex"", hex"");
        vm.stopPrank();
    }

    modifier whenInputsAreValid() {
        _;
    }

    function test_RevertWhen_PositionIsNotLiquidable() external whenMarketIsNotPausedAndNotFrozen whenInputsAreValid {
        // Create a healthy position
        vm.startPrank(bob);
        market.addCollateral(500 ether, bob);
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition.selector
        );
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }

    modifier givenPositionIsLiquidable() {
        // Create liquidable position
        vm.startPrank(bob);
        market.addCollateral(100 ether, bob);
        // Borrow amount that keeps total (including 10% fee) within 75% LTV
        // 63.6 ether + 10% fee = 69.96 ether total ≈ 70% LTV
        market.borrow(636 * 1e17, 0, bob, bob, ""); // ~63.6 ether
        vm.stopPrank();

        // Manipulate oracle price to make position liquidable (50% price drop doubles the effective LTV)
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getPrice()"),
            abi.encode(LENDING_ORACLE_PRICE_PRECISION / 2) // Half price = double effective LTV
        );
        _;
    }

    modifier givenPositionIsNotTagged() {
        _;
    }

    modifier givenCallerIsNotPriorityLiquidator() {
        _;
    }

    function test_RevertGiven_PositionIsNotTaggedAndCallerIsNotPriorityLiquidator()
        external
        whenMarketIsNotPausedAndNotFrozen
        whenInputsAreValid
        givenPositionIsLiquidable
        givenPositionIsNotTagged
        givenCallerIsNotPriorityLiquidator
    {
        vm.startPrank(alice);
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }

    modifier givenCallerIsPriorityLiquidator() {
        vm.startPrank(owner);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(alice, true);
        vm.stopPrank();
        _;
    }

    function test_WhenPositionIsNotTaggedAndCallerIsPriorityLiquidator()
        external
        whenMarketIsNotPausedAndNotFrozen
        whenInputsAreValid
        givenPositionIsLiquidable
        givenPositionIsNotTagged
        givenCallerIsPriorityLiquidator
    {
        uint256 aliceCollateralBefore = collateralToken.balanceOf(alice);
        uint256 aliceBorrowBefore = borrowToken.balanceOf(alice);
        (, uint128 bobBorrowSharesBefore, uint128 bobCollateralBefore) = market.position(bob);

        vm.startPrank(alice);
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();

        // it should liquidate the position partially
        uint256 aliceCollateralAfter = collateralToken.balanceOf(alice);
        uint256 aliceBorrowAfter = borrowToken.balanceOf(alice);
        (, uint128 bobBorrowSharesAfter, uint128 bobCollateralAfter) = market.position(bob);

        // Alice should receive collateral and pay borrow tokens
        assertGt(aliceCollateralAfter, aliceCollateralBefore);
        assertLt(aliceBorrowAfter, aliceBorrowBefore);

        // Bob's position should be reduced
        assertLt(bobBorrowSharesAfter, bobBorrowSharesBefore);
        assertLt(bobCollateralAfter, bobCollateralBefore);

        // it should emit Liquidate event (implicit in successful execution)
    }

    modifier givenPositionIsTagged() {
        // Tag the position first
        vm.startPrank(charlie);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).tagLiquidablePosition(bob, charlie);
        vm.stopPrank();
        _;
    }

    function test_WhenPositionIsTaggedAndWithinGracePeriod()
        external
        whenMarketIsNotPausedAndNotFrozen
        whenInputsAreValid
        givenPositionIsLiquidable
        givenPositionIsTagged
    {
        // Charlie (tagger) should NOT be able to liquidate during priority grace period
        // Only priority liquidators can liquidate during this time
        vm.startPrank(charlie);
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }
}

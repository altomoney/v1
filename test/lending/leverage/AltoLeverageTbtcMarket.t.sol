// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarket, IMarketErrors, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoTbtcLendingOracle} from "@alto/oracles/lending/AltoTbtcLendingOracle.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode,
    ERC4626RatioNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {ORACLE_PRICE_PRECISION, IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {console} from "forge-std/console.sol";

contract AltoLeverageTbtcMarketTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    IERC20 constant borrowToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20 constant collateralToken = IERC20(0x18084fbA666a33d37592fA2633fD49a74DD93a88); // tBTC
    address constant SWAP_TARGET = 0x0000000000001fF3684f28c67538d4D072C22734;
    AltoLeverage leverage;
    AltoLeverageSwapper swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant REDSTONE_BTC_USD_PRICE_FEED = 0xAB7f623fb2F6fea6601D4350FA0E2290663C28Fc;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18; // 90%
    uint256 constant REDSTONE_WEIGHT = 0.1e18; // 10%
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16; // 1%
    address oracle;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");

        (, uint256 blockNumber) =
            _loadInputFromJson("test/lending/leverage/0xswapData/tbtc/data_240000_dai_to_tbtc.txt");
        vm.createSelectFork(rpcUrl, blockNumber);

        swapper = new AltoLeverageSwapper(address(this), SWAP_TARGET);
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        ChainlinkNode memory chainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 18, 18);
        RedstoneNode memory redstoneNode =
            RedstoneNode(AggregatorV3Interface(REDSTONE_BTC_USD_PRICE_FEED), 1, 26 hours, 18, 18);
        ChainlinkRedstoneNode memory chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);

        oracle = address(new AltoTbtcLendingOracle(address(this), chainlinkRedstoneNode));

        market = IMarket(
            MarketDeployer.deployBorrowMarket(
                address(borrowToken),
                address(collateralToken),
                address(irm),
                address(this),
                address(oracle),
                0.8 ether,
                0,
                address(this),
                LiquidationConfiguration({
                    maxLiquidationLtv: 0.8 ether,
                    dynamicBonusFeeStart: 0.03 ether,
                    ltvForCompleteLiquidation: 0.9 ether,
                    dynamicBonusFeeDecaySteepness: 5 ether,
                    liquidationBaseFee: 0.05 ether,
                    minPenaltyPercentage: 0.01 ether,
                    protocolFeePercentage: 0.075 ether,
                    isEnabledPriorityLiquidation: true,
                    disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                    priorityLiquidationGracePeriod: 5 minutes,
                    taggerLiquidationGracePeriod: 2 minutes,
                    liquidationWindowTag: 3 days
                })
            )
        );

        swapper.setWhitelisted(address(leverage), true);
        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        market.setAuthorizedCallback(address(leverage), true);
        // Allow market in leverage
        leverage.setMarket(address(market), true);
    }

    function testBorrowWithAltoLeverageAsRecipient() public {
        uint256 borrowAmount = 240_000 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of tBTC is around 120,000 DAI
        // with ltv of 0.8, we can borrow 120,000 * 1 * 0.8 = 96000
        // but we will borrow 240_000 due to levarage
        uint256 collateralAddAmount = 1 ether;
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/tbtc/data_240000_dai_to_tbtc.txt");

        // Prepare SwapParams
        // swap params to swap 240_000 DAI to tBTC
        // minimum expected tBTC amount is 1.9 tBTC
        SwapParams memory leverageData = SwapParams({minAmountOut: 1.9 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter, uint256 maxBorrowValueAfter, uint256 borrowValueAfter) = isSolvent(alice, address(market));

        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should have health");

        // Assert Alice's collateral increased (should be > collateralAddAmount if leverage worked)
        assertGt(
            position.collateralAssets, collateralAddAmount, "Alice's collateral should have increased due to leverage"
        );

        // Assert leverage contract has no leftover borrow tokens (if swapper mock does nothing, may still have tokens)
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function testRemoveCollateralWithAltoLeverage() public {
        // borrowing 240_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) = _loadInputFromJson("test/lending/leverage/0xswapData/tbtc/data_2_tbtc_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 2 tBTC to DAI
        // minimum expected DAI amount is 220_000  DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 220_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);

        uint256 collateralRemoveAmount = 2 ether;

        vm.prank(alice);
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));

        Position memory positionAfter = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertLt(positionAfter.borrowShares, position.borrowShares, "Alice's borrow shares should decrease");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");

        assertEq(
            positionAfter.collateralAssets + collateralRemoveAmount,
            position.collateralAssets,
            "Alice's collateral should be decreased by the amount of collateral removed"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function testRemoveCollateralWithAltoLeverage_repay_more_than_borrowed() public {
        // borrow 240_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) = _loadInputFromJson("test/lending/leverage/0xswapData/tbtc/data_2.5_tbtc_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 2.5 tBTC to DAI
        // minimum expected DAI amount is 280_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 280_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);
        uint256 aliceBorrowTokenBalanceBefore = borrowToken.balanceOf(alice);

        vm.prank(alice);
        uint256 collateralRemoveAmount = 2.5 ether;
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);
        uint256 aliceBorrowTokenBalanceAfter = borrowToken.balanceOf(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertEq(positionAfter.borrowShares, 0, "Alice's borrow shares should be zero");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");
        assertEq(
            positionAfter.collateralAssets + collateralRemoveAmount,
            position.collateralAssets,
            "Alice's collateral should be decreased by the amount of collateral removed"
        );
        assertGt(
            aliceBorrowTokenBalanceAfter,
            aliceBorrowTokenBalanceBefore,
            "Alice should receive the extra token returned by the AltoLeverage swap"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function testSendExtraBorrowTokensToSender() public {
        // borrow 120_000 DAI
        uint256 borrowAmount = 120_000 ether;
        uint256 leftOverAmount = 20_000 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        uint256 collateralAddAmount = 1 ether;
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/tbtc/data_100000_dai_to_tbtc.txt");

        // Prepare SwapParams
        // swap params to swap 100_000 DAI to tBTC
        // minimum expected tBTC amount is 0.85 tBTC
        // since 120_000 DAI is borrowed, 20_000 DAI will be leftover
        SwapParams memory leverageData = SwapParams({minAmountOut: 0.85 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);
        (, uint256 maxBorrowValue, uint256 borrowValue) = isSolvent(alice, address(market));

        uint256 borrowTokenBalanceOfAliceBefore = borrowToken.balanceOf(alice);

        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter, uint256 maxBorrowValueAfter, uint256 borrowValueAfter) = isSolvent(alice, address(market));

        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should have health");

        // Assert Alice's collateral increased (should be > collateralAddAmount if leverage worked)
        assertGt(
            position.collateralAssets, collateralAddAmount, "Alice's collateral should have increased due to leverage"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should remain same balance as before");
        assertEq(
            borrowToken.balanceOf(alice),
            borrowTokenBalanceOfAliceBefore + leftOverAmount,
            "Alice should receive leftover tokens"
        );
    }

    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of tBTC is around 120,000 DAI
        // with ltv of 0.8, we can borrow 120_000 * 1 * 0.8 = 96000
        // but we will borrow 600_000 due to levarage
        uint256 collateralAddAmount = 1 ether;
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/tbtc/data_600000_dai_to_tbtc.txt");

        // Prepare SwapParams
        // swap params to swap 600_000 DAI to tBTC
        // minimum expected tBTC amount is 5 tBTC
        SwapParams memory leverageData = SwapParams({minAmountOut: 5 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        vm.prank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(600_000 ether, 0, alice, address(leverage), data);

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function isSolvent(address user, address _market) internal view returns (bool, uint256 max, uint256 current) {
        uint256 collateralPrice = IOracle(oracle).getPrice();
        uint256 collateralValue = uint256(IMarket(_market).position(user).collateralAssets).divideWithRounding(
            collateralPrice, ORACLE_PRICE_PRECISION, false
        );
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(IMarket(_market).maxLtv());
        uint256 borrowValue = uint256(IMarket(_market).position(user).borrowShares).convertToAssetsUp(
            IMarket(_market).totalBorrowed().assets, IMarket(_market).totalBorrowed().shares
        );

        return (maxBorrowValue >= borrowValue, maxBorrowValue, borrowValue);
    }

    function _loadInputFromJson(string memory fileName) internal returns (bytes memory swapData, uint256 blockNumber) {
        string memory json = vm.readFile(fileName);

        swapData = vm.parseJsonBytes(json, ".transaction.data");
        blockNumber = vm.parseJsonUint(json, ".blockNumber");
    }
}

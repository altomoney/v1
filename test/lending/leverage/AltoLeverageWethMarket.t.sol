// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {LENDING_ORACLE_PRICE_PRECISION, IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket, Position, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {console} from "forge-std/console.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {AltoLiquidationEngine} from "@alto/lending/AltoLiquidationEngine.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoLeverageWethMarketTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    IERC20 constant borrowToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20 constant collateralToken = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    address constant SWAP_TARGET = 0x0000000000001fF3684f28c67538d4D072C22734;
    AltoLeverage leverage;
    AltoLeverageSwapper swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address oracle;
    ChainlinkNode[] public chainlinkNodes;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        (, uint256 blockNumber) = _loadInputFromJson("test/lending/leverage/0xswapData/weth/data_100_weth_to_dai.txt");
        vm.createSelectFork(rpcUrl, blockNumber);

        swapper = new AltoLeverageSwapper(address(this), SWAP_TARGET);
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        ChainlinkNode memory chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        chainlinkNodes.push(chainlinkNode);
        oracle = address(new AltoMultiChainlinkLendingOracle(address(this), chainlinkNodes));

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
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
        });

        // Create liquidation engine before market deployment
        address liquidationEngine = address(new AltoLiquidationEngine(address(this)));

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(borrowToken),
                collateralToken: address(collateralToken),
                irm: address(irm),
                owner: address(this),
                oracle: address(oracle),
                maxLtv: 0.8 ether,
                feeRecipient: address(this),
                liquidationEngine: liquidationEngine
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0
        });

        market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        AltoLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

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
        uint256 borrowAmount = 600_000 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(INITIAL_AMOUNT, 0, alice);
        // price of ETH is around 4200 USD
        // with ltv of 0.8, we can borrow 4200 * 100 * 0.8 = 336000
        // but we will borrow 600_000 due to levarage
        market.addCollateral(100 ether, alice);
        vm.stopPrank();

        // Prepare SwapParams
        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/weth/data_600000_dai_to_weth.txt");

        // swap params to swap 600_000 DAI to WETH
        // minumum expected ETH amount is 135 ETH
        SwapParams memory leverageData = SwapParams({minAmountOut: 135 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter, uint256 maxBorrowValueAfter, uint256 borrowValueAfter) = isSolvent(alice, address(market));

        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should have health");

        // Assert Alice's collateral increased (should be > 100 ether if leverage worked)
        assertGt(position.collateralAssets, 100 ether, "Alice's collateral should have increased due to leverage");

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function testRemoveCollateralWithAltoLeverage() public {
        // borrowing 600_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) = _loadInputFromJson("test/lending/leverage/0xswapData/weth/data_100_weth_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 100 WETH to DAI
        // minimum expected DAI amount is 400_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 400_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);

        // Remove collateral of 100 WETH and repay the leveraged debt by swapping 100 WETH to DAI
        uint256 collateralRemoveAmount = 100 ether;
        vm.prank(alice);
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));

        Position memory positionAfter = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        // borrow shares should be reduced equivalent to the amount of DAI received by swapping removed collateral
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
        // borrow 600_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) = _loadInputFromJson("test/lending/leverage/0xswapData/weth/data_200_weth_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 200 WETH to DAI
        // borrowed amount is 600_000 DAI
        // we are repaying DAI amount received by swapping 200 WETH which will be more than 800_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 800_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);
        uint256 aliceBalanceOfBorrowTokenBefore = borrowToken.balanceOf(alice);

        uint256 collateralRemoveAmount = 200 ether;
        vm.prank(alice);
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);
        uint256 aliceBalanceOfBorrowTokenAfter = borrowToken.balanceOf(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertEq(positionAfter.borrowShares, 0, "Alice's borrow shares should be zero");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");
        assertEq(
            positionAfter.collateralAssets + collateralRemoveAmount,
            position.collateralAssets,
            "Alice's collateral should be decreased by the amount of collateral removed"
        );
        // alice received extra borrow tokens that were remaining after repaying full debt
        assertGt(
            aliceBalanceOfBorrowTokenAfter,
            aliceBalanceOfBorrowTokenBefore,
            "Alice should receive the extra token returned by the AltoLeverage swap"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of ETH is around 4200 USD
        // with ltv of 0.8, we can borrow 4200 * 100 * 0.8 = 336000
        // but we will borrow 3_00_000 due to levarage
        market.addCollateral(100 ether, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/weth/data_3000000_dai_to_weth.txt");

        // Prepare SwapParams
        // swap params to swap 3_000_000 DAI to WETH
        SwapParams memory leverageData = SwapParams({minAmountOut: 600 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        vm.prank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(3_000_000 ether, 0, alice, address(leverage), data);

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function isSolvent(address user, address _market) internal view returns (bool, uint256 max, uint256 current) {
        uint256 collateralPrice = IOracle(oracle).getPrice();
        uint256 collateralValue = uint256(IMarket(_market).position(user).collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(IMarket(_market).maxLtv());
        uint256 borrowValue = uint256(IMarket(_market).position(user).borrowShares)
            .convertToAssetsUp(IMarket(_market).totalBorrowed().assets, IMarket(_market).totalBorrowed().shares);

        return (maxBorrowValue >= borrowValue, maxBorrowValue, borrowValue);
    }

    function _loadInputFromJson(string memory fileName) internal returns (bytes memory swapData, uint256 blockNumber) {
        string memory json = vm.readFile(fileName);

        swapData = vm.parseJsonBytes(json, ".transaction.data");
        blockNumber = vm.parseJsonUint(json, ".blockNumber");
    }
}

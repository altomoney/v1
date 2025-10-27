// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {ORACLE_PRICE_PRECISION, IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket, Position, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {console} from "forge-std/console.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {AltoSboldLendingOracle} from "@alto/oracles/lending/AltoSboldLendingOracle.sol";
import {
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode,
    ERC4626RatioNode,
    CurveNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {AltoBoldWrapper} from "@alto/lending/leverage/helper/AltoBoldWrapper.sol";
import {AltoSboldLeverageSwapper} from "@alto/lending/leverage/AltoSboldLeverageSwapper.sol";

contract AltoLeverageSboldMarket is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    IERC20 constant borrowToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20 constant collateralToken = IERC20(0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11); // SBOLD
    address constant SWAP_TARGET = 0x0000000000001fF3684f28c67538d4D072C22734;
    AltoLeverage leverage;
    AltoSboldLeverageSwapper swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address constant SBOLD = 0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11;
    address constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address constant CHAINLINK_USDC_USD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant REDSTONE_USDC_USD_PRICE_FEED = 0xeeF31c7d9F2E82e8A497b140cc60cc082Be4b94e;
    address constant BOLD_USDC_CURVE_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18; // 90%
    uint256 constant REDSTONE_WEIGHT = 0.1e18; // 10%
    uint256 maxAllowedDeviation = 1e15; // 0.1%
    address oracle;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        (, uint256 blockNumber) =
            _loadInputFromJson("test/lending/leverage/0xswapData/sbold/data_120000_dai_to_bold.txt");
        vm.createSelectFork(rpcUrl, blockNumber);

        // deploy wrapper contract to wrap and unwrap BOLD and SBOLD
        AltoBoldWrapper boldWrapper = new AltoBoldWrapper(SBOLD);

        swapper = new AltoSboldLeverageSwapper(address(this), SWAP_TARGET, address(boldWrapper));
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        // assuming 6% yearly growth based on deployment timestamp of sBOLD contract
        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode(1 ether, 1749092411, 0.06 ether);
        CurveNode memory curveNode = CurveNode(ICurvePool(BOLD_USDC_CURVE_POOL), 0, 0, 18, 18, 10 minutes, 1 days);
        ChainlinkNode memory chainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_USDC_USD_PRICE_FEED), 1, 26 hours, 6, 8);
        RedstoneNode memory redstoneNode =
            RedstoneNode(AggregatorV3Interface(REDSTONE_USDC_USD_PRICE_FEED), 1, 26 hours, 6, 8);
        ChainlinkRedstoneNode memory chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, maxAllowedDeviation, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);
        // minimum liquidity for BOLD(18 decimals) and USDC(6 decimals)
        uint256[] memory minAllowedLiquidityPool = new uint256[](2);
        minAllowedLiquidityPool[0] = 1_000_000 * 10 ** 18;
        minAllowedLiquidityPool[1] = 1_000_000 * 10 ** 6;
        oracle = address(
            new AltoSboldLendingOracle(
                address(this), SBOLD, erc4626RatioNode, curveNode, minAllowedLiquidityPool, chainlinkRedstoneNode
            )
        );

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
        // borrow 120_000 DAI
        uint256 borrowAmount = 120_000 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of SBOLD is around 1.01 DUSD
        // with ltv of 0.8, we can borrow 1.01 * 120_000 * 0.8 = 96_960
        // but we will borrow 120_000 due to levarage
        uint256 collateralAddAmount = 120_000 ether;
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/sbold/data_120000_dai_to_bold.txt");

        // Prepare SwapParams
        // swap params to swap 120_000 DAI to BOLD
        // minimum expected SBOLD amount is 115_000 SBOLD
        SwapParams memory leverageData = SwapParams({minAmountOut: 115_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter, uint256 maxBorrowValueAfter, uint256 borrowValueAfter) = isSolvent(alice, address(market));

        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should have health");

        // Assert Alice's collateral increased (should be >  collateralAddAmount if leverage worked)
        assertGt(
            position.collateralAssets, collateralAddAmount, "Alice's collateral should have increased due to leverage"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );

        assertEq(IERC20(BOLD).balanceOf(address(leverage)), 0, "Leverage contract should not retain BOLD tokens");

        assertEq(
            IERC20(SBOLD).balanceOf(address(swapper.boldWrapper())),
            0,
            "Wrapper contract should not retain SBOLD tokens"
        );

        assertEq(
            IERC20(BOLD).balanceOf(address(swapper.boldWrapper())), 0, "Wrapper contract should not retain BOLD tokens"
        );
    }

    function testRemoveCollateralWithAltoLeverage() public {
        // borrowing 120_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/sbold/data_80000_bold_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 80_000 BOLD to DAI
        // minimum expected DAI amount is 79_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 79_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);

        uint256 collateralRemoveAmount = 80_000 ether;
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

        assertEq(IERC20(BOLD).balanceOf(address(leverage)), 0, "Leverage contract should not retain BOLD tokens");

        assertEq(
            IERC20(SBOLD).balanceOf(address(swapper.boldWrapper())),
            0,
            "Wrapper contract should not retain SBOLD tokens"
        );

        assertEq(
            IERC20(BOLD).balanceOf(address(swapper.boldWrapper())), 0, "Wrapper contract should not retain BOLD tokens"
        );
    }

    function testRemoveCollateralWithAltoLeverage_repay_more_than_borrowed() public {
        // borrow 120_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/sbold/data_125000_bold_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 125_000 BOLD to DAI
        // minimum expected DAI amount is 121_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 121_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);

        vm.prank(alice);
        uint256 collateralRemoveAmount = 125_000 ether;
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertEq(positionAfter.borrowShares, 0, "Alice's borrow shares should be zero");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");
        assertEq(
            positionAfter.collateralAssets + collateralRemoveAmount,
            position.collateralAssets,
            "Alice's collateral should be decreased by the amount of collateral removed"
        );
        assertGt(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should receive the extra token returned by the AltoLeverage swap"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );

        assertEq(IERC20(BOLD).balanceOf(address(leverage)), 0, "Leverage contract should not retain BOLD tokens");

        assertEq(
            IERC20(SBOLD).balanceOf(address(swapper.boldWrapper())),
            0,
            "Wrapper contract should not retain SBOLD tokens"
        );

        assertEq(
            IERC20(BOLD).balanceOf(address(swapper.boldWrapper())), 0, "Wrapper contract should not retain BOLD tokens"
        );
    }

    function testSendExtraBorrowTokensToSender() public {
        // borrow 120_000 DAI
        uint256 borrowAmount = 120_000 ether;
        uint256 leftOver = 20_000 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        uint256 collateralAddAmount = 120_000 ether;
        market.addCollateral(120_000 ether, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/sbold/data_100000_dai_to_bold.txt");

        // Prepare SwapParams
        // swap params to swap 100_000 DAI to BOLD
        // minimum expected SBOLD amount is 95_000 SBOLD
        // since 120_000 DAI is borrowed, 20_000 DAI will be leftover
        SwapParams memory leverageData = SwapParams({minAmountOut: 95_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);
        (, uint256 maxBorrowValue, uint256 borrowValue) = isSolvent(alice, address(market));

        uint256 borrowTokenBalanceOfAliceBefore = borrowToken.balanceOf(alice);

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

        // Assert leverage contract has no leftover borrow tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );

        // Assert leverage contract has no leftover borrow tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should remain same balance as before");
        assertEq(IERC20(BOLD).balanceOf(address(leverage)), 0, "Leverage contract should not retain BOLD tokens");
        assertEq(
            borrowToken.balanceOf(alice),
            borrowTokenBalanceOfAliceBefore + leftOver,
            "Alice should receive leftover tokens"
        );

        assertEq(
            IERC20(SBOLD).balanceOf(address(swapper.boldWrapper())),
            0,
            "Wrapper contract should not retain SBOLD tokens"
        );

        assertEq(
            IERC20(BOLD).balanceOf(address(swapper.boldWrapper())), 0, "Wrapper contract should not retain BOLD tokens"
        );
    }

    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of SBOLD is around 1.01 DAI
        // with ltv of 0.8, we can borrow 1.01 * 100_000 * 0.8 = 80800
        // but we will borrow 600_000 due to levarage
        market.addCollateral(100_000 ether, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/sbold/data_600000_dai_to_bold.txt");

        // Prepare SwapParams
        // swap params to swap 600_000 DAI to SBOLD
        // minimum expected SBOLD amount is 550_000 SBOLD
        SwapParams memory leverageData = SwapParams({minAmountOut: 550_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        uint256 borrowAmount = 600_000 ether;
        vm.prank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

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

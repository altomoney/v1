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
import {
    ERC4626RatioChainlinkOracleMETH
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleMETH.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {
    LiquidationConfiguration,
    BaseMarketInitParams,
    BorrowMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {LENDING_ORACLE_PRICE_PRECISION, IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {console} from "forge-std/console.sol";

contract AltoLeverageMethMarketTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    IERC20 constant borrowToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20 constant collateralToken = IERC20(0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa); // METH
    address constant SWAP_TARGET = 0x0000000000001fF3684f28c67538d4D072C22734;
    AltoLeverage leverage;
    AltoLeverageSwapper swapper;
    address OWNER = makeAddr("Alto-multisig");
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address constant METH_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkNode chainlinkNode;

    address oracle;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");

        (, uint256 blockNumber) =
            _loadInputFromJson("test/lending/leverage/0xswapData/meth/data_700000_dai_to_meth.txt");
        vm.createSelectFork(rpcUrl, blockNumber);

        swapper = new AltoLeverageSwapper(address(this), SWAP_TARGET);
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));

        erc4626RatioNode = ERC4626RatioNode(1 ether, 1696594100, 0.08 ether);
        chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        oracle = address(new ERC4626RatioChainlinkOracleMETH(OWNER, METH_STAKING, erc4626RatioNode, chainlinkNode));

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(borrowToken),
                collateralToken: address(collateralToken),
                irm: address(irm),
                owner: address(this),
                oracle: address(oracle),
                maxLtv: 0.8 ether,
                feeRecipient: address(this),
                liquidationConfiguration: LiquidationConfiguration({
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
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0
        });

        market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

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
        // borrowing 700_000 DAI due to levarage
        uint256 borrowAmount = 700_000 ether;
        uint256 collateralAddAmount = 100 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of METH is around 4150 DAI
        // with ltv of 0.8, we can borrow 4150 * 100 * 0.8 = 332000
        // but we will borrow 700_000 DAI due to levarage
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/meth/data_700000_dai_to_meth.txt");

        // Prepare SwapParams
        // swap params to swap 700_000 DAI to METH
        // minimum expected METH amount is 165 METH
        SwapParams memory leverageData = SwapParams({minAmountOut: 165 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter, uint256 maxBorrowValueAfter, uint256 borrowValueAfter) = isSolvent(alice, address(market));

        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should have health");

        // Assert Alice's collateral increased (should be > 100 ether if leverage worked)
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
        // borrowing 700_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) = _loadInputFromJson("test/lending/leverage/0xswapData/meth/data_100_meth_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 100 METH to DAI
        // minimum expected DAI amount is 410_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 410_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);

        uint256 collateralRemoveAmount = 100 ether;

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
        // borrow 700_000 DAI due to levarage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) = _loadInputFromJson("test/lending/leverage/0xswapData/meth/data_200_meth_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 200 METH to DAI
        // borrowed amount is 700_000 DAI
        // we are repaying DAI amount received by swapping 200 METH which will be more than 700_000 DAI
        // minimum expected DAI amount is 820_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 820_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);
        uint256 aliceBorrowTokenBalanceBefore = borrowToken.balanceOf(alice);

        uint256 collateralRemoveAmount = 200 ether;

        vm.prank(alice);
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);
        uint256 aliceBorrowTokenBalanceAfter = borrowToken.balanceOf(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertEq(positionAfter.borrowShares, 0, "Alice's borrow shares should be zero");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");
        assertGt(
            aliceBorrowTokenBalanceAfter,
            aliceBorrowTokenBalanceBefore,
            "Alice should receive the extra token returned by the AltoLeverage swap"
        );
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

    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of METH is around 4150 DAI
        // with ltv of 0.8, we can borrow 4150 * 100 * 0.8 = 332000
        // but we will borrow 3_00_000 due to levarage
        market.addCollateral(100 ether, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/meth/data_3000000_dai_to_meth.txt");

        // Prepare SwapParams
        // Generate swapData for swapping 3_000_000 DAI to METH
        SwapParams memory leverageData = SwapParams({minAmountOut: 500 ether, swapData: swapData});
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

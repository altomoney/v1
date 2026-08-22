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
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {LENDING_ORACLE_PRICE_PRECISION, IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";

contract AltoLeverageWstEthMarketTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    IERC20 constant borrowToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    IERC20 constant collateralToken = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); // WSTETH
    address constant SWAP_TARGET = 0x0000000000001fF3684f28c67538d4D072C22734;
    AltoLeverage leverage;
    AltoLeverageSwapper swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16; // 1%
    address oracle;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");

        (, uint256 blockNumber) =
            _loadInputFromJson("test/lending/leverage/0xswapData/wsteth/data_700000_dai_to_wsteth.txt");
        vm.createSelectFork(rpcUrl, blockNumber);

        swapper = new AltoLeverageSwapper(address(this), SWAP_TARGET);
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        oracle = address(EthereumMainnetOracleDeployer.deployWstEthOracle(address(this)));

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
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(address(this)));

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(borrowToken),
                collateralToken: address(collateralToken),
                irm: address(irm),
                owner: address(this),
                emergencyAdmin: address(this),
                oracle: address(oracle),
                maxLtv: 0.8 ether,
                feeRecipient: address(this),
                liquidationEngine: liquidationEngine
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

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
        uint256 collateralAddAmount = 100 ether;
        uint256 borrowAmount = 700_000 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of WSTETH is around 5200 DAI
        // with ltv of 0.8, we can borrow 5200 * 100 * 0.8 = 416000
        // but we will borrow 700_000 DAI due to levarage
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/wsteth/data_700000_dai_to_wsteth.txt");

        // Prepare SwapParams
        // swap params to swap 700_000 DAI(borrowAmount) to WSTETH
        // minimum expected WSTETH amount is 120 WSTETH
        SwapParams memory leverageData = SwapParams({minAmountOut: 120 ether, swapData: swapData});
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

        uint256 collateralRemoveAmount = 100 ether;

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/wsteth/data_100_wsteth_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 100 WSTETH to DAI
        // minimum expected DAI amount is 515_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 515_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);

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

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/wsteth/data_200_wsteth_to_dai.txt");

        // Prepare SwapParams
        // swap params to swap 200 WSTETH to DAI
        // borrowed amount is 700_000 DAI
        // we are repaying DAI amount received by swapping 200 WSTETH which will be more than 700_000 DAI
        // minimum expected DAI amount is 1_000_000 DAI
        SwapParams memory leverageData = SwapParams({minAmountOut: 1_000_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);

        uint256 collateralRemoveAmount = 200 ether;

        vm.prank(alice);
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
    }

    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        uint256 collateralAddAmount = 100 ether;

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        // price of WSTETH is around 5200 DUSD
        // with ltv of 0.8, we can borrow 5200 * 100 * 0.8 = 416000
        // but we will borrow 3_00_000 due to levarage
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/wsteth/data_3000000_dai_to_wsteth.txt");

        // Prepare SwapParams
        // swap params to swap 3_000_000 DAI to WSTETH
        // minimum expected WSTETH amount is 500 WSTETH
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

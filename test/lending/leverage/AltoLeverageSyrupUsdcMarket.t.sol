// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LENDING_ORACLE_PRICE_PRECISION, IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket, Position, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoLeverageSyrupUsdcMarketTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    // Token decimals
    uint256 constant DUSD_DECIMALS = 18;
    uint256 constant SYRUP_USDC_DECIMALS = 6;

    // Deployed contracts
    IMarket market = IMarket(0x33B24510233281350bF8679A7c427d04db0ed208); // SyrupUSDC Borrow Market
    IERC20 constant borrowToken = IERC20(0x63d74d22E689C715a04F2C13962b1f77F443d35b); // DUSD (18 decimals)
    IERC20 constant collateralToken = IERC20(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b); // SyrupUSDC (6 decimals)
    address constant SWAP_TARGET = 0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05; // Odos Router V3

    AltoLeverage leverage = AltoLeverage(0xA30Fbc6847e27F795C33C8e298AaD9136A08DA87);
    AltoLeverageSwapper swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100_000_000_000 ether;
    address oracle;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        (, uint256 blockNumber) =
            _loadInputFromJson("test/lending/leverage/0xswapData/syrupusdc/data_150000_dusd_to_syrupUsdc.txt");
        vm.createSelectFork(rpcUrl, blockNumber);

        swapper = new AltoLeverageSwapper(address(this), SWAP_TARGET);

        vm.startPrank(leverage.owner());
        leverage.setSwapper(swapper);
        vm.stopPrank();

        swapper.setWhitelisted(address(leverage), true);

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Set oracle from market
        oracle = market.oracle();
    }

    /// @notice Test borrowing with leverage - borrowed DUSD is swapped to SyrupUSDC and added as collateral
    function testBorrowWithAltoLeverageAsRecipient() public {
        uint256 borrowAmount = 150_000 ether; // 150,000 DUSD (18 decimals)

        // Alice supplies DUSD and adds SyrupUSDC collateral
        vm.startPrank(alice);
        market.addSupply(INITIAL_AMOUNT, 0, alice);

        // Add 150,000 SyrupUSDC as collateral (6 decimals)
        // Price of SyrupUSDC is ~1.15 DUSD
        // With LTV of 0.8: max borrow = 150,000 * 1.15 * 0.8 = 138,000 DUSD
        // But with leverage, we can borrow 150,000 DUSD
        uint256 collateralAddAmount = 150_000 * 10 ** SYRUP_USDC_DECIMALS;
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/syrupusdc/data_150000_dusd_to_syrupUsdc.txt");

        // Swap 150,000 DUSD to SyrupUSDC
        // Expected output: ~130,000 SyrupUSDC (150k / 1.15)
        // Min amount out: 120,000 SyrupUSDC (6 decimals)
        SwapParams memory leverageData =
            SwapParams({minAmountOut: 130_000 * 10 ** SYRUP_USDC_DECIMALS, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertGt(
            position.collateralAssets, collateralAddAmount, "Alice's collateral should have increased due to leverage"
        );

        // Assert leverage contract has no leftover tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    /// @notice Test removing collateral with leverage - collateral is swapped to DUSD and used to repay debt
    function testRemoveCollateralWithAltoLeverage() public {
        // First, borrow 150,000 DUSD with leverage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/syrupusdc/data_200000_syrupUsdc_to_dusd.txt");

        // Swap 200,000 SyrupUSDC to DUSD
        // Expected output: ~229,000 DUSD (200k * 1.15)
        // Min amount out: 210,000 DUSD (18 decimals)
        SwapParams memory leverageData = SwapParams({minAmountOut: 215_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);

        // Remove 200,000 SyrupUSDC (6 decimals)
        uint256 collateralRemoveAmount = 200_000 * 10 ** SYRUP_USDC_DECIMALS;

        vm.prank(alice);
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertLt(positionAfter.borrowShares, positionBefore.borrowShares, "Alice's borrow shares should decrease");
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice's collateral should decrease");
        assertEq(
            positionAfter.collateralAssets + collateralRemoveAmount,
            positionBefore.collateralAssets,
            "Alice's collateral should be decreased by the amount of collateral removed"
        );

        // Assert leverage contract has no leftover tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    /// @notice Test removing collateral and repaying more than borrowed - excess DUSD is returned to user
    function testRemoveCollateralWithAltoLeverage_repay_more_than_borrowed() public {
        // First, borrow 150,000 DUSD with leverage
        testBorrowWithAltoLeverageAsRecipient();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/syrupusdc/data_150000_syrupUsdc_to_dusd.txt");

        // Swap 150,000 SyrupUSDC to DUSD
        // Expected output: ~172,000 DUSD (150k * 1.15)
        // This will yield more than the 150,000 DUSD borrowed
        // Min amount out: 165,000 DUSD (18 decimals)
        SwapParams memory leverageData = SwapParams({minAmountOut: 165_000 ether, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);
        uint256 aliceBorrowTokenBalanceBefore = borrowToken.balanceOf(alice);

        // Remove 200,000 SyrupUSDC (6 decimals) - more than swap amount, excess stays as collateral
        uint256 collateralRemoveAmount = 200_000 * 10 ** SYRUP_USDC_DECIMALS;

        vm.prank(alice);
        market.removeCollateral(collateralRemoveAmount, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);
        uint256 aliceBorrowTokenBalanceAfter = borrowToken.balanceOf(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertEq(positionAfter.borrowShares, 0, "Alice's borrow shares should be zero");
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice's collateral should decrease");
        assertGt(
            aliceBorrowTokenBalanceAfter,
            aliceBorrowTokenBalanceBefore,
            "Alice should receive the extra DUSD from the swap"
        );
        assertEq(
            positionAfter.collateralAssets + collateralRemoveAmount,
            positionBefore.collateralAssets,
            "Alice's collateral should be decreased by the amount of collateral removed"
        );

        // Assert leverage contract has no leftover tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    /// @notice Test that borrowing reverts when leverage would result in unhealthy position
    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        vm.startPrank(alice);
        market.addSupply(INITIAL_AMOUNT, 0, alice);

        // Add only 10,000 SyrupUSDC as collateral (6 decimals)
        // Price of SyrupUSDC is ~1.15 DUSD
        // With LTV of 0.8: max borrow = 10,000 * 1.15 * 0.8 = 9,200 DUSD
        // Trying to borrow 100,000 DUSD will fail even with leverage
        uint256 collateralAddAmount = 10_000 * 10 ** SYRUP_USDC_DECIMALS;
        market.addCollateral(collateralAddAmount, alice);
        vm.stopPrank();

        (bytes memory swapData,) =
            _loadInputFromJson("test/lending/leverage/0xswapData/syrupusdc/data_100000_dusd_to_syrupUsdc.txt");

        // Swap 100,000 DUSD to SyrupUSDC
        // Expected output: ~87,000 SyrupUSDC (100k / 1.15)
        // Min amount out: 85,000 SyrupUSDC (6 decimals)
        SwapParams memory leverageData =
            SwapParams({minAmountOut: 85_000 * 10 ** SYRUP_USDC_DECIMALS, swapData: swapData});
        bytes memory data = abi.encode(leverageData);

        vm.prank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(100_000 ether, 0, alice, address(leverage), data);

        // Assert leverage contract has no leftover tokens
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    /// @notice Calculate if a position is solvent
    function isSolvent(address user, address _market) internal view returns (bool, uint256 max, uint256 current) {
        uint256 collateralPrice = IOracle(oracle).getPrice();
        uint256 collateralValue = uint256(IMarket(_market).position(user).collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(IMarket(_market).maxLtv());
        uint256 borrowValue = uint256(IMarket(_market).position(user).borrowShares)
            .convertToAssetsUp(IMarket(_market).totalBorrowed().assets, IMarket(_market).totalBorrowed().shares);

        return (maxBorrowValue >= borrowValue, maxBorrowValue, borrowValue);
    }

    /// @notice Load swap data from JSON file
    function _loadInputFromJson(string memory fileName)
        internal
        view
        returns (bytes memory swapData, uint256 blockNumber)
    {
        string memory json = vm.readFile(fileName);
        swapData = vm.parseJsonBytes(json, ".transaction.data");
        blockNumber = vm.parseJsonUint(json, ".blockNumber");
    }
}

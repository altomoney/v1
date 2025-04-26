// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AltoBorrowMarket,
    LiquidationConfiguration,
    LiquidationResult,
    Balance
} from "../../contracts/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "../../contracts/lending/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {OracleMock} from "../../contracts/lending/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "../../contracts/lending/interfaces/IOracle.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";

import {console2} from "forge-std/console2.sol";

// Create mock implementation for testing
contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockMarket is AltoBorrowMarket {
    using SharesMathLib for uint256;

    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        LiquidationConfiguration memory _liquidationConfiguration
    ) AltoBorrowMarket(_borrowToken, _collateralToken, _irm, _owner, _oracle, _maxLtv, _liquidationConfiguration) {}

    function addInterest(uint256 amount) external {
        totalSupply.assets += uint128(amount);
        totalBorrowed.assets += uint128(amount);
    }

    function borrowSharesToAmount(uint256 shares) external view returns (uint256) {
        return shares.toAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
    }
}

contract AltoBorrowMarketTest is Test {
    MockMarket market;
    MockERC20 borrowToken;
    MockERC20 collateralToken;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC0C);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function createMarket(
        LiquidationConfiguration memory liquidationConfiguration,
        uint256 collateralPrice,
        uint256 maxLtv
    ) public {
        borrowToken = new MockERC20("Borrow Token", "BTKN");
        collateralToken = new MockERC20("Collateral Token", "CTKN");

        // LiquidationConfiguration memory liquidationConfiguration = LiquidationConfiguration({
        //     maxLiquidationLtv: 0.8 ether,
        //     dynamicBonusFeeStart: 0.01 ether,
        //     ltvForCompleteLiquidation: 0.9 ether
        // });

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(collateralPrice);

        market = new MockMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            maxLtv,
            liquidationConfiguration
        );

        // Setup initial balances for test accounts
        borrowToken.mint(alice, INITIAL_AMOUNT);
        borrowToken.mint(bob, INITIAL_AMOUNT);
        borrowToken.mint(charlie, INITIAL_AMOUNT);
        collateralToken.mint(alice, INITIAL_AMOUNT);
        collateralToken.mint(bob, INITIAL_AMOUNT);
        collateralToken.mint(charlie, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function setUp() public {}

    uint256 internal constant VIRTUAL_SHARES = 1e6;

    /// @dev A number of virtual assets of 1 enforces a conversion rate between shares and assets when a market is
    /// empty.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivUp(shares, totalAssets + 1, totalShares + VIRTUAL_SHARES);
    }

    function testLiquidate() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether
            }),
            1e35,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(10 ether);
        market.borrow(0.5 ether, 0);
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.32 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 0.82 ether);

        LiquidationResult memory liquidationResult = market.liquidate(bob);

        assertEq(liquidationResult.currentLtv, 0.82 ether);
        assertEq(liquidationResult.newLtv, 0.6 ether);
        assertEq(liquidationResult.optimalRepayAmount, 0.641655096406579765 ether);
        assertEq(liquidationResult.collateralAmount, 7.02758494010966275 ether);

        vm.stopPrank();
    }

    function testFullLiquidate() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether
            }),
            2 * ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether);
        market.borrow(1 ether, 0);
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 1 ether);
        market.addInterest(2 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 3 ether - 1);

        vm.stopPrank();

        vm.startPrank(charlie);

        LiquidationResult memory liquidationResult = market.liquidate(bob);
        assertEq(liquidationResult.currentLtv, 1.5 ether);
        assertEq(liquidationResult.newLtv, 0 ether);
        assertEq(liquidationResult.optimalRepayAmount, 3 ether - 1);
        assertEq(liquidationResult.collateralAmount, 1 ether);

        (uint128 assets, uint128 shares) = market.totalBorrowed();
        assertEq(assets, 1);
        assertEq(shares, 0 ether);

        assertEq(collateralToken.balanceOf(charlie), INITIAL_AMOUNT + 1 ether);
        assertEq(borrowToken.balanceOf(charlie), INITIAL_AMOUNT - (3 ether - 1));

        vm.stopPrank();
    }

    function testLiquidateAtLltv() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether);
        market.borrow(0.5 ether, 0);
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.3 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.8 ether);

        LiquidationResult memory liquidationResult = market.liquidate(bob);
        assertEq(liquidationResult.currentLtv, 0.8 ether);
        assertEq(liquidationResult.newLtv, 0.7125 ether);
        assertEq(liquidationResult.collateralAmount, 0.513043478260869566 ether);
        assertEq(liquidationResult.optimalRepayAmount, 0.453043478260869566 ether);

        vm.stopPrank();
    }

    function testLiquidateAtTlltv() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether);
        market.borrow(0.5 ether, 0);
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);

        LiquidationResult memory liquidationResult = market.liquidate(bob);
        assertEq(liquidationResult.currentLtv, 0.9 ether);
        assertEq(liquidationResult.newLtv, 0 ether);
        assertEq(liquidationResult.collateralAmount, 0.95 ether);
        assertEq(liquidationResult.optimalRepayAmount, 0.9 ether);

        vm.stopPrank();
    }
}

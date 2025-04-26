// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "../../contracts/lending/AltoBorrowMarket.sol";
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

    function borrowAmountToShares(uint256 amount) external view returns (uint256) {
        return amount.toSharesDown(totalBorrowed.assets, totalBorrowed.shares);
    }
}

contract AltoBorrowMarketTest is Test {
    MockMarket market;
    MockERC20 borrowToken;
    MockERC20 collateralToken;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new MockERC20("Borrow Token", "BTKN");
        collateralToken = new MockERC20("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new MockMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            0.75 ether,
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether
            })
        );

        // Setup initial balances for test accounts
        borrowToken.mint(alice, INITIAL_AMOUNT);
        borrowToken.mint(bob, INITIAL_AMOUNT);
        collateralToken.mint(alice, INITIAL_AMOUNT);
        collateralToken.mint(bob, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function testAddSupplyWithAssets() public {
        uint256 supplyAmount = 100 ether;

        vm.startPrank(alice);

        // Initial state check
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT);
        assertEq(borrowToken.balanceOf(address(market)), 0);

        // Add supply with assets
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(supplyAmount, 0);

        // Verify assets were transferred
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - supplyAmount);
        assertEq(borrowToken.balanceOf(address(market)), supplyAmount);

        // Verify shares were minted correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(addedShares));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        // Verify total supply was updated correctly
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        assertEq(totalAssets, uint128(supplyAmount));
        assertEq(totalShares, uint128(addedShares));

        vm.stopPrank();
    }

    function testAddSupplyWithShares() public {
        // First deposit to initialize the exchange rate
        vm.startPrank(alice);
        market.addSupply(100 ether, 0);
        vm.stopPrank();

        uint256 shareAmount = 50 ether;

        vm.startPrank(bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Add supply with shares
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(0, shareAmount);

        // Verify assets were transferred
        assertEq(borrowToken.balanceOf(bob), initialBalance - addedAssets);

        // Verify shares were minted correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(supplyShares, uint128(shareAmount));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        vm.stopPrank();
    }

    function testRemoveSupply() public {
        // First add supply
        vm.startPrank(alice);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(100 ether, 0);

        // Verify initial state
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - addedAssets);

        // Remove part of the supply
        uint256 withdrawAmount = 40 ether;
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(withdrawAmount, 0);

        // Verify assets were transferred back
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - addedAssets + removedAssets);

        // Verify shares were burned correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(addedShares - removedShares));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        // Verify total supply was updated correctly
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        assertEq(totalAssets, uint128(addedAssets - removedAssets));
        assertEq(totalShares, uint128(addedShares - removedShares));

        vm.stopPrank();
    }

    function testRemoveSupplyWithShares() public {
        // First add supply
        vm.startPrank(alice);
        (uint256 addedAssets, uint256 addedShares) = market.addSupply(100 ether, 0);

        // Remove part of the supply using shares
        uint256 sharesToWithdraw = 60 ether;
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(0, sharesToWithdraw);

        // Verify assets were transferred back
        assertEq(borrowToken.balanceOf(alice), INITIAL_AMOUNT - addedAssets + removedAssets);

        // Verify shares were burned correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(addedShares - sharesToWithdraw));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        // Verify total supply was updated correctly
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        assertEq(totalAssets, uint128(addedAssets - removedAssets));
        assertEq(totalShares, uint128(addedShares - sharesToWithdraw));

        vm.stopPrank();
    }

    function testRevertWhenBothAssetsAndSharesProvided() public {
        vm.startPrank(alice);

        // Try to add supply with both assets and shares provided
        vm.expectRevert(bytes("inconsistent input"));
        market.addSupply(100 ether, 50 ether);

        // First add some supply
        market.addSupply(100 ether, 0);

        // Try to remove supply with both assets and shares provided
        vm.expectRevert(bytes("inconsistent input"));
        market.removeSupply(40 ether, 50 ether);

        vm.stopPrank();
    }

    function testAddCollateralWithAssets() public {
        uint256 collateralAmount = 100 ether;

        vm.startPrank(alice);

        // Initial state check
        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT);
        assertEq(collateralToken.balanceOf(address(market)), 0);

        // Add collateral with assets
        uint256 addedAssets = market.addCollateral(collateralAmount);

        // Verify assets were transferred
        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT - collateralAmount);
        assertEq(collateralToken.balanceOf(address(market)), collateralAmount);

        // Verify returned values match expectations
        assertEq(addedAssets, collateralAmount);

        vm.stopPrank();
    }

    function testRemoveCollateralWithAssets() public {
        vm.startPrank(alice);
        market.addCollateral(100 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 removedAssets = market.removeCollateral(50 ether);
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT - 50 ether);
        assertEq(collateralToken.balanceOf(address(market)), 50 ether);
        assertEq(removedAssets, 50 ether);
    }

    function testRevertWhenAddingCollateralWithInsufficientLiquidity() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes("insufficient liquidity"));
        market.borrow(100 ether, 0);
        vm.stopPrank();
    }

    function testRevertWhenBorrowingWithInsufficientCollateral() public {
        vm.startPrank(alice);
        market.addSupply(100 ether, 0);
        vm.expectRevert(bytes("insufficient collateral"));
        market.borrow(100 ether, 0);
        vm.stopPrank();
    }

    function testAddCollateralAndBorrow() public {
        vm.startPrank(bob);
        market.addSupply(100 ether, 0);
        vm.stopPrank();

        vm.startPrank(alice);
        market.addCollateral(100 ether);
        market.borrow(30 ether, 0);
        vm.stopPrank();
    }

    function testAddCollateralBorrowAndRepay() public {
        vm.startPrank(bob);
        market.addSupply(100 ether, 0);
        vm.stopPrank();

        vm.startPrank(alice);
        market.addCollateral(10 ether);
        market.borrow(3 ether, 0);
        market.addInterest(1 ether);
        (uint128 assets, uint128 shares) = market.totalBorrowed();

        assertEq(assets, 4 ether);
        assertEq(shares, 3 ether * 1e6);

        market.addInterest(0.1 ether);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(borrowShares, 3 ether * 1e6);

        // assertEq(market.borrowSharesToAmount(borrowShares), 4.1 ether);
        // assertEq(market.borrowAmountToShares(4.1 ether), borrowShares);

        //market.repay(3037500000000000000, 0);
        vm.stopPrank();
    }

    function testAccrueInterest() public {
        vm.startPrank(alice);
        market.addSupply(100 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1000 ether);
        market.borrow(100 ether, 0);
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(alice);

        // Advance time by one year (365 days)
        vm.warp(block.timestamp + 365 days);

        market.accrueInterest();

        vm.stopPrank();
    }
}

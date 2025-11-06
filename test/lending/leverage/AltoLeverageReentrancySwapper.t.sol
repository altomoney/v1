// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket, Position, IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {console} from "forge-std/console.sol";
import {SwapParams} from "@alto/lending/interfaces/IAltoLeverageSwapper.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {MockSwapper, MockSwapperData} from "./mocks/MockSwapper.sol";
import {MaliciousERC20} from "./mocks/MaliciousERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract AltoLeverageReentrancySwapperTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    AltoLeverage leverage;
    MockSwapper swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address oracle;
    MaliciousERC20 maliciousERC20;

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        swapper = new MockSwapper(address(this));
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(1 * ORACLE_PRICE_PRECISION);

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

        maliciousERC20 = new MaliciousERC20(alice, address(market));

        swapper.setWhitelisted(address(leverage), true);
        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), address(maliciousERC20), INITIAL_AMOUNT);
        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);
        deal(address(borrowToken), address(maliciousERC20), 100 ether);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        market.setAuthorizedCallback(address(leverage), true);
        // Allow market in leverage
        leverage.setMarket(address(market), true);
    }

    // test after fixing reentrancy vulnerability
    function testLiquidateDuringDevelerage() public {
        uint256 borrowAmount = 600 ether;

        vm.startPrank(address(alice));
        market.addSupply(10000000000 ether, 0, alice);
        // alice supplies 1000 assets as collateral
        market.addCollateral(1000 ether, alice);
        vm.stopPrank();

        vm.prank(address(alice));
        // alice borrows 600 assets
        market.borrow(borrowAmount, 0, alice, alice, hex"");

        (bool isHealthyAfter,,) = isSolvent(alice, address(market));

        // assert alice is solvent
        assertTrue(isHealthyAfter, "Alice should have health");

        MockSwapperData memory data = MockSwapperData({maliciousERC20: address(maliciousERC20), minAmountOut: 1 wei});

        bytes memory swapParams = abi.encode(data);

        vm.startPrank(alice);
        market.setAuthorization(address(maliciousERC20), true);

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.removeCollateral(999 ether, alice, address(leverage), swapParams);
    }

    function isSolvent(address user, address _market) internal view returns (bool, uint256 max, uint256 current) {
        uint256 collateralPrice = OracleMock(oracle).getPrice();
        uint256 collateralValue = uint256(IMarket(_market).position(user).collateralAssets).divideWithRounding(
            collateralPrice, ORACLE_PRICE_PRECISION, false
        );
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(IMarket(_market).maxLtv());
        uint256 borrowValue = uint256(IMarket(_market).position(user).borrowShares).convertToAssetsUp(
            IMarket(_market).totalBorrowed().assets, IMarket(_market).totalBorrowed().shares
        );

        return (maxBorrowValue >= borrowValue, maxBorrowValue, borrowValue);
    }
}

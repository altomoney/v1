// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Fork} from "@alto-test/helpers/Fork.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarket, Position} from "@alto/lending/interfaces/IMarket.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {WrapperToken} from "@alto/lending/wrappedToken/WrapperToken.sol";
import {SwapTargetMetadata} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {AltoLeverageSwapperForWrapperToken} from "@alto/lending/wrappedToken/AltoLeverageSwapperForWrapperToken.sol";
import {SwapParamsWrapperToken} from "@alto/lending/wrappedToken/IAltoLeverageSwapperForWrapperToken.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {PtExpiryDiscountOracleMock} from "./mocks/PtExpiryDiscountOracleMock.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {console} from "forge-std/console.sol";

/// @dev Mainnet fork integration test for PT-sUSDe wrapper collateral leverage.
///      Setup rolls wrapper underlying from PT-sUSDe-7MAY to PT-sUSDe-13AUG, then tests leveraged borrow.
///      A supplier provides market liquidity; the leverage user posts seed collateral before borrowing.
contract WrapperTokenLeverageTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    address internal constant PT_SUSDE_7MAY_2026 = 0x3de0ff76E8b528C092d47b9DaC775931cef80F49;
    address internal constant PT_SUSDE_13AUG_2026 = 0x5A19fa369F2895dCD8d2cEE62E4Ceae58eF92BBb;
    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    string internal constant ROLLOVER_ROUTE_FILE =
        "test/lending/fork/WrapperToken/routes/rollover_route_pt_susde-7may_to_13aug.json";
    string internal constant LEVERAGE_ROUTE_FILE =
        "test/lending/fork/WrapperToken/routes/swap_pt_susde_100000_dusd_to_pt_susde_13_aug.json";
    string internal constant DELEVERAGE_ROUTE_FILE =
        "test/lending/fork/WrapperToken/routes/swap_120000_pt_susde_13aug_to_dusd.json";

    uint256 internal constant PT_ROLLOVER_AMOUNT = 100_000 ether;
    uint256 internal constant USER_PT_AMOUNT = 50_000 ether;
    uint256 internal constant PT_REMOVE_AMOUNT = 120_000 ether;
    uint256 internal constant MARKET_SUPPLY = 10_000_000 ether;
    uint256 internal constant LEVERAGE_BORROW_AMOUNT = 100_000 ether;
    uint256 internal constant MIN_WRAPPED_OUT_SLIPPAGE_BPS = 10; // 0.1%

    uint256 internal constant INITIAL_EXCHANGE_RATE = 1e18;
    uint8 internal constant TOKEN_DECIMALS = 18;

    address internal supplier;
    address internal user;
    address internal pauser;
    WrapperToken internal wrapper;
    IMarket internal market;
    AltoLeverage internal leverage;
    AltoLeverageSwapperForWrapperToken internal swapper;
    address internal oracle;

    function setUp() public {
        Fork.selectEthereum(25230280);

        supplier = makeAddr("supplier");
        user = makeAddr("user");
        pauser = makeAddr("pauser");

        wrapper = new WrapperToken("Wrapped PT-sUSDe", "wPT-sUSDe", PT_SUSDE_7MAY_2026, address(this), address(this));

        wrapper.setPauser(pauser, PAUSE_TYPE, true);
        wrapper.setSwapTargetToApproveTarget(
            PENDLE_ROUTER_V4, SwapTargetMetadata({approveTarget: PENDLE_ROUTER_V4, isValid: true})
        );

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        oracle = _deployPtOracle(PT_SUSDE_7MAY_2026, INITIAL_EXCHANGE_RATE);

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

        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(address(this)));

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: DUSD,
                collateralToken: address(wrapper),
                irm: address(irm),
                owner: address(this),
                emergencyAdmin: address(this),
                oracle: oracle,
                maxLtv: 0.8 ether,
                feeRecipient: address(this),
                liquidationEngine: liquidationEngine
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

        _rolloverWrapperUnderlying();

        address[] memory validSwapTargets = new address[](1);
        validSwapTargets[0] = PENDLE_ROUTER_V4;
        swapper = new AltoLeverageSwapperForWrapperToken(address(this), address(market), validSwapTargets);

        leverage = new AltoLeverage(address(swapper), address(this));

        swapper.setWhitelisted(address(leverage), true);
        market.setAuthorizedCallback(address(leverage), true);
        leverage.setMarket(address(market), true);

        deal(DUSD, supplier, MARKET_SUPPLY);
        deal(PT_SUSDE_13AUG_2026, user, USER_PT_AMOUNT);

        vm.prank(supplier);
        IERC20(DUSD).approve(address(market), type(uint256).max);

        vm.startPrank(user);
        IERC20(PT_SUSDE_13AUG_2026).approve(address(wrapper), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function test_leverage_borrow_afterRollover() public {
        _performLeverageBorrowAfterRollover();
    }

    function test_removeCollateral_afterLeverageBorrow() public {
        _performLeverageBorrowAfterRollover();

        Position memory positionBeforeRemove = market.position(user);
        uint256 wrappedToRemove = wrapper.previewWrap(PT_REMOVE_AMOUNT);

        assertGt(wrappedToRemove, 0, "wrapped remove amount should be non-zero");
        assertGe(
            positionBeforeRemove.collateralAssets,
            wrappedToRemove,
            "user should have enough wrapped collateral to remove"
        );

        bytes memory deleverageData = _encodeDeleverageSwapParams();

        vm.prank(user);
        market.removeCollateral(wrappedToRemove, user, address(leverage), deleverageData);

        Position memory positionAfterRemove = market.position(user);

        assertLt(
            positionAfterRemove.collateralAssets, positionBeforeRemove.collateralAssets, "collateral should decrease"
        );
        assertLt(
            positionAfterRemove.borrowShares,
            positionBeforeRemove.borrowShares,
            "borrow should decrease after deleverage"
        );
        assertEq(
            positionBeforeRemove.collateralAssets - positionAfterRemove.collateralAssets,
            wrappedToRemove,
            "collateral should decrease by wrapped remove amount"
        );
        uint256 collateralRemoved = positionBeforeRemove.collateralAssets - positionAfterRemove.collateralAssets;
        assertTrue(_isSolvent(user), "position should remain solvent after deleverage");

        assertEq(IERC20(DUSD).balanceOf(address(leverage)), 0, "leverage should not retain DUSD");
        assertEq(wrapper.balanceOf(address(leverage)), 0, "leverage should not retain wrapper tokens");
        assertEq(IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(leverage)), 0, "leverage should not retain PT");
        assertEq(IERC20(DUSD).balanceOf(address(swapper)), 0, "swapper should not retain DUSD");
        assertEq(wrapper.balanceOf(address(swapper)), 0, "swapper should not retain wrapper tokens");
        assertEq(IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(swapper)), 0, "swapper should not retain PT");

        console.log("collateral before remove", positionBeforeRemove.collateralAssets);
        console.log("collateral after remove", positionAfterRemove.collateralAssets);
        console.log("collateral removed", collateralRemoved);
        console.log("dusd balance of user", IERC20(DUSD).balanceOf(user));
        console.log("borrow shares before remove", positionBeforeRemove.borrowShares);
        console.log("borrow shares after remove", positionAfterRemove.borrowShares);
    }

    function _performLeverageBorrowAfterRollover() internal {
        _assertPostRolloverSetup();

        vm.prank(supplier);
        market.addSupply(MARKET_SUPPLY, 0, supplier);

        vm.startPrank(user);
        uint256 expectedWrapped = wrapper.previewWrap(USER_PT_AMOUNT);
        uint256 wrappedAmount = wrapper.wrap(USER_PT_AMOUNT);
        assertEq(wrappedAmount, expectedWrapped, "initial wrapped collateral should match previewWrap");
        market.addCollateral(wrappedAmount, user);
        vm.stopPrank();

        Position memory positionBeforeLeverage = market.position(user);
        assertEq(
            positionBeforeLeverage.collateralAssets, wrappedAmount, "user should have seed collateral before leverage"
        );
        assertEq(positionBeforeLeverage.borrowShares, 0, "user should have no borrow before leverage");
        assertTrue(_isSolvent(user), "position should be solvent before leverage");

        bytes memory leverageData = _encodeLeverageSwapParams();

        vm.prank(user);
        market.borrow(LEVERAGE_BORROW_AMOUNT, 0, user, address(leverage), leverageData);

        Position memory positionAfterLeverage = market.position(user);

        assertGt(positionAfterLeverage.collateralAssets, 0, "collateral should be added via leverage");
        assertGt(
            positionAfterLeverage.collateralAssets,
            positionBeforeLeverage.collateralAssets,
            "collateral should increase after leveraged borrow"
        );
        uint256 collateralAdded = positionAfterLeverage.collateralAssets - positionBeforeLeverage.collateralAssets;
        assertGt(positionAfterLeverage.borrowShares, 0, "user should have borrow shares after leverage");
        assertTrue(_isSolvent(user), "position should remain solvent after leverage");

        assertEq(IERC20(DUSD).balanceOf(address(leverage)), 0, "leverage should not retain DUSD");
        assertEq(wrapper.balanceOf(address(leverage)), 0, "leverage should not retain wrapper tokens");
        assertEq(IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(leverage)), 0, "leverage should not retain PT");
        assertEq(IERC20(DUSD).balanceOf(address(swapper)), 0, "swapper should not retain DUSD");
        assertEq(wrapper.balanceOf(address(swapper)), 0, "swapper should not retain wrapper tokens");
        assertEq(IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(swapper)), 0, "swapper should not retain PT");

        console.log("collateral before leverage", positionBeforeLeverage.collateralAssets);
        console.log("collateral after leverage", positionAfterLeverage.collateralAssets);
        console.log("collateral added", collateralAdded);
        console.log("borrow shares after leverage", positionAfterLeverage.borrowShares);
    }

    function _encodeDeleverageSwapParams() internal view returns (bytes memory) {
        (bytes memory swapData, uint256 minDusdAmountOut) = _loadDeleverageRoute();
        console.log("expected minDusdAmountOut", minDusdAmountOut);

        return abi.encode(
            SwapParamsWrapperToken({
                minAmountOut: minDusdAmountOut,
                underlyingToken: PT_SUSDE_13AUG_2026,
                swapTarget: PENDLE_ROUTER_V4,
                swapData: swapData
            })
        );
    }

    function _rolloverWrapperUnderlying() internal {
        deal(PT_SUSDE_7MAY_2026, address(wrapper), PT_ROLLOVER_AMOUNT);

        bytes memory rolloverSwapData = _loadRouteData(ROLLOVER_ROUTE_FILE);

        vm.prank(pauser);
        wrapper.pause(PAUSE_TYPE, true);

        uint256 exchangeRateBefore = wrapper.exchangeRate();

        wrapper.rollover(PT_SUSDE_13AUG_2026, PT_ROLLOVER_AMOUNT, 100_000 ether, PENDLE_ROUTER_V4, rolloverSwapData);

        assertEq(wrapper.underlyingToken(), PT_SUSDE_13AUG_2026, "wrapper underlying should be PT-sUSDe-13AUG");
        assertGt(wrapper.exchangeRate(), exchangeRateBefore, "exchange rate should increase after rollover");
        assertEq(IERC20(PT_SUSDE_7MAY_2026).balanceOf(address(wrapper)), 0, "wrapper should hold no 7MAY PT");
        assertGt(IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(wrapper)), 0, "wrapper should hold 13AUG PT");

        uint256 newExchangeRate = wrapper.exchangeRate();
        oracle = _deployPtOracle(PT_SUSDE_13AUG_2026, newExchangeRate);
        market.setOracle(oracle);

        vm.prank(pauser);
        wrapper.pause(PAUSE_TYPE, false);
    }

    function _assertPostRolloverSetup() internal view {
        assertEq(wrapper.underlyingToken(), PT_SUSDE_13AUG_2026, "setup: wrapper underlying should be 13AUG PT");
        assertEq(IERC20(PT_SUSDE_7MAY_2026).balanceOf(address(wrapper)), 0, "setup: wrapper should hold no 7MAY PT");
        assertGt(IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(wrapper)), 0, "setup: wrapper should hold 13AUG PT");
        assertGt(wrapper.exchangeRate(), INITIAL_EXCHANGE_RATE, "setup: exchange rate should reflect rollover");
        assertTrue(swapper.isValidSwapTarget(PENDLE_ROUTER_V4), "setup: Pendle router should be valid swap target");
        assertTrue(swapper.isWhitelisted(address(leverage)), "setup: leverage should be whitelisted on swapper");
        assertTrue(leverage.supportedMarkets(address(market)), "setup: market should be supported by leverage");
        assertGt(
            ILendingOracle(oracle).getPrice(), 0.9e36, "setup: post-rollover oracle price should be greater than 0.9e36"
        );
    }

    function _encodeLeverageSwapParams() internal view returns (bytes memory) {
        (bytes memory swapData, uint256 minPtAmountOut) = _loadLeverageRoute();
        console.log("expected minPtAmountOut", minPtAmountOut);

        return abi.encode(
            SwapParamsWrapperToken({
                minAmountOut: minPtAmountOut,
                underlyingToken: PT_SUSDE_13AUG_2026,
                swapTarget: PENDLE_ROUTER_V4,
                swapData: swapData
            })
        );
    }

    function _isSolvent(address user_) internal view returns (bool) {
        uint256 collateralPrice = ILendingOracle(market.oracle()).getPrice();
        Position memory userPosition = market.position(user_);
        uint256 collateralValue = uint256(userPosition.collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(market.maxLtv());
        uint256 borrowValue = uint256(userPosition.borrowShares)
            .convertToAssetsUp(market.totalBorrowed().assets, market.totalBorrowed().shares);

        return maxBorrowValue >= borrowValue;
    }

    function _deployPtOracle(address ptToken, uint256 exchangeRate) internal returns (address) {
        return
            address(
                new PtExpiryDiscountOracleMock(ptToken, TOKEN_DECIMALS, TOKEN_DECIMALS, exchangeRate, TOKEN_DECIMALS)
            );
    }

    function _loadRouteData(string memory filePath) internal view returns (bytes memory swapData) {
        string memory json = vm.readFile(filePath);
        swapData = vm.parseJsonBytes(json, ".routes[0].tx.data");
        assertGt(swapData.length, 0, "route swap calldata should not be empty");
    }

    function _loadLeverageRoute() internal view returns (bytes memory swapData, uint256 minPtAmountOut) {
        string memory json = vm.readFile(LEVERAGE_ROUTE_FILE);

        swapData = vm.parseJsonBytes(json, ".routes[0].tx.data");
        assertGt(swapData.length, 0, "leverage route swap calldata should not be empty");

        address routeInputToken = vm.parseJsonAddress(json, ".inputs[0].token");
        assertEq(routeInputToken, DUSD, "leverage route input token should be DUSD");

        uint256 routeInputAmount = vm.parseJsonUint(json, ".inputs[0].amount");
        assertEq(routeInputAmount, LEVERAGE_BORROW_AMOUNT, "leverage route input should match borrow amount");

        uint256 ptAmountOut = vm.parseJsonUint(json, ".routes[0].outputs[0].amount");
        minPtAmountOut = ptAmountOut * (10_000 - MIN_WRAPPED_OUT_SLIPPAGE_BPS) / 10_000;
    }

    function _loadDeleverageRoute() internal view returns (bytes memory swapData, uint256 minDusdAmountOut) {
        string memory json = vm.readFile(DELEVERAGE_ROUTE_FILE);

        swapData = vm.parseJsonBytes(json, ".routes[0].tx.data");
        assertGt(swapData.length, 0, "deleverage route swap calldata should not be empty");

        address routeInputToken = vm.parseJsonAddress(json, ".inputs[0].token");
        assertEq(routeInputToken, PT_SUSDE_13AUG_2026, "deleverage route input token should be PT-sUSDe-13AUG");

        uint256 expectedPtIn = wrapper.previewUnwrap(wrapper.previewWrap(PT_REMOVE_AMOUNT));
        uint256 routeInputAmount = vm.parseJsonUint(json, ".inputs[0].amount");
        assertEq(routeInputAmount, expectedPtIn, "deleverage route PT input should match unwrapped collateral");

        address outputToken = vm.parseJsonAddress(json, ".routes[0].outputs[0].token");
        assertEq(outputToken, DUSD, "deleverage route output token should be DUSD");

        uint256 outputAmount = vm.parseJsonUint(json, ".routes[0].outputs[0].amount");
        minDusdAmountOut = outputAmount * (10_000 - MIN_WRAPPED_OUT_SLIPPAGE_BPS) / 10_000;
    }
}

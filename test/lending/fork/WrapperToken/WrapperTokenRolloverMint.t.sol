// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, MintMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarket, Position} from "@alto/lending/interfaces/IMarket.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {WrapperToken} from "@alto/lending/wrappedToken/WrapperToken.sol";
import {SwapTargetMetadata} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {PtExpiryDiscountOracleMock} from "./mocks/PtExpiryDiscountOracleMock.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {console} from "forge-std/console.sol";

/// @dev Mainnet fork integration test for PT-sUSDe wrapper collateral mint markets.
///      Covers wrap → add collateral → mint borrow → owner rollover via `WrapperToken.swap`.
contract WrapperTokenRolloverMintTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    address internal constant PT_SUSDE_7MAY_2026 = 0x3de0ff76E8b528C092d47b9DaC775931cef80F49;
    address internal constant PT_SUSDE_13AUG_2026 = 0x5A19fa369F2895dCD8d2cEE62E4Ceae58eF92BBb;
    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    string internal constant SWAP_ROUTE_FILE =
        "test/lending/fork/WrapperToken/routes/rollover_route_pt_susde-7may_to_13aug.json";

    uint256 internal constant PT_AMOUNT = 100_000 ether;
    uint256 internal constant DEBT_CEILING = 10_000_000 ether;
    uint256 internal constant BORROW_AMOUNT = 50_000 ether;

    uint256 internal constant INITIAL_EXCHANGE_RATE = 1e18;
    uint8 internal constant TOKEN_DECIMALS = 18;

    address internal user;
    address internal pauser;
    WrapperToken internal wrapper;
    IMarket internal market;
    address internal oracle;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 25222387);

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

        MintMarketInitParams memory mintMarketInitParams = MintMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: DUSD,
                collateralToken: address(wrapper),
                irm: address(irm),
                owner: address(this),
                oracle: oracle,
                maxLtv: 0.8 ether,
                feeRecipient: address(this),
                liquidationEngine: liquidationEngine
            }),
            debtCeiling: DEBT_CEILING,
            initialBorrowOpeningFee: 0
        });

        market = IMarket(MarketDeployer.deployMintMarket(mintMarketInitParams));
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

        _configureDusdMinter(address(market));

        deal(PT_SUSDE_7MAY_2026, user, PT_AMOUNT);

        vm.startPrank(user);
        IERC20(PT_SUSDE_7MAY_2026).approve(address(wrapper), type(uint256).max);
        wrapper.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function test_rollover_preservesUserCollateralAfterBorrow() public {
        vm.startPrank(user);
        uint256 wrappedAmount = wrapper.wrap(PT_AMOUNT);
        market.addCollateral(wrappedAmount, user);
        market.borrow(BORROW_AMOUNT, 0, user, user, "");
        vm.stopPrank();

        Position memory positionBeforeRollover = market.position(user);
        assertGt(positionBeforeRollover.collateralAssets, 0, "user should have collateral");
        assertGt(positionBeforeRollover.borrowShares, 0, "user should have borrow shares");
        assertEq(IERC20(DUSD).balanceOf(user), BORROW_AMOUNT, "user should receive minted DUSD");

        uint256 ptBalanceInWrapper = IERC20(PT_SUSDE_7MAY_2026).balanceOf(address(wrapper));
        assertEq(ptBalanceInWrapper, PT_AMOUNT, "wrapper should hold all deposited PT");

        bytes memory swapData = _loadSwapRoute();

        vm.prank(pauser);
        wrapper.pause(PAUSE_TYPE, true);

        _logWrapperPtBalances("before rollover");

        uint256 exchangeRateBefore = wrapper.exchangeRate();
        uint256 marketWrapperBalanceBefore = wrapper.balanceOf(address(market));
        assertEq(wrapper.balanceOf(user), 0, "user wrapper balance should be 0 before rollover");

        wrapper.rollover(PT_SUSDE_13AUG_2026, PT_AMOUNT, 100_000 ether, PENDLE_ROUTER_V4, swapData);
        assertEq(wrapper.underlyingToken(), PT_SUSDE_13AUG_2026, "wrapper underlying should be rolled over");

        _logWrapperPtBalances("after rollover");

        assertEq(wrapper.balanceOf(user), 0, "user wrapper balance should be 0 after rollover");
        assertEq(
            wrapper.balanceOf(address(market)),
            marketWrapperBalanceBefore,
            "market wrapper balance should be unchanged after rollover"
        );
        assertGt(wrapper.exchangeRate(), exchangeRateBefore, "exchange rate should increase after rollover");

        uint256 newExchangeRate = wrapper.exchangeRate();
        console.log("oracle price before update", ILendingOracle(market.oracle()).getPrice());
        assertTrue(_isSolvent(user), "position should be solvent before oracle update");

        address postRolloverOracle = _deployPtOracle(PT_SUSDE_13AUG_2026, newExchangeRate);
        market.setOracle(postRolloverOracle);
        assertEq(market.oracle(), postRolloverOracle, "market oracle should be updated after rollover");
        console.log("oracle price after update", ILendingOracle(market.oracle()).getPrice());
        assertTrue(_isSolvent(user), "position should be solvent after oracle update");

        vm.prank(pauser);
        wrapper.pause(PAUSE_TYPE, false);

        Position memory positionAfterRollover = market.position(user);
        assertEq(
            positionAfterRollover.collateralAssets,
            positionBeforeRollover.collateralAssets,
            "user collateral in wrapped tokens should be unchanged after rollover attempt"
        );
    }

    function _configureDusdMinter(address minter) internal {
        address dusdOwner = Ownable(DUSD).owner();

        vm.startPrank(dusdOwner);
        IDUSD(DUSD).setMinterStatus(minter, true);
        IDUSD(DUSD).setMinterCeiling(minter, DEBT_CEILING);
        vm.stopPrank();
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

    function _loadSwapRoute() internal view returns (bytes memory swapData) {
        string memory json = vm.readFile(SWAP_ROUTE_FILE);
        swapData = vm.parseJsonBytes(json, ".routes[0].tx.data");
    }

    function _logWrapperPtBalances(string memory label) internal view {
        console.log("--- PT balances in wrapper", label, "---");
        console.log("PT-sUSDe-7MAY-2026:", IERC20(PT_SUSDE_7MAY_2026).balanceOf(address(wrapper)));
        console.log("PT-sUSDe-13AUG-2026:", IERC20(PT_SUSDE_13AUG_2026).balanceOf(address(wrapper)));
    }
}

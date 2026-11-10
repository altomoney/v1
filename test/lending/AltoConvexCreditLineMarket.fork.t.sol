// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Fork} from "@alto-test/helpers/Fork.sol";

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {
    CreditMarketInitParams,
    ConvexCreditLineInitParams
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IConvexBooster} from "@alto/lending/interfaces/vendor/IConvexBooster.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";
import {Balance, BaseMarketInitParams, IMarketErrors, MarketType, Position} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";

interface ICurveFrxUsdDusdPool {
    function coins(uint256 index) external view returns (address);

    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);

    function get_dy(int128 fromIndex, int128 toIndex, uint256 fromAmount) external view returns (uint256);

    function remove_liquidity(
        uint256 burnAmount,
        uint256[] calldata minimumAmounts,
        address receiver,
        bool claimAdminFees
    ) external returns (uint256[] memory amounts);

    function exchange(int128 fromIndex, int128 toIndex, uint256 fromAmount, uint256 minimumToAmount, address receiver)
        external
        returns (uint256 toAmount);
}

interface IConvexRewardPoolFork is IConvexRewardPool {
    function earned(address account) external view returns (uint256);

    function periodFinish() external view returns (uint256);

    function rewardRate() external view returns (uint256);
}

contract AltoConvexCreditLineMarketForkTest is Test {
    // Pinned while the primary Convex reward period is active for pool 565.
    uint256 private constant FORK_BLOCK = 25_933_066;
    uint256 private constant CONVEX_POOL_ID = 565;

    uint256 private constant MAX_LTV = 0.6 ether;
    uint256 private constant FORECLOSURE_LTV = 0.8 ether;
    uint256 private constant CREDIT_LIMIT = 1_000_000 ether;
    uint256 private constant DUSD_MINTER_CEILING = CREDIT_LIMIT * 1.05 ether / FORECLOSURE_LTV;
    uint256 private constant BORROW_RATE = 0.04 ether / uint256(365 days);
    uint256 private constant FRXUSD_DEPOSIT = 1_000 ether;
    uint256 private constant RECOVERY_FRXUSD_DEPOSIT = 510_000 ether;
    uint256 private constant RECOVERY_COLLATERAL = 500_000 ether;
    uint256 private constant RECOVERY_MAX_LTV = 0.4 ether;
    uint256 private constant RECOVERY_FORECLOSURE_LTV = 0.5 ether;
    uint256 private constant REWARD_ACCRUAL_TIME = 1 days;
    uint256 private constant REWARD_ACCRUAL_BLOCKS = 7_200;

    address private constant CURVE_POOL_ADDRESS = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address private constant FRXUSD_ADDRESS = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address private constant DUSD_ADDRESS = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address private constant CONVEX_BOOSTER_ADDRESS = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private constant CONVEX_REWARD_POOL_ADDRESS = 0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb;
    address private constant CONVEX_DEPOSIT_TOKEN_ADDRESS = 0xEFB03B5f93c0E7C29Ab0AD4DE06bfA871aE23749;
    address private constant CRV_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX_ADDRESS = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address private constant WFRAX_ADDRESS = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;
    address private constant ALTO_TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address private constant FEE_RECIPIENT = 0x5F80c18b6B73B1C4F06fa5233De32778eC90FA96;
    address private constant CREDIT_ACCOUNT = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    ICurveFrxUsdDusdPool private constant CURVE_POOL = ICurveFrxUsdDusdPool(CURVE_POOL_ADDRESS);
    IConvexBooster private constant CONVEX_BOOSTER = IConvexBooster(CONVEX_BOOSTER_ADDRESS);
    IConvexRewardPoolFork private constant CONVEX_REWARD_POOL = IConvexRewardPoolFork(CONVEX_REWARD_POOL_ADDRESS);
    DUSD private constant DUSD_TOKEN = DUSD(DUSD_ADDRESS);
    IERC20 private constant FRXUSD = IERC20(FRXUSD_ADDRESS);
    IERC20 private constant CURVE_LP = IERC20(CURVE_POOL_ADDRESS);
    IERC20 private constant CONVEX_DEPOSIT_TOKEN = IERC20(CONVEX_DEPOSIT_TOKEN_ADDRESS);
    IERC20 private constant CRV = IERC20(CRV_ADDRESS);
    IERC20 private constant CVX = IERC20(CVX_ADDRESS);
    IERC20 private constant WFRAX = IERC20(WFRAX_ADDRESS);

    address private claimCaller;
    address private collateralReceiver;

    AltoConvexCreditLineMarket private market;
    FixedRateIrm private irm;
    OracleMock private oracle;

    uint256 private initialOraclePrice;
    uint256 private collateralAmount;

    function setUp() public {
        Fork.selectEthereum(FORK_BLOCK);

        claimCaller = makeAddr("ClaimCaller");
        collateralReceiver = makeAddr("CollateralReceiver");

        oracle = new OracleMock();
        // Test valuation uses virtual price with both underlying assets assumed at $1.
        // The deployment script uses AltoCreditMarketLpOracle's fixed 1 DUSD per LP instead.
        initialOraclePrice = CURVE_POOL.get_virtual_price() * 1e18;
        oracle.setPrice(initialOraclePrice);

        irm = new FixedRateIrm(BORROW_RATE, ALTO_TIMELOCK);
        AltoConvexCreditLineMarket implementation = new AltoConvexCreditLineMarket();
        market = AltoConvexCreditLineMarket(address(new ERC1967Proxy(address(implementation), "")));
        market.initialize(_marketInitParams());

        _authorizeMarketOnDusd();
        collateralAmount = _mintCurveLp();
    }

    function testFork_InitializationUsesLiveCurveAndConvexConfiguration() external {
        assertEq(CURVE_POOL.coins(0), FRXUSD_ADDRESS);
        assertEq(CURVE_POOL.coins(1), DUSD_ADDRESS);

        (address lpToken, address depositToken,, address rewardPool,, bool shutdown) =
            CONVEX_BOOSTER.poolInfo(CONVEX_POOL_ID);
        assertEq(lpToken, CURVE_POOL_ADDRESS);
        assertEq(depositToken, CONVEX_DEPOSIT_TOKEN_ADDRESS);
        assertEq(rewardPool, CONVEX_REWARD_POOL_ADDRESS);
        assertFalse(shutdown);

        assertEq(CONVEX_REWARD_POOL.pid(), CONVEX_POOL_ID);
        assertEq(CONVEX_REWARD_POOL.operator(), CONVEX_BOOSTER_ADDRESS);
        assertEq(CONVEX_REWARD_POOL.stakingToken(), CONVEX_DEPOSIT_TOKEN_ADDRESS);
        assertEq(CONVEX_REWARD_POOL.rewardToken(), CRV_ADDRESS);
        assertGt(CONVEX_REWARD_POOL.rewardRate(), 0);

        assertEq(uint256(market.MARKET_TYPE()), uint256(MarketType.CREDIT_MINT));
        assertEq(market.borrowToken(), DUSD_ADDRESS);
        assertEq(market.collateralToken(), CURVE_POOL_ADDRESS);
        assertEq(market.owner(), ALTO_TIMELOCK);
        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
        assertEq(market.irm(), address(irm));
        assertEq(irm.market(), address(market));
        assertEq(irm.owner(), ALTO_TIMELOCK);
        (uint256 borrowRate,) = irm.irState();
        assertEq(borrowRate, BORROW_RATE);
        assertEq(market.oracle(), address(oracle));
        assertEq(market.feeRecipient(), FEE_RECIPIENT);
        assertEq(market.maxLtv(), MAX_LTV);
        assertEq(market.foreclosureLtv(), FORECLOSURE_LTV);
        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(creditCapacity, CREDIT_LIMIT);
        assertEq(market.borrowOpeningFee(), 0);
        assertEq(market.badDebtAssets(), 0);
        assertEq(market.liquidationEngine(), address(0));

        assertEq(market.convexBooster(), CONVEX_BOOSTER_ADDRESS);
        assertEq(market.convexPoolId(), CONVEX_POOL_ID);
        assertEq(market.convexRewardPool(), CONVEX_REWARD_POOL_ADDRESS);
        assertEq(market.rewardRecipient(), CREDIT_ACCOUNT);
        assertTrue(market.convexActive());
        assertEq(market.rewardToken(0), CRV_ADDRESS);
        assertEq(market.rewardToken(1), CVX_ADDRESS);
        assertEq(market.rewardToken(2), WFRAX_ADDRESS);
        vm.expectRevert();
        market.rewardToken(3);

        assertTrue(DUSD_TOKEN.allowedMinter(address(market)));
        assertTrue(DUSD_TOKEN.allowedBurner(address(market)));
        (uint256 minted, uint256 ceiling) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(minted, 0);
        assertEq(ceiling, DUSD_MINTER_CEILING);
        assertGt(collateralAmount, 0);
    }

    function testFork_AddAndRemoveCollateralThroughConvex() external {
        uint256 rewardPoolDepositTokenBefore = CONVEX_DEPOSIT_TOKEN.balanceOf(CONVEX_REWARD_POOL_ADDRESS);

        uint256 addedAssets = _addAllCollateral();

        Position memory creditPosition = _creditPosition();
        assertEq(addedAssets, collateralAmount);
        assertEq(creditPosition.collateralAssets, collateralAmount);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), collateralAmount);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
        // With stake=true, the reward pool holds the cvxLP while crediting the market through balanceOf.
        assertEq(CONVEX_DEPOSIT_TOKEN.balanceOf(address(market)), 0);
        assertEq(
            CONVEX_DEPOSIT_TOKEN.balanceOf(CONVEX_REWARD_POOL_ADDRESS) - rewardPoolDepositTokenBefore, collateralAmount
        );

        uint256 assetsToRemove = collateralAmount / 2;
        uint256 receiverBalanceBefore = CURVE_LP.balanceOf(collateralReceiver);
        vm.prank(CREDIT_ACCOUNT);
        uint256 removedAssets = market.removeCollateral(assetsToRemove, CREDIT_ACCOUNT, collateralReceiver, bytes(""));

        creditPosition = _creditPosition();
        assertEq(removedAssets, assetsToRemove);
        assertEq(CURVE_LP.balanceOf(collateralReceiver) - receiverBalanceBefore, assetsToRemove);
        assertEq(creditPosition.collateralAssets, collateralAmount - assetsToRemove);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), collateralAmount - assetsToRemove);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
        assertEq(CONVEX_DEPOSIT_TOKEN.balanceOf(address(market)), 0);
        assertEq(
            CONVEX_DEPOSIT_TOKEN.balanceOf(CONVEX_REWARD_POOL_ADDRESS) - rewardPoolDepositTokenBefore,
            collateralAmount - assetsToRemove
        );
    }

    function testFork_BorrowAndRepayProductionDusd() external {
        _addAllCollateral();
        uint256 borrowAmount = _halfCollateralValue();

        uint256 dusdBalanceBefore = DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT);
        vm.prank(CREDIT_ACCOUNT);
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFee) =
            market.borrow(borrowAmount, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, bytes(""));

        Position memory creditPosition = _creditPosition();
        Balance memory totalBorrowed = _totalBorrowed();
        (uint256 minted, uint256 ceiling) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(borrowedAssets, borrowAmount);
        assertGt(borrowedShares, 0);
        assertEq(openingFee, 0);
        assertEq(DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT) - dusdBalanceBefore, borrowAmount);
        assertEq(creditPosition.borrowShares, borrowedShares);
        assertEq(totalBorrowed.assets, borrowAmount);
        assertEq(totalBorrowed.shares, borrowedShares);
        assertEq(minted, borrowAmount);
        assertEq(ceiling, DUSD_MINTER_CEILING);

        vm.prank(CREDIT_ACCOUNT);
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(0, borrowedShares, CREDIT_ACCOUNT);

        creditPosition = _creditPosition();
        totalBorrowed = _totalBorrowed();
        (minted, ceiling) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(repaidAssets, borrowAmount);
        assertEq(repaidShares, borrowedShares);
        assertEq(DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT), dusdBalanceBefore);
        assertEq(creditPosition.borrowShares, 0);
        assertEq(totalBorrowed.assets, 0);
        assertEq(totalBorrowed.shares, 0);
        assertEq(minted, 0);
        assertEq(ceiling, DUSD_MINTER_CEILING);

        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(collateralAmount, CREDIT_ACCOUNT, CREDIT_ACCOUNT, bytes(""));

        creditPosition = _creditPosition();
        assertEq(creditPosition.collateralAssets, 0);
        assertEq(CURVE_LP.balanceOf(CREDIT_ACCOUNT), collateralAmount);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), 0);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
    }

    function testFork_ClaimRewardsForwardsConfiguredTokens() external {
        _addAllCollateral();

        uint256 stakedBefore = CONVEX_REWARD_POOL.balanceOf(address(market));
        Position memory positionBefore = _creditPosition();
        assertGt(CONVEX_REWARD_POOL.periodFinish(), block.timestamp + REWARD_ACCRUAL_TIME);

        vm.warp(block.timestamp + REWARD_ACCRUAL_TIME);
        vm.roll(block.number + REWARD_ACCRUAL_BLOCKS);
        assertGt(CONVEX_REWARD_POOL.earned(address(market)), 0);

        uint256 recipientCrvBefore = CRV.balanceOf(CREDIT_ACCOUNT);
        uint256 recipientCvxBefore = CVX.balanceOf(CREDIT_ACCOUNT);
        uint256 recipientWfraxBefore = WFRAX.balanceOf(CREDIT_ACCOUNT);
        uint256 callerCrvBefore = CRV.balanceOf(claimCaller);
        uint256 callerCvxBefore = CVX.balanceOf(claimCaller);
        uint256 callerWfraxBefore = WFRAX.balanceOf(claimCaller);

        vm.prank(claimCaller);
        uint256[] memory claimedAmounts = market.claimRewards();

        uint256 claimedCrv = CRV.balanceOf(CREDIT_ACCOUNT) - recipientCrvBefore;
        uint256 claimedCvx = CVX.balanceOf(CREDIT_ACCOUNT) - recipientCvxBefore;
        uint256 claimedWfrax = WFRAX.balanceOf(CREDIT_ACCOUNT) - recipientWfraxBefore;
        assertEq(claimedAmounts.length, 3);
        assertEq(claimedAmounts[0], claimedCrv);
        assertEq(claimedAmounts[1], claimedCvx);
        assertEq(claimedAmounts[2], claimedWfrax);
        assertGt(claimedCrv, 0);
        assertGt(claimedCvx, 0);
        assertEq(CRV.balanceOf(address(market)), 0);
        assertEq(CVX.balanceOf(address(market)), 0);
        assertEq(WFRAX.balanceOf(address(market)), 0);
        assertEq(CRV.balanceOf(claimCaller), callerCrvBefore);
        assertEq(CVX.balanceOf(claimCaller), callerCvxBefore);
        assertEq(WFRAX.balanceOf(claimCaller), callerWfraxBefore);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), stakedBefore);

        Position memory positionAfter = _creditPosition();
        assertEq(positionAfter.supplyShares, positionBefore.supplyShares);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares);
        assertEq(positionAfter.collateralAssets, positionBefore.collateralAssets);
    }

    function testFork_GovernanceLiquidateAfterPriceHalving() external {
        _addAllCollateral();
        uint256 borrowAmount = _halfCollateralValue();

        vm.prank(CREDIT_ACCOUNT);
        market.borrow(borrowAmount, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, bytes(""));

        Balance memory totalBorrowedBefore = _totalBorrowed();
        Position memory positionBefore = _creditPosition();
        uint256 governanceLpBefore = CURVE_LP.balanceOf(ALTO_TIMELOCK);
        uint256 borrowerDusdBefore = DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT);
        (uint256 mintedBefore, uint256 ceilingBefore) = DUSD_TOKEN.minterConfig(address(market));

        oracle.setPrice(initialOraclePrice / 2);
        vm.prank(ALTO_TIMELOCK);
        (uint256 seizedCollateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT, false);

        Position memory positionAfter = _creditPosition();
        Balance memory totalBorrowedAfter = _totalBorrowed();
        (uint256 mintedAfter, uint256 ceilingAfter) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(seizedCollateral, collateralAmount);
        assertEq(badDebt, totalBorrowedBefore.assets);
        assertEq(CURVE_LP.balanceOf(ALTO_TIMELOCK) - governanceLpBefore, collateralAmount);
        assertEq(positionBefore.collateralAssets, collateralAmount);
        assertGt(positionBefore.borrowShares, 0);
        assertEq(positionAfter.supplyShares, 0);
        assertEq(positionAfter.borrowShares, 0);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(totalBorrowedAfter.assets, 0);
        assertEq(totalBorrowedAfter.shares, 0);
        assertEq(market.badDebtAssets(), badDebt);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), 0);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
        assertTrue(market.convexActive());
        assertEq(DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT), borrowerDusdBefore);
        // Foreclosure realizes bad debt in market accounting; it does not burn DUSD held by the borrower.
        assertEq(mintedAfter, mintedBefore);
        assertEq(ceilingAfter, ceilingBefore);
        assertEq(mintedAfter, borrowAmount);
    }

    function testFork_ForeclosureRecoveryUnwindsLpAndSettlesMaximumBadDebt() external {
        uint256 maximumBorrow = _openMaximumRecoveryPosition();
        _forecloseRecoveryPosition(maximumBorrow);
        uint256 recoveredDusd = _unwindAndSwapSeizedCollateral();
        _settleRecoveredBadDebt(recoveredDusd, maximumBorrow);
    }

    function _openMaximumRecoveryPosition() private returns (uint256 maximumBorrow) {
        _mintCurveLp(RECOVERY_FRXUSD_DEPOSIT);
        assertGe(CURVE_LP.balanceOf(CREDIT_ACCOUNT), RECOVERY_COLLATERAL);

        vm.prank(CREDIT_ACCOUNT);
        uint256 addedCollateral = market.addCollateral(RECOVERY_COLLATERAL, CREDIT_ACCOUNT);
        assertEq(addedCollateral, RECOVERY_COLLATERAL);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), RECOVERY_COLLATERAL);

        uint256 collateralValue = Math.mulDiv(RECOVERY_COLLATERAL, initialOraclePrice, LENDING_ORACLE_PRICE_PRECISION);
        maximumBorrow = Math.mulDiv(collateralValue, MAX_LTV, 1 ether);
        uint256 borrowerDusdBefore = DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT);

        vm.prank(CREDIT_ACCOUNT);
        (uint256 borrowedAssets,,) = market.borrow(maximumBorrow, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, bytes(""));
        assertEq(borrowedAssets, maximumBorrow);
        assertEq(DUSD_TOKEN.balanceOf(CREDIT_ACCOUNT) - borrowerDusdBefore, maximumBorrow);

        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        vm.prank(CREDIT_ACCOUNT);
        market.borrow(1, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, bytes(""));
    }

    function _forecloseRecoveryPosition(uint256 maximumBorrow) private {
        vm.startPrank(ALTO_TIMELOCK);
        market.setMaxLtv(RECOVERY_MAX_LTV);
        market.setForeclosureLtv(RECOVERY_FORECLOSURE_LTV);
        vm.stopPrank();
        assertEq(market.maxLtv(), RECOVERY_MAX_LTV);
        assertEq(market.foreclosureLtv(), RECOVERY_FORECLOSURE_LTV);

        Balance memory debtBeforeLiquidation = _totalBorrowed();
        uint256 collateralValue = Math.mulDiv(RECOVERY_COLLATERAL, initialOraclePrice, LENDING_ORACLE_PRICE_PRECISION);
        uint256 foreclosureDebt = Math.mulDiv(collateralValue, RECOVERY_FORECLOSURE_LTV, 1 ether);
        assertEq(debtBeforeLiquidation.assets, maximumBorrow);
        assertGt(debtBeforeLiquidation.assets, foreclosureDebt);

        uint256 ownerLpBefore = CURVE_LP.balanceOf(ALTO_TIMELOCK);
        vm.prank(ALTO_TIMELOCK);
        (uint256 seizedCollateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(seizedCollateral, RECOVERY_COLLATERAL);
        assertEq(badDebt, maximumBorrow);
        assertEq(CURVE_LP.balanceOf(ALTO_TIMELOCK) - ownerLpBefore, RECOVERY_COLLATERAL);
        assertEq(market.badDebtAssets(), badDebt);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), 0);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
        Position memory liquidatedPosition = _creditPosition();
        Balance memory totalBorrowedAfterLiquidation = _totalBorrowed();
        assertEq(liquidatedPosition.borrowShares, 0);
        assertEq(liquidatedPosition.collateralAssets, 0);
        assertEq(totalBorrowedAfterLiquidation.assets, 0);
        assertEq(totalBorrowedAfterLiquidation.shares, 0);
    }

    function _unwindAndSwapSeizedCollateral() private returns (uint256 recoveredDusd) {
        uint256 ownerLpBefore = CURVE_LP.balanceOf(ALTO_TIMELOCK) - RECOVERY_COLLATERAL;
        uint256 ownerFrxUsdBefore = FRXUSD.balanceOf(ALTO_TIMELOCK);
        uint256 ownerDusdBefore = DUSD_TOKEN.balanceOf(ALTO_TIMELOCK);
        uint256[] memory minimumAmounts = new uint256[](2);

        vm.prank(ALTO_TIMELOCK);
        uint256[] memory withdrawnAmounts =
            CURVE_POOL.remove_liquidity(RECOVERY_COLLATERAL, minimumAmounts, ALTO_TIMELOCK, true);

        assertEq(withdrawnAmounts.length, 2);
        assertGt(withdrawnAmounts[0], 0);
        assertGt(withdrawnAmounts[1], 0);
        assertEq(FRXUSD.balanceOf(ALTO_TIMELOCK) - ownerFrxUsdBefore, withdrawnAmounts[0]);
        assertEq(DUSD_TOKEN.balanceOf(ALTO_TIMELOCK) - ownerDusdBefore, withdrawnAmounts[1]);
        assertEq(CURVE_LP.balanceOf(ALTO_TIMELOCK), ownerLpBefore);

        uint256 quotedDusd = CURVE_POOL.get_dy(0, 1, withdrawnAmounts[0]);
        vm.startPrank(ALTO_TIMELOCK);
        FRXUSD.approve(CURVE_POOL_ADDRESS, withdrawnAmounts[0]);
        uint256 swappedDusd = CURVE_POOL.exchange(0, 1, withdrawnAmounts[0], 0, ALTO_TIMELOCK);
        vm.stopPrank();

        recoveredDusd = DUSD_TOKEN.balanceOf(ALTO_TIMELOCK) - ownerDusdBefore;
        assertEq(swappedDusd, quotedDusd);
        assertEq(recoveredDusd, withdrawnAmounts[1] + swappedDusd);
        assertEq(FRXUSD.balanceOf(ALTO_TIMELOCK), ownerFrxUsdBefore);
    }

    function _settleRecoveredBadDebt(uint256 recoveredDusd, uint256 maximumBorrow) private {
        (uint256 mintedBeforeSettlement,) = DUSD_TOKEN.minterConfig(address(market));
        uint256 badDebtBeforeSettlement = market.badDebtAssets();
        uint256 claimableFeesBeforeSettlement = market.claimableFeesAssets();
        uint256 ownerDusdBeforeSettlement = DUSD_TOKEN.balanceOf(ALTO_TIMELOCK);
        uint256 totalSupplyBeforeSettlement = DUSD_TOKEN.totalSupply();
        uint256 settlementAmount = Math.min(recoveredDusd, Math.min(badDebtBeforeSettlement, mintedBeforeSettlement));

        assertEq(mintedBeforeSettlement, maximumBorrow);
        assertEq(settlementAmount, maximumBorrow);
        assertEq(DUSD_TOKEN.allowance(ALTO_TIMELOCK, address(market)), 0);

        vm.prank(ALTO_TIMELOCK);
        market.settleBadDebt(settlementAmount);

        (uint256 mintedAfterSettlement,) = DUSD_TOKEN.minterConfig(address(market));
        uint256 residualBadDebt = badDebtBeforeSettlement - settlementAmount;
        assertEq(DUSD_TOKEN.balanceOf(ALTO_TIMELOCK), ownerDusdBeforeSettlement - settlementAmount);
        assertEq(DUSD_TOKEN.totalSupply(), totalSupplyBeforeSettlement - settlementAmount);
        assertEq(mintedAfterSettlement, 0);
        assertEq(market.badDebtAssets(), residualBadDebt);
        assertEq(residualBadDebt, 0);
        assertEq(residualBadDebt, claimableFeesBeforeSettlement);
        assertEq(market.claimableFeesAssets(), claimableFeesBeforeSettlement);
        assertEq(DUSD_TOKEN.balanceOf(address(market)), 0);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
    }

    function _marketInitParams() private view returns (ConvexCreditLineInitParams memory params) {
        address[] memory rewardTokens = new address[](3);
        rewardTokens[0] = CRV_ADDRESS;
        rewardTokens[1] = CVX_ADDRESS;
        rewardTokens[2] = WFRAX_ADDRESS;

        params = ConvexCreditLineInitParams({
            creditMarketInitParams: CreditMarketInitParams({
                baseMarketInitParams: BaseMarketInitParams({
                    borrowToken: DUSD_ADDRESS,
                    collateralToken: CURVE_POOL_ADDRESS,
                    irm: address(irm),
                    owner: ALTO_TIMELOCK,
                    emergencyAdmin: ALTO_TIMELOCK,
                    oracle: address(oracle),
                    maxLtv: MAX_LTV,
                    feeRecipient: FEE_RECIPIENT,
                    liquidationEngine: address(0)
                }),
                creditAccount: CREDIT_ACCOUNT,
                creditLimit: CREDIT_LIMIT,
                foreclosureLtv: FORECLOSURE_LTV,
                initialBorrowOpeningFee: 0
            }),
            convexBooster: CONVEX_BOOSTER_ADDRESS,
            convexPoolId: CONVEX_POOL_ID,
            rewardRecipient: CREDIT_ACCOUNT,
            rewardTokens: rewardTokens
        });
    }

    function _authorizeMarketOnDusd() private {
        address dusdOwner = DUSD_TOKEN.owner();
        vm.startPrank(dusdOwner);
        DUSD_TOKEN.setMinterStatus(address(market), true);
        DUSD_TOKEN.setMinterCeiling(address(market), DUSD_MINTER_CEILING);
        DUSD_TOKEN.setBurnerStatus(address(market), true);
        vm.stopPrank();
    }

    function _mintCurveLp() private returns (uint256 mintedLp) {
        return _mintCurveLp(FRXUSD_DEPOSIT);
    }

    function _mintCurveLp(uint256 frxUsdDeposit) private returns (uint256 mintedLp) {
        deal(FRXUSD_ADDRESS, CREDIT_ACCOUNT, FRXUSD.balanceOf(CREDIT_ACCOUNT) + frxUsdDeposit);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = frxUsdDeposit;
        uint256 lpBalanceBefore = CURVE_LP.balanceOf(CREDIT_ACCOUNT);

        vm.startPrank(CREDIT_ACCOUNT);
        FRXUSD.approve(CURVE_POOL_ADDRESS, frxUsdDeposit);
        mintedLp = CURVE_POOL.add_liquidity(amounts, 0, CREDIT_ACCOUNT);
        CURVE_LP.approve(address(market), type(uint256).max);
        vm.stopPrank();

        assertEq(CURVE_LP.balanceOf(CREDIT_ACCOUNT) - lpBalanceBefore, mintedLp);
        assertGt(mintedLp, 0);
    }

    function _addAllCollateral() private returns (uint256 addedAssets) {
        vm.prank(CREDIT_ACCOUNT);
        addedAssets = market.addCollateral(collateralAmount, CREDIT_ACCOUNT);
    }

    function _halfCollateralValue() private view returns (uint256) {
        return Math.mulDiv(collateralAmount, initialOraclePrice, LENDING_ORACLE_PRICE_PRECISION) / 2;
    }

    function _creditPosition() private view returns (Position memory creditPosition) {
        (creditPosition.supplyShares, creditPosition.borrowShares, creditPosition.collateralAssets) =
            market.position(CREDIT_ACCOUNT);
    }

    function _totalBorrowed() private view returns (Balance memory borrowed) {
        (borrowed.assets, borrowed.shares) = market.totalBorrowed();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {CreditMarketInitParams} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {ConvexCreditLineInitParams} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {IConvexBooster} from "@alto/lending/interfaces/vendor/IConvexBooster.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";
import {Balance, BaseMarketInitParams, MarketType, Position} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";

interface ICurveFrxUsdDusdPool {
    function coins(uint256 index) external view returns (address);

    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);
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

    uint256 private constant MAX_LTV = 0.75 ether;
    uint256 private constant FORECLOSURE_LTV = 0.9 ether;
    uint256 private constant CREDIT_LIMIT = 1_000_000 ether;
    uint256 private constant BORROW_RATE = 0.04 ether / uint256(365 days);
    uint256 private constant FRXUSD_DEPOSIT = 1_000 ether;
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

    ICurveFrxUsdDusdPool private constant CURVE_POOL = ICurveFrxUsdDusdPool(CURVE_POOL_ADDRESS);
    IConvexBooster private constant CONVEX_BOOSTER = IConvexBooster(CONVEX_BOOSTER_ADDRESS);
    IConvexRewardPoolFork private constant CONVEX_REWARD_POOL = IConvexRewardPoolFork(CONVEX_REWARD_POOL_ADDRESS);
    DUSD private constant DUSD_TOKEN = DUSD(DUSD_ADDRESS);
    IERC20 private constant FRXUSD = IERC20(FRXUSD_ADDRESS);
    IERC20 private constant CURVE_LP = IERC20(CURVE_POOL_ADDRESS);
    IERC20 private constant CONVEX_DEPOSIT_TOKEN = IERC20(CONVEX_DEPOSIT_TOKEN_ADDRESS);
    IERC20 private constant CRV = IERC20(CRV_ADDRESS);
    IERC20 private constant CVX = IERC20(CVX_ADDRESS);

    address private creditAccount;
    address private feeRecipient;
    address private rewardRecipient;
    address private claimCaller;
    address private collateralReceiver;

    AltoConvexCreditLineMarket private market;
    FixedRateIrm private irm;
    OracleMock private oracle;

    uint256 private initialOraclePrice;
    uint256 private collateralAmount;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);

        creditAccount = makeAddr("CreditAccount");
        feeRecipient = makeAddr("FeeRecipient");
        rewardRecipient = makeAddr("RewardRecipient");
        claimCaller = makeAddr("ClaimCaller");
        collateralReceiver = makeAddr("CollateralReceiver");

        oracle = new OracleMock();
        // PRICING_LP option 1: virtual price multiplied by the minimum underlying price (both assumed at $1).
        initialOraclePrice = CURVE_POOL.get_virtual_price() * 1e18;
        oracle.setPrice(initialOraclePrice);

        irm = new FixedRateIrm(BORROW_RATE, address(this));
        AltoConvexCreditLineMarket implementation = new AltoConvexCreditLineMarket();
        market = AltoConvexCreditLineMarket(address(new ERC1967Proxy(address(implementation), "")));
        market.initialize(_marketInitParams());

        _authorizeMarketOnDusd();
        collateralAmount = _mintCurveLp();
    }

    function testFork_InitializationUsesLiveCurveAndConvexConfiguration() external view {
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
        assertEq(market.creditAccount(), creditAccount);
        assertEq(market.irm(), address(irm));
        assertEq(irm.market(), address(market));
        assertEq(market.oracle(), address(oracle));
        assertEq(market.maxLtv(), MAX_LTV);
        assertEq(market.foreclosureLtv(), FORECLOSURE_LTV);
        assertEq(market.creditLimit(), CREDIT_LIMIT);
        assertEq(market.liquidationEngine(), address(0));

        assertEq(market.convexBooster(), CONVEX_BOOSTER_ADDRESS);
        assertEq(market.convexPoolId(), CONVEX_POOL_ID);
        assertEq(market.convexRewardPool(), CONVEX_REWARD_POOL_ADDRESS);
        assertEq(market.convexDepositToken(), CONVEX_DEPOSIT_TOKEN_ADDRESS);
        assertEq(market.rewardRecipient(), rewardRecipient);
        assertTrue(market.convexActive());
        assertEq(market.rewardTokenCount(), 2);
        assertEq(market.rewardToken(0), CRV_ADDRESS);
        assertEq(market.rewardToken(1), CVX_ADDRESS);

        assertTrue(DUSD_TOKEN.allowedMinter(address(market)));
        assertTrue(DUSD_TOKEN.allowedBurner(address(market)));
        (uint256 minted, uint256 ceiling) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(minted, 0);
        assertEq(ceiling, CREDIT_LIMIT);
        assertGt(collateralAmount, 0);
    }

    function testFork_AddAndRemoveCollateralThroughConvex() external {
        uint256 rewardPoolDepositTokenBefore = CONVEX_DEPOSIT_TOKEN.balanceOf(CONVEX_REWARD_POOL_ADDRESS);

        uint256 addedAssets = _addAllCollateral();

        Position memory creditPosition = _creditPosition();
        assertEq(addedAssets, collateralAmount);
        assertEq(creditPosition.collateralAssets, collateralAmount);
        assertEq(market.stakedCollateralAssets(), collateralAmount);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), collateralAmount);
        assertEq(market.idleCollateralAssets(), 0);
        assertEq(CURVE_LP.balanceOf(address(market)), 0);
        // With stake=true, the reward pool holds the cvxLP while crediting the market through balanceOf.
        assertEq(CONVEX_DEPOSIT_TOKEN.balanceOf(address(market)), 0);
        assertEq(
            CONVEX_DEPOSIT_TOKEN.balanceOf(CONVEX_REWARD_POOL_ADDRESS) - rewardPoolDepositTokenBefore, collateralAmount
        );

        uint256 assetsToRemove = collateralAmount / 2;
        uint256 receiverBalanceBefore = CURVE_LP.balanceOf(collateralReceiver);
        vm.prank(creditAccount);
        uint256 removedAssets = market.removeCollateral(assetsToRemove, creditAccount, collateralReceiver, bytes(""));

        creditPosition = _creditPosition();
        assertEq(removedAssets, assetsToRemove);
        assertEq(CURVE_LP.balanceOf(collateralReceiver) - receiverBalanceBefore, assetsToRemove);
        assertEq(creditPosition.collateralAssets, collateralAmount - assetsToRemove);
        assertEq(market.stakedCollateralAssets(), collateralAmount - assetsToRemove);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), collateralAmount - assetsToRemove);
        assertEq(market.idleCollateralAssets(), 0);
        assertEq(CONVEX_DEPOSIT_TOKEN.balanceOf(address(market)), 0);
        assertEq(
            CONVEX_DEPOSIT_TOKEN.balanceOf(CONVEX_REWARD_POOL_ADDRESS) - rewardPoolDepositTokenBefore,
            collateralAmount - assetsToRemove
        );
    }

    function testFork_BorrowAndRepayProductionDusd() external {
        _addAllCollateral();
        uint256 borrowAmount = _halfCollateralValue();

        uint256 dusdBalanceBefore = DUSD_TOKEN.balanceOf(creditAccount);
        vm.prank(creditAccount);
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFee) =
            market.borrow(borrowAmount, 0, creditAccount, creditAccount, bytes(""));

        Position memory creditPosition = _creditPosition();
        Balance memory totalBorrowed = _totalBorrowed();
        (uint256 minted, uint256 ceiling) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(borrowedAssets, borrowAmount);
        assertGt(borrowedShares, 0);
        assertEq(openingFee, 0);
        assertEq(DUSD_TOKEN.balanceOf(creditAccount) - dusdBalanceBefore, borrowAmount);
        assertEq(creditPosition.borrowShares, borrowedShares);
        assertEq(totalBorrowed.assets, borrowAmount);
        assertEq(totalBorrowed.shares, borrowedShares);
        assertEq(minted, borrowAmount);
        assertEq(ceiling, CREDIT_LIMIT);

        vm.prank(creditAccount);
        (uint256 repaidAssets, uint256 repaidShares) = market.repay(0, borrowedShares, creditAccount);

        creditPosition = _creditPosition();
        totalBorrowed = _totalBorrowed();
        (minted, ceiling) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(repaidAssets, borrowAmount);
        assertEq(repaidShares, borrowedShares);
        assertEq(DUSD_TOKEN.balanceOf(creditAccount), dusdBalanceBefore);
        assertEq(creditPosition.borrowShares, 0);
        assertEq(totalBorrowed.assets, 0);
        assertEq(totalBorrowed.shares, 0);
        assertEq(minted, 0);
        assertEq(ceiling, CREDIT_LIMIT);

        vm.prank(creditAccount);
        market.removeCollateral(collateralAmount, creditAccount, creditAccount, bytes(""));

        creditPosition = _creditPosition();
        assertEq(creditPosition.collateralAssets, 0);
        assertEq(CURVE_LP.balanceOf(creditAccount), collateralAmount);
        assertEq(market.stakedCollateralAssets(), 0);
        assertEq(market.idleCollateralAssets(), 0);
    }

    function testFork_ClaimRewardsForwardsCrvAndCvx() external {
        _addAllCollateral();

        uint256 stakedBefore = market.stakedCollateralAssets();
        Position memory positionBefore = _creditPosition();
        assertGt(CONVEX_REWARD_POOL.periodFinish(), block.timestamp + REWARD_ACCRUAL_TIME);

        vm.warp(block.timestamp + REWARD_ACCRUAL_TIME);
        vm.roll(block.number + REWARD_ACCRUAL_BLOCKS);
        assertGt(CONVEX_REWARD_POOL.earned(address(market)), 0);

        uint256 recipientCrvBefore = CRV.balanceOf(rewardRecipient);
        uint256 recipientCvxBefore = CVX.balanceOf(rewardRecipient);
        uint256 callerCrvBefore = CRV.balanceOf(claimCaller);
        uint256 callerCvxBefore = CVX.balanceOf(claimCaller);

        vm.prank(claimCaller);
        uint256[] memory claimedAmounts = market.claimRewards();

        uint256 claimedCrv = CRV.balanceOf(rewardRecipient) - recipientCrvBefore;
        uint256 claimedCvx = CVX.balanceOf(rewardRecipient) - recipientCvxBefore;
        assertEq(claimedAmounts.length, 2);
        assertEq(claimedAmounts[0], claimedCrv);
        assertEq(claimedAmounts[1], claimedCvx);
        assertGt(claimedCrv, 0);
        assertGt(claimedCvx, 0);
        assertEq(CRV.balanceOf(address(market)), 0);
        assertEq(CVX.balanceOf(address(market)), 0);
        assertEq(CRV.balanceOf(claimCaller), callerCrvBefore);
        assertEq(CVX.balanceOf(claimCaller), callerCvxBefore);
        assertEq(market.stakedCollateralAssets(), stakedBefore);
        assertEq(CONVEX_REWARD_POOL.balanceOf(address(market)), stakedBefore);

        Position memory positionAfter = _creditPosition();
        assertEq(positionAfter.supplyShares, positionBefore.supplyShares);
        assertEq(positionAfter.borrowShares, positionBefore.borrowShares);
        assertEq(positionAfter.collateralAssets, positionBefore.collateralAssets);
    }

    function testFork_GovernanceLiquidateAfterPriceHalving() external {
        _addAllCollateral();
        uint256 borrowAmount = _halfCollateralValue();

        vm.prank(creditAccount);
        market.borrow(borrowAmount, 0, creditAccount, creditAccount, bytes(""));

        Balance memory totalBorrowedBefore = _totalBorrowed();
        Position memory positionBefore = _creditPosition();
        uint256 governanceLpBefore = CURVE_LP.balanceOf(address(this));
        uint256 borrowerDusdBefore = DUSD_TOKEN.balanceOf(creditAccount);
        (uint256 mintedBefore, uint256 ceilingBefore) = DUSD_TOKEN.minterConfig(address(market));

        oracle.setPrice(initialOraclePrice / 2);
        (uint256 seizedCollateral, uint256 badDebt) = market.governanceLiquidate(creditAccount);

        Position memory positionAfter = _creditPosition();
        Balance memory totalBorrowedAfter = _totalBorrowed();
        (uint256 mintedAfter, uint256 ceilingAfter) = DUSD_TOKEN.minterConfig(address(market));
        assertEq(seizedCollateral, collateralAmount);
        assertEq(badDebt, totalBorrowedBefore.assets);
        assertEq(CURVE_LP.balanceOf(address(this)) - governanceLpBefore, collateralAmount);
        assertEq(positionBefore.collateralAssets, collateralAmount);
        assertGt(positionBefore.borrowShares, 0);
        assertEq(positionAfter.supplyShares, 0);
        assertEq(positionAfter.borrowShares, 0);
        assertEq(positionAfter.collateralAssets, 0);
        assertEq(totalBorrowedAfter.assets, 0);
        assertEq(totalBorrowedAfter.shares, 0);
        assertEq(market.stakedCollateralAssets(), 0);
        assertEq(market.idleCollateralAssets(), 0);
        assertTrue(market.convexActive());
        assertEq(DUSD_TOKEN.balanceOf(creditAccount), borrowerDusdBefore);
        // Foreclosure realizes bad debt in market accounting; it does not burn DUSD held by the borrower.
        assertEq(mintedAfter, mintedBefore);
        assertEq(ceilingAfter, ceilingBefore);
        assertEq(mintedAfter, borrowAmount);
    }

    function _marketInitParams() private view returns (ConvexCreditLineInitParams memory params) {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = CRV_ADDRESS;
        rewardTokens[1] = CVX_ADDRESS;

        params = ConvexCreditLineInitParams({
            creditMarketInitParams: CreditMarketInitParams({
                baseMarketInitParams: BaseMarketInitParams({
                    borrowToken: DUSD_ADDRESS,
                    collateralToken: CURVE_POOL_ADDRESS,
                    irm: address(irm),
                    owner: address(this),
                    oracle: address(oracle),
                    maxLtv: MAX_LTV,
                    feeRecipient: feeRecipient,
                    liquidationEngine: address(0)
                }),
                creditAccount: creditAccount,
                creditLimit: CREDIT_LIMIT,
                foreclosureLtv: FORECLOSURE_LTV,
                initialBorrowOpeningFee: 0
            }),
            convexBooster: CONVEX_BOOSTER_ADDRESS,
            convexPoolId: CONVEX_POOL_ID,
            rewardRecipient: rewardRecipient,
            rewardTokens: rewardTokens
        });
    }

    function _authorizeMarketOnDusd() private {
        address dusdOwner = DUSD_TOKEN.owner();
        vm.startPrank(dusdOwner);
        DUSD_TOKEN.setMinterStatus(address(market), true);
        DUSD_TOKEN.setMinterCeiling(address(market), CREDIT_LIMIT);
        DUSD_TOKEN.setBurnerStatus(address(market), true);
        vm.stopPrank();
    }

    function _mintCurveLp() private returns (uint256 mintedLp) {
        deal(FRXUSD_ADDRESS, creditAccount, FRXUSD_DEPOSIT);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = FRXUSD_DEPOSIT;
        uint256 lpBalanceBefore = CURVE_LP.balanceOf(creditAccount);

        vm.startPrank(creditAccount);
        FRXUSD.approve(CURVE_POOL_ADDRESS, FRXUSD_DEPOSIT);
        mintedLp = CURVE_POOL.add_liquidity(amounts, 0, creditAccount);
        CURVE_LP.approve(address(market), type(uint256).max);
        vm.stopPrank();

        assertEq(CURVE_LP.balanceOf(creditAccount) - lpBalanceBefore, mintedLp);
        assertGt(mintedLp, 0);
    }

    function _addAllCollateral() private returns (uint256 addedAssets) {
        vm.prank(creditAccount);
        addedAssets = market.addCollateral(collateralAmount, creditAccount);
    }

    function _halfCollateralValue() private view returns (uint256) {
        return Math.mulDiv(collateralAmount, initialOraclePrice, LENDING_ORACLE_PRICE_PRECISION) / 2;
    }

    function _creditPosition() private view returns (Position memory creditPosition) {
        (creditPosition.supplyShares, creditPosition.borrowShares, creditPosition.collateralAssets) =
            market.position(creditAccount);
    }

    function _totalBorrowed() private view returns (Balance memory borrowed) {
        (borrowed.assets, borrowed.shares) = market.totalBorrowed();
    }
}

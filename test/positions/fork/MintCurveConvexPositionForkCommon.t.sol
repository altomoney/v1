// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PositionFactory} from "@alto/positions/PositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IPositionFactory.sol";
import {
    MintCurveConvexAddParams,
    MintCurveConvexRemoveMode,
    MintCurveConvexRemoveParams
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IConvexRewardPool} from "@alto/positions/interfaces/IConvex.sol";
import {IMarket, Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    CONVEX_BOOSTER_MAINNET,
    CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    FRXUSD_MAINNET,
    POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
    VELORA_AUGUSTUS_V6_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Shared mainnet-fork harness for MintCurveConvexPosition integration tests.
abstract contract MintCurveConvexPositionForkCommon is Test {
    uint256 internal constant BORROW_ASSETS = 20_000 ether;
    uint256 internal constant COLLATERAL_WETH = 25 ether;
    uint256 internal constant SLIPPAGE_BPS = 100; // 1.0%

    address internal constant WETH_MARKET_OWNER_MAINNET = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

    address internal constant DUSD_MAINNET = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant WETH_MINT_MARKET_MAINNET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address internal constant MARKET_REGISTRY_MAINNET = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;

    address internal user;
    PositionFactory internal factory;
    PositionBeacon internal positionBeacon;
    MintCurveConvexPosition internal position;

    function setUp() public virtual {
        user = makeAddr("User");
        _deployPositionInfrastructure();
        position = _createPosition(user);
    }

    function _deployPositionInfrastructure() internal {
        factory = PositionFactory(UnsafeUpgrades.deployUUPSProxy(address(new PositionFactory()), ""));
        factory.initialize(address(this), MARKET_REGISTRY_MAINNET);

        MintCurveConvexPosition implementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(implementation), address(this));

        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));
        factory.setMintCurveConvexConfig(_mainnetConfig());
        factory.setApprovedSwapTarget(VELORA_AUGUSTUS_V6_MAINNET, true);
    }

    function _mainnetConfig() internal pure returns (MintCurveConvexConfig memory config) {
        config = MintCurveConvexConfig({
            frxUsd: FRXUSD_MAINNET,
            curvePool: FRXUSD_DUSD_CURVE_POOL_MAINNET,
            convexBooster: CONVEX_BOOSTER_MAINNET,
            convexRewardPool: CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
            convexPid: POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
            crv: CRV_TOKEN_MAINNET,
            cvx: CVX_TOKEN_MAINNET
        });
    }

    function _createPosition(address owner) internal returns (MintCurveConvexPosition deployed) {
        vm.prank(owner);
        address positionAddr =
            factory.createPosition(PositionType.MINT_CURVE_CONVEX, abi.encode(WETH_MINT_MARKET_MAINNET));
        deployed = MintCurveConvexPosition(positionAddr);
    }

    function _fundUserWeth(uint256 amount) internal {
        deal(WETH_MAINNET, user, amount);
        vm.prank(user);
        IERC20(WETH_MAINNET).approve(address(position), type(uint256).max);
    }

    function _marketPosition(address account) internal view returns (Position memory) {
        return IMarket(WETH_MINT_MARKET_MAINNET).position(account);
    }

    function _stakedLpBalance() internal view returns (uint256) {
        return IConvexRewardPool(CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET).balanceOf(address(position));
    }

    function _addParams(
        uint256 collateralAmount,
        uint256 borrowAssets,
        bytes memory dusdToFrxUsdSwapData,
        bool relaxedMinOuts
    ) internal pure returns (MintCurveConvexAddParams memory params) {
        uint256 minFrxOut = borrowAssets == 0 || relaxedMinOuts ? 0 : _applySlippage(borrowAssets / 2);
        uint256 minLpOut = borrowAssets == 0 || relaxedMinOuts ? 0 : _applySlippage(borrowAssets);

        params = MintCurveConvexAddParams({
            collateralAmount: collateralAmount,
            borrowAssets: borrowAssets,
            swapTarget: VELORA_AUGUSTUS_V6_MAINNET,
            swapData: borrowAssets == 0 ? bytes("") : dusdToFrxUsdSwapData,
            minFrxUsdOutFromDusdSwap: minFrxOut,
            minLpOutFromCurve: minLpOut
        });
    }

    function _removeParams(
        MintCurveConvexRemoveMode mode,
        uint256 convexLpAmount,
        uint256 fraxAmount,
        uint256 repayShares,
        uint256 collateralAmount,
        bool claimRewards,
        bytes memory frxUsdToDusdSwapData,
        uint256 expectedDusdFromFrxSwap
    ) internal pure returns (MintCurveConvexRemoveParams memory params) {
        params = MintCurveConvexRemoveParams({
            mode: mode,
            convexLpAmount: convexLpAmount,
            minDusdFromCurve: 0,
            minFrxUsdFromCurve: 0,
            frxUsdAmountToSwap: fraxAmount,
            swapTarget: VELORA_AUGUSTUS_V6_MAINNET,
            swapData: fraxAmount == 0 ? bytes("") : frxUsdToDusdSwapData,
            minDusdOutFromFrxUsdSwap: fraxAmount == 0 ? 0 : _applySlippage(expectedDusdFromFrxSwap),
            repayShares: repayShares,
            collateralAmountToWithdraw: collateralAmount,
            claimRewards: claimRewards
        });
    }

    function _applySlippage(uint256 amount) internal pure returns (uint256) {
        return amount - (amount * SLIPPAGE_BPS / 10_000);
    }

    function _addSlippage(uint256 amount) internal pure returns (uint256) {
        return amount + (amount * SLIPPAGE_BPS / 10_000);
    }

    function _borrowAssetsForShares(uint256 shares) internal view returns (uint256 assets) {
        if (shares == 0) return 0;

        Balance memory totalBorrowed = IMarket(WETH_MINT_MARKET_MAINNET).totalBorrowed();
        if (totalBorrowed.shares == 0) return 0;

        assets = (shares * uint256(totalBorrowed.assets) + totalBorrowed.shares - 1) / totalBorrowed.shares;
    }

    /// @dev Floor estimate of DUSD returned when removing `lpAmount` from the Curve pool.
    function _estimateDusdFromLpRemove(uint256 lpAmount) internal view returns (uint256) {
        uint256 totalSupply = IERC20(FRXUSD_DUSD_CURVE_POOL_MAINNET).totalSupply();
        if (totalSupply == 0) return 0;

        return lpAmount * IERC20(DUSD_MAINNET).balanceOf(FRXUSD_DUSD_CURVE_POOL_MAINNET) / totalSupply;
    }

    /// @dev Minimum DUSD top-up so full share repayment succeeds after LP unwind + frx swap.
    function _fullCloseRepayBuffer(uint256 repayAssets, uint256 lpAmount, uint256 expectedDusdFromFrxSwap)
        internal
        view
        returns (uint256)
    {
        uint256 availableDusd = _estimateDusdFromLpRemove(lpAmount) + expectedDusdFromFrxSwap;
        if (repayAssets <= availableDusd) return 0;

        // +1 ether covers pool-ratio vs actual remove/swap drift on the fork block.
        return repayAssets - availableDusd + 1 ether;
    }

    function _encodeAdd(MintCurveConvexAddParams memory params) internal pure returns (bytes memory) {
        return abi.encode(params);
    }

    function _encodeRemove(MintCurveConvexRemoveParams memory params) internal pure returns (bytes memory) {
        return abi.encode(params);
    }

    function _makePositionLiquidatable() internal {
        _mockOraclePrice(900 * LENDING_ORACLE_PRICE_PRECISION);
    }

    function _mockOraclePrice(uint256 price) internal {
        IMarket market = IMarket(WETH_MINT_MARKET_MAINNET);
        address oracle = market.oracle();
        vm.mockCall(oracle, abi.encodeWithSelector(ILendingOracle.getPrice.selector), abi.encode(price));
    }

    function _partialLiquidatePosition(address borrower) internal returns (uint256 seized, uint256 repaid) {
        address liquidator = makeAddr("Liquidator");
        deal(DUSD_MAINNET, liquidator, BORROW_ASSETS);

        vm.startPrank(liquidator);
        IERC20(DUSD_MAINNET).approve(WETH_MINT_MARKET_MAINNET, type(uint256).max);
        (seized, repaid,) = IMarket(WETH_MINT_MARKET_MAINNET).liquidate(borrower, hex"", hex"");
        vm.stopPrank();
    }

    function _governanceLiquidatePosition(address borrower) internal {
        vm.prank(WETH_MARKET_OWNER_MAINNET);
        IMarket(WETH_MINT_MARKET_MAINNET).governanceLiquidate(borrower, false);
    }
}

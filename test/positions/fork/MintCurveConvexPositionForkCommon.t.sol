// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {IConvexRewardPool} from "@alto/positions/interfaces/IConvex.sol";
import {IMarket, Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    CONVEX_BOOSTER_MAINNET,
    CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Shared mainnet-fork harness for the dedicated MintCurveConvexPosition (one-sided DUSD flow).
abstract contract MintCurveConvexPositionForkCommon is Test {
    uint256 internal constant FORK_BLOCK = 25537175;

    uint256 internal constant BORROW_ASSETS = 20_000 ether;
    uint256 internal constant COLLATERAL_WETH = 25 ether;
    uint256 internal constant SLIPPAGE_BPS = 200; // 2.0% covers one-sided add/remove imbalance

    address internal constant WETH_MARKET_OWNER_MAINNET = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;

    address internal constant DUSD_MAINNET = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant WETH_MINT_MARKET_MAINNET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address internal constant MARKET_REGISTRY_MAINNET = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;

    address internal user;
    MintCurveConvexPositionFactory internal factory;
    PositionBeacon internal positionBeacon;
    MintCurveConvexPosition internal position;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);

        user = makeAddr("User");
        _deployPositionInfrastructure();
        position = _createPosition(user);
    }

    function _deployPositionInfrastructure() internal {
        factory = MintCurveConvexPositionFactory(
            UnsafeUpgrades.deployUUPSProxy(address(new MintCurveConvexPositionFactory()), "")
        );
        factory.initialize(address(this), MARKET_REGISTRY_MAINNET, _mainnetConfig());

        MintCurveConvexPosition implementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(implementation), address(this));

        factory.setBeacon(address(positionBeacon));
    }

    function _mainnetConfig() internal pure returns (MintCurveConvexConfig memory config) {
        config = MintCurveConvexConfig({
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
        deployed = MintCurveConvexPosition(factory.createPosition(WETH_MINT_MARKET_MAINNET));
    }

    /// @dev Deals WETH to the user and approves the position to pull it.
    function _fundUserWeth(uint256 amount) internal {
        deal(WETH_MAINNET, user, amount);
        vm.prank(user);
        IERC20(WETH_MAINNET).approve(address(position), type(uint256).max);
    }

    /// @dev Deals DUSD to the user and approves the position to pull it (for repay top-ups).
    function _fundUserDusd(uint256 amount) internal {
        deal(DUSD_MAINNET, user, amount);
        vm.prank(user);
        IERC20(DUSD_MAINNET).approve(address(position), type(uint256).max);
    }

    function _addCollateral(uint256 amount) internal {
        _fundUserWeth(amount);
        vm.prank(user);
        position.addCollateral(amount);
    }

    function _borrowAndDepositToLp(uint256 borrowAssets, uint256 minLpOut) internal {
        vm.prank(user);
        position.borrowAndDepositToLp(borrowAssets, minLpOut);
    }

    /// @dev Opens a full position: WETH collateral + borrowed DUSD supplied one-sided and staked.
    function _openBorrowPosition() internal returns (uint256 lpStaked) {
        _addCollateral(COLLATERAL_WETH);
        _borrowAndDepositToLp(BORROW_ASSETS, 0);
        lpStaked = _stakedLpBalance();
        assertGt(lpStaked, 0);
        assertGt(_marketPosition(address(position)).borrowShares, 0);
    }

    function _marketPosition(address account) internal view returns (Position memory) {
        return IMarket(WETH_MINT_MARKET_MAINNET).position(account);
    }

    function _stakedLpBalance() internal view returns (uint256) {
        return IConvexRewardPool(CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET).balanceOf(address(position));
    }

    /// @dev Pins the current market oracle price via mockCall so later time warps (for reward
    ///      accrual) don't trip Chainlink staleness in the market's solvency checks. Call while the
    ///      underlying feed is still fresh (before warping time forward).
    function _pinCollateralOraclePrice() internal {
        address oracle = IMarket(WETH_MINT_MARKET_MAINNET).oracle();
        (bool ok, bytes memory data) = oracle.staticcall(abi.encodeWithSignature("getPrice()"));
        require(ok, "oracle getPrice failed");
        uint256 price = abi.decode(data, (uint256));
        vm.mockCall(oracle, abi.encodeWithSignature("getPrice()"), abi.encode(price));
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

    function _governanceLiquidatePosition(address borrower) internal {
        vm.prank(WETH_MARKET_OWNER_MAINNET);
        IMarket(WETH_MINT_MARKET_MAINNET).governanceLiquidate(borrower, false);
    }
}

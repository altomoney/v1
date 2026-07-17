// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMintCurveConvexPosition} from "./interfaces/IMintCurveConvexPosition.sol";
import {IMintCurveConvexPositionFactory, MintCurveConvexConfig} from "./interfaces/IMintCurveConvexPositionFactory.sol";
import {ICurveStablePool} from "./interfaces/ICurveStablePool.sol";
import {IConvexBooster, IConvexRewardPool} from "./interfaces/IConvex.sol";

import {IMarket, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";

/// @title MintCurveConvexPosition
/// @notice Dedicated position implementation for the Mint borrow token -> Curve -> Convex strategy and its reverse.
/// @dev This contract needs to be deployed and set as the implementation in PositionBeacon contract.
contract MintCurveConvexPosition is
    IMintCurveConvexPosition,
    Initializable,
    OwnableUpgradeable,
    AuthUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable
{
    using SafeERC20 for IERC20;
    using AssetShareConversionMath for uint256;

    /// @inheritdoc IMintCurveConvexPosition
    IMintCurveConvexPositionFactory public factory;

    /// @inheritdoc IMintCurveConvexPosition
    IMarket public market;

    /// @inheritdoc IMintCurveConvexPosition
    MintCurveConvexConfig public config;

    /// @inheritdoc IMintCurveConvexPosition
    address public borrowToken;

    /// @inheritdoc IMintCurveConvexPosition
    uint256 public indexOfBorrowTokenInPool;

    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a beacon proxy instance for one owner.
    /// @param _owner The position owner.
    /// @param _factory The factory that deployed this position.
    /// @param _market The Alto mint market used for collateral and borrow token minting.
    /// @param _config The Curve/Convex configuration snapshot for this position.
    function initialize(address _owner, address _factory, address _market, MintCurveConvexConfig calldata _config)
        external
        virtual
        initializer
    {
        __MintCurveConvexPosition_init(_owner, _factory, _market, _config);
    }

    function __MintCurveConvexPosition_init(
        address _owner,
        address _factory,
        address _market,
        MintCurveConvexConfig calldata _config
    ) internal onlyInitializing {
        if (_factory == address(0) || _market == address(0)) {
            revert MintCurveConvexPositionInvalidInput();
        }
        __Ownable_init(_owner);
        __Auth_init();
        __ReentrancyGuard_init();
        __Multicall_init();
        factory = IMintCurveConvexPositionFactory(_factory);
        market = IMarket(_market);
        config = _config;
        borrowToken = market.borrowToken();
        indexOfBorrowTokenInPool = _coinIndex(_config.curvePool);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function addCollateral(uint256 amount) external override onlyOwnerOrAuthorized nonReentrant {
        if (amount == 0) revert MintCurveConvexPositionInvalidInput();

        address collateralToken = market.collateralToken();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(collateralToken).forceApprove(address(market), amount);
        market.addCollateral(amount, address(this));
        IERC20(collateralToken).forceApprove(address(market), 0);

        emit CollateralAdded(amount);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function removeCollateral(uint256 amount) external override onlyOwnerOrAuthorized nonReentrant {
        if (amount == 0) revert MintCurveConvexPositionInvalidInput();

        market.removeCollateral(amount, address(this), owner(), bytes(""));

        emit CollateralRemoved(amount);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function borrowAndDepositToLp(uint256 assetsToBorrow, uint256 minLpOut)
        external
        override
        onlyOwnerOrAuthorized
        nonReentrant
        returns (uint256 lpMinted)
    {
        if (assetsToBorrow == 0) revert MintCurveConvexPositionInvalidInput();

        address curvePool = config.curvePool;
        market.borrow(assetsToBorrow, 0, address(this), address(this), bytes(""));

        lpMinted = _depositCoin(curvePool, assetsToBorrow, minLpOut);

        _stakeToConvex(config.convexBooster, config.convexPid, curvePool, lpMinted);

        emit Deposited(assetsToBorrow, lpMinted);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function withdrawFromLpAndRepay(
        uint256 lpToWithdraw,
        uint256 minBorrowTokenOut,
        uint256 sharesToRepay,
        bool claimRewards
    )
        external
        override
        onlyOwnerOrAuthorized
        nonReentrant
        returns (uint256 borrowTokenReceived, uint256 assetsRepaid, uint256 crvAmount, uint256 cvxAmount)
    {
        if (lpToWithdraw == 0 && sharesToRepay == 0) revert MintCurveConvexPositionInvalidInput();
        if (lpToWithdraw == 0 && minBorrowTokenOut > 0) revert MintCurveConvexPositionInvalidInput();
        if (lpToWithdraw == 0 && claimRewards) revert MintCurveConvexPositionInvalidInput();

        address positionOwner = owner();

        if (lpToWithdraw > 0) {
            IConvexRewardPool(config.convexRewardPool).withdrawAndUnwrap(lpToWithdraw, claimRewards);
            borrowTokenReceived = _withdrawCoin(config.curvePool, lpToWithdraw, minBorrowTokenOut);

            if (claimRewards) {
                (crvAmount, cvxAmount) = _sweepRewards(positionOwner);
            }
        }

        if (sharesToRepay > 0) {
            assetsRepaid = _repay(sharesToRepay);
            emit Repaid(positionOwner, sharesToRepay, assetsRepaid);
        }

        uint256 borrowTokenBalance = IERC20(borrowToken).balanceOf(address(this));
        if (borrowTokenBalance > 0) {
            IERC20(borrowToken).safeTransfer(positionOwner, borrowTokenBalance);
        }

        emit Withdrawn(positionOwner, lpToWithdraw, borrowTokenReceived, sharesToRepay);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function repay(uint256 repayShares)
        external
        override
        onlyOwnerOrAuthorized
        nonReentrant
        returns (uint256 assetsRepaid)
    {
        if (repayShares == 0) revert MintCurveConvexPositionInvalidInput();

        assetsRepaid = _repay(repayShares);

        emit Repaid(owner(), repayShares, assetsRepaid);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function claimRewards()
        external
        override
        onlyOwnerOrAuthorized
        nonReentrant
        returns (uint256 crvAmount, uint256 cvxAmount)
    {
        IConvexRewardPool(config.convexRewardPool).getReward();
        (crvAmount, cvxAmount) = _sweepRewards(owner());
    }

    /// @inheritdoc IMintCurveConvexPosition
    function recoverERC20(address token, uint256 amount) external override onlyOwnerOrAuthorized nonReentrant {
        if (token == address(0) || amount == 0) revert MintCurveConvexPositionInvalidInput();

        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function version() external pure virtual override returns (uint256) {
        return 1;
    }

    /// @dev Deposits `borrowAmount` of borrow token into the Curve pool and mints LP to this contract.
    /// @dev This is one sided deposit of borrow token into the Curve pool while keeping other coin amount as 0
    function _depositCoin(address curvePool, uint256 borrowAmount, uint256 minLpOut)
        internal
        returns (uint256 lpMinted)
    {
        uint256[] memory amounts = new uint256[](2);
        amounts[indexOfBorrowTokenInPool] = borrowAmount;

        IERC20(borrowToken).forceApprove(curvePool, borrowAmount);
        lpMinted = ICurveStablePool(curvePool).add_liquidity(amounts, minLpOut);
        IERC20(borrowToken).forceApprove(curvePool, 0);
    }

    /// @dev Burns `lpToWithdraw` of Curve LP and withdraws borrow token back to this contract.
    function _withdrawCoin(address curvePool, uint256 lpToWithdraw, uint256 minBorrowTokenOut)
        internal
        returns (uint256 borrowTokenReceived)
    {
        int128 index = int128(uint128(indexOfBorrowTokenInPool));
        borrowTokenReceived =
            ICurveStablePool(curvePool).remove_liquidity_one_coin(lpToWithdraw, index, minBorrowTokenOut);
    }

    /// @dev Stakes Curve LP through the Convex booster; the receipt tokens are staked in the reward pool.
    function _stakeToConvex(address booster, uint256 poolId, address curveLpToken, uint256 lpAmount) internal {
        if (lpAmount == 0) return;

        IERC20(curveLpToken).forceApprove(booster, lpAmount);
        IConvexBooster(booster).deposit(poolId, lpAmount, true);
        IERC20(curveLpToken).forceApprove(booster, 0);
    }

    /// @dev Repays `repayShares` of debt, pulling any borrow token shortfall from the caller before repaying.
    function _repay(uint256 repayShares) internal returns (uint256 assetsNeeded) {
        market.accrueInterest();

        Balance memory totalBorrowed = market.totalBorrowed();
        assetsNeeded = repayShares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        uint256 borrowTokenBalance = IERC20(borrowToken).balanceOf(address(this));
        if (borrowTokenBalance < assetsNeeded) {
            IERC20(borrowToken).safeTransferFrom(msg.sender, address(this), assetsNeeded - borrowTokenBalance);
        }

        market.repay(0, repayShares, address(this));
    }

    /// @dev Transfers any CRV/CVX held by this contract to the owner.
    function _sweepRewards(address owner) internal returns (uint256 crvAmount, uint256 cvxAmount) {
        address crv = config.crv;
        address cvx = config.cvx;
        crvAmount = IERC20(crv).balanceOf(address(this));
        if (crvAmount > 0) {
            IERC20(crv).safeTransfer(owner, crvAmount);
        }

        cvxAmount = IERC20(cvx).balanceOf(address(this));
        if (cvxAmount > 0) {
            IERC20(cvx).safeTransfer(owner, cvxAmount);
        }

        emit RewardsClaimed(crvAmount, cvxAmount);
    }

    /// @dev Returns the index of borrow token within the two-coin Curve pool.
    function _coinIndex(address curvePool) internal view returns (uint256) {
        if (ICurveStablePool(curvePool).coins(0) == borrowToken) {
            return 0;
        } else if (ICurveStablePool(curvePool).coins(1) == borrowToken) {
            return 1;
        } else {
            revert MintCurveConvexPositionInvalidInput();
        }
    }

    modifier onlyOwnerOrAuthorized() {
        if (!_isSenderAuthorized(owner())) revert MintCurveConvexPositionUnauthorized();
        _;
    }
}

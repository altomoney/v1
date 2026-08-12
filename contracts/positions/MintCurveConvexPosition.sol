// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IMintCurveConvexPosition} from "./interfaces/IMintCurveConvexPosition.sol";
import {IMintCurveConvexPositionFactory, MintCurveConvexConfig} from "./interfaces/IMintCurveConvexPositionFactory.sol";
import {ICurveStableSwapNGLiquidity} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {IConvexBooster, IConvexRewardPool, IConvexStashTokenWrapper} from "./interfaces/IConvex.sol";

import {IMarket, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";

/// @title MintCurveConvexPosition
/// @notice Dedicated position implementation for the Mint borrow token -> Curve -> Convex strategy and its reverse.
/// @dev This contract needs to be deployed and set as the implementation in PositionBeacon contract.
/// @custom:audit Pending
contract MintCurveConvexPosition is
    IMintCurveConvexPosition,
    Initializable,
    Ownable2StepUpgradeable,
    AuthUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable
{
    using SafeERC20 for IERC20;
    using AssetShareConversionMath for uint256;

    bytes4 private constant CONVEX_STASH_REWARD_POOL_SELECTOR = bytes4(keccak256("rewardPool()"));
    bytes4 private constant CONVEX_STASH_BOOSTER_SELECTOR = bytes4(keccak256("booster()"));

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
        __Ownable2Step_init();
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
        returns (
            uint256 borrowTokenReceived,
            uint256 assetsRepaid,
            address[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        if (lpToWithdraw == 0 && sharesToRepay == 0) {
            revert MintCurveConvexPositionInvalidInput();
        }
        if (lpToWithdraw == 0 && minBorrowTokenOut > 0) revert MintCurveConvexPositionInvalidInput();
        if (lpToWithdraw == 0 && claimRewards) revert MintCurveConvexPositionInvalidInput();

        address positionOwner = owner();

        if (lpToWithdraw > 0) {
            bool success = IConvexRewardPool(config.convexRewardPool).withdrawAndUnwrap(lpToWithdraw, claimRewards);
            if (!success) revert MintCurveConvexPositionWithdrawalFromConvexRewardPoolFailed();
            borrowTokenReceived = _withdrawCoin(config.curvePool, lpToWithdraw, minBorrowTokenOut);
        }

        if (sharesToRepay > 0) {
            assetsRepaid = _repay(sharesToRepay);
            emit Repaid(positionOwner, sharesToRepay, assetsRepaid);
        }

        // Commit unwind proceeds to the requested repayment before sweeping arbitrary reward tokens.
        // An extra reward may legitimately use the borrow token, so it cannot safely be swept earlier.
        if (claimRewards) {
            (rewardTokens, rewardAmounts) = _sweepRewards(positionOwner);
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
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        bool success = IConvexRewardPool(config.convexRewardPool).getReward();
        if (!success) revert MintCurveConvexPositionClaimingRewardsFailed();
        (tokens, amounts) = _sweepRewards(owner());
    }

    /// @inheritdoc IMintCurveConvexPosition
    function recoverERC20(address token, uint256 amount) external override onlyOwnerOrAuthorized nonReentrant {
        if (token == address(0) || amount == 0) revert MintCurveConvexPositionInvalidInput();

        IERC20(token).safeTransfer(owner(), amount);

        emit ERC20Recovered(token, amount);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function version() external pure virtual override returns (uint256) {
        return 1;
    }

    /// @inheritdoc IMintCurveConvexPosition
    function renounceOwnership() public pure override(IMintCurveConvexPosition, OwnableUpgradeable) {
        revert MintCurveConvexPositionRenounceDisabled();
    }

    /// @inheritdoc IMintCurveConvexPosition
    function pendingOwner() public view override(IMintCurveConvexPosition, Ownable2StepUpgradeable) returns (address) {
        return super.pendingOwner();
    }

    /// @inheritdoc IMintCurveConvexPosition
    function transferOwnership(address newOwner) public override(IMintCurveConvexPosition, Ownable2StepUpgradeable) {
        super.transferOwnership(newOwner);
    }

    /// @inheritdoc IMintCurveConvexPosition
    function acceptOwnership() public override(IMintCurveConvexPosition, Ownable2StepUpgradeable) {
        address previousOwner = owner();
        super.acceptOwnership();
        factory.onPositionOwnershipTransferred(previousOwner);
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
        lpMinted = ICurveStableSwapNGLiquidity(curvePool).add_liquidity(amounts, minLpOut);
        IERC20(borrowToken).forceApprove(curvePool, 0);
    }

    /// @dev Burns `lpToWithdraw` of Curve LP and withdraws borrow token back to this contract.
    function _withdrawCoin(address curvePool, uint256 lpToWithdraw, uint256 minBorrowTokenOut)
        internal
        returns (uint256 borrowTokenReceived)
    {
        int128 index = int128(uint128(indexOfBorrowTokenInPool));
        borrowTokenReceived =
            ICurveStableSwapNGLiquidity(curvePool).remove_liquidity_one_coin(lpToWithdraw, index, minBorrowTokenOut);
    }

    /// @dev Stakes Curve LP through the Convex booster; the receipt tokens are staked in the reward pool.
    function _stakeToConvex(address booster, uint256 poolId, address curveLpToken, uint256 lpAmount) internal {
        if (lpAmount == 0) return;

        IERC20(curveLpToken).forceApprove(booster, lpAmount);
        bool success = IConvexBooster(booster).deposit(poolId, lpAmount, true);
        if (!success) revert MintCurveConvexPositionStakingFailed();
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

    /// @dev Transfers all Convex rewards held by this contract to `recipient`.
    function _sweepRewards(address recipient) internal returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = _rewardTokens();
        amounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            amounts[i] = amount;

            if (amount > 0) {
                IERC20(token).safeTransfer(recipient, amount);
                emit RewardClaimed(recipient, token, amount);
            }
        }
    }

    /// @dev Queries Convex for the current complete reward-token list and removes duplicates.
    function _rewardTokens() internal view returns (address[] memory tokens) {
        address rewardPool = config.convexRewardPool;
        uint256 extraRewardsLength = _extraRewardsLength(rewardPool);
        tokens = new address[](extraRewardsLength + 2);

        uint256 tokenCount = _appendUnique(tokens, 0, config.crv);
        tokenCount = _appendUnique(tokens, tokenCount, config.cvx);

        for (uint256 i = 0; i < extraRewardsLength; ++i) {
            (bool extraPoolSuccess, address extraRewardPool) =
                _readAddress(rewardPool, abi.encodeCall(IConvexRewardPool.extraRewards, (i)));
            if (!extraPoolSuccess || extraRewardPool.code.length == 0) continue;

            (bool rewardTokenSuccess, address rewardToken) =
                _readAddress(extraRewardPool, abi.encodeCall(IConvexRewardPool.rewardToken, ()));
            if (!rewardTokenSuccess || rewardToken.code.length == 0) continue;

            tokenCount = _appendUnique(tokens, tokenCount, _resolveRewardToken(extraRewardPool, rewardToken));
        }

        assembly ("memory-safe") {
            mstore(tokens, tokenCount)
        }
    }

    /// @dev Returns zero when the primary pool's extra-reward metadata cannot be queried safely.
    function _extraRewardsLength(address rewardPool) internal view returns (uint256 length) {
        (bool success, bytes memory returnData) =
            rewardPool.staticcall(abi.encodeCall(IConvexRewardPool.extraRewardsLength, ()));
        if (success && returnData.length == 32) {
            length = abi.decode(returnData, (uint256));
        }
    }

    /// @dev Uses the underlying token only for a positively identified Convex stash wrapper.
    function _resolveRewardToken(address extraRewardPool, address rewardToken) internal view returns (address token) {
        token = rewardToken;
        (bool tokenSuccess, address underlyingToken) =
            _readAddress(rewardToken, abi.encodeCall(IConvexStashTokenWrapper.token, ()));
        if (!tokenSuccess || underlyingToken.code.length == 0) return token;

        (bool rewardPoolSuccess, address wrapperRewardPool) =
            _readAddress(rewardToken, abi.encodeWithSelector(CONVEX_STASH_REWARD_POOL_SELECTOR));
        if (!rewardPoolSuccess || wrapperRewardPool != extraRewardPool) return token;

        (bool boosterSuccess, address wrapperBooster) =
            _readAddress(rewardToken, abi.encodeWithSelector(CONVEX_STASH_BOOSTER_SELECTOR));
        if (!boosterSuccess || wrapperBooster != config.convexBooster) return token;

        return underlyingToken;
    }

    /// @dev Safely reads one ABI-encoded, nonzero address from `target`.
    function _readAddress(address target, bytes memory callData) internal view returns (bool success, address result) {
        bytes memory returnData;
        (success, returnData) = target.staticcall(callData);
        if (!success || returnData.length != 32) return (false, address(0));

        uint256 decodedAddress = abi.decode(returnData, (uint256));
        if (decodedAddress == 0 || decodedAddress > type(uint160).max) return (false, address(0));

        // The bounds check above guarantees this narrowing conversion is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        result = address(uint160(decodedAddress));
    }

    /// @dev Appends `token` if it is nonzero and has not already been discovered.
    function _appendUnique(address[] memory tokens, uint256 tokenCount, address token) internal pure returns (uint256) {
        if (token == address(0)) return tokenCount;

        for (uint256 i = 0; i < tokenCount; ++i) {
            if (tokens[i] == token) return tokenCount;
        }

        tokens[tokenCount] = token;
        return tokenCount + 1;
    }

    /// @dev Returns the index of borrow token within the two-coin Curve pool.
    function _coinIndex(address curvePool) internal view returns (uint256) {
        if (ICurveStableSwapNGLiquidity(curvePool).coins(0) == borrowToken) {
            return 0;
        } else if (ICurveStableSwapNGLiquidity(curvePool).coins(1) == borrowToken) {
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

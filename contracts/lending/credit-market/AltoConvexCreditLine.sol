// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {AltoCreditMarketBase} from "@alto/lending/credit-market/AltoCreditMarketBase.sol";
import {ConvexCreditLineInitParams, IAltoConvexCreditLine} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {IConvexBooster} from "@alto/lending/interfaces/vendor/IConvexBooster.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";

/// @title Alto Convex Credit Line
///
/// @author Alto
///
/// @custom:contact security@altofoundation.org
///
/// @notice A single-account mint credit line gated by Curve LP deposited in
/// Convex, without public liquidation.
///
/// @dev The Curve LP is a locked facility deposit. It cannot be voluntarily
/// withdrawn while any borrow shares remain. Governance may seize the entire
/// position and close its debt after the foreclosure LTV is breached. Convex
/// rewards remain economically separate from collateral and debt accounting.
contract AltoConvexCreditLine is AltoCreditMarketBase, IAltoConvexCreditLine {
    // ========================================================================
    // Type Declarations
    // ========================================================================

    using SafeERC20 for IERC20;

    // ========================================================================
    // Constants
    // ========================================================================

    /// @notice Maximum number of reward tokens processed by a single claim.
    ///
    /// @dev Bounds the loop, token calls, and event emissions in `claimRewards()`.
    uint256 public constant MAX_REWARD_TOKENS = 16;

    // ========================================================================
    // State
    // ========================================================================

    /// @dev Convex Booster used to deposit the underlying Curve LP.
    address private s_convexBooster;

    /// @dev Pool identifier passed to the configured Convex Booster.
    uint256 private s_convexPoolId;

    /// @dev Convex reward pool that holds the market's staked balance.
    address private s_convexRewardPool;

    /// @dev Convex deposit token registered as the reward pool's staking token.
    address private s_convexDepositToken;

    /// @dev Fixed destination for rewards at the time a claim executes.
    address private s_rewardRecipient;

    /// @dev Whether new collateral may still be routed into Convex.
    bool private s_convexActive;

    /// @dev Reward tokens forwarded by `claimRewards`; order may change after removal.
    address[] private s_rewardTokens;

    /// @dev Constant-time membership check for the reward-token list.
    mapping(address => bool) private s_isRewardToken;

    // ========================================================================
    // Initialization
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the credit facility and binds it to a validated
    /// Convex pool.
    ///
    /// @param _params Credit-market and Convex initialization parameters.
    ///
    /// @dev The Booster pool must use the configured collateral token, be active,
    /// and resolve to a reward pool whose pool id, operator, and staking token
    /// match the Booster configuration. The initial reward list must be nonempty
    /// and include the reward pool's primary reward token.
    function initialize(ConvexCreditLineInitParams memory _params) public initializer {
        __AltoCreditMarketBase_init(_params.market);
        _initializeConvex(_params);
    }

    // ========================================================================
    // Functions - Market State
    // ========================================================================

    /// @inheritdoc IAltoConvexCreditLine
    function convexBooster() external view returns (address) {
        return s_convexBooster;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function convexPoolId() external view returns (uint256) {
        return s_convexPoolId;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function convexRewardPool() external view returns (address) {
        return s_convexRewardPool;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function convexDepositToken() external view returns (address) {
        return s_convexDepositToken;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function rewardRecipient() external view returns (address) {
        return s_rewardRecipient;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function convexActive() external view returns (bool) {
        return s_convexActive;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function rewardTokenCount() external view returns (uint256) {
        return s_rewardTokens.length;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function rewardToken(uint256 _index) external view returns (address) {
        return s_rewardTokens[_index];
    }

    /// @inheritdoc IAltoConvexCreditLine
    function isRewardToken(address _token) external view returns (bool) {
        return s_isRewardToken[_token];
    }

    /// @inheritdoc IAltoConvexCreditLine
    function stakedCollateralAssets() public view returns (uint256) {
        return IConvexRewardPool(s_convexRewardPool).balanceOf(address(this));
    }

    /// @inheritdoc IAltoConvexCreditLine
    function idleCollateralAssets() public view returns (uint256) {
        return IERC20(collateralToken()).balanceOf(address(this));
    }

    // ========================================================================
    // Functions - Position Management
    // ========================================================================

    /// @inheritdoc IAltoConvexCreditLine
    function claimRewards() external nonReentrant returns (uint256[] memory claimedAmounts) {
        bool success = IConvexRewardPool(s_convexRewardPool).getReward(address(this), true);
        if (!success) {
            revert AltoConvexCreditLine__ExternalCallFailed();
        }

        uint256 tokenCount = s_rewardTokens.length;
        claimedAmounts = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; ++i) {
            IERC20 token = IERC20(s_rewardTokens[i]);
            uint256 amount = token.balanceOf(address(this));
            claimedAmounts[i] = amount;

            if (amount != 0) {
                token.safeTransfer(s_rewardRecipient, amount);
            }

            emit RewardsClaimed(msg.sender, s_rewardRecipient, address(token), amount);
        }
    }

    /// @inheritdoc IAltoConvexCreditLine
    function setRewardRecipient(address _newRecipient) external {
        if (msg.sender != creditAccount()) {
            revert AltoCreditMarket__UnauthorizedAccount();
        }

        _assertNonZero(_newRecipient);

        emit SetRewardRecipient(s_rewardRecipient, _newRecipient);
        s_rewardRecipient = _newRecipient;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function addRewardToken(address _token) external onlyOwner {
        _addRewardToken(_token);
        emit RewardTokenAdded(_token);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function removeRewardToken(address _token) external onlyOwner {
        _assert(s_isRewardToken[_token]);
        _assert(_token != IConvexRewardPool(s_convexRewardPool).rewardToken());
        _assert(IERC20(_token).balanceOf(address(this)) == 0);

        uint256 n = s_rewardTokens.length;
        uint256 index = n;

        for (uint256 i; i < n; ++i) {
            if (s_rewardTokens[i] == _token) {
                index = i;
                break;
            }
        }

        _assert(index != n);

        uint256 lastIndex = n - 1;
        if (index != lastIndex) s_rewardTokens[index] = s_rewardTokens[lastIndex];
        s_rewardTokens.pop();
        delete s_isRewardToken[_token];

        emit RewardTokenRemoved(_token);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function emergencyExitConvex() external nonReentrant onlyOwner returns (uint256 assets) {
        if (!paused[PAUSE_TYPE]) revert AltoConvexCreditLine__MustBePaused();
        if (!s_convexActive) revert AltoConvexCreditLine__StrategyInactive();

        assets = stakedCollateralAssets();
        if (assets != 0) {
            uint256 idleBefore = idleCollateralAssets();
            bool success = IConvexRewardPool(s_convexRewardPool).withdrawAndUnwrap(assets, false);
            if (!success) {
                revert AltoConvexCreditLine__ExternalCallFailed();
            }

            if (idleCollateralAssets() - idleBefore != assets) {
                revert AltoConvexCreditLine__UnexpectedAssetDelta();
            }
        }

        s_convexActive = false;
        IERC20(collateralToken()).forceApprove(s_convexBooster, 0);
        emit ConvexEmergencyExit(assets);
    }

    // ========================================================================
    // Functions - Private and Internal Helpers
    // ========================================================================

    /// @notice Validates and stores Convex custody and reward configuration.
    ///
    /// @param _params Credit-line initialization parameters containing the
    /// Convex configuration.
    ///
    /// @dev Grants the Booster a maximum collateral-token allowance after
    /// validation.
    function _initializeConvex(ConvexCreditLineInitParams memory _params) private {
        _assertNonZero(_params.convexBooster);
        _assertNonZero(_params.rewardRecipient);

        (address lpToken, address depositToken, address gauge, address rewardPool,, bool shutdown) =
            IConvexBooster(_params.convexBooster).poolInfo(_params.convexPoolId);

        _assertNonZero(lpToken);
        _assertNonZero(depositToken);
        _assertNonZero(gauge);
        _assertNonZero(rewardPool);
        _assert(!shutdown);
        _assert(lpToken == collateralToken());

        IConvexRewardPool rewards = IConvexRewardPool(rewardPool);
        _assert(rewards.pid() == _params.convexPoolId);
        _assert(rewards.operator() == _params.convexBooster);
        _assert(rewards.stakingToken() == depositToken);

        uint256 tokenCount = _params.rewardTokens.length;
        _assertNonZero(tokenCount);

        s_convexBooster = _params.convexBooster;
        s_convexPoolId = _params.convexPoolId;
        s_convexRewardPool = rewardPool;
        s_convexDepositToken = depositToken;
        s_rewardRecipient = _params.rewardRecipient;
        s_convexActive = true;

        for (uint256 i = 0; i < tokenCount; ++i) {
            _addRewardToken(_params.rewardTokens[i]);
        }

        _assert(s_isRewardToken[rewards.rewardToken()]);

        // @TODO: Confirm max approve on init is inteded behaviour vs per
        // interaction on deposit.
        IERC20(collateralToken()).forceApprove(_params.convexBooster, type(uint256).max);

        emit ConvexConfigured(
            _params.convexBooster, _params.convexPoolId, rewardPool, depositToken, _params.rewardRecipient
        );
    }

    /// @notice Adds a validated token to the reward-forwarding list.
    ///
    /// @param _token Reward token to add.
    ///
    /// @dev Rejects zero, protected market assets, duplicate entries, and
    /// additions above `MAX_REWARD_TOKENS`.
    function _addRewardToken(address _token) private {
        _assertNonZero(_token);
        _assert(_token.code.length != 0);
        _assert(s_rewardTokens.length < MAX_REWARD_TOKENS);
        _assert(_token != collateralToken());
        _assert(_token != borrowToken());
        _assert(_token != s_convexDepositToken);
        _assert(!s_isRewardToken[_token]);

        s_isRewardToken[_token] = true;
        s_rewardTokens.push(_token);
    }

    /// @inheritdoc AltoCreditMarketBase
    ///
    /// @dev Pulls the exact Curve LP amount from the caller, deposits it through
    /// the Booster with staking enabled, and verifies both the idle LP decrease
    /// and reward-pool stake increase.
    function _receiveCollateral(uint256 _assets) internal override {
        _assert(s_convexActive);

        IERC20 lpToken = IERC20(collateralToken());
        uint256 idleBefore = lpToken.balanceOf(address(this));
        uint256 stakedBefore = stakedCollateralAssets();

        lpToken.safeTransferFrom(msg.sender, address(this), _assets);
        if (lpToken.balanceOf(address(this)) - idleBefore != _assets) {
            revert AltoConvexCreditLine__UnexpectedAssetDelta();
        }

        bool success = IConvexBooster(s_convexBooster).deposit(s_convexPoolId, _assets, true);
        if (!success) {
            revert AltoConvexCreditLine__ExternalCallFailed();
        }

        uint256 idleAfter = lpToken.balanceOf(address(this));
        if (idleAfter != idleBefore || stakedCollateralAssets() - stakedBefore != _assets) {
            revert AltoConvexCreditLine__UnexpectedAssetDelta();
        }

        emit CollateralStaked(msg.sender, _assets);
    }

    /// @inheritdoc AltoCreditMarketBase
    ///
    /// @dev While Convex is active, unstakes and unwraps the exact requested LP
    /// amount before transferring it. After an emergency exit, transfers the
    /// amount directly from idle custody. Reward claiming is deliberately
    /// disabled during unstaking so custody operations are not blocked by
    /// reward-token behavior.
    function _sendCollateral(address _receiver, uint256 _assets) internal override {
        IERC20 lpToken = IERC20(collateralToken());

        if (s_convexActive) {
            uint256 idleBefore = lpToken.balanceOf(address(this));
            bool success = IConvexRewardPool(s_convexRewardPool).withdrawAndUnwrap(_assets, false);
            if (!success) {
                revert AltoConvexCreditLine__ExternalCallFailed();
            }

            if (lpToken.balanceOf(address(this)) - idleBefore != _assets) {
                revert AltoConvexCreditLine__UnexpectedAssetDelta();
            }
        } else if (lpToken.balanceOf(address(this)) < _assets) {
            revert AltoConvexCreditLine__UnexpectedAssetDelta();
        }

        lpToken.safeTransfer(_receiver, _assets);
        emit CollateralUnstaked(_receiver, _assets);
    }
}

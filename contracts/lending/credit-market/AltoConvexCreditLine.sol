// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {AltoCreditMarketBase} from "./AltoCreditMarketBase.sol";
import {ConvexCreditLineInitParams, IAltoConvexCreditLine} from "../interfaces/IAltoConvexCreditLine.sol";
import {IConvexBooster} from "../interfaces/vendor/IConvexBooster.sol";
import {IConvexRewardPool} from "../interfaces/vendor/IConvexRewardPool.sol";

/// @title Alto Convex Credit Line
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Convex Credit Line
/// @dev Convex rewards remain separate from collateral and debt accounting
contract AltoConvexCreditLine is AltoCreditMarketBase, IAltoConvexCreditLine {
    using SafeERC20 for IERC20;

    /// @notice Maximum number of reward tokens processed by a single claim
    uint256 public constant MAX_REWARD_TOKENS = 16;

    /// @inheritdoc IAltoConvexCreditLine
    address public convexBooster;

    /// @inheritdoc IAltoConvexCreditLine
    uint256 public convexPoolId;

    /// @inheritdoc IAltoConvexCreditLine
    address public convexRewardPool;

    /// @inheritdoc IAltoConvexCreditLine
    address public convexDepositToken;

    /// @inheritdoc IAltoConvexCreditLine
    address public rewardRecipient;

    /// @inheritdoc IAltoConvexCreditLine
    bool public convexActive;

    /// @dev Reward tokens forwarded by `claimRewards`; order may change after removal
    address[] private _rewardTokens;

    /// @inheritdoc IAltoConvexCreditLine
    mapping(address => bool) public isRewardToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the credit market and Convex pool
    /// @param _initParams The credit market and Convex initialization parameters
    function initialize(ConvexCreditLineInitParams memory _initParams) public initializer {
        __AltoCreditMarketBase_init(_initParams.creditMarketInitParams);
        _initializeConvex(_initParams);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function rewardTokenCount() external view returns (uint256) {
        return _rewardTokens.length;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function rewardToken(uint256 index) external view returns (address) {
        return _rewardTokens[index];
    }

    /// @inheritdoc IAltoConvexCreditLine
    function stakedCollateralAssets() public view returns (uint256) {
        return IConvexRewardPool(convexRewardPool).balanceOf(address(this));
    }

    /// @inheritdoc IAltoConvexCreditLine
    function idleCollateralAssets() public view returns (uint256) {
        return IERC20(collateralToken).balanceOf(address(this));
    }

    /// @inheritdoc IAltoConvexCreditLine
    function claimRewards() external nonReentrant returns (uint256[] memory claimedAmounts) {
        bool success = IConvexRewardPool(convexRewardPool).getReward(address(this), true);
        if (!success) {
            revert AltoConvexCreditLineExternalCallFailed();
        }

        uint256 tokenCount = _rewardTokens.length;
        claimedAmounts = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; ++i) {
            IERC20 token = IERC20(_rewardTokens[i]);
            uint256 amount = token.balanceOf(address(this));
            claimedAmounts[i] = amount;

            if (amount != 0) {
                token.safeTransfer(rewardRecipient, amount);
            }

            emit RewardsClaimed(msg.sender, rewardRecipient, address(token), amount);
        }
    }

    /// @inheritdoc IAltoConvexCreditLine
    function setRewardRecipient(address _newRecipient) external {
        if (msg.sender != creditAccount) {
            revert AltoCreditMarketUnauthorizedAccount();
        }
        if (_newRecipient == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }

        emit SetRewardRecipient(rewardRecipient, _newRecipient);
        rewardRecipient = _newRecipient;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function addRewardToken(address _token) external onlyOwner {
        _addRewardToken(_token);
        emit RewardTokenAdded(_token);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function removeRewardToken(address _token) external onlyOwner {
        if (
            !isRewardToken[_token] || _token == IConvexRewardPool(convexRewardPool).rewardToken()
                || IERC20(_token).balanceOf(address(this)) != 0
        ) {
            revert AltoCreditMarketInvalidInput();
        }

        uint256 n = _rewardTokens.length;
        uint256 index = n;

        for (uint256 i; i < n; ++i) {
            if (_rewardTokens[i] == _token) {
                index = i;
                break;
            }
        }

        if (index == n) {
            revert AltoCreditMarketInvalidInput();
        }

        uint256 lastIndex = n - 1;
        if (index != lastIndex) {
            _rewardTokens[index] = _rewardTokens[lastIndex];
        }
        _rewardTokens.pop();
        delete isRewardToken[_token];

        emit RewardTokenRemoved(_token);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function emergencyExitConvex() external nonReentrant onlyOwner returns (uint256 assets) {
        if (!paused[PAUSE_TYPE]) {
            revert AltoConvexCreditLineMustBePaused();
        }
        if (!convexActive) {
            revert AltoConvexCreditLineStrategyInactive();
        }

        assets = stakedCollateralAssets();
        if (assets != 0) {
            uint256 idleBefore = idleCollateralAssets();
            bool success = IConvexRewardPool(convexRewardPool).withdrawAndUnwrap(assets, false);
            if (!success) {
                revert AltoConvexCreditLineExternalCallFailed();
            }

            if (idleCollateralAssets() - idleBefore != assets) {
                revert AltoConvexCreditLineUnexpectedAssetDelta();
            }
        }

        convexActive = false;
        IERC20(collateralToken).forceApprove(convexBooster, 0);
        emit ConvexEmergencyExit(assets);
    }

    /// @dev Validates and stores the Convex custody and reward configuration
    function _initializeConvex(ConvexCreditLineInitParams memory _initParams) private {
        if (_initParams.convexBooster == address(0) || _initParams.rewardRecipient == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }

        (address lpToken, address depositToken, address gauge, address rewardPool,, bool shutdown) =
            IConvexBooster(_initParams.convexBooster).poolInfo(_initParams.convexPoolId);

        if (lpToken == address(0) || depositToken == address(0) || gauge == address(0) || rewardPool == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
        if (shutdown || lpToken != collateralToken) {
            revert AltoCreditMarketInvalidInput();
        }

        IConvexRewardPool rewards = IConvexRewardPool(rewardPool);
        if (
            rewards.pid() != _initParams.convexPoolId || rewards.operator() != _initParams.convexBooster
                || rewards.stakingToken() != depositToken
        ) {
            revert AltoCreditMarketInvalidInput();
        }

        uint256 tokenCount = _initParams.rewardTokens.length;
        if (tokenCount == 0) {
            revert AltoCreditMarketInvalidInput();
        }

        convexBooster = _initParams.convexBooster;
        convexPoolId = _initParams.convexPoolId;
        convexRewardPool = rewardPool;
        convexDepositToken = depositToken;
        rewardRecipient = _initParams.rewardRecipient;
        convexActive = true;

        for (uint256 i = 0; i < tokenCount; ++i) {
            _addRewardToken(_initParams.rewardTokens[i]);
        }

        if (!isRewardToken[rewards.rewardToken()]) {
            revert AltoCreditMarketInvalidInput();
        }

        // @TODO: Confirm max approve on init is intended behaviour vs per
        // interaction on deposit.
        IERC20(collateralToken).forceApprove(_initParams.convexBooster, type(uint256).max);

        emit ConvexConfigured(
            _initParams.convexBooster, _initParams.convexPoolId, rewardPool, depositToken, _initParams.rewardRecipient
        );
    }

    /// @dev Adds a validated token to the reward forwarding list
    function _addRewardToken(address _token) private {
        if (_token == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
        if (
            _token.code.length == 0 || _rewardTokens.length >= MAX_REWARD_TOKENS || _token == collateralToken
                || _token == borrowToken || _token == convexDepositToken || isRewardToken[_token]
        ) {
            revert AltoCreditMarketInvalidInput();
        }

        isRewardToken[_token] = true;
        _rewardTokens.push(_token);
    }

    /// @inheritdoc AltoCreditMarketBase
    function _receiveCollateral(uint256 assets) internal override {
        if (!convexActive) {
            revert AltoCreditMarketInvalidInput();
        }

        IERC20 lpToken = IERC20(collateralToken);
        uint256 idleBefore = lpToken.balanceOf(address(this));
        uint256 stakedBefore = stakedCollateralAssets();

        lpToken.safeTransferFrom(msg.sender, address(this), assets);
        if (lpToken.balanceOf(address(this)) - idleBefore != assets) {
            revert AltoConvexCreditLineUnexpectedAssetDelta();
        }

        bool success = IConvexBooster(convexBooster).deposit(convexPoolId, assets, true);
        if (!success) {
            revert AltoConvexCreditLineExternalCallFailed();
        }

        uint256 idleAfter = lpToken.balanceOf(address(this));
        if (idleAfter != idleBefore || stakedCollateralAssets() - stakedBefore != assets) {
            revert AltoConvexCreditLineUnexpectedAssetDelta();
        }

        emit CollateralStaked(msg.sender, assets);
    }

    /// @inheritdoc AltoCreditMarketBase
    function _sendCollateral(address receiver, uint256 assets) internal override {
        IERC20 lpToken = IERC20(collateralToken);

        if (convexActive) {
            uint256 idleBefore = lpToken.balanceOf(address(this));
            bool success = IConvexRewardPool(convexRewardPool).withdrawAndUnwrap(assets, false);
            if (!success) {
                revert AltoConvexCreditLineExternalCallFailed();
            }

            if (lpToken.balanceOf(address(this)) - idleBefore != assets) {
                revert AltoConvexCreditLineUnexpectedAssetDelta();
            }
        } else if (lpToken.balanceOf(address(this)) < assets) {
            revert AltoConvexCreditLineUnexpectedAssetDelta();
        }

        lpToken.safeTransfer(receiver, assets);
        emit CollateralUnstaked(receiver, assets);
    }
}

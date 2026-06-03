// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IWrapperTokenBase, IWrapperTokenStaticTypes, SwapTargetMetadata} from "./IWrapperToken.sol";

/// @title PWrapperToken
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This contract is used to wrap and unwrap underlying token into wrapped tokens and vice versa.
/// @notice The main usecase is to rollover PT assets to other PT assets when expired without user manually move across markets
contract WrapperToken is AltoOwnable2Step, Pausable, ERC20, IWrapperTokenStaticTypes {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

    /// @inheritdoc IWrapperTokenBase
    address public underlyingToken;

    /// @inheritdoc IWrapperTokenBase
    uint8 public immutable DECIMALS;

    /// @inheritdoc IWrapperTokenBase
    uint256 public exchangeRate;

    /// @inheritdoc IWrapperTokenStaticTypes
    mapping(address => SwapTargetMetadata) public swapTargetToApproveTarget;

    /// @inheritdoc IWrapperTokenBase
    address public rollOverBot;

    constructor(
        string memory name,
        string memory symbol,
        address _underlyingToken,
        address _owner,
        address _rollOverBot
    ) Ownable(_owner) ERC20(name, symbol) {
        if (_rollOverBot == address(0)) {
            revert ZeroAddress();
        }
        rollOverBot = _rollOverBot;
        emit RollOverBotSet(address(0), _rollOverBot);

        if (_underlyingToken == address(0)) {
            revert ZeroAddress();
        }
        underlyingToken = _underlyingToken;

        emit UnderlyingTokenSet(address(0), _underlyingToken);

        DECIMALS = IERC20Metadata(underlyingToken).decimals();

        exchangeRate = 10 ** DECIMALS;

        emit ExchangeRateUpdated(exchangeRate);
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    /// @dev Modifier to check if the token is not paused.
    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    /// @inheritdoc IWrapperTokenBase
    function previewWrap(uint256 assetAmount) public view returns (uint256 wrappedTokenAmount) {
        if (assetAmount == 0) return 0;

        wrappedTokenAmount = assetAmount.divideWithRounding(10 ** DECIMALS, exchangeRate, false);
    }

    /// @inheritdoc IWrapperTokenBase
    function wrap(uint256 assetAmount) public whenNotPaused returns (uint256) {
        uint256 wrappedTokenAmountToMint = previewWrap(assetAmount);

        if (wrappedTokenAmountToMint == 0) revert InvalidInput();

        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), assetAmount);

        _mint(msg.sender, wrappedTokenAmountToMint);

        emit Wrapped(msg.sender, assetAmount, wrappedTokenAmountToMint);

        return wrappedTokenAmountToMint;
    }

    /// @inheritdoc IWrapperTokenBase
    function previewUnwrap(uint256 wrappedTokenAmount) public view returns (uint256 assetAmount) {
        if (wrappedTokenAmount == 0) return 0;

        assetAmount = wrappedTokenAmount.divideWithRounding(exchangeRate, 10 ** DECIMALS, false);
    }

    /// @inheritdoc IWrapperTokenBase
    function unwrap(uint256 wrappedTokenAmount) public whenNotPaused returns (uint256) {
        uint256 assetAmountToTransfer = previewUnwrap(wrappedTokenAmount);

        if (assetAmountToTransfer == 0) revert InvalidInput();

        _burn(msg.sender, wrappedTokenAmount);

        IERC20(underlyingToken).safeTransfer(msg.sender, assetAmountToTransfer);

        emit Unwrapped(msg.sender, wrappedTokenAmount, assetAmountToTransfer);

        return assetAmountToTransfer;
    }

    /// @inheritdoc IWrapperTokenBase
    function rollover(
        address newUnderlyingToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address swapTarget,
        bytes calldata swapData
    ) public {
        if (msg.sender != rollOverBot) revert NotRollOverBot();
        if (!paused[PAUSE_TYPE]) revert IsNotPaused(PAUSE_TYPE);
        if (newUnderlyingToken == address(0) || newUnderlyingToken == underlyingToken) revert InvalidInput();
        if (IERC20Metadata(newUnderlyingToken).decimals() != DECIMALS) revert InvalidInput();
        if (swapTarget == address(0) || !swapTargetToApproveTarget[swapTarget].isValid) revert InvalidInput();
        if (minAmountOut == 0 || amountIn == 0) revert InvalidInput();

        address sellToken = underlyingToken;
        address approveTarget = swapTargetToApproveTarget[swapTarget].approveTarget;

        if (approveTarget == address(0)) revert InvalidInput();

        IERC20(underlyingToken).forceApprove(approveTarget, amountIn);

        uint256 buyTokenBalanceBefore = IERC20(newUnderlyingToken).balanceOf(address(this));
        uint256 sellTokenBalanceBefore = IERC20(sellToken).balanceOf(address(this)) - amountIn;

        (bool success,) = swapTarget.call(swapData);
        if (!success) revert SwapFailed();

        IERC20(underlyingToken).forceApprove(approveTarget, 0);

        uint256 buyTokenBalanceReceived = IERC20(newUnderlyingToken).balanceOf(address(this)) - buyTokenBalanceBefore;
        uint256 sellTokenBalanceLeftover = IERC20(sellToken).balanceOf(address(this)) - sellTokenBalanceBefore;

        if (sellTokenBalanceLeftover != 0) revert SellTokenBalanceLeftover(sellTokenBalanceLeftover);
        if (buyTokenBalanceReceived < minAmountOut) revert MinAmountOutNotMet(minAmountOut, buyTokenBalanceReceived);

        exchangeRate = exchangeRate.divideWithRounding(buyTokenBalanceReceived, amountIn, false);

        if (exchangeRate == 0) revert ExchangeRateZero();

        address oldUnderlyingToken = underlyingToken;
        underlyingToken = newUnderlyingToken;

        emit UnderlyingTokenSet(oldUnderlyingToken, newUnderlyingToken);

        emit ExchangeRateUpdated(exchangeRate);

        emit Rollover(oldUnderlyingToken, newUnderlyingToken, amountIn, buyTokenBalanceReceived);
    }

    /// @inheritdoc IWrapperTokenBase
    function setSwapTargetToApproveTarget(address swapTarget, SwapTargetMetadata memory swapTargetMetadata)
        external
        onlyOwner
    {
        if (swapTargetMetadata.isValid) {
            swapTargetToApproveTarget[swapTarget] = swapTargetMetadata;
        } else {
            delete swapTargetToApproveTarget[swapTarget];
        }

        emit SetSwapTargetToApproveTarget(
            swapTarget,
            swapTargetToApproveTarget[swapTarget].approveTarget,
            swapTargetToApproveTarget[swapTarget].isValid
        );
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status) external override onlyOwner {
        _setPauser(pauser, pauseType, status);
    }

    /// @inheritdoc IWrapperTokenBase
    function setRollOverBot(address _rollOverBot) external onlyOwner {
        if (_rollOverBot == address(0)) revert ZeroAddress();
        emit RollOverBotSet(rollOverBot, _rollOverBot);
        rollOverBot = _rollOverBot;
    }
}

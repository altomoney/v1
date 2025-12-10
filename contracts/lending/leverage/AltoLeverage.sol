// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {IMarket, Balance, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IBorrowCallback, IRemoveCollateralCallback} from "../../lending/interfaces/IMarketCallbacks.sol";
import {AssetShareConversionMath} from "../libraries/AssetShareConversionMath.sol";

/// @title Alto Leverage
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice A contract that allows users to leverage and deleverage their collateral by swapping it for a different asset.
/// @dev This contract is used to leverage and deleverage collateral of a borrow position on behalf of users.
/// It is used in the AltoLeverageSwapper contract to swap assets.
/// It is also used in the AltoBaseMarket contract in `borrow` and `removeCollateral` functions.
contract AltoLeverage is AltoOwnable2Step, IBorrowCallback, IRemoveCollateralCallback {
    using AssetShareConversionMath for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    IAltoLeverageSwapper public swapper;
    mapping(address => bool) public supportedMarkets;

    event SwapperUpdated(address indexed oldAddr, address indexed newAddr);
    event MarketUpdated(address indexed markerAddr, bool value);

    error MinAmountNotValid(uint256 expected, uint256 received);
    error NotAuthorized();

    constructor(address _swapper, address _owner) Ownable(_owner) {
        swapper = IAltoLeverageSwapper(_swapper);
    }

    /// @notice sets swapper
    /// @param _swapper the new IAltoLeverageSwapper
    function setSwapper(IAltoLeverageSwapper _swapper) external onlyOwner {
        emit SwapperUpdated(address(swapper), address(_swapper));
        swapper = _swapper;
    }

    /// @notice sets if a market is supported
    /// @param market the market address
    /// @param isSupported true if the market is supported, false otherwise
    function setMarket(address market, bool isSupported) external onlyOwner {
        supportedMarkets[market] = isSupported;
        emit MarketUpdated(market, isSupported);
    }

    /// IBorrowCallback
    function onBorrowCallback(uint256 assets, address onBehalf, bytes calldata swapParams) external {
        if (!supportedMarkets[msg.sender]) revert NotAuthorized();
        address sellToken = IMarket(msg.sender).borrowToken();
        address buyToken = IMarket(msg.sender).collateralToken();

        uint256 amountOut = _swap(sellToken, buyToken, assets, swapParams);

        _addCollateral(buyToken, msg.sender, onBehalf, amountOut);
    }

    /// @inheritdoc IRemoveCollateralCallback
    function onRemoveCollateralCallback(uint256 assets, address onBehalf, bytes calldata swapParams) external {
        if (!supportedMarkets[msg.sender]) revert NotAuthorized();
        address sellToken = IMarket(msg.sender).collateralToken();
        address buyToken = IMarket(msg.sender).borrowToken();

        uint256 balanceBefore = IERC20(sellToken).balanceOf(address(this)) - assets;

        uint256 amountOut = _swap(sellToken, buyToken, assets, swapParams);

        uint256 balanceAfter = IERC20(sellToken).balanceOf(address(this));

        uint256 balanceDiff = balanceAfter - balanceBefore;
        if (balanceDiff > 0) {
            IERC20(sellToken).safeTransfer(onBehalf, balanceDiff);
        }

        _repay(buyToken, msg.sender, onBehalf, amountOut);
    }

    /// @notice recovers ERC20 tokens from the contract
    /// @param tokenAddress the address of the token to recover
    /// @param tokenAmount the amount of tokens to recover
    /// @param recipient the recipient of the tokens
    function recoverERC20(address tokenAddress, uint256 tokenAmount, address recipient) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(recipient, tokenAmount);
    }

    function _swap(address sellToken, address buyToken, uint256 amountIn, bytes calldata swapParams)
        internal
        returns (uint256)
    {
        IERC20(sellToken).forceApprove(address(swapper), amountIn);

        uint256 amountOut = swapper.swap(sellToken, buyToken, amountIn, swapParams);

        IERC20(sellToken).forceApprove(address(swapper), 0);
        return amountOut;
    }

    function _addCollateral(address token, address market, address onBehalf, uint256 amountOut) internal {
        IERC20(token).forceApprove(address(market), amountOut);
        IMarket(market).addCollateral(amountOut, onBehalf);
        IERC20(token).forceApprove(address(market), 0);
    }

    function _repay(address token, address market, address onBehalf, uint256 amountOut) internal {
        IMarket(market).accrueInterest();
        Balance memory totalBorrowed = IMarket(market).totalBorrowed();
        Position memory userPosition = IMarket(market).position(onBehalf);
        uint256 userBorrowedAssets =
            uint256(userPosition.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        if (amountOut >= userBorrowedAssets) {
            // if the user is trying to repay more than they borrowed, we need to repay the full amount of the borrowed assets
            IERC20(token).forceApprove(address(market), userBorrowedAssets);
            (uint256 assets,) = IMarket(market).repay(0, userPosition.borrowShares, onBehalf);
            IERC20(token).forceApprove(address(market), 0);
            // and transfer the difference to the user
            IERC20(token).safeTransfer(onBehalf, amountOut - assets);
        } else {
            IERC20(token).forceApprove(address(market), amountOut);
            IMarket(market).repay(amountOut, 0, onBehalf);
            IERC20(token).forceApprove(address(market), 0);
        }
    }
}

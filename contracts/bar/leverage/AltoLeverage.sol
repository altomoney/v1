// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoLeverageSwapper} from "tapioca-bar/leverage/IAltoLeverageSwapper.sol";
import {IMarket, Balance, Position} from "../../lending/interfaces/IMarket.sol";
import {IBorrowCallback} from "../../lending/interfaces/IMarketCallbacks.sol";
import {AssetShareConversionMath} from "../../lending/libraries/AssetShareConversionMath.sol";

struct FlashBorrowLeverageData {
    address onBehalf;
    uint256 minAmountOut;
    bytes swapData;
}

struct FlashRemoveCollateralLeverageData {
    address onBehalf;
    uint256 minAmountOut;
    bytes swapData;
}

contract AltoLeverage is Ownable, IBorrowCallback {
    using AssetShareConversionMath for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    IAltoLeverageSwapper public swapper;
    mapping(address => bool) public supportedMarkets;

    event AddressUpdated(address indexed oldAddr, address indexed newAddr);
    event MarketUpdated(address indexed markerAddr, bool value);

    error MinAmountNotValid(uint256 expected, uint256 received);
    error NotAuthorized();

    constructor(address _swapper, address _owner) Ownable(_owner) {
        swapper = IAltoLeverageSwapper(_swapper);
    }

    /// @notice sets swapper
    /// @param _swapper the new IAltoLeverageSwapper
    function setSwapper(IAltoLeverageSwapper _swapper) external onlyOwner {
        emit AddressUpdated(address(swapper), address(_swapper));
        swapper = _swapper;
    }

    /// @notice sets if a market is supported
    /// @param market the market address
    /// @param isSupported true if the market is supported, false otherwise
    function setMarket(address market, bool isSupported) external onlyOwner {
        supportedMarkets[market] = isSupported;
        emit MarketUpdated(market, isSupported);
    }

    /// @notice leverage collateral position on behalf of user, called by the market during a flash borrow
    /// @param amountIn the amount of tokens borrowed
    /// @param data the data encoded in the flash borrow
    function onBorrowCallback(uint256 amountIn, bytes calldata data) external {
        if (!supportedMarkets[msg.sender]) revert NotAuthorized();
        FlashBorrowLeverageData memory input = abi.decode(data, (FlashBorrowLeverageData));
        address sellToken = IMarket(msg.sender).borrowToken();
        address buyToken = IMarket(msg.sender).collateralToken();

        uint256 balanceBefore = IERC20(sellToken).balanceOf(address(this)) - amountIn;

        uint256 amountOut = _swap(sellToken, buyToken, input.swapData, amountIn, input.minAmountOut);

        if (amountOut < input.minAmountOut) revert MinAmountNotValid(input.minAmountOut, amountOut);

        uint256 balanceAfter = IERC20(sellToken).balanceOf(address(this));

        // return any remaining unsold tokens to the user
        uint256 balanceDiff = balanceAfter - balanceBefore;
        if (balanceDiff > 0) {
            IERC20(sellToken).safeTransfer(input.onBehalf, balanceDiff);
        }

        _addCollateral(buyToken, msg.sender, input.onBehalf, amountOut);
    }

    /// @notice remove collateral from the market, called by the market during a flash remove collateral
    /// @param amountIn the amount of tokens removed
    /// @param data the data encoded in the flash remove collateral
    function onRemoveCollateralCallback(uint256 amountIn, bytes calldata data) external {
        if (!supportedMarkets[msg.sender]) revert NotAuthorized();
        FlashRemoveCollateralLeverageData memory input = abi.decode(data, (FlashRemoveCollateralLeverageData));
        address sellToken = IMarket(msg.sender).collateralToken();
        address buyToken = IMarket(msg.sender).borrowToken();

        uint256 balanceBefore = IERC20(sellToken).balanceOf(address(this)) - amountIn;

        uint256 amountOut = _swap(sellToken, buyToken, input.swapData, amountIn, input.minAmountOut);

        if (amountOut < input.minAmountOut) revert MinAmountNotValid(input.minAmountOut, amountOut);

        uint256 balanceAfter = IERC20(sellToken).balanceOf(address(this));

        uint256 balanceDiff = balanceAfter - balanceBefore;
        if (balanceDiff > 0) {
            IERC20(sellToken).safeTransfer(input.onBehalf, balanceDiff);
        }

        _repay(buyToken, msg.sender, input.onBehalf, amountOut);
    }

    /// @notice recovers ERC20 tokens from the contract
    /// @param tokenAddress the address of the token to recover
    /// @param tokenAmount the amount of tokens to recover
    /// @param recipient the recipient of the tokens
    function recoverERC20(address tokenAddress, uint256 tokenAmount, address recipient) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(recipient, tokenAmount);
    }

    function _swap(
        address sellToken,
        address buyToken,
        bytes memory swapperData,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256) {
        IERC20(sellToken).forceApprove(address(swapper), amountIn);

        uint256 amountOut = swapper.swap(swapperData, sellToken, buyToken, amountIn, minAmountOut);

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

        bool isTringToRepayMoreThanBorrowed = amountOut > userBorrowedAssets;

        if (isTringToRepayMoreThanBorrowed) {
            IERC20(token).safeTransfer(onBehalf, amountOut - userBorrowedAssets);
            amountOut = userBorrowedAssets;
        }

        IERC20(token).forceApprove(address(market), amountOut);
        if (isTringToRepayMoreThanBorrowed) {
            IMarket(market).repay(0, userPosition.borrowShares, onBehalf);
        } else {
            IMarket(market).repay(amountOut, 0, onBehalf);
        }
        IERC20(token).forceApprove(address(market), 0);
    }
}

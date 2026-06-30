// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {ILiquidationPeripheryCallback} from "./interfaces/ILiquidationPeripheryCallback.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidationPeripheryBase} from "./interfaces/ILiquidationPeriphery.sol";
import {IAdvancedPermissionsUsm} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";

/// @title LiquidationPeriphery
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This contract is used as a periphery to liquidate positions in a market
/// @notice This contract sources borrow tokens from USM by selling underlying asset of USM in USM
/// @custom:audit Pending
contract LiquidationPeriphery is AltoOwnable2Step, ILiquidateCallback, ILiquidationPeripheryBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILiquidationPeripheryBase
    mapping(address => bool) public supportedMarkets;

    /// @inheritdoc ILiquidationPeripheryBase
    address public immutable BORROW_TOKEN;

    /// @inheritdoc ILiquidationPeripheryBase
    address public usmRegistry;

    /// @inheritdoc ILiquidationPeripheryBase
    address public treasury;

    /// @notice Constructor
    /// @param owner The address of the owner
    /// @param _borrowToken The address of the borrow token
    /// @param _usmRegistry The address of the USM registry
    /// @param _treasury The address of the treasury
    constructor(address owner, address _borrowToken, address _usmRegistry, address _treasury) Ownable(owner) {
        if (_borrowToken == address(0) || _usmRegistry == address(0) || _treasury == address(0)) revert ZeroAddress();

        BORROW_TOKEN = _borrowToken;

        usmRegistry = _usmRegistry;
        emit UsmRegistrySet(address(0), _usmRegistry);

        treasury = _treasury;
        emit TreasurySet(address(0), _treasury);
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function liquidate(
        address market,
        address borrower,
        address usm,
        bytes calldata liquidationData,
        bytes calldata liquidationPeripheryCallbackData
    ) external returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee) {
        if (!supportedMarkets[market]) revert InvalidInput();

        // msg.sender is the liquidator
        bytes memory callbackData = abi.encode(msg.sender, market, usm, liquidationPeripheryCallbackData);

        if (!IMarket(market).authorizedLiquidationPeriphery(address(this))) {
            revert UnauthorizedLiquidationPeriphery();
        }

        bytes memory modifiedLiquidationData = abi.encode(msg.sender, liquidationData);

        (seizedCollateral, repaidBorrow, protocolFee) =
            IMarket(market).liquidate(borrower, callbackData, modifiedLiquidationData);

        // resets the approval given to market for the borrow token in onLiquidateCallback function
        IERC20(BORROW_TOKEN).forceApprove(market, 0);

        emit Liquidation(market, msg.sender, borrower, seizedCollateral, protocolFee, repaidBorrow);
    }

    /// @inheritdoc ILiquidateCallback
    /// @dev This callback function uses nonreentrant modifier to prevent liquidation callback
    /// from different market when there is ongoing liquidation in one market.
    /// for ex: external liquidator contractcalls market1.liquidate() which will call Periphery.onLiquidateCallback()
    /// and in callback, external liquidator contract calls market2.liquidate() which will call Periphery.onLiquidateCallback()
    /// This will revert due to nonReentrant modifier.
    /// @dev collateral will already be transferred to the original liquidator by the market before receiving this callback
    function onLiquidateCallback(uint256 borrowAmountToRepay, uint256 collateralReceived, bytes calldata callbackData)
        external
        override
        nonReentrant
    {
        (address liquidator, address market, address usm, bytes memory liquidationPeripheryCallbackData) =
            abi.decode(callbackData, (address, address, address, bytes));

        if (market != msg.sender || !supportedMarkets[market]) revert InvalidInput();
        if (!IUsmRegistry(usmRegistry).isUsm(usm)) revert InvalidInput();
        if (IAdvancedPermissionsUsm(usm).STABLE_TOKEN() != BORROW_TOKEN) revert InvalidInput();

        // gets the asset amount of underlying asset required to repay the borrow amount
        (uint256 assetAmount,,,) =
            IAdvancedPermissionsUsm(usm).getAssetAmountForSellAsset(borrowAmountToRepay, address(this));

        // gets the underlying asset of the USM
        address underlyingAsset = IAdvancedPermissionsUsm(usm).UNDERLYING_ASSET();

        if (liquidationPeripheryCallbackData.length > 0) {
            // @dev the first argument of onLiquidateCallback for liquidator is the assetAmount and not borrowAmountToRepay
            // because liquidator needs to give approval of assetAmount of underlying asset of USM to the periphery
            ILiquidationPeripheryCallback(liquidator)
                .onLiquidationPeripheryCallback(assetAmount, collateralReceived, liquidationPeripheryCallbackData);
        }

        // transfers the underlying asset from the liquidator to the periphery
        IERC20(underlyingAsset).safeTransferFrom(liquidator, address(this), assetAmount);

        // approves the underlying asset to the USM
        IERC20(underlyingAsset).forceApprove(address(usm), assetAmount);

        // sells the underlying asset to the USM
        // this will utilize assetAmount of underlying asset to buy stable token and won't leave any dust in underlying asset
        // this is because the assetAmount is determined by getAssetAmountForSellAsset
        // which returns the amount of underlying asset the user sells to the USM to get borrowAmountToRepay amount of stable token
        // stableTokenBought can be more than borrowAmountToRepay due to rounding and extra amount will be refunded to liquidator
        (, uint256 stableTokenBought) = IAdvancedPermissionsUsm(usm).sellAsset(assetAmount, address(this));

        // resets the approval given to the USM for the underlying asset
        IERC20(underlyingAsset).forceApprove(address(usm), 0);

        // approves the borrow token to the market so that market can pull it from periphery to repay the borrow amount
        IERC20(BORROW_TOKEN).forceApprove(market, borrowAmountToRepay);

        if (stableTokenBought > borrowAmountToRepay) {
            // transfers the extra stable token bought to the liquidator
            IERC20(BORROW_TOKEN).safeTransfer(liquidator, stableTokenBought - borrowAmountToRepay);
        }
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function setSupportedMarket(address market, bool isSupported) external onlyOwner {
        if (market == address(0)) revert ZeroAddress();
        if (isSupported && IMarket(market).borrowToken() != BORROW_TOKEN) revert InvalidInput();
        supportedMarkets[market] = isSupported;
        emit SupportedMarketSet(market, isSupported);
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function setUsmRegistry(address _usmRegistry) external onlyOwner {
        if (_usmRegistry == address(0)) revert ZeroAddress();
        emit UsmRegistrySet(usmRegistry, _usmRegistry);
        usmRegistry = _usmRegistry;
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        emit TreasurySet(treasury, _treasury);
        treasury = _treasury;
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(treasury, tokenAmount);
    }
}

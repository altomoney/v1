// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidationPeripheryBase, IUsm, IMarketRegistry} from "./interfaces/ILiquidationPeriphery.sol";

/// @title LiquidationPeriphery
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This contract is used as a periphery to liquidate positions in a market
/// @notice This contract supports sourcing of borrow token of market from USM by selling underlying asset of USM in USM
contract LiquidationPeriphery is AltoOwnable2Step, ILiquidateCallback, ILiquidationPeripheryBase {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILiquidationPeripheryBase
    IMarketRegistry public marketRegistry;

    /// @inheritdoc ILiquidationPeripheryBase
    IUsm public usm;

    /// @inheritdoc ILiquidationPeripheryBase
    address public immutable BORROW_TOKEN;

    /// @notice Constructor
    /// @param owner The address of the owner
    /// @param _marketRegistry The address of the market registry
    /// @param _usm The address of the USM
    constructor(address owner, address _marketRegistry, address _usm) Ownable(owner) {
        if (_marketRegistry == address(0)) revert ZeroAddress();
        if (_usm == address(0)) revert ZeroAddress();

        emit MarketRegistrySet(address(0), _marketRegistry);
        marketRegistry = IMarketRegistry(_marketRegistry);

        emit UsmSet(address(0), _usm);
        usm = IUsm(_usm);

        BORROW_TOKEN = usm.STABLE_TOKEN();
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function liquidate(address market, address borrower, bool repayViaUsm, bytes calldata liquidationData)
        external
        isValidMarket(market)
        returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee)
    {
        // msg.sender is the liquidator
        // repayViaUsm is the flag to indicate if the borrow amount should be repaid via USM
        bytes memory callbackData = abi.encode(msg.sender, repayViaUsm, market);

        (seizedCollateral, repaidBorrow, protocolFee) =
            IMarket(market).liquidate(borrower, callbackData, liquidationData);

        // resets the approval given to market for the borrow token in onLiquidateCallback function
        IERC20(BORROW_TOKEN).forceApprove(market, 0);
    }

    /// @inheritdoc ILiquidateCallback
    function onLiquidateCallback(uint256 borrowAmountToRepay, uint256 collateralReceived, bytes calldata callbackData)
        external
        override
        isValidMarket(msg.sender)
    {
        (address liquidator, bool repayViaUsm, address market) = abi.decode(callbackData, (address, bool, address));

        if (market != msg.sender) revert InvalidInput();

        // transfers the collateral seized of the borrower to the liquidator
        IERC20(IMarket(market).collateralToken()).safeTransfer(liquidator, collateralReceived);

        if (repayViaUsm) {
            // gets the asset amount required to repay the borrow amount
            (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(borrowAmountToRepay);

            // gets the underlying asset of the USM
            address underlyingAsset = usm.UNDERLYING_ASSET();

            // transfers the underlying asset from the liquidator to the periphery
            IERC20(underlyingAsset).safeTransferFrom(liquidator, address(this), assetAmount);

            // approves the underlying asset to the USM
            IERC20(underlyingAsset).forceApprove(address(usm), assetAmount);

            // sells the underlying asset to the USM
            (, uint256 stableTokenBought) = usm.sellAsset(assetAmount, address(this));

            // approves the borrow token to the market so that market can pull it from periphery to repay the borrow amount
            IERC20(BORROW_TOKEN).forceApprove(market, borrowAmountToRepay);

            if (stableTokenBought > borrowAmountToRepay) {
                // transfers the extra stable token bought to the liquidator
                IERC20(BORROW_TOKEN).safeTransfer(liquidator, stableTokenBought - borrowAmountToRepay);
            }
        } else {
            // transfers the borrow amount to the periphery
            IERC20(BORROW_TOKEN).safeTransferFrom(liquidator, address(this), borrowAmountToRepay);

            // approves the borrow token to the market so that market can pull it from periphery to repay the borrow amount
            IERC20(BORROW_TOKEN).forceApprove(market, borrowAmountToRepay);
        }
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function setMarketRegistry(address newMarketRegistry) external onlyOwner {
        if (newMarketRegistry == address(0)) revert ZeroAddress();
        if (newMarketRegistry == address(marketRegistry)) revert AlreadySet();

        emit MarketRegistrySet(address(marketRegistry), newMarketRegistry);
        marketRegistry = IMarketRegistry(newMarketRegistry);
    }

    /// @inheritdoc ILiquidationPeripheryBase
    function setUsm(address newUsm) external onlyOwner {
        if (newUsm == address(0)) revert ZeroAddress();
        if (newUsm == address(usm)) revert AlreadySet();
        if (IUsm(newUsm).STABLE_TOKEN() != BORROW_TOKEN) revert InvalidInput();

        emit UsmSet(address(usm), newUsm);
        usm = IUsm(newUsm);
    }

    /// @dev Modifier to check if the market is valid
    /// @param market The address of the market to check
    modifier isValidMarket(address market) {
        if (!marketRegistry.isMintMarket(market) && !marketRegistry.isBorrowMarket(market)) revert InvalidInput();
        _;
    }
}

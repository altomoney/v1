// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IAdvancedPermissionsUsm} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {ILiquidationPeripheryCallback} from "@alto/lending/liquidation/interfaces/ILiquidationPeripheryCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockSwapper} from "./MockSwapper.sol";

/// @dev Test helper liquidator: swaps seized collateral to USM underlying via MockSwapper, then approves periphery.
contract SimpleLiquidator is ILiquidationPeripheryCallback {
    using SafeERC20 for IERC20;

    address public immutable periphery;
    IAdvancedPermissionsUsm public immutable usm;
    MockSwapper public immutable swapper;

    uint256 public callbackCallCount;
    uint256 public lastAssetsToRepay;
    uint256 public lastCollateralReceived;
    address public lastUnderlyingAsset;
    uint256 public lastUnderlyingAmount;
    bytes public lastCallbackData;

    error InvalidCaller();

    constructor(address periphery_, address usm_, address swapper_) {
        periphery = periphery_;
        usm = IAdvancedPermissionsUsm(usm_);
        swapper = MockSwapper(swapper_);
    }

    /// @inheritdoc ILiquidationPeripheryCallback
    /// @dev Periphery passes required underlying amount as `assetsToRepay`; `data` is abi.encode(market).
    function onLiquidationPeripheryCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data)
        external
    {
        if (msg.sender != periphery) revert InvalidCaller();

        address underlyingAsset = usm.UNDERLYING_ASSET();
        address market = abi.decode(data, (address));
        address marketCollateralToken = IMarket(market).collateralToken();

        callbackCallCount++;
        lastAssetsToRepay = assetsToRepay;
        lastCollateralReceived = collateralReceived;
        lastUnderlyingAsset = underlyingAsset;
        lastUnderlyingAmount = assetsToRepay;
        lastCallbackData = data;

        IERC20(marketCollateralToken).forceApprove(address(swapper), collateralReceived);

        bytes memory swapData = abi.encode(marketCollateralToken, collateralReceived, underlyingAsset, assetsToRepay);
        uint256 amountOut = swapper.swap(swapData);

        IERC20(underlyingAsset).forceApprove(periphery, amountOut);
    }

    /// @notice Initiates liquidation through the periphery; EOA calls this.
    function liquidateMarket(
        address market,
        address borrower,
        address targetUsm,
        bytes calldata liquidationData,
        bytes calldata liquidationPeripheryCallbackData
    ) external returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee) {
        return ILiquidationPeripheryBase(periphery)
            .liquidate(market, borrower, targetUsm, liquidationData, liquidationPeripheryCallbackData);
    }
}

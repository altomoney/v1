// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IAdvancedPermissionsUsm} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {ILiquidationPeripheryCallback} from "@alto/lending/liquidation/interfaces/ILiquidationPeripheryCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Sample liquidator that resembles to mainnet implementation for fork testing
/// @dev This contract doesn't have any checks on who is caller and is for testing purposes and should not be used in production
contract Liquidator is ILiquidationPeripheryCallback {
    using SafeERC20 for IERC20;

    address public immutable periphery;
    IAdvancedPermissionsUsm public immutable usm;
    address public immutable paraswapAugustus;

    error InvalidCaller();
    error ZeroAddress();
    error SwapFailed();

    constructor(address periphery_, address usm_, address paraswapAugustus_) {
        if (periphery_ == address(0) || usm_ == address(0) || paraswapAugustus_ == address(0)) revert ZeroAddress();
        periphery = periphery_;
        usm = IAdvancedPermissionsUsm(usm_);
        paraswapAugustus = paraswapAugustus_;
    }

    /// @inheritdoc ILiquidationPeripheryCallback
    function onLiquidationPeripheryCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data)
        external
    {
        if (msg.sender != periphery) revert InvalidCaller();

        (address market, address tokenTransferProxy, bytes memory swapCalldata) =
            abi.decode(data, (address, address, bytes));

        address collateralToken = IMarket(market).collateralToken();
        IERC20(collateralToken).forceApprove(tokenTransferProxy, collateralReceived);

        (bool success,) = paraswapAugustus.call(swapCalldata);
        if (!success) revert SwapFailed();

        address underlyingAsset = usm.UNDERLYING_ASSET();
        IERC20(underlyingAsset).forceApprove(periphery, assetsToRepay);
    }

    /// @notice Entry point for an external EOA; liquidator holds no inventory besides what this transaction seizes and swaps.
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILiquidationPeripheryCallback} from "@alto/lending/liquidation/interfaces/ILiquidationPeripheryCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Test helper: approves the periphery for `assetToSend` when called by the configured periphery.
contract SimpleLiquidationPeripheryCallback is ILiquidationPeripheryCallback {
    using SafeERC20 for IERC20;

    address public immutable periphery;

    uint256 public callbackCallCount;
    uint256 public lastCollateralReceived;
    address public lastAssetToSend;
    uint256 public lastAssetAmountToSend;

    error InvalidCaller();

    constructor(address periphery_) {
        periphery = periphery_;
    }

    /// @inheritdoc ILiquidationPeripheryCallback
    function onLiquidationPeripheryCallback(
        uint256 collateralReceived,
        address assetToSend,
        uint256 assetAmountToSend,
        bytes calldata
    ) external {
        if (msg.sender != periphery) revert InvalidCaller();

        callbackCallCount++;
        lastCollateralReceived = collateralReceived;
        lastAssetToSend = assetToSend;
        lastAssetAmountToSend = assetAmountToSend;

        IERC20(assetToSend).forceApprove(periphery, assetAmountToSend);
    }
}

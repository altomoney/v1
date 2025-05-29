// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IBorrowCallback {
    function onBorrowCallback(uint256 assets, bytes calldata data) external;
}

interface IRemoveCollateralCallback {
    function onRemoveCollateralCallback(uint256 assets, bytes calldata data) external;
}

interface ILiquidateCallback {
    function onLiquidateCallback(uint256 assets, bytes calldata data) external;
}

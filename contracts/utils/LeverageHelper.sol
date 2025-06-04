// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    FlashRemoveCollateralLeverageData, FlashBorrowLeverageData
} from "@alto-monorepo/bar/leverage/AltoLeverage.sol";

/// @title LeverageABIHelper
/// @notice Helper contract for leverage operations
/// @dev This is solely for ABI generation of structs to make it easier to integrate leverage operations
/// @dev No deployment needed
contract LeverageABIHelper {
    function leverageHelperRemoveCollateral(FlashRemoveCollateralLeverageData memory leverageData) external {
        revert("Not implemented");
    }

    function leverageHelperBorrow(FlashBorrowLeverageData memory leverageData) external {
        revert("Not implemented");
    }
}

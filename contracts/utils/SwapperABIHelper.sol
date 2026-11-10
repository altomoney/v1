// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SwapParams, SwapParamsMultiTarget} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";

/// @title SwapperABIHelper
/// @notice Helper contract for swap operations
/// @dev This is solely for ABI generation of structs to make it easier to integrate swap operations
/// @dev No deployment needed
contract SwapperABIHelper {
    function swapParamsStructHelper(SwapParams calldata) external pure {
        revert("Not implemented");
    }

    function swapParamsMultiTargetStructHelper(SwapParamsMultiTarget calldata) external pure {
        revert("Not implemented");
    }
}

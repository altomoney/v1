// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBoldWrapper} from "@alto/lending/leverage/interfaces/IBoldWrapper.sol";

/// @title AltoBoldWrapper
/// @notice A contract that wraps and unwraps BOLD token to SBOLD token and vice versa
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
contract AltoBoldWrapper is IBoldWrapper {
    using SafeERC20 for IERC20;

    /// @inheritdoc IBoldWrapper
    address public immutable SBOLD;

    /// @inheritdoc IBoldWrapper
    address public immutable BOLD;

    /// @notice Constructor
    /// @param _sbold the address of the SBOLD token
    constructor(address _sbold) {
        if (_sbold == address(0)) revert BoldWrapperInvalidInput();
        SBOLD = _sbold;
        BOLD = IERC4626(SBOLD).asset();
    }

    /// @inheritdoc IBoldWrapper
    function wrap(uint256 amount, address receiver) external {
        IERC20(BOLD).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(BOLD).forceApprove(address(SBOLD), amount);
        uint256 sBoldAmount = IERC4626(SBOLD).deposit(amount, receiver);
        IERC20(BOLD).forceApprove(address(SBOLD), 0);

        emit Wrap(amount, sBoldAmount);
    }

    /// @inheritdoc IBoldWrapper
    function unwrap(uint256 amount, address receiver) external {
        IERC20(address(SBOLD)).safeTransferFrom(msg.sender, address(this), amount);
        uint256 boldAmount = IERC4626(SBOLD).redeem(amount, receiver, address(this));

        emit Unwrap(amount, boldAmount);
    }
}

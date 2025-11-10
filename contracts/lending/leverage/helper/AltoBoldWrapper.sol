// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWrapper} from "@alto/lending/leverage/interfaces/IWrapper.sol";

/// @title AltoBoldWrapper
/// @notice A contract that wraps and unwraps BOLD token to SBOLD token and vice versa
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
contract AltoBoldWrapper is IWrapper {
    using SafeERC20 for IERC20;

    /// @inheritdoc IWrapper
    address public immutable BASE_TOKEN;

    /// @inheritdoc IWrapper
    address public immutable WRAPPED_TOKEN;

    error AltoBoldWrapperInvalidInput();

    /// @notice Constructor
    /// @param _sbold the address of the SBOLD token
    constructor(address _sbold) {
        if (_sbold == address(0)) revert AltoBoldWrapperInvalidInput();
        WRAPPED_TOKEN = _sbold;
        BASE_TOKEN = IERC4626(WRAPPED_TOKEN).asset();
    }

    /// @inheritdoc IWrapper
    function wrap(uint256 amount, address receiver) external {
        IERC20(BASE_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(BASE_TOKEN).forceApprove(address(WRAPPED_TOKEN), amount);
        uint256 wrappedAmount = IERC4626(WRAPPED_TOKEN).deposit(amount, receiver);
        IERC20(BASE_TOKEN).forceApprove(address(WRAPPED_TOKEN), 0);
    }

    /// @inheritdoc IWrapper
    function unwrap(uint256 amount, address receiver) external {
        IERC20(address(WRAPPED_TOKEN)).safeTransferFrom(msg.sender, address(this), amount);
        uint256 baseAmount = IERC4626(WRAPPED_TOKEN).redeem(amount, receiver, address(this));
    }
}

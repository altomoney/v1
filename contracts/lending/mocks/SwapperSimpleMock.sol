// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAltoLeverageSwapper} from "@alto/lending/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SwapperSimpleMock
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A simple mock for the AltoLeverageSwapper contract.
/// @dev This contract is used to test the AltoLeverageSwapper contract.
contract SwapperSimpleMock is IAltoLeverageSwapper, Ownable {
    mapping(address => bool) public isWhitelisted;

    error SenderNotValid(address sender);

    uint256 public returnLeftoverTokens;

    constructor(address _owner) Ownable(_owner) {}

    function setWhitelisted(address _address, bool _isWhitelisted) external onlyOwner {
        isWhitelisted[_address] = _isWhitelisted;
    }

    function setLeftoverTokens(uint256 _returnLeftoverTokens) external onlyOwner {
        returnLeftoverTokens = _returnLeftoverTokens;
    }

    function swap(bytes calldata, address sellToken, address buyToken, uint256 amountIn, uint256 minAmountOut)
        public
        payable
        returns (uint256 amountOut)
    {
        if (!isWhitelisted[msg.sender]) {
            revert SenderNotValid(msg.sender);
        }
        // Transfer tokens to this contract
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(sellToken).transferFrom(msg.sender, address(this), amountIn);

        if (returnLeftoverTokens > 0) {
            /// forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(sellToken).transfer(msg.sender, returnLeftoverTokens);
            returnLeftoverTokens = 0;
        }

        amountOut = minAmountOut;

        // Transfer the bought tokens to the sender
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(buyToken).transfer(msg.sender, amountOut);
    }
}

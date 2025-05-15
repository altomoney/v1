// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IAltoLeverageSwapper} from "@alto-monorepo/bar/leverage/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapperSimpleMock is IAltoLeverageSwapper, Ownable {
    mapping(address => bool) public isWhitelisted;

    error SenderNotValid(address sender);

    uint256 public defaultAmountOut;
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
        IERC20(sellToken).transferFrom(msg.sender, address(this), amountIn);

        if (returnLeftoverTokens > 0) {
            IERC20(sellToken).transfer(msg.sender, returnLeftoverTokens);
            returnLeftoverTokens = 0;
        }

        if (defaultAmountOut > 0) {
            amountOut = defaultAmountOut;
        } else {
            amountOut = minAmountOut;
        }

        // Transfer the bought tokens to the sender
        IERC20(buyToken).transfer(msg.sender, amountOut);
    }

    /**
     * @notice Payable fallback to allow this contract to receive protocol fee refunds.
     * https://0x.org/docs/0x-swap-api/guides/use-0x-api-liquidity-in-your-smart-contracts#payable-fallback
     */
    receive() external payable {}

    /// @dev Set the default amount out for the swap. If 0, always returns minAmountOut.
    function setDefaultAmountOut(uint256 _defaultAmountOut) external onlyOwner {
        defaultAmountOut = _defaultAmountOut;
    }
}

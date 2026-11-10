// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

abstract contract ASampleLiquidator is Ownable {
    /**
     * @notice Triggers seizure of a GSM, sending seized funds to the Treasury
     * @param gsm Address of the GSM
     * @return The amount of underlying asset seized and transferred to Treasury
     */
    function triggerSeize(address gsm) external onlyOwner returns (uint256) {
        return IUsm(gsm).seize();
    }

    /**
     * @notice Pulls GHO from the sender and burns it via the GSM
     * @param gsm Address of the GSM
     * @param amount The maximum amount of GHO to be burned
     * @return The amount of GHO burned
     */
    function triggerBurnAfterSeize(address gsm, uint256 amount) external onlyOwner returns (uint256) {
        IERC20 ghoToken = IERC20(IUsm(gsm).STABLE_TOKEN());
        uint256 ghoMinted = _getCurrentlyMintedStableTokenByAddress(gsm);
        if (amount > ghoMinted) {
            amount = ghoMinted;
        }
        ghoToken.transferFrom(msg.sender, address(this), amount);
        ghoToken.approve(gsm, amount);
        return IUsm(gsm).burnAfterSeize(amount);
    }

    /**
     * @dev Returns the amount of Stable Token minted by the USM
     * @return The amount of Stable Token minted by the USM
     */
    function _getCurrentlyMintedStableTokenByAddress(address gsm) internal view virtual returns (uint256);
}

/**
 * @title SampleLiquidator
 * @author Aave
 * @notice Minimal Liquidator that can serve as sample contract
 */
contract SampleLiquidator is ASampleLiquidator {
    constructor() Ownable(msg.sender) {}

    function _getCurrentlyMintedStableTokenByAddress(address gsm) internal view override returns (uint256) {
        (uint256 minted,) = IDUSD(IUsm(gsm).STABLE_TOKEN()).minterConfig(gsm);
        return minted;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUsmFeeStrategy} from "./interfaces/IUsmFeeStrategy.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title FixedFeeStrategy
 * @author Aave
 * @notice Fee strategy using a fixed rate to calculate buy/sell fees
 */
contract FixedFeeStrategy is IUsmFeeStrategy, Ownable2Step {
    using Math for uint256;

    uint256 internal constant PERCENTAGE_PRECISION = 10000;

    uint256 internal constant MAXIMUM_FEE_PERCENT = 5000;

    uint256 internal _buyFee;
    uint256 internal _sellFee;

    /**
     * @dev Constructor
     * @dev Fees must be lower than 5000 bps (e.g. 50.00%)
     * @param buyFee The fee paid when buying the underlying asset in exchange for GHO, expressed in bps
     * @param sellFee The fee paid when selling the underlying asset in exchange for GHO, expressed in bps
     */
    constructor(uint256 buyFee, uint256 sellFee, address owner) Ownable(owner) {
        require(buyFee < MAXIMUM_FEE_PERCENT, "INVALID_BUY_FEE");
        require(sellFee < MAXIMUM_FEE_PERCENT, "INVALID_SELL_FEE");
        require(buyFee > 0 || sellFee > 0, "MUST_HAVE_ONE_NONZERO_FEE");
        _buyFee = buyFee;
        _sellFee = sellFee;
    }

    /// @inheritdoc IUsmFeeStrategy
    function setFee(uint256 buyFee, uint256 sellFee) external onlyOwner {
        require(buyFee < MAXIMUM_FEE_PERCENT, "INVALID_BUY_FEE");
        require(sellFee < MAXIMUM_FEE_PERCENT, "INVALID_SELL_FEE");
        require(buyFee > 0 || sellFee > 0, "MUST_HAVE_ONE_NONZERO_FEE");
        _buyFee = buyFee;
        _sellFee = sellFee;
    }

    /// @inheritdoc IUsmFeeStrategy
    function getBuyFee(uint256 grossAmount) external view returns (uint256) {
        return grossAmount.mulDiv(_buyFee, PERCENTAGE_PRECISION, Math.Rounding.Ceil);
    }

    /// @inheritdoc IUsmFeeStrategy
    function getSellFee(uint256 grossAmount) external view returns (uint256) {
        return grossAmount.mulDiv(_sellFee, PERCENTAGE_PRECISION, Math.Rounding.Ceil);
    }

    /// @inheritdoc IUsmFeeStrategy
    function getGrossAmountFromTotalBought(uint256 totalAmount) external view returns (uint256) {
        if (totalAmount == 0) {
            return 0;
        } else if (_buyFee == 0) {
            return totalAmount;
        } else {
            return totalAmount.mulDiv(PERCENTAGE_PRECISION, PERCENTAGE_PRECISION + _buyFee, Math.Rounding.Floor);
        }
    }

    /// @inheritdoc IUsmFeeStrategy
    function getGrossAmountFromTotalSold(uint256 totalAmount) external view returns (uint256) {
        if (totalAmount == 0) {
            return 0;
        } else if (_sellFee == 0) {
            return totalAmount;
        } else {
            return totalAmount.mulDiv(PERCENTAGE_PRECISION, PERCENTAGE_PRECISION - _sellFee, Math.Rounding.Ceil);
        }
    }
}

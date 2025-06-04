// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IIrm} from "../interfaces/IIrm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarket} from "../interfaces/IMarket.sol";
import {FixedPointMath} from "../libraries/FixedPointMath.sol";

/// @title Fixed Rate Interest Rate Model
/// @author Alto Foundation
/// @custom:contact security@alto.xyz
contract FixedRateIrm is Ownable, IIrm {
    using FixedPointMath for uint256;

    event SetBorrowRate(uint256 borrowRate);

    /// @notice Internal cached state of the interest rate model.
    struct IRState {
        /// @dev The fixed borrow rate.
        uint256 borrowRate;
        /// @dev The timestamp of the last update to the model.
        uint48 lastUpdate;
    }

    uint256 public constant MAX_BORROW_RATE = 8.0 ether / uint256(365 days);

    IRState public irState;
    address public market;

    /// @notice Constructor
    /// @param _borrowRate The fixed borrow rate in second percent yield (SPY)
    /// @param _owner The owner of the IRM - shouldn't be market
    constructor(uint256 _borrowRate, address _owner) Ownable(_owner) {
        if (_borrowRate == 0 || _borrowRate > MAX_BORROW_RATE) revert Alto_IrmInvalidParams();

        irState.borrowRate = _borrowRate;
    }

    /// @notice Sets the market address
    /// @param _market The market to set
    /// @dev Used for the first time by the market to set itself to the IRM
    function setMarket(address _market) external {
        if (market != address(0)) revert Alto_IrmMarketAlreadySet();
        market = _market;
        irState.lastUpdate = uint48(block.timestamp);
    }

    /// @notice Sets the borrow rate
    /// @param _borrowRate The new borrow rate in second percent yield (SPY)
    /// @dev Reverts on not set market, so the rate has to be set before the market creation.
    function setBorrowRate(uint256 _borrowRate) external onlyOwner {
        if (market == address(0)) revert Alto_IrmMarketNotSet();
        if (_borrowRate == 0 || _borrowRate > MAX_BORROW_RATE) revert Alto_IrmInvalidParams();

        IMarket(market).accrueInterest();
        irState.borrowRate = _borrowRate;

        emit SetBorrowRate(_borrowRate);
    }

    /// @inheritdoc IIrm
    function updateInterestRateView(uint256 _totalSupply, uint256 _totalBorrowed)
        external
        view
        returns (uint256, uint256)
    {
        return _accrueInterest(_totalSupply, _totalBorrowed);
    }

    /// @inheritdoc IIrm
    function updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed) external returns (uint256, uint256) {
        if (msg.sender != market) revert Alto_IrmUnauthorized();

        return _updateInterestRate(_totalSupply, _totalBorrowed);
    }

    function _accrueInterest(uint256, uint256 _totalBorrowed) internal view returns (uint256, uint256) {
        // If the market is not set, the lastUpdate is not set, so we revert.
        if (market == address(0)) revert Alto_IrmMarketNotSet();

        uint256 interest = _totalBorrowed.multiplyWithPrecision(
            irState.borrowRate.calculateCompoundInterest(block.timestamp - irState.lastUpdate)
        );

        return (interest, irState.borrowRate);
    }

    function _updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed) internal returns (uint256, uint256) {
        (uint256 interest, uint256 newBorrowRate) = _accrueInterest(_totalSupply, _totalBorrowed);

        irState.lastUpdate = uint48(block.timestamp);

        return (interest, newBorrowRate);
    }
}

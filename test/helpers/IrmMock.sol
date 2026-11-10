// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

contract IrmMock is IIrm {
    using FixedPointMath for uint256;

    address public market;

    struct IRState {
        uint256 borrowRate;
        uint48 lastUpdate;
    }

    IRState public irState;

    function setBorrowRate(uint256 newBorrowRate) external {
        irState.borrowRate = newBorrowRate;
        irState.lastUpdate = uint48(block.timestamp);
    }

    function IRM_TYPE() external pure returns (IRMType) {
        return IRMType.FIXED_RATE;
    }

    function setMarket(address _market) external override {
        market = _market;
    }

    function onMarketPause(bool _paused) external override {}

    function updateInterestRateView(uint256 _totalSupply, uint256 _totalBorrowed)
        external
        view
        returns (uint256, uint256)
    {
        return _accrueInterest(_totalSupply, _totalBorrowed);
    }

    /// @inheritdoc IIrm
    function updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed) external returns (uint256, uint256) {
        if (msg.sender != market) revert IrmUnauthorized();

        return _updateInterestRate(_totalSupply, _totalBorrowed);
    }

    function _accrueInterest(uint256, uint256 _totalBorrowed) internal view returns (uint256, uint256) {
        // If the market is not set, the lastUpdate is not set, so we revert.
        if (market == address(0)) revert IrmMarketNotSet();

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

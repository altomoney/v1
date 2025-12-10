// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IIrm, IRMType} from "../interfaces/IIrm.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {IMarket} from "../interfaces/IMarket.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

/// @title Fixed Rate Interest Rate Model
/// @author GPM
/// @custom:contact security@altofoundation.org
contract FixedRateIrm is AltoOwnable2Step, IIrm {
    using FixedPointMath for uint256;

    event SetBorrowRate(uint256 borrowRate);

    event IRStateUpdated(IRState newIRState);

    /// @notice Internal cached state of the interest rate model.
    struct IRState {
        /// @dev The fixed borrow rate.
        uint256 borrowRate;
        /// @dev The timestamp of the last update to the model.
        uint48 lastUpdate;
    }

    uint256 public constant MAX_BORROW_RATE = 8.0 ether / uint256(365 days);

    /// @inheritdoc IIrm
    IRMType public constant IRM_TYPE = IRMType.FIXED_RATE;

    IRState public irState;
    address public market;

    /// @notice Constructor
    /// @param _borrowRate The fixed borrow rate in second percent yield (SPY)
    /// @param _owner The owner of the IRM - shouldn't be market
    constructor(uint256 _borrowRate, address _owner) Ownable(_owner) {
        if (_borrowRate == 0 || _borrowRate > MAX_BORROW_RATE) revert IrmInvalidParams();

        irState.borrowRate = _borrowRate;

        emit IRStateUpdated(irState);
    }

    /// @notice Sets the market address
    /// @param _market The market to set
    /// @dev Used for the first time by the market to set itself to the IRM
    function setMarket(address _market) external {
        if (market != address(0)) revert IrmMarketAlreadySet();
        market = _market;
        irState.lastUpdate = uint48(block.timestamp);

        emit IRStateUpdated(irState);
    }

    /// @inheritdoc IIrm
    function onMarketPause(bool _paused) external {
        if (msg.sender != market) revert IrmUnauthorized();
        if (!_paused) {
            irState.lastUpdate = uint48(block.timestamp);
            emit IRStateUpdated(irState);
        }
    }

    /// @notice Sets the borrow rate
    /// @param _borrowRate The new borrow rate in second percent yield (SPY)
    /// @dev Reverts on not set market, so the rate has to be set before the market creation.
    function setBorrowRate(uint256 _borrowRate) external onlyOwner {
        if (market == address(0)) revert IrmMarketNotSet();
        if (_borrowRate == 0 || _borrowRate > MAX_BORROW_RATE) revert IrmInvalidParams();

        if (!IMarket(market).paused(PAUSE_TYPE)) {
            IMarket(market).accrueInterest();
        }

        irState.borrowRate = _borrowRate;

        emit IRStateUpdated(irState);

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

        emit IRStateUpdated(irState);

        return (interest, newBorrowRate);
    }
}

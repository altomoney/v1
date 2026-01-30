// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {BaseMarketInitParams, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

contract MarketInstance is AltoBaseMarket {
    uint256 private _borrowOpeningFee;

    /// @notice The interest fee in MATH_PRECISION charged on accrued interest
    uint256 public interestFee;

    /// @notice Emitted when the interest fee is set
    /// @param oldInterestFee The old interest fee
    /// @param newInterestFee The new interest fee
    event SetInterestFee(uint256 oldInterestFee, uint256 newInterestFee);

    function initialize(BaseMarketInitParams memory _baseMarketInitParams, uint256 _borrowOpeningFeeWad)
        public
        initializer
    {
        __AltoBaseMarket_init(_baseMarketInitParams, MarketType.BORROW);
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }

    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        uint256 protocolFeePercentage = IAltoLiquidationEngine(liquidationEngine).protocolFeePercentage();
        if (_feeRecipient == address(0) && (borrowOpeningFee() > 0 || protocolFeePercentage > 0 || interestFee > 0)) {
            revert AltoBaseMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setBorrowOpeningFee(uint256 _borrowOpeningFeeWad) external onlyOwner {
        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (feeRecipient == address(0) && _borrowOpeningFeeWad > 0) {
            revert AltoBaseMarketInvalidInput();
        }
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }

    /// @notice Setter of the interest fee
    /// @param _newInterestFee The new interest fee
    /// @param _skipAccrueInterest Whether to skip accruing interest
    function setInterestFee(uint256 _newInterestFee, bool _skipAccrueInterest) external onlyOwner {
        if (_newInterestFee > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }

        if (feeRecipient == address(0) && _newInterestFee > 0) {
            revert AltoBaseMarketInvalidInput();
        }

        if (!paused[PAUSE_TYPE] && !_skipAccrueInterest) {
            _accrueInterest();
        }

        emit SetInterestFee(interestFee, _newInterestFee);
        interestFee = _newInterestFee;
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}

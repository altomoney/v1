// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IIrm} from "./interfaces/IIrm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {AltoBorrowMarket} from "./AltoBorrowMarket.sol";
/// @title FixedRateIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org

contract FixedRateIrm is Ownable, IIrm {
    using MathLib for uint256;

    error Alto_IrmMarketAlreadySet();
    error Alto_IrmMarketNotSet();

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

    constructor(uint256 _borrowRate, address _owner) {
        require(_borrowRate != 0, "Borrow rate cannot be 0");
        require(_borrowRate <= MAX_BORROW_RATE, "Borrow rate cannot be greater than MAX_BORROW_RATE");

        irState.borrowRate = _borrowRate;

        _transferOwnership(_owner);
    }

    function setBorrowRate(uint256 _borrowRate) external onlyOwner {
        if (market == address(0)) revert Alto_IrmMarketNotSet();
        require(_borrowRate != 0, "Borrow rate cannot be 0");
        require(_borrowRate <= MAX_BORROW_RATE, "Borrow rate cannot be greater than MAX_BORROW_RATE");

        AltoBorrowMarket(market).accrueInterest();
        irState.borrowRate = _borrowRate;
    }

    function setMarket(address _market) external {
        if (market != address(0)) revert Alto_IrmMarketAlreadySet();
        market = _market;

        _updateInterestRate(0, 0);
    }

    /// @inheritdoc IIrm
    function updateInterestRateView(uint256 _totalSupply, uint256 _totalBorrowed)
        external
        view
        returns (uint256, uint256)
    {
        if (irState.lastUpdate == 0) {
            return (irState.borrowRate, 0);
        }

        return _accrueInterest(_totalSupply, _totalBorrowed);
    }

    /// @inheritdoc IIrm
    /// @dev Reverts on not set rate, so the rate has to be set before the market creation.
    function updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed) external returns (uint256, uint256) {
        if (market == address(0)) revert Alto_IrmMarketNotSet();
        if (msg.sender != market) revert Alto_IrmUnauthorized();

        return _updateInterestRate(_totalSupply, _totalBorrowed);
    }

    function _accrueInterest(uint256 _totalSupply, uint256 _totalBorrowed) internal view returns (uint256, uint256) {
        if (irState.lastUpdate == 0) {
            return (irState.borrowRate, 0);
        }

        uint256 interest =
            _totalBorrowed.wMulDown(irState.borrowRate.wTaylorCompounded(block.timestamp - irState.lastUpdate));

        return (irState.borrowRate, interest);
    }

    function _updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed) internal returns (uint256, uint256) {
        if (irState.lastUpdate == 0) {
            irState.lastUpdate = uint48(block.timestamp);
            return (irState.borrowRate, 0);
        }

        (uint256 interest, uint256 newBorrowRate) = _accrueInterest(_totalSupply, _totalBorrowed);

        irState.lastUpdate = uint48(block.timestamp);

        return (interest, newBorrowRate);
    }
}

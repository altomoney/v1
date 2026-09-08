// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {Balance} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

/// @notice Minimal stateful market double for the IRM's market-facing API.
/// @dev `accrueInterest` follows the production market's pause check, IRM
/// callback, zero-interest short circuit, balance update, and event shape.
contract MockPegResponsiveExponentialIrmMarket {
    using SafeCast for uint256;

    enum AccrueRevertPoint {
        NONE,
        BEFORE_CALLBACK,
        AFTER_CALLBACK
    }

    error MockPegResponsiveExponentialIrmMarketAccrueReverted(AccrueRevertPoint point);

    event AccrueInterest(uint256 borrowRate, uint256 interest, uint128 totalBorrowAssets, uint128 totalSupplyAssets);

    IIrm public irm;
    mapping(bytes32 pauseType => bool isPaused) public paused;
    Balance public totalSupply;
    Balance public totalBorrowed;
    uint256 public accrueInterestCalls;
    uint256 public lastInterest;
    uint256 public lastBorrowRate;
    AccrueRevertPoint public accrueRevertPoint;

    constructor(IIrm irm_) {
        irm = irm_;
    }

    /// @notice Calls the permissionless one-shot binding as this market.
    function bindIrm() external {
        irm.setMarket(address(this));
    }

    /// @notice Sets one pause mapping entry.
    function setPaused(bytes32 pauseType, bool isPaused) external {
        paused[pauseType] = isPaused;
    }

    /// @notice Selects an optional deterministic failure around the IRM callback.
    function setAccrueRevertPoint(AccrueRevertPoint point_) external {
        accrueRevertPoint = point_;
    }

    /// @notice Checkpoints interest using the production market call sequence.
    function accrueInterest() external {
        if (paused[PAUSE_TYPE]) revert IPausable.IsPaused(PAUSE_TYPE);

        ++accrueInterestCalls;
        if (accrueRevertPoint == AccrueRevertPoint.BEFORE_CALLBACK) {
            revert MockPegResponsiveExponentialIrmMarketAccrueReverted(AccrueRevertPoint.BEFORE_CALLBACK);
        }

        uint256 interest;
        uint256 borrowRate;
        if (address(irm) != address(0)) {
            (interest, borrowRate) = irm.updateInterestRate(totalSupply.assets, totalBorrowed.assets);
            lastInterest = interest;
            lastBorrowRate = borrowRate;
        }

        if (accrueRevertPoint == AccrueRevertPoint.AFTER_CALLBACK) {
            revert MockPegResponsiveExponentialIrmMarketAccrueReverted(AccrueRevertPoint.AFTER_CALLBACK);
        }
        if (interest == 0) return;

        totalSupply.assets += interest.toUint128();
        totalBorrowed.assets += interest.toUint128();

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    /// @notice Calls the state-changing IRM endpoint as the bound market.
    function callUpdateInterestRate(uint256 totalSupply_, uint256 totalBorrowed_)
        external
        returns (uint256 interest, uint256 borrowRate)
    {
        return irm.updateInterestRate(totalSupply_, totalBorrowed_);
    }

    /// @notice Calls the IRM pause hook as the bound market.
    function callOnMarketPause(bool isPaused) external {
        irm.onMarketPause(isPaused);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {PauseType} from "tap-utils/interfaces/bar/IMarket.sol";

// Tapioca
import {BBLendingCommon} from "./BBLendingCommon.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract BBBorrow is BBLendingCommon {
    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //

    /// @notice Sender borrows `amount` and transfers it to `to`.
    /// @param from Account to borrow for.
    /// @param to The receiver of borrowed tokens.
    /// @param amount Amount to borrow.
    /// @return part Total part of the debt held by borrowers.
    function borrow(address from, address to, uint256 amount)
        external
        optionNotPaused(PauseType.Borrow)
        solvent(from)
        returns (uint256 part)
    {
        _notSelf(to);
        if (amount <= minBorrowAmount) revert MinBorrowAmountNotMet();
        _allowedBorrow(from, amount);

        _penrose.reAccrueBigBangMarkets();

        uint256 feeAmount = _computeVariableOpeningFee(amount);
        part = _borrow(from, to, amount, feeAmount);
    }

    /// @notice Repays a loan.
    /// @dev The bool param is not used but we added it to respect the ISingularity interface for MarketsHelper compatibility
    /// @param from Address to repay from.
    /// @param to Address of the user this payment should go.
    /// @param part The amount to repay. See `userBorrowPart`.
    /// @return amount The total amount repayed.
    function repay(address from, address to, uint256 part)
        external
        optionNotPaused(PauseType.Repay)
        returns (uint256 amount)
    {
        _notSelf(to);
        _tryUpdateExchangeRate();

        _accrue();
        _penrose.reAccrueBigBangMarkets();

        amount = _repay(from, to, part, true);
    }
}

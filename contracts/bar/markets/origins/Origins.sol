// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca

import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {IUsdo} from "tapioca-bar/usdo/IUsdo.sol";
import {SafeApprove} from "../../libraries/SafeApprove.sol";
import {Market} from "../Market.sol";
import {MarketERC4626} from "../MarketERC4626.sol";
import {PauseType} from "tap-utils/interfaces/bar/IMarket.sol";

// solhint-disable max-line-length

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/// @notice used for initial USDO mint
contract Origins is Ownable, Market {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;
    using SafeCast for uint256;
    using SafeApprove for address;

    // ************ //
    // *** VARS *** //
    // ************ //
    mapping(address => bool) allowedParticipants;

    error NotAuthorized();
    error BorrowCapReached();
    error NothingToRepay();
    error BadPair();

    // ************** //
    // *** EVENTS *** //
    // ************** //
    /// @notice event emitted when collateral is added
    event LogAddCollateral(address indexed from, address indexed to, uint256 indexed share);
    /// @notice event emitted when collateral is removed
    event LogRemoveCollateral(address indexed from, address indexed to, uint256 indexed share);
    /// @notice event emitted when borrow is performed
    event LogBorrow(address indexed from, address indexed to, uint256 indexed amount, uint256 part);
    /// @notice event emitted when a repay operation is performed
    event LogRepay(address indexed from, address indexed to, uint256 indexed amount, uint256 part);
    /// @notice event emitted when an allowed participant status changes
    event UpdateParticipants(address indexed participant, bool indexed status);

    constructor(address __owner) Market("Origins", "ORI") {
        allowedParticipants[__owner] = true;
        _transferOwnership(__owner);
    }

    // TODO Check initialization and constructor
    function init(
        IERC20 __asset,
        address __collateral,
        ITapiocaOracle __oracle,
        uint256 __exchangeRatePrecision,
        uint256 __collateralizationRate,
        IPenrose __penrose
    ) external onlyOnce {
        if (__collateral == address(0)) revert BadPair();
        if (address(__asset) == address(0)) revert BadPair();
        if (address(__oracle) == address(0)) revert BadPair();
        if (__collateralizationRate > FEE_PRECISION) revert NotValid();

        _asset = __asset;
        _collateral = __collateral;
        oracle = __oracle;
        _penrose = __penrose;
        updateExchangeRate();

        EXCHANGE_RATE_PRECISION = __exchangeRatePrecision > 0 ? __exchangeRatePrecision : 1e18;

        collateralizationRate = __collateralizationRate;
        liquidationCollateralizationRate = 1e5;

        rateValidDuration = 24 hours;
        minBorrowAmount = 1e15;
    }

    // ************************* //
    // *** OWNER FUNCTIONS ***** //
    // ************************* //

    /// @notice sets or removes an allowed participant
    /// @param _participant the participant's address
    /// @param _val true/false
    function updateAllowedParticipants(address _participant, bool _val) external onlyOwner {
        allowedParticipants[_participant] = _val;
        emit UpdateParticipants(_participant, _val);
    }

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //
    /// @notice Adds `collateral`
    /// False if tokens from msg.sender  should be transferred.
    /// @param amount The amount to add for `msg.sender`.
    /// @param share The amount of shares to add for `msg.sender`.
    function addCollateral(uint256 amount, uint256 share) external optionNotPaused(PauseType.AddCollateral) {
        if (!allowedParticipants[msg.sender]) revert NotAuthorized();

        if (share == 0) {
            share = previewDeposit(amount);
        }

        _addCollateral(msg.sender, msg.sender, amount, share);
    }

    /// @notice Removes `share` amount of collateral
    /// @param share Amount of shares to remove.
    function removeCollateral(uint256 share) external optionNotPaused(PauseType.RemoveCollateral) solvent(msg.sender) {
        if (!allowedParticipants[msg.sender]) revert NotAuthorized();
        _removeCollateral(msg.sender, msg.sender, share);
    }

    /// @notice Sender borrows `amount` and transfers it to `to`.
    /// @param amount Amount to borrow.
    /// @return part Total part of the debt held by borrowers.
    /// @return share Total amount in shares borrowed.
    function borrow(uint256 amount)
        external
        optionNotPaused(PauseType.Borrow)
        solvent(msg.sender)
        returns (uint256 part, uint256 share)
    {
        if (!allowedParticipants[msg.sender]) revert NotAuthorized();

        if (amount <= minBorrowAmount) revert MinBorrowAmountNotMet();

        (part, share) = _borrow(msg.sender, msg.sender, amount);
    }

    /// @notice Repays a loan.
    /// @dev The bool param is not used but we added it to respect the ISingularity interface for MarketsHelper compatibility
    /// @param part The amount to repay. See `userBorrowPart`.
    /// @return amount The total amount repayed.
    function repay(uint256 part) external optionNotPaused(PauseType.Repay) returns (uint256 amount) {
        if (!allowedParticipants[msg.sender]) revert NotAuthorized();

        updateExchangeRate();
        amount = _repay(msg.sender, msg.sender, part);
    }

    function _accrue() internal pure override {
        // does nothign on this market
    }

    function _accrueView() internal pure override returns (Rebase memory) {
        // does nothign on this market
        Rebase memory rb = Rebase({elastic: 0, base: 0});
        return rb;
    }

    receive() external payable {}

    // ************************* //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //
    function _repay(address from, address to, uint256 part) internal returns (uint256 amountOut) {
        if (part > userBorrowPart[to]) {
            part = userBorrowPart[to];
        }
        if (part == 0) revert NothingToRepay();

        uint256 amount;
        (totalBorrow, amount) = totalBorrow.sub(part, true);
        userBorrowPart[to] -= part;

        // amount includes the opening & accrued fees
        amountOut = amount;

        //burn USDO
        _borrowableToken().safeTransferFrom(from, address(this), amount);
        IUsdo(address(_borrowableToken())).burn(address(this), amount);

        emit LogRepay(from, to, amountOut, part);
    }

    function _borrow(address from, address to, uint256 amount) internal returns (uint256 part, uint256 share) {
        (totalBorrow, part) = totalBorrow.add(amount, true);

        if (totalBorrowCap > 0) {
            if (totalBorrow.elastic > totalBorrowCap) revert BorrowCapReached();
        }

        userBorrowPart[from] += part;
        emit LogBorrow(from, to, amount, part);

        //mint USDO
        IUsdo(address(_borrowableToken())).mint(address(this), amount);

        IERC20(_borrowableToken()).safeTransfer(to, amount);
    }

    function _addCollateral(address from, address to, uint256 amount, uint256 share) internal {
        if (share == 0) {
            share = previewDeposit(amount);
        }
        mint(share, to);
        emit LogAddCollateral(from, to, share);
    }

    function _removeCollateral(address from, address to, uint256 share) internal {
        withdraw(share, to, from);
        emit LogRemoveCollateral(from, to, share);
    }
}

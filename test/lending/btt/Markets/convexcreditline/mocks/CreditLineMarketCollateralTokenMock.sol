// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

contract CreditLineMarketCollateralTokenMock is ERC20, IMintableERC20 {
    bool public revertMint;
    bool public revertBurn;
    bool public revertTransfer;
    bool public revertTransferFrom;
    bool public revertApprove;
    bool public returnFalseOnTransfer;
    bool public revertBalanceQuery;
    bool public armBalanceRevertAfterTransfer;
    uint256 public transferReceivedBps = 10_000;
    uint256 public debitRecipientAfterTransfer;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackOnMint;
    bool public callbackOnBurn;
    bool public callbackOnTransfer;
    bool public callbackOnTransferFrom;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function setTransferBehavior(bool shouldRevert, bool shouldReturnFalse, uint256 receivedBps, uint256 recipientDebit)
        external
    {
        revertTransfer = shouldRevert;
        returnFalseOnTransfer = shouldReturnFalse;
        transferReceivedBps = receivedBps;
        debitRecipientAfterTransfer = recipientDebit;
    }

    function setMintBurnFailure(bool shouldRevertMint, bool shouldRevertBurn) external {
        revertMint = shouldRevertMint;
        revertBurn = shouldRevertBurn;
    }

    function setTransferFromFailure(bool shouldRevert) external {
        revertTransferFrom = shouldRevert;
    }

    function setApproveFailure(bool shouldRevert) external {
        revertApprove = shouldRevert;
    }

    function setBalanceFailure(bool shouldRevert, bool armAfterTransfer) external {
        revertBalanceQuery = shouldRevert;
        armBalanceRevertAfterTransfer = armAfterTransfer;
    }

    function setCallback(address target, bytes calldata data, uint8 modes) external {
        callbackTarget = target;
        callbackData = data;
        callbackOnMint = modes & 1 != 0;
        callbackOnBurn = modes & 2 != 0;
        callbackOnTransfer = modes & 4 != 0;
        callbackOnTransferFrom = modes & 8 != 0;
    }

    function mint(address to, uint256 amount) external override {
        if (revertMint) revert("MINT_REVERTED");
        _mint(to, amount);
        if (callbackOnMint) _callback();
    }

    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        if (revertBalanceQuery) revert("BALANCE_REVERTED");
        return super.balanceOf(account);
    }

    function burn(address from, uint256 amount) external override {
        if (revertBurn) revert("BURN_REVERTED");
        _burn(from, amount);
        if (callbackOnBurn) _callback();
    }

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (revertTransfer) revert("TRANSFER_REVERTED");
        if (returnFalseOnTransfer) return false;
        _transferWithDelta(msg.sender, to, amount);
        if (armBalanceRevertAfterTransfer) revertBalanceQuery = true;
        if (callbackOnTransfer) _callback();
        return true;
    }

    function approve(address spender, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (revertApprove) revert("APPROVE_REVERTED");
        return super.approve(spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (revertTransferFrom) revert("TRANSFER_FROM_REVERTED");
        _spendAllowance(from, msg.sender, amount);
        _transferWithDelta(from, to, amount);
        if (callbackOnTransferFrom) _callback();
        return true;
    }

    function _transferWithDelta(address from, address to, uint256 amount) private {
        uint256 received = amount * transferReceivedBps / 10_000;
        _update(from, to, received);
        if (debitRecipientAfterTransfer != 0) {
            _burn(to, debitRecipientAfterTransfer);
        }
    }

    function _callback() private {
        (bool success, bytes memory reason) = callbackTarget.call(callbackData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }
}

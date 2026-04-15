// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IUsmMinimal {
    function sellAsset(uint256 maxAmount, address receiver) external returns (uint256, uint256);
}

/// @title UsmSellAdapter
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @dev Stateless adapter that allows liquidators to swap an underlying asset (e.g. USDC) into
///      DUSD via a USM's `sellAsset` in a single call. The caller must have previously approved
///      this contract to spend their underlying asset. The adapter pulls tokens from the caller,
///      forwards them to the USM, and sends any dust back. Approvals to the USM are zeroed after
///      each call to prevent dangling allowances.
contract UsmSellAdapter {
    error AdapterCallFailed();
    error InsufficientBalance();
    error InvalidAmount();

    function sellAssetFromSenderBalance(address underlyingAsset, address usm, address receiver, uint256 maxAmount)
        external
        returns (uint256 assetSold, uint256 stableOut)
    {
        if (maxAmount == 0) revert InvalidAmount();

        uint256 senderBalance = IERC20Minimal(underlyingAsset).balanceOf(msg.sender);
        uint256 amountToSell = senderBalance < maxAmount ? senderBalance : maxAmount;

        if (amountToSell == 0) revert InsufficientBalance();

        _callOptionalReturn(
            underlyingAsset, abi.encodeCall(IERC20Minimal.transferFrom, (msg.sender, address(this), amountToSell))
        );
        _forceApprove(underlyingAsset, usm, amountToSell);

        (bool ok, bytes memory data) = usm.call(abi.encodeCall(IUsmMinimal.sellAsset, (amountToSell, receiver)));
        if (!ok) _revertWithData(data);

        (assetSold, stableOut) = abi.decode(data, (uint256, uint256));
        _callOptionalReturn(underlyingAsset, abi.encodeCall(IERC20Minimal.approve, (usm, 0)));

        uint256 dust = IERC20Minimal(underlyingAsset).balanceOf(address(this));
        if (dust > 0) {
            _callOptionalReturn(underlyingAsset, abi.encodeCall(IERC20Minimal.transfer, (msg.sender, dust)));
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20Minimal.approve, (spender, 0)));
        _callOptionalReturn(token, abi.encodeCall(IERC20Minimal.approve, (spender, amount)));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returnData) = token.call(data);
        if (!ok) _revertWithData(returnData);
        if (returnData.length > 0 && !abi.decode(returnData, (bool))) {
            revert AdapterCallFailed();
        }
    }

    function _revertWithData(bytes memory revertData) internal pure {
        if (revertData.length == 0) revert AdapterCallFailed();

        assembly ("memory-safe") {
            revert(add(revertData, 32), mload(revertData))
        }
    }
}

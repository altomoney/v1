// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev ERC4626 test double exposing the AltoVault fee-recipient view and a configurable liquidity limit.
contract ProtocolFeeCollectorVaultMock is ERC4626 {
    address public feeRecipient;
    uint256 public liquidityLimitShares = type(uint256).max;
    uint256 public pendingFeeAssets;

    constructor(IERC20 asset_, address feeRecipient_) ERC20("Fee Vault", "FV") ERC4626(asset_) {
        feeRecipient = feeRecipient_;
    }

    function setFeeRecipient(address newFeeRecipient) external {
        feeRecipient = newFeeRecipient;
    }

    function setLiquidityLimitShares(uint256 newLiquidityLimitShares) external {
        liquidityLimitShares = newLiquidityLimitShares;
    }

    function addPendingFeeAssets(uint256 assets) external {
        require(IERC20(asset()).transferFrom(msg.sender, address(this), assets));
        pendingFeeAssets += assets;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        if (shares == 0 && pendingFeeAssets != 0) {
            uint256 fees = pendingFeeAssets;
            pendingFeeAssets = 0;
            _mint(feeRecipient, fees);
        }
        assets = super.redeem(shares, receiver, owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return Math.min(super.maxRedeem(owner), liquidityLimitShares);
    }
}

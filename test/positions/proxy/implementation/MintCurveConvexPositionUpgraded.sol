// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionType} from "@alto/positions/interfaces/IPosition.sol";

/// @title MintCurveConvexPositionUpgraded
/// @notice V2 beacon implementation used to validate position proxy upgrades.
contract MintCurveConvexPositionUpgraded is MintCurveConvexPosition {
    /// @notice Nonce reserved for post-upgrade position logic.
    uint256 public upgradeNonce;

    /// @notice Secondary owner reference introduced in V2.
    address public otherOwner;

    uint256[46] private __gap_upgraded;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc MintCurveConvexPosition
    function version() external view override returns (uint256) {
        return 2;
    }

    /// @inheritdoc MintCurveConvexPosition
    function positionType() external view override returns (PositionType) {
        return PositionType.MINT_CURVE_CONVEX;
    }

    /// @notice Sets the V2 other-owner reference.
    /// @param _otherOwner The other owner address to store.
    function setOtherOwner(address _otherOwner) external onlyOwner {
        otherOwner = _otherOwner;
    }

    /// @notice Updates the V2 nonce.
    /// @param nonce New nonce value.
    function setUpgradeNonce(uint256 nonce) external onlyOwner {
        upgradeNonce = nonce;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";

/// @title MintCurveConvexPositionUpgraded
/// @notice V2 beacon implementation used to validate position proxy upgrades.
/// @custom:oz-upgrades-from MintCurveConvexPosition
contract MintCurveConvexPositionUpgraded is MintCurveConvexPosition {
    /// @notice Nonce reserved for post-upgrade position logic.
    uint256 public upgradeNonce;

    /// @notice Secondary owner reference introduced in V2.
    address public otherOwner;

    uint256[48] private __gap_upgraded;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc MintCurveConvexPosition
    function version() external pure override returns (uint256) {
        return 2;
    }

    /// @inheritdoc MintCurveConvexPosition
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address _owner, address _factory, address _market, MintCurveConvexConfig calldata _config)
        external
        override
        initializer
    {
        __MintCurveConvexPosition_init(_owner, _factory, _market, _config);
    }

    /// @notice Initializes V2 storage on an already-deployed position proxy after a beacon upgrade.
    /// @dev Mirrors the recommended reinitializer pattern for future position upgrades that add storage.
    /// @param _upgradeNonce Initial V2 nonce value.
    /// @param _otherOwner Initial V2 other-owner reference.
    function initializeV2(uint256 _upgradeNonce, address _otherOwner) external reinitializer(2) onlyOwner {
        upgradeNonce = _upgradeNonce;
        otherOwner = _otherOwner;
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

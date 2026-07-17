// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";

/// @title MintCurveConvexPositionFactoryUpgraded
/// @notice V2 implementation used to validate UUPS storage layout extensions for `MintCurveConvexPositionFactory`.
/// @custom:oz-upgrades-from MintCurveConvexPositionFactory
contract MintCurveConvexPositionFactoryUpgraded is MintCurveConvexPositionFactory {
    /// @notice Counter reserved for post-upgrade factory logic.
    uint256 public addedCounter;

    /// @notice Secondary admin reference introduced in V2.
    address public addedAdmin;

    /// @notice Feature flag introduced in V2.
    bool public addedFlag;

    uint256[36] private __gap_upgraded;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc MintCurveConvexPositionFactory
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address admin, address _marketRegistry, MintCurveConvexConfig calldata _config)
        external
        override
        initializer
    {
        __MintCurveConvexPositionFactory_init(admin, _marketRegistry, _config);
    }

    /// @notice Initializes V2 storage on an upgraded factory proxy.
    /// @param counter Initial counter value.
    /// @param admin Initial admin reference.
    /// @param flag Initial feature flag.
    function initializeV2(uint256 counter, address admin, bool flag) external reinitializer(2) onlyOwner {
        addedCounter = counter;
        addedAdmin = admin;
        addedFlag = flag;
    }

    /// @notice Updates the V2 counter.
    /// @param counter New counter value.
    function setAddedCounter(uint256 counter) external onlyOwner {
        addedCounter = counter;
    }

    /// @notice Updates the V2 admin reference.
    /// @param admin New admin reference.
    function setAddedAdmin(address admin) external onlyOwner {
        addedAdmin = admin;
    }

    /// @notice Updates the V2 feature flag.
    /// @param flag New feature flag.
    function setAddedFlag(bool flag) external onlyOwner {
        addedFlag = flag;
    }
}

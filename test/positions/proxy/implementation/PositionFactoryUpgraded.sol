// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionFactory} from "@alto/positions/PositionFactory.sol";

/// @title PositionFactoryUpgraded
/// @notice V2 implementation used to validate UUPS storage layout extensions for `PositionFactory`.
/// @custom:oz-upgrades-from PositionFactory
contract PositionFactoryUpgraded is PositionFactory {
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

    /// @inheritdoc PositionFactory
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address admin, address _marketRegistry) external override initializer {
        __PositionFactory_init(admin, _marketRegistry);
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

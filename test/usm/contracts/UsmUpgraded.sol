// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Usm} from "@alto/usm/Usm.sol";

/// @custom:oz-upgrades-from Usm
abstract contract UsmUpgraded is Usm {
    uint256 public addedProperty1;
    uint256 public addedProperty2;
    address public addedProperty3;

    /// upgrade gap
    uint256[47] private __gap_usm_upgraded;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address stableToken, address underlyingAsset) Usm(stableToken, underlyingAsset) {
        _disableInitializers();
    }

    function USM_REVISION() public pure virtual override returns (uint256) {
        return 2;
    }

    /// @dev Reinitializer for version 2 upgrade - initializes new storage variables
    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3)
        public
        virtual
        reinitializer(2)
    {
        addedProperty1 = _addedProperty1;
        addedProperty2 = _addedProperty2;
        addedProperty3 = _addedProperty3;
    }

    function setAddedProperty1(uint256 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(uint256 value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(address value) external {
        addedProperty3 = value;
    }
}


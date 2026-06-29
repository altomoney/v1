// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPosition} from "./interfaces/IPosition.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";

/// @title PositionBase
/// @notice Base contract for all the strategies(position)
abstract contract PositionBase is
    IPosition,
    Initializable,
    OwnableUpgradeable,
    AuthUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @inheritdoc IPosition
    function add(bytes calldata data) public {
        _add(data);
    }

    /// @inheritdoc IPosition
    function remove(bytes calldata data) public {
        _remove(data);
    }

    /// @dev Internal hook for add logic. Must be implemented by derived contracts.
    function _add(bytes calldata data) internal virtual;

    /// @dev Internal hook for remove logic. Must be implemented by derived contracts.
    function _remove(bytes calldata data) internal virtual;

    function __PositionBase_init(address _owner) internal onlyInitializing {
        __Ownable_init(_owner);
        __Auth_init();
        __ReentrancyGuard_init();
    }
}

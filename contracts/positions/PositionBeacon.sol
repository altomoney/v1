// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title PositionBeacon
/// @notice Thin wrapper around OpenZeppelin's upgradeable beacon
/// @dev The implementation of this beacon needs to be MintCurveConvexPosition contract for MintCurveConvexPosition strategy
/// @dev This beacon contract will be set in MintCurveConvexPositionFactory contract as a beacon
/// @custom:audit Pending
contract PositionBeacon is UpgradeableBeacon {
    constructor(address implementation, address admin) UpgradeableBeacon(implementation, admin) {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AltoTimelockController
 * @author GPM
 * @custom:contact security@altofoundation.org
 * @dev Custom TimelockController that requires AccessControl role changes - grantRole, revokeRole -
 *      to go through the timelock process. Addiontaly, renounceRole is disabled for the admin role.
 *      This prevents malicious transactions from immediately granting/revoking roles,
 *      even if the caller has admin permissions.
 */
contract AltoTimelockController is TimelockController {
    error AltoTimelockController_OnlyCallableFromTimelock();
    error AltoTimelockController_AdminRoleCannotBeRenounced();

    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}

    /// @inheritdoc AccessControl
    function grantRole(bytes32 role, address account) public virtual override {
        if (msg.sender != address(this)) {
            revert AltoTimelockController_OnlyCallableFromTimelock();
        }

        super._grantRole(role, account);
    }

    /// @inheritdoc AccessControl
    function revokeRole(bytes32 role, address account) public virtual override {
        if (msg.sender != address(this)) {
            revert AltoTimelockController_OnlyCallableFromTimelock();
        }

        super._revokeRole(role, account);
    }

    /// @inheritdoc AccessControl
    function renounceRole(bytes32 role, address callerConfirmation) public virtual override {
        if (callerConfirmation != _msgSender()) {
            revert AccessControlBadConfirmation();
        }

        if (role == DEFAULT_ADMIN_ROLE) {
            revert AltoTimelockController_AdminRoleCannotBeRenounced();
        }

        super._revokeRole(role, callerConfirmation);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {PegResponsiveExponentialIrmConfig, IRState} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";

/// @notice Test harness for reaching cached controller states that are otherwise
/// only produced over multiple market checkpoints.
contract PegResponsiveExponentialIrmHarness is PegResponsiveExponentialIrm {
    constructor(address initialPegOracle, PegResponsiveExponentialIrmConfig memory initialConfig, address initialOwner)
        PegResponsiveExponentialIrm(initialPegOracle, initialConfig, initialOwner)
    {}

    /// @notice Replaces the complete cached controller state.
    /// @dev This is the only production-state hook exposed by the harness.
    function setIRStateForTest(IRState calldata state) external {
        irState = state;
    }
}

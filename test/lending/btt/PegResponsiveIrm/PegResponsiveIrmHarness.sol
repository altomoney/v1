// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {CurveConfig, IRState} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {PegResponsiveIrm} from "@alto/lending/irm/PegResponsiveIrm.sol";

/// @notice Test harness for reaching cached controller states that are otherwise
/// only produced over multiple market checkpoints.
contract PegResponsiveIrmHarness is PegResponsiveIrm {
    constructor(address oracle_, CurveConfig memory config_, address initialOwner_)
        PegResponsiveIrm(oracle_, config_, initialOwner_)
    {}

    /// @notice Replaces the complete cached controller state.
    /// @dev This is the only production-state hook exposed by the harness.
    function setIRStateForTest(IRState calldata state_) external {
        irState = state_;
    }
}

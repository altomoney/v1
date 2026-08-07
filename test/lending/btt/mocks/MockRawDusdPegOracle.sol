// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IDusdPegOracleCurveBase} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";

/// @notice Low-level oracle double used to exercise caller-side ABI decoding.
/// @dev Normal behavior tests should use `MockDusdPegOracle`. This contract is
/// deliberately untyped so it can return empty, short, or non-canonical ABI data.
contract MockRawDusdPegOracle {
    error MockRawDusdPegOracleUnsupportedCall(bytes4 selector);

    bytes private s_responseData;

    constructor() {
        s_responseData = abi.encode(uint256(1e18), uint48(block.timestamp), true);
    }

    /// @notice Configures raw bytes to return from `getPrice`.
    function setRawReturnData(bytes calldata responseData_) external {
        s_responseData = responseData_;
    }

    fallback() external {
        if (msg.sig != IDusdPegOracleCurveBase.getPrice.selector) {
            revert MockRawDusdPegOracleUnsupportedCall(msg.sig);
        }

        bytes memory responseData = s_responseData;
        assembly ("memory-safe") {
            return(add(responseData, 0x20), mload(responseData))
        }
    }
}

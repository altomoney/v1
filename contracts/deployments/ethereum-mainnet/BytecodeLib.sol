// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/// @title BytecodeLib
/// @notice Compares deployed bytecode with compiled bytecode while ignoring the compiler metadata.
/// @dev Solidity appends CBOR metadata to runtime code, followed by two bytes with its length. The metadata holds a
/// hash of the source files, so any comment or license-header change alters it although the executed code is the same.
library BytecodeLib {
    /// @notice Returns true when the code at `deployed` equals `compiledRuntimeCode` once both trailers are removed.
    function matchesDeployed(address deployed, bytes memory compiledRuntimeCode) internal view returns (bool) {
        return hashWithoutMetadata(deployed.code) == hashWithoutMetadata(compiledRuntimeCode);
    }

    /// @notice Returns true when the code at `deployed` is either the recorded `knownCodehash` or a fresh compile of
    /// `compiledRuntimeCode`, so a known mainnet deployment and a deployment from the current sources both pass.
    function matchesKnownOrCompiled(address deployed, bytes32 knownCodehash, bytes memory compiledRuntimeCode)
        internal
        view
        returns (bool)
    {
        bytes32 codehash = deployed.codehash;
        return codehash == knownCodehash || codehash == keccak256(compiledRuntimeCode);
    }

    /// @notice Hashes `code` without its trailing CBOR metadata.
    /// @dev Falls back to hashing the whole input when it is too short to carry a trailer.
    function hashWithoutMetadata(bytes memory code) internal pure returns (bytes32 hash) {
        uint256 length = code.length;
        if (length < 2) return keccak256(code);

        uint256 trailerLength = (uint256(uint8(code[length - 2])) << 8 | uint256(uint8(code[length - 1]))) + 2;
        if (trailerLength > length) return keccak256(code);

        uint256 bodyLength = length - trailerLength;
        assembly ("memory-safe") {
            hash := keccak256(add(code, 32), bodyLength)
        }
    }
}

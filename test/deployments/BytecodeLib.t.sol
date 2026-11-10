// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {BytecodeLib} from "@alto/deployments/ethereum-mainnet/BytecodeLib.sol";

contract Probe {
    function answer() external pure returns (uint256) {
        return 42;
    }
}

contract BytecodeLibTest is Test {
    function test_hashWithoutMetadata_ignoresMetadataChanges() public pure {
        bytes memory code = type(Probe).runtimeCode;
        bytes memory changed = bytes.concat(code);
        uint256 metadataLength = uint256(uint8(code[code.length - 2])) << 8 | uint256(uint8(code[code.length - 1]));
        uint256 insideMetadata = code.length - 2 - metadataLength / 2;
        changed[insideMetadata] = bytes1(uint8(changed[insideMetadata]) ^ 0xff);

        assertNotEq(keccak256(code), keccak256(changed));
        assertEq(BytecodeLib.hashWithoutMetadata(code), BytecodeLib.hashWithoutMetadata(changed));
    }

    function test_hashWithoutMetadata_detectsCodeChanges() public pure {
        bytes memory code = type(Probe).runtimeCode;
        bytes memory changed = bytes.concat(code);
        changed[0] = bytes1(uint8(changed[0]) ^ 0xff);

        assertNotEq(BytecodeLib.hashWithoutMetadata(code), BytecodeLib.hashWithoutMetadata(changed));
    }

    function test_hashWithoutMetadata_hashesShortInputWhole() public pure {
        assertEq(BytecodeLib.hashWithoutMetadata(hex""), keccak256(hex""));
        assertEq(BytecodeLib.hashWithoutMetadata(hex"00"), keccak256(hex"00"));
        assertEq(BytecodeLib.hashWithoutMetadata(hex"00ff"), keccak256(hex"00ff"));
    }

    function test_matchesDeployed() public {
        Probe probe = new Probe();

        assertTrue(BytecodeLib.matchesDeployed(address(probe), type(Probe).runtimeCode));
        assertFalse(BytecodeLib.matchesDeployed(address(this), type(Probe).runtimeCode));
        assertFalse(BytecodeLib.matchesDeployed(address(0xdead), type(Probe).runtimeCode));
    }

    function test_matchesKnownOrCompiled() public {
        Probe probe = new Probe();
        bytes32 otherHash = keccak256(hex"600160005260206000f3");

        assertTrue(BytecodeLib.matchesKnownOrCompiled(address(probe), otherHash, type(Probe).runtimeCode));
        assertTrue(BytecodeLib.matchesKnownOrCompiled(address(probe), address(probe).codehash, hex""));
        assertFalse(BytecodeLib.matchesKnownOrCompiled(address(probe), otherHash, hex""));
    }
}

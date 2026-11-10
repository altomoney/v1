// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Vm} from "forge-std/Vm.sol";

/// @notice Creates Ethereum mainnet forks for tests.
/// @dev `forge test` runs offline by default. When `ALCHEMY_KEY` is unset, the calling test or suite is skipped
/// instead of failing, so fork tests only run when an RPC key is configured.
library Fork {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Matches the `ethereum` entry under `[rpc_endpoints]` in `foundry.toml`.
    string private constant ETHEREUM_RPC_ALIAS = "ethereum";
    string private constant RPC_KEY_ENV = "ALCHEMY_KEY";

    /// @notice Selects a mainnet fork at `blockNumber`, or skips the caller when no RPC key is configured.
    function selectEthereum(uint256 blockNumber) internal returns (uint256 forkId) {
        _skipWithoutRpcKey();
        return VM.createSelectFork(VM.rpcUrl(ETHEREUM_RPC_ALIAS), blockNumber);
    }

    /// @notice Selects a mainnet fork at the latest block, or skips the caller when no RPC key is configured.
    function selectEthereum() internal returns (uint256 forkId) {
        _skipWithoutRpcKey();
        return VM.createSelectFork(VM.rpcUrl(ETHEREUM_RPC_ALIAS));
    }

    function _skipWithoutRpcKey() private {
        if (!VM.envExists(RPC_KEY_ENV)) VM.skip(true);
    }
}

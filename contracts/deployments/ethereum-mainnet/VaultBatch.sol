// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {AltoVault} from "@alto/lending/vault/AltoVault.sol";

struct VaultBatchParams {
    address timelock;
    address dusd;
    address marketRegistry;
    address curator;
    address allocator;
    address guardian;
    address skimRecipient;
    address feeRecipient;
    uint256 fee;
    address[] markets;
    uint256[] caps;
    address[] supplyQueue;
    uint256 finalTimelock;
}

struct VaultBatchReport {
    address vault;
}

/// @title VaultBatch
/// @notice Deploys and configures the Alto DUSD Vault in a single transaction.
/// @dev The batch contract is the temporary owner during deployment so it can run all
///      `onlyOwner` / `onlyCuratorRole` / `onlyAllocatorRole` configuration calls. At the end,
///      it transfers ownership to the final timelock using `transferOwnershipSkip2Step`.
contract VaultBatch {
    VaultBatchReport public report;

    string public constant VAULT_NAME = "Alto DUSD Vault";
    string public constant VAULT_SYMBOL = "aDUSD";

    error LengthMismatch();
    error EmptyMarketSet();
    error InvalidParams();

    constructor(VaultBatchParams memory _params) {
        if (_params.markets.length == 0) revert EmptyMarketSet();
        if (_params.markets.length != _params.caps.length) revert LengthMismatch();
        if (
            _params.curator == address(0) || _params.guardian == address(0) || _params.allocator == address(0)
                || _params.skimRecipient == address(0) || _params.feeRecipient == address(0)
                || _params.dusd == address(0) || _params.marketRegistry == address(0) || _params.timelock == address(0)
                || _params.finalTimelock == 0
        ) revert InvalidParams();

        // Deploy vault with timelock = 0 so caps can be accepted immediately.
        AltoVault vault = new AltoVault({
            owner: address(this),
            initialTimelock: 0,
            _asset: _params.dusd,
            __name: VAULT_NAME,
            __symbol: VAULT_SYMBOL,
            _marketRegistry: _params.marketRegistry
        });

        vault.setCurator(_params.curator);
        vault.setIsAllocator(_params.allocator, true);
        vault.submitGuardian(_params.guardian);

        vault.setSkimRecipient(_params.skimRecipient);
        vault.setFeeRecipient(_params.feeRecipient);

        if (_params.fee != 0) {
            vault.setFee(_params.fee);
        }

        // Caps: with timelock = 0, each submitCap creates a pending entry whose validAt is the
        // current block timestamp, so acceptCap can be called immediately in the same tx.
        for (uint256 i; i < _params.markets.length; ++i) {
            vault.submitCap(_params.markets[i], _params.caps[i]);
            vault.acceptCap(_params.markets[i]);
        }

        // Supply queue (markets must already have a non-zero cap, which we just set above)
        vault.setSupplyQueue(_params.supplyQueue);

        // Increase timelock from 0 -> finalTimelock. Since new > current, submitTimelock applies it
        // immediately without a pending state.
        vault.submitTimelock(_params.finalTimelock);

        // Hand ownership to the timelock without the 2-step dance (deployment-only convenience).
        vault.transferOwnershipSkip2Step(_params.timelock);

        report = VaultBatchReport({vault: address(vault)});
    }

    function getReport() external view returns (VaultBatchReport memory) {
        return report;
    }
}

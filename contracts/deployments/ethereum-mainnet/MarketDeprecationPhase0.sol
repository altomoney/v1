// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";

struct MarketDeprecationPhase0Batch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

struct MarketDeprecationPhase0Params {
    address timelock;
    address freezer;
    address vault;
    address[] borrowMarketsToDeprecate;
    uint256[] borrowMarketsToDeprecateT0RatesSpy;
    address[] mintMarketsToDeprecate;
    uint256[] mintMarketsToDeprecateT0RatesSpy;
    address[] mintMarketsAlreadyDeprecated;
    uint256[] mintMarketsAlreadyDeprecatedT0RatesSpy;
}

struct MarketDeprecationPhase0Report {
    address ownerFixedRateIrmFactory;
    address vaultCurator;
    MarketDeprecationPhase0Batch freezerBatch;
    MarketDeprecationPhase0Batch vaultCuratorBatch;
    MarketDeprecationPhase0Batch timelockBatch;
}

/// @notice Builds the T0 Freezer Safe payload and atomic Timelock IRM operation for the August 2026 deprecation.
library MarketDeprecationPhase0 {
    function prepare(MarketDeprecationPhase0Params memory params)
        internal
        returns (MarketDeprecationPhase0Report memory report)
    {
        address timelock = params.timelock;
        address vault = params.vault;
        address[] memory borrowMarkets = params.borrowMarketsToDeprecate;
        address[] memory mintMarkets = params.mintMarketsToDeprecate;

        OwnerFixedRateIrmFactory factory = new OwnerFixedRateIrmFactory(timelock);
        report.ownerFixedRateIrmFactory = address(factory);

        report.freezerBatch = _buildFreezerBatch(borrowMarkets, mintMarkets);

        report.vaultCurator = IAltoVaultBase(vault).curator();
        report.vaultCuratorBatch = _buildVaultCuratorBatch(vault, borrowMarkets);
        report.timelockBatch = _buildTimelockBatch(params, address(factory));
    }

    function _buildFreezerBatch(address[] memory borrowMarkets, address[] memory mintMarkets)
        private
        pure
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        uint256 callCount = borrowMarkets.length + mintMarkets.length;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);

        uint256 callIndex;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            batch.targets[callIndex] = borrowMarkets[i];
            batch.payloads[callIndex] = abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true));
            ++callIndex;
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            batch.targets[callIndex] = mintMarkets[i];
            batch.payloads[callIndex] = abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true));
            ++callIndex;
        }
        assert(callIndex == batch.targets.length);
    }

    function _buildVaultCuratorBatch(address vault, address[] memory borrowMarkets)
        private
        pure
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        batch.targets = new address[](borrowMarkets.length);
        batch.values = new uint256[](borrowMarkets.length);
        batch.payloads = new bytes[](borrowMarkets.length);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            batch.targets[i] = vault;
            batch.payloads[i] = abi.encodeCall(IAltoVaultBase.submitCap, (borrowMarkets[i], 0));
        }
    }

    function _buildTimelockBatch(MarketDeprecationPhase0Params memory params, address factory)
        private
        view
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        uint256 callCount = params.borrowMarketsToDeprecate.length * 2 + params.mintMarketsToDeprecate.length
            + params.mintMarketsAlreadyDeprecated.length;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);

        uint256 callIndex;
        for (uint256 i; i < params.borrowMarketsToDeprecate.length; ++i) {
            batch.targets[callIndex] = factory;
            batch.payloads[callIndex] = abi.encodeCall(
                OwnerFixedRateIrmFactory.deploy,
                (params.borrowMarketsToDeprecate[i], params.borrowMarketsToDeprecateT0RatesSpy[i], params.timelock)
            );
            ++callIndex;
        }

        OwnerFixedRateIrmFactory fixedRateIrmFactory = OwnerFixedRateIrmFactory(factory);
        uint256 initialNonce = fixedRateIrmFactory.nonce();
        for (uint256 i; i < params.borrowMarketsToDeprecate.length; ++i) {
            address fixedRateIrm = fixedRateIrmFactory.predictIrmAddress(
                params.borrowMarketsToDeprecateT0RatesSpy[i], params.timelock, initialNonce + i
            );
            batch.targets[callIndex] = params.borrowMarketsToDeprecate[i];
            batch.payloads[callIndex] = abi.encodeCall(IMarketBase.setIrm, (fixedRateIrm, false));
            ++callIndex;
        }

        for (uint256 i; i < params.mintMarketsToDeprecate.length; ++i) {
            batch.targets[callIndex] = IMarketBase(params.mintMarketsToDeprecate[i]).irm();
            batch.payloads[callIndex] =
                abi.encodeCall(FixedRateIrm.setBorrowRate, (params.mintMarketsToDeprecateT0RatesSpy[i]));
            ++callIndex;
        }

        for (uint256 i; i < params.mintMarketsAlreadyDeprecated.length; ++i) {
            batch.targets[callIndex] = IMarketBase(params.mintMarketsAlreadyDeprecated[i]).irm();
            batch.payloads[callIndex] =
                abi.encodeCall(FixedRateIrm.setBorrowRate, (params.mintMarketsAlreadyDeprecatedT0RatesSpy[i]));
            ++callIndex;
        }

        assert(callIndex == batch.targets.length);
    }
}

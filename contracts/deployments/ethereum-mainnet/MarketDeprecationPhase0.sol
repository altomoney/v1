// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";

uint256 constant T0_IRM_VERSION = 1;

struct MarketRate {
    address market;
    uint256 rateSpy;
}

struct MarketDeprecationPhase0Config {
    uint256 sourceBlock;
    MarketRate[] borrowMarkets;
    MarketRate[] mintMarkets;
    MarketRate[] alreadyDeprecatedMintMarkets;
}

struct MarketDeprecationPhase0Batch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

struct MarketDeprecationPhase0Params {
    address timelock;
    address vault;
    address factory;
    MarketRate[] borrowMarkets;
    MarketRate[] mintMarkets;
    MarketRate[] alreadyDeprecatedMintMarkets;
}

struct MarketDeprecationPhase0Report {
    address vaultCurator;
    MarketDeprecationPhase0Batch freezerBatch;
    MarketDeprecationPhase0Batch vaultCapBatch;
    MarketDeprecationPhase0Batch timelockBatch;
}

library MarketDeprecationPhase0 {
    function prepare(MarketDeprecationPhase0Params memory params)
        internal
        view
        returns (MarketDeprecationPhase0Report memory report)
    {
        report.vaultCurator = IAltoVaultBase(params.vault).curator();
        report.freezerBatch = _buildFreezerBatch(params.borrowMarkets, params.mintMarkets);
        report.vaultCapBatch = _buildVaultCapBatch(params.vault, params.borrowMarkets);
        report.timelockBatch = _buildTimelockBatch(params);
    }

    function _buildFreezerBatch(MarketRate[] memory borrowMarkets, MarketRate[] memory mintMarkets)
        private
        pure
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        batch = _newBatch(borrowMarkets.length + mintMarkets.length);

        uint256 callIndex;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            batch.targets[callIndex] = borrowMarkets[i].market;
            batch.payloads[callIndex] = abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true));
            ++callIndex;
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            batch.targets[callIndex] = mintMarkets[i].market;
            batch.payloads[callIndex] = abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true));
            ++callIndex;
        }
    }

    function _buildVaultCapBatch(address vault, MarketRate[] memory borrowMarkets)
        private
        pure
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        batch = _newBatch(borrowMarkets.length);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            batch.targets[i] = vault;
            batch.payloads[i] = abi.encodeCall(IAltoVaultBase.submitCap, (borrowMarkets[i].market, 0));
        }
    }

    function _buildTimelockBatch(MarketDeprecationPhase0Params memory params)
        private
        view
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        batch = _newBatch(
            params.borrowMarkets.length * 2 + params.mintMarkets.length + params.alreadyDeprecatedMintMarkets.length
        );

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(params.factory);
        uint256 callIndex;

        for (uint256 i; i < params.borrowMarkets.length; ++i) {
            MarketRate memory marketRate = params.borrowMarkets[i];
            address irm = factory.predictIrmAddress(marketRate.market, T0_IRM_VERSION, marketRate.rateSpy);

            batch.targets[callIndex] = params.factory;
            batch.payloads[callIndex] = abi.encodeCall(
                OwnerFixedRateIrmFactory.deploy, (marketRate.market, T0_IRM_VERSION, marketRate.rateSpy)
            );
            ++callIndex;

            batch.targets[callIndex] = marketRate.market;
            batch.payloads[callIndex] = abi.encodeCall(IMarketBase.setIrm, (irm, false));
            ++callIndex;
        }

        callIndex = _appendRateCalls(batch, callIndex, params.mintMarkets);
        _appendRateCalls(batch, callIndex, params.alreadyDeprecatedMintMarkets);
    }

    function _appendRateCalls(MarketDeprecationPhase0Batch memory batch, uint256 callIndex, MarketRate[] memory markets)
        private
        view
        returns (uint256)
    {
        for (uint256 i; i < markets.length; ++i) {
            batch.targets[callIndex] = IMarketBase(markets[i].market).irm();
            batch.payloads[callIndex] = abi.encodeCall(FixedRateIrm.setBorrowRate, (markets[i].rateSpy));
            ++callIndex;
        }
        return callIndex;
    }

    function _newBatch(uint256 length) private pure returns (MarketDeprecationPhase0Batch memory batch) {
        batch.targets = new address[](length);
        batch.values = new uint256[](length);
        batch.payloads = new bytes[](length);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {
    AltoEthereumMainnetInput,
    AltoEthereumMainnetParams,
    DeploymentPhase,
    MarketDeprecationCorrectionParams
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {
    MarketDeprecationPhase0,
    MarketDeprecationPhase0Params,
    MarketDeprecationPhase0Report
} from "@alto/deployments/ethereum-mainnet/MarketDeprecationPhase0.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

library MarketDeprecationDeployment {
    uint256 private constant T0_RATE_SPY = 0.1 ether / uint256(365 days);

    function deploy(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        if (params.phase == DeploymentPhase.MARKET_DEPRECATION_PHASE_0) {
            return _deployPhase0(params, input);
        }
        return deployCorrection(_correctionParams(input), params.phase, input);
    }

    function deployCorrection(
        MarketDeprecationCorrectionParams[] memory correctionParams,
        DeploymentPhase phase,
        AltoEthereumMainnetInput memory input
    ) internal returns (AltoEthereumMainnetInput memory) {
        uint256 callCount = correctionParams.length * 3;
        address[] memory targets = new address[](callCount);
        uint256[] memory values = new uint256[](callCount);
        bytes[] memory payloads = new bytes[](callCount);

        uint256 callIndex;
        for (uint256 i; i < correctionParams.length; ++i) {
            MarketDeprecationCorrectionParams memory correction = correctionParams[i];
            address fixedRateIrm = IMarketBase(correction.market).irm();
            address liquidationEngine = IMarketBase(correction.market).liquidationEngine();

            LiquidationConfiguration memory liquidationConfiguration =
                IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
            liquidationConfiguration.maxLiquidationLtv = correction.liquidationLtv;
            liquidationConfiguration.ltvForCompleteLiquidation = correction.completeLiquidationLtv;

            targets[callIndex] = fixedRateIrm;
            payloads[callIndex] = abi.encodeCall(FixedRateIrm.setBorrowRate, (correction.irmBorrowRate));
            ++callIndex;

            targets[callIndex] = correction.market;
            payloads[callIndex] = abi.encodeCall(IMarketBase.setMaxLtv, (correction.maxLtv));
            ++callIndex;

            targets[callIndex] = liquidationEngine;
            payloads[callIndex] = abi.encodeCall(
                IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (liquidationConfiguration)
            );
            ++callIndex;
        }

        address timelock = input.contracts.timelock;
        SafeTransactionBuilder.writeTimelockBatch(
            _correctionBatchName(phase),
            timelock,
            targets,
            values,
            payloads,
            TimelockController(payable(timelock)).getMinDelay()
        );
        return input;
    }

    function _deployPhase0(AltoEthereumMainnetParams memory params, AltoEthereumMainnetInput memory input)
        private
        returns (AltoEthereumMainnetInput memory)
    {
        require(input.contracts.ownerFixedRateIrmFactory == address(0), "Market deprecation phase already prepared");

        address[] memory borrowMarkets = _borrowMarkets(input);
        address[] memory mintMarkets = _mintMarkets(input);
        address[] memory alreadyDeprecatedMintMarkets = _alreadyDeprecatedMintMarkets(input);
        MarketDeprecationPhase0Report memory report = MarketDeprecationPhase0.prepare(
            MarketDeprecationPhase0Params({
                timelock: input.contracts.timelock,
                freezer: params.freezer,
                vault: input.contracts.dusdVault,
                borrowMarketsToDeprecate: borrowMarkets,
                borrowMarketsToDeprecateT0RatesSpy: _rates(borrowMarkets.length),
                mintMarketsToDeprecate: mintMarkets,
                mintMarketsToDeprecateT0RatesSpy: _rates(mintMarkets.length),
                mintMarketsAlreadyDeprecated: alreadyDeprecatedMintMarkets,
                mintMarketsAlreadyDeprecatedT0RatesSpy: _rates(alreadyDeprecatedMintMarkets.length)
            })
        );

        SafeTransactionBuilder.writeDirectBatch(
            "market-deprecation-phase-0-freezer",
            params.freezer,
            report.freezerBatch.targets,
            report.freezerBatch.values,
            report.freezerBatch.payloads
        );
        SafeTransactionBuilder.writeDirectBatch(
            "market-deprecation-phase-0-vault-caps",
            report.vaultCurator,
            report.vaultCuratorBatch.targets,
            report.vaultCuratorBatch.values,
            report.vaultCuratorBatch.payloads
        );

        address timelock = input.contracts.timelock;
        SafeTransactionBuilder.writeTimelockBatch(
            "market-deprecation-phase-0",
            timelock,
            report.timelockBatch.targets,
            report.timelockBatch.values,
            report.timelockBatch.payloads,
            TimelockController(payable(timelock)).getMinDelay()
        );

        input.contracts.ownerFixedRateIrmFactory = report.ownerFixedRateIrmFactory;
        return input;
    }

    function _correctionParams(AltoEthereumMainnetInput memory input)
        private
        pure
        returns (MarketDeprecationCorrectionParams[] memory corrections)
    {
        address[] memory markets = new address[](12);
        markets[0] = input.contracts.wbtcBorrowMarket.market;
        markets[1] = input.contracts.cbbtcBorrowMarket.market;
        markets[2] = input.contracts.susdeBorrowMarket.market;
        markets[3] = input.contracts.syrupUsdcBorrowMarket.market;
        markets[4] = input.contracts.paxgBorrowMarket.market;
        markets[5] = input.contracts.susdeMintMarket.market;
        markets[6] = input.contracts.syrupUsdcMintMarket.market;
        markets[7] = input.contracts.wethMarket.market;
        markets[8] = input.contracts.wstethMarket.market;
        markets[9] = input.contracts.rethMarket.market;
        markets[10] = input.contracts.methMarket.market;
        markets[11] = input.contracts.tbtcMarket.market;

        // TODO(Risk): Fill the approved values for each correction phase.
        corrections = new MarketDeprecationCorrectionParams[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            corrections[i].market = markets[i];
        }
    }

    function _borrowMarkets(AltoEthereumMainnetInput memory input) private pure returns (address[] memory markets) {
        markets = new address[](5);
        markets[0] = input.contracts.wbtcBorrowMarket.market;
        markets[1] = input.contracts.cbbtcBorrowMarket.market;
        markets[2] = input.contracts.susdeBorrowMarket.market;
        markets[3] = input.contracts.syrupUsdcBorrowMarket.market;
        markets[4] = input.contracts.paxgBorrowMarket.market;
    }

    function _mintMarkets(AltoEthereumMainnetInput memory input) private pure returns (address[] memory markets) {
        markets = new address[](5);
        markets[0] = input.contracts.susdeMintMarket.market;
        markets[1] = input.contracts.syrupUsdcMintMarket.market;
        markets[2] = input.contracts.wethMarket.market;
        markets[3] = input.contracts.wstethMarket.market;
        markets[4] = input.contracts.rethMarket.market;
    }

    function _alreadyDeprecatedMintMarkets(AltoEthereumMainnetInput memory input)
        private
        pure
        returns (address[] memory markets)
    {
        markets = new address[](2);
        markets[0] = input.contracts.methMarket.market;
        markets[1] = input.contracts.tbtcMarket.market;
    }

    function _rates(uint256 length) private pure returns (uint256[] memory rates) {
        rates = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            rates[i] = T0_RATE_SPY;
        }
    }

    function _correctionBatchName(DeploymentPhase phase) private pure returns (string memory) {
        if (phase == DeploymentPhase.MARKET_DEPRECATION_PHASE_X) return "market-deprecation-phase-x";
        if (phase == DeploymentPhase.MARKET_DEPRECATION_PHASE_Y) return "market-deprecation-phase-y";
        if (phase == DeploymentPhase.MARKET_DEPRECATION_PHASE_Z) return "market-deprecation-phase-z";
        revert("Invalid correction phase");
    }
}

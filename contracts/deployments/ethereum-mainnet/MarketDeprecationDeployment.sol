// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketBase, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVaultBase, IAltoVaultStaticTypes} from "@alto/lending/interfaces/IAltoVault.sol";
import {
    MarketDeprecationPhase0,
    MarketDeprecationPhase0Batch,
    MarketDeprecationPhase0Config,
    MarketDeprecationPhase0Params,
    MarketDeprecationPhase0Report,
    MarketRate,
    T0_IRM_VERSION
} from "@alto/deployments/ethereum-mainnet/MarketDeprecationPhase0.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {
    AltoEthereumMainnetInput,
    AltoEthereumMainnetParams
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Vm} from "forge-std/Vm.sol";

library MarketDeprecationDeployment {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string private constant CONFIG_PATH =
        "contracts/deployments/ethereum-mainnet/config/market-deprecation-phase-0.json";

    function deployFactory(AltoEthereumMainnetInput memory input) internal returns (AltoEthereumMainnetInput memory) {
        address factory = input.contracts.ownerFixedRateIrmFactory;
        if (factory == address(0)) {
            factory = address(new OwnerFixedRateIrmFactory(input.contracts.timelock));
            input.contracts.ownerFixedRateIrmFactory = factory;
        }
        _validateFactory(factory, input.contracts.timelock);
        return input;
    }

    function generate(AltoEthereumMainnetParams memory deploymentParams, AltoEthereumMainnetInput memory input)
        internal
        returns (AltoEthereumMainnetInput memory)
    {
        MarketDeprecationPhase0Config memory config = _loadConfig();
        MarketDeprecationPhase0Params memory params = _params(input, config);
        _validateConfig(input, config);
        _validateState(params, deploymentParams.timelockAdmin, deploymentParams.freezer, false);

        MarketDeprecationPhase0Report memory report = MarketDeprecationPhase0.prepare(params);
        address timelock = params.timelock;
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();

        bytes memory scheduleData = abi.encodeCall(
            TimelockController.scheduleBatch,
            (
                report.timelockBatch.targets,
                report.timelockBatch.values,
                report.timelockBatch.payloads,
                bytes32(0),
                bytes32(0),
                delay
            )
        );
        MarketDeprecationPhase0Batch memory scheduleBatch = _singleCall(timelock, scheduleData);
        SafeTransactionBuilder.writeDirectBatch(
            "market-deprecation-phase-0-schedule",
            report.vaultCurator,
            scheduleBatch.targets,
            scheduleBatch.values,
            scheduleBatch.payloads
        );

        SafeTransactionBuilder.writeDirectBatch(
            "market-deprecation-phase-0-freezer",
            deploymentParams.freezer,
            report.freezerBatch.targets,
            report.freezerBatch.values,
            report.freezerBatch.payloads
        );

        bytes memory executeData = abi.encodeCall(
            TimelockController.executeBatch,
            (
                report.timelockBatch.targets,
                report.timelockBatch.values,
                report.timelockBatch.payloads,
                bytes32(0),
                bytes32(0)
            )
        );
        MarketDeprecationPhase0Batch memory activationBatch = _append(report.vaultCapBatch, timelock, executeData);
        SafeTransactionBuilder.writeDirectBatch(
            "market-deprecation-phase-0-execute",
            report.vaultCurator,
            activationBatch.targets,
            activationBatch.values,
            activationBatch.payloads
        );
        return input;
    }

    function preflight(AltoEthereumMainnetParams memory deploymentParams, AltoEthereumMainnetInput memory input)
        internal
        view
    {
        MarketDeprecationPhase0Config memory config = _loadConfig();
        MarketDeprecationPhase0Params memory params = _params(input, config);
        _validateConfig(input, config);
        _validateState(params, deploymentParams.timelockAdmin, deploymentParams.freezer, true);

        MarketDeprecationPhase0Batch memory batch = MarketDeprecationPhase0.prepare(params).timelockBatch;
        TimelockController timelock = TimelockController(payable(params.timelock));
        bytes32 operationId =
            timelock.hashOperationBatch(batch.targets, batch.values, batch.payloads, bytes32(0), bytes32(0));
        require(timelock.isOperationReady(operationId), "Timelock not ready");
    }

    function reconcile(AltoEthereumMainnetParams memory deploymentParams, AltoEthereumMainnetInput memory input)
        internal
        view
        returns (AltoEthereumMainnetInput memory)
    {
        MarketDeprecationPhase0Config memory config = _loadConfig();
        MarketDeprecationPhase0Params memory params = _params(input, config);
        _validateConfig(input, config);
        _validateFinalState(params, deploymentParams.timelockAdmin, deploymentParams.freezer);

        input.contracts.wbtcBorrowMarket.marketIrm = IMarketBase(config.borrowMarkets[0].market).irm();
        input.contracts.cbbtcBorrowMarket.marketIrm = IMarketBase(config.borrowMarkets[1].market).irm();
        input.contracts.susdeBorrowMarket.marketIrm = IMarketBase(config.borrowMarkets[2].market).irm();
        input.contracts.syrupUsdcBorrowMarket.marketIrm = IMarketBase(config.borrowMarkets[3].market).irm();
        input.contracts.paxgBorrowMarket.marketIrm = IMarketBase(config.borrowMarkets[4].market).irm();
        return input;
    }

    function _loadConfig() private view returns (MarketDeprecationPhase0Config memory config) {
        string memory json = vm.readFile(CONFIG_PATH);
        config.sourceBlock = vm.parseJsonUint(json, ".sourceBlock");
        config.borrowMarkets = abi.decode(vm.parseJson(json, ".borrowMarkets"), (MarketRate[]));
        config.mintMarkets = abi.decode(vm.parseJson(json, ".mintMarkets"), (MarketRate[]));
        config.alreadyDeprecatedMintMarkets =
            abi.decode(vm.parseJson(json, ".alreadyDeprecatedMintMarkets"), (MarketRate[]));
    }

    function _params(AltoEthereumMainnetInput memory input, MarketDeprecationPhase0Config memory config)
        private
        pure
        returns (MarketDeprecationPhase0Params memory)
    {
        return MarketDeprecationPhase0Params({
            timelock: input.contracts.timelock,
            vault: input.contracts.dusdVault,
            factory: input.contracts.ownerFixedRateIrmFactory,
            borrowMarkets: config.borrowMarkets,
            mintMarkets: config.mintMarkets,
            alreadyDeprecatedMintMarkets: config.alreadyDeprecatedMintMarkets
        });
    }

    function _validateConfig(AltoEthereumMainnetInput memory input, MarketDeprecationPhase0Config memory config)
        private
        pure
    {
        require(config.sourceBlock != 0, "Invalid source block");
        require(config.borrowMarkets.length == 5, "Expected five borrow markets");
        require(config.mintMarkets.length == 5, "Expected five mint markets");
        require(config.alreadyDeprecatedMintMarkets.length == 2, "Expected two deprecated mint markets");

        require(config.borrowMarkets[0].market == input.contracts.wbtcBorrowMarket.market, "Wrong WBTC market");
        require(config.borrowMarkets[1].market == input.contracts.cbbtcBorrowMarket.market, "Wrong cbBTC market");
        require(config.borrowMarkets[2].market == input.contracts.susdeBorrowMarket.market, "Wrong sUSDe BM");
        require(config.borrowMarkets[3].market == input.contracts.syrupUsdcBorrowMarket.market, "Wrong syrupUSDC BM");
        require(config.borrowMarkets[4].market == input.contracts.paxgBorrowMarket.market, "Wrong PAXG market");

        require(config.mintMarkets[0].market == input.contracts.susdeMintMarket.market, "Wrong sUSDe MM");
        require(config.mintMarkets[1].market == input.contracts.syrupUsdcMintMarket.market, "Wrong syrupUSDC MM");
        require(config.mintMarkets[2].market == input.contracts.wethMarket.market, "Wrong WETH market");
        require(config.mintMarkets[3].market == input.contracts.wstethMarket.market, "Wrong wstETH market");
        require(config.mintMarkets[4].market == input.contracts.rethMarket.market, "Wrong rETH market");

        require(config.alreadyDeprecatedMintMarkets[0].market == input.contracts.methMarket.market, "Wrong mETH market");
        require(config.alreadyDeprecatedMintMarkets[1].market == input.contracts.tbtcMarket.market, "Wrong tBTC market");
    }

    function _validateState(
        MarketDeprecationPhase0Params memory params,
        address ownerSafe,
        address freezer,
        bool frozen
    ) private view {
        _validateFactory(params.factory, params.timelock);
        require(IAltoVaultBase(params.vault).curator() == ownerSafe, "Wrong vault curator");

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(params.factory);
        for (uint256 i; i < params.borrowMarkets.length; ++i) {
            MarketRate memory marketRate = params.borrowMarkets[i];
            _validateMarket(
                marketRate.market, params.timelock, freezer, MarketType.BORROW, IRMType.ADAPTIVE_CURVE, frozen
            );
            _validateVaultCap(params.vault, marketRate.market);
            (address deployed,,) = factory.deployments(marketRate.market, T0_IRM_VERSION);
            require(deployed == address(0), "IRM version already deployed");
        }
        for (uint256 i; i < params.mintMarkets.length; ++i) {
            _validateMarket(
                params.mintMarkets[i].market, params.timelock, freezer, MarketType.MINT, IRMType.FIXED_RATE, frozen
            );
        }
        for (uint256 i; i < params.alreadyDeprecatedMintMarkets.length; ++i) {
            _validateMarket(
                params.alreadyDeprecatedMintMarkets[i].market,
                params.timelock,
                freezer,
                MarketType.MINT,
                IRMType.FIXED_RATE,
                true
            );
        }
    }

    function _validateFinalState(MarketDeprecationPhase0Params memory params, address ownerSafe, address freezer)
        private
        view
    {
        _validateFactory(params.factory, params.timelock);
        require(IAltoVaultBase(params.vault).curator() == ownerSafe, "Wrong vault curator");

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(params.factory);
        for (uint256 i; i < params.borrowMarkets.length; ++i) {
            MarketRate memory marketRate = params.borrowMarkets[i];
            _validateMarket(marketRate.market, params.timelock, freezer, MarketType.BORROW, IRMType.FIXED_RATE, true);
            _validateFixedRate(marketRate.market, marketRate.rateSpy);

            (address deployed, address irmOwner, uint256 borrowRate) =
                factory.deployments(marketRate.market, T0_IRM_VERSION);
            require(deployed == IMarketBase(marketRate.market).irm(), "Wrong deployed IRM");
            require(irmOwner == params.timelock && borrowRate == marketRate.rateSpy, "Wrong IRM deployment");

            (uint184 cap, bool enabled, uint64 removableAt) =
                IAltoVaultStaticTypes(params.vault).config(marketRate.market);
            require(cap == 0 && enabled && removableAt == 0, "Wrong final vault cap");
        }
        for (uint256 i; i < params.mintMarkets.length; ++i) {
            MarketRate memory marketRate = params.mintMarkets[i];
            _validateMarket(marketRate.market, params.timelock, freezer, MarketType.MINT, IRMType.FIXED_RATE, true);
            _validateFixedRate(marketRate.market, marketRate.rateSpy);
        }
        for (uint256 i; i < params.alreadyDeprecatedMintMarkets.length; ++i) {
            MarketRate memory marketRate = params.alreadyDeprecatedMintMarkets[i];
            _validateMarket(marketRate.market, params.timelock, freezer, MarketType.MINT, IRMType.FIXED_RATE, true);
            _validateFixedRate(marketRate.market, marketRate.rateSpy);
        }
    }

    function _validateFactory(address factory, address timelock) private view {
        require(factory.codehash == keccak256(type(OwnerFixedRateIrmFactory).runtimeCode), "Wrong factory code");
        require(OwnerFixedRateIrmFactory(factory).owner() == timelock, "Wrong factory owner");
        require(OwnerFixedRateIrmFactory(factory).pendingOwner() == address(0), "Unexpected pending factory owner");
    }

    function _validateMarket(
        address market,
        address timelock,
        address freezer,
        MarketType marketType,
        IRMType irmType,
        bool frozen
    ) private view {
        IMarketBase marketContract = IMarketBase(market);
        address irm = marketContract.irm();

        require(market.code.length != 0 && Ownable(market).owner() == timelock, "Wrong market owner");
        require(marketContract.MARKET_TYPE() == marketType, "Wrong market type");
        require(IPausable(market).paused(FROZEN_TYPE) == frozen, "Wrong frozen state");
        require(!IPausable(market).paused(PAUSE_TYPE), "Market fully paused");
        require(Pausable(market).pausers(freezer, FROZEN_TYPE), "Wrong freezer");

        require(irm.code.length != 0 && Ownable(irm).owner() == timelock, "Wrong IRM owner");
        require(IIrm(irm).IRM_TYPE() == irmType, "Wrong IRM type");
        require(FixedRateIrm(irm).market() == market, "Wrong IRM binding");
    }

    function _validateFixedRate(address market, uint256 expectedRate) private view {
        (uint256 rate,) = FixedRateIrm(IMarketBase(market).irm()).irState();
        require(rate == expectedRate, "Wrong fixed rate");
    }

    function _validateVaultCap(address vault, address market) private view {
        (uint184 cap, bool enabled, uint64 removableAt) = IAltoVaultStaticTypes(vault).config(market);
        (, uint64 pendingValidAt) = IAltoVaultStaticTypes(vault).pendingCap(market);
        require(cap != 0 && enabled && removableAt == 0, "Invalid vault cap state");
        require(pendingValidAt == 0, "Pending vault cap");
    }

    function _singleCall(address target, bytes memory payload)
        private
        pure
        returns (MarketDeprecationPhase0Batch memory batch)
    {
        batch.targets = new address[](1);
        batch.values = new uint256[](1);
        batch.payloads = new bytes[](1);
        batch.targets[0] = target;
        batch.payloads[0] = payload;
    }

    function _append(MarketDeprecationPhase0Batch memory batch, address target, bytes memory payload)
        private
        pure
        returns (MarketDeprecationPhase0Batch memory result)
    {
        uint256 length = batch.targets.length;
        result.targets = new address[](length + 1);
        result.values = new uint256[](length + 1);
        result.payloads = new bytes[](length + 1);

        for (uint256 i; i < length; ++i) {
            result.targets[i] = batch.targets[i];
            result.values[i] = batch.values[i];
            result.payloads[i] = batch.payloads[i];
        }
        result.targets[length] = target;
        result.payloads[length] = payload;
    }
}

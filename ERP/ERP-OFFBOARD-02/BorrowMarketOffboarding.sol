// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    BatchAContainParams,
    BatchBReduceLtvParams,
    BatchBSetFixedRateIrmParams,
    BatchCRecoverParams,
    BorrowMarketOffboardingContracts,
    BorrowMarketOffboardingBatch,
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingParams,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingReport,
    BorrowMarketRateParams,
    DeployOwnerFixedRateIrmFactoryParams
} from "./IBorrowMarketOffboarding.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

interface IPauserState is IPausable {
    function pausers(address account, bytes32 pauseType) external view returns (bool);
}

/// @notice Executes the deployment phase or builds, validates and writes one operational phase of ERP-OFFBOARD-02.
library BorrowMarketOffboarding {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant LTV_REDUCTION = 0.05 ether;
    uint256 internal constant TRANSACTIONS_PER_RECOVERY_MARKET = 7;
    string internal constant ERP_OUTPUT_DIR = "ERP/ERP-OFFBOARD-02/output";

    function runPhase(BorrowMarketOffboardingParams memory params, BorrowMarketOffboardingInput memory input)
        internal
        returns (BorrowMarketOffboardingInput memory)
    {
        BorrowMarketOffboardingContracts memory contracts = input.contracts;

        if (params.phase == BorrowMarketOffboardingPhase.DEPLOY_OWNER_FIXED_RATE_IRM_FACTORY) {
            input.contracts.ownerFixedRateIrmFactory = _deployOwnerFixedRateIrmFactory(
                DeployOwnerFixedRateIrmFactoryParams({
                    timelock: contracts.timelock,
                    recordedFactory: contracts.ownerFixedRateIrmFactory
                })
            );
            return input;
        }

        _validateBorrowMarketsRegistered(contracts.marketRegistry, _borrowMarkets(contracts));
        BorrowMarketOffboardingReport memory report;

        if (params.phase == BorrowMarketOffboardingPhase.BATCH_A_CONTAIN) {
            report = _prepareContainment(
                BatchAContainParams({
                    freezerSafe: params.freezerSafe,
                    borrowMarkets: _borrowMarkets(contracts),
                    affectedVaults: _affectedVaults(contracts)
                })
            );
            _writeReport(params.phase, contracts.timelock, report);
            return input;
        }
        if (params.phase == BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM) {
            report = _prepareFixedRateIrmAttachment(
                BatchBSetFixedRateIrmParams({
                    timelockSafe: params.timelockSafe,
                    timelock: contracts.timelock,
                    ownerFixedRateIrmFactory: contracts.ownerFixedRateIrmFactory,
                    markets: _fixedRateIrmMarkets(contracts)
                })
            );
            _writeReport(params.phase, contracts.timelock, report);
            return input;
        }
        if (params.phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            report = _prepareRateAndLtvReduction(
                BatchBReduceLtvParams({
                    timelockSafe: params.timelockSafe,
                    timelock: contracts.timelock,
                    markets: _rateAndLtvReductionMarkets(contracts)
                })
            );
            _writeReport(params.phase, contracts.timelock, report);
            return input;
        }
        if (params.phase == BorrowMarketOffboardingPhase.BATCH_C_RECOVER) {
            report = _prepareRecovery(
                BatchCRecoverParams({
                    timelockSafe: params.timelockSafe,
                    timelock: contracts.timelock,
                    marketRegistry: contracts.marketRegistry,
                    altoAdapter: contracts.altoAdapter,
                    liquidationPeriphery: contracts.liquidationPeriphery,
                    borrowMarkets: _borrowMarkets(contracts),
                    leverages: _leverages(contracts),
                    affectedVaults: _affectedVaults(contracts)
                })
            );
            _writeReport(params.phase, contracts.timelock, report);
            return input;
        }

        revert("ERP: invalid phase");
    }

    function _deployOwnerFixedRateIrmFactory(DeployOwnerFixedRateIrmFactoryParams memory params)
        private
        returns (address)
    {
        require(params.timelock != address(0), "Factory deploy: invalid Timelock");
        require(params.recordedFactory == address(0), "Factory deploy: factory already recorded");

        OwnerFixedRateIrmFactory factory = new OwnerFixedRateIrmFactory(params.timelock);

        console2.log("OwnerFixedRateIrmFactory:", address(factory));
        console2.log("Owner:", params.timelock);
        console2.log("Manual update required in addresses.json: .contracts.ownerFixedRateIrmFactory");

        return address(factory);
    }

    function reduceByFivePercentagePoints(uint256 value) internal pure returns (uint256) {
        return value > LTV_REDUCTION ? value - LTV_REDUCTION : 0;
    }

    function _prepareContainment(BatchAContainParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        require(params.freezerSafe != address(0), "Batch A: zero freezer Safe");
        require(params.affectedVaults.length != 0, "Batch A: no affected Vaults");

        uint256 marketCount = params.borrowMarkets.length;
        report.freezerBatch = _newBatch(params.freezerSafe, marketCount);

        for (uint256 i; i < marketCount; ++i) {
            address market = params.borrowMarkets[i];
            require(!IPauserState(market).paused(FROZEN_TYPE), "Batch A: market already frozen");
            require(!IPauserState(market).paused(PAUSE_TYPE), "Batch A: market paused");
            require(IPauserState(market).pausers(params.freezerSafe, FROZEN_TYPE), "Batch A: Safe is not freezer");

            report.freezerBatch.targets[i] = market;
            report.freezerBatch.payloads[i] = abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true));
        }

        address curator = IAltoVaultBase(params.affectedVaults[0]).curator();
        require(curator != address(0), "Batch A: zero Vault curator");

        uint256 curatorCallCount = marketCount * params.affectedVaults.length;
        for (uint256 vaultIndex; vaultIndex < params.affectedVaults.length; ++vaultIndex) {
            address vault = params.affectedVaults[vaultIndex];
            require(vault != address(0) && vault.code.length != 0, "Batch A: invalid Vault");
            require(IAltoVaultBase(vault).curator() == curator, "Batch A: different Vault curators");

            for (uint256 marketIndex; marketIndex < marketCount; ++marketIndex) {
                if (IAltoVault(vault).pendingCap(params.borrowMarkets[marketIndex]).validAt != 0) {
                    ++curatorCallCount;
                }
            }
        }

        report.vaultCuratorBatch = _newBatch(curator, curatorCallCount);
        uint256 callIndex;
        for (uint256 vaultIndex; vaultIndex < params.affectedVaults.length; ++vaultIndex) {
            address vault = params.affectedVaults[vaultIndex];
            for (uint256 marketIndex; marketIndex < marketCount; ++marketIndex) {
                address market = params.borrowMarkets[marketIndex];
                if (IAltoVault(vault).pendingCap(market).validAt != 0) {
                    report.vaultCuratorBatch.targets[callIndex] = vault;
                    report.vaultCuratorBatch.payloads[callIndex] =
                        abi.encodeCall(IAltoVaultBase.revokePendingCap, (market));
                    ++callIndex;
                }

                report.vaultCuratorBatch.targets[callIndex] = vault;
                report.vaultCuratorBatch.payloads[callIndex] = abi.encodeCall(IAltoVaultBase.submitCap, (market, 0));
                ++callIndex;
            }
        }
        assert(callIndex == curatorCallCount);
    }

    function _prepareFixedRateIrmAttachment(BatchBSetFixedRateIrmParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        address factoryAddress = params.ownerFixedRateIrmFactory;
        require(factoryAddress != address(0) && factoryAddress.code.length != 0, "Batch B: invalid IRM factory");

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(factoryAddress);
        require(factory.owner() == params.timelock, "Batch B: Timelock does not own factory");
        require(factory.pendingOwner() == address(0), "Batch B: factory ownership transfer pending");

        uint256 marketCount = params.markets.length;
        uint256 initialNonce = factory.nonce();
        report.timelockBatch = _newBatch(params.timelockSafe, marketCount * 2);
        report.timelockDelay = TimelockController(payable(params.timelock)).getMinDelay();

        for (uint256 i; i < marketCount; ++i) {
            address market = params.markets[i].market;
            uint256 borrowRateSpy = params.markets[i].borrowRateSpy;
            _validateFrozenMarket(market);
            require(borrowRateSpy <= 8 ether / uint256(365 days), "Batch B: rate above IRM maximum");

            address predictedIrm = factory.predictIrmAddress(borrowRateSpy, params.timelock, initialNonce + i);
            require(predictedIrm.code.length == 0, "Batch B: predicted IRM already deployed");

            report.timelockBatch.targets[i] = factoryAddress;
            report.timelockBatch.payloads[i] =
                abi.encodeCall(OwnerFixedRateIrmFactory.deploy, (market, borrowRateSpy, params.timelock));

            report.timelockBatch.targets[marketCount + i] = market;
            report.timelockBatch.payloads[marketCount + i] = abi.encodeCall(IMarketBase.setIrm, (predictedIrm, false));
        }
    }

    function _prepareRateAndLtvReduction(BatchBReduceLtvParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        uint256 marketCount = params.markets.length;
        report.timelockBatch = _newBatch(params.timelockSafe, marketCount * 3);
        report.timelockDelay = TimelockController(payable(params.timelock)).getMinDelay();

        for (uint256 i; i < marketCount; ++i) {
            IMarketBase market = IMarketBase(params.markets[i].market);
            uint256 borrowRateSpy = params.markets[i].borrowRateSpy;
            _validateFrozenMarket(address(market));

            address fixedRateIrm = market.irm();
            address liquidationEngine = market.liquidationEngine();
            require(fixedRateIrm.code.length != 0, "Batch B: invalid IRM");
            require(liquidationEngine.code.length != 0, "Batch B: invalid liquidation engine");
            require(IIrm(fixedRateIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Batch B: IRM is not fixed-rate");
            require(FixedRateIrm(fixedRateIrm).market() == address(market), "Batch B: IRM not dedicated");
            require(FixedRateIrm(fixedRateIrm).owner() == params.timelock, "Batch B: Timelock does not own IRM");
            require(
                IDcfDlbPriorityLiquidationEngine(liquidationEngine).market() == address(market),
                "Batch B: wrong liquidation engine"
            );
            require(
                Ownable(liquidationEngine).owner() == params.timelock,
                "Batch B: Timelock does not own liquidation engine"
            );
            require(borrowRateSpy <= FixedRateIrm(fixedRateIrm).MAX_BORROW_RATE(), "Batch B: rate above IRM maximum");

            (uint256 currentBorrowRate,) = FixedRateIrm(fixedRateIrm).irState();
            require(borrowRateSpy >= currentBorrowRate, "Batch B: rate below current rate");

            LiquidationConfiguration memory liquidationConfiguration =
                IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
            uint256 reducedMarketMaxLtv = reduceByFivePercentagePoints(market.maxLtv());
            liquidationConfiguration.maxLiquidationLtv =
                reduceByFivePercentagePoints(liquidationConfiguration.maxLiquidationLtv);
            liquidationConfiguration.ltvForCompleteLiquidation =
                reduceByFivePercentagePoints(liquidationConfiguration.ltvForCompleteLiquidation);
            require(
                reducedMarketMaxLtv <= liquidationConfiguration.maxLiquidationLtv
                    && liquidationConfiguration.maxLiquidationLtv <= liquidationConfiguration.ltvForCompleteLiquidation,
                "Batch B: invalid LTV order"
            );

            uint256 callIndex = i * 3;
            report.timelockBatch.targets[callIndex] = fixedRateIrm;
            report.timelockBatch.payloads[callIndex] = abi.encodeCall(FixedRateIrm.setBorrowRate, (borrowRateSpy));
            report.timelockBatch.targets[callIndex + 1] = address(market);
            report.timelockBatch.payloads[callIndex + 1] = abi.encodeCall(IMarketBase.setMaxLtv, (reducedMarketMaxLtv));
            report.timelockBatch.targets[callIndex + 2] = liquidationEngine;
            report.timelockBatch.payloads[callIndex + 2] = abi.encodeCall(
                IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (liquidationConfiguration)
            );
        }
    }

    function _prepareRecovery(BatchCRecoverParams memory params)
        private
        view
        returns (BorrowMarketOffboardingReport memory report)
    {
        _validateRecoveryConfiguration(params);
        _validateZeroDebt(params.borrowMarkets);
        _validateVaultRemovalComplete(params.borrowMarkets, params.affectedVaults);
        _validateFinalRemovalState(params);
        uint256 marketCount = params.borrowMarkets.length;
        report.timelockBatch = _newBatch(params.timelockSafe, marketCount * TRANSACTIONS_PER_RECOVERY_MARKET);
        report.timelockDelay = TimelockController(payable(params.timelock)).getMinDelay();
        uint256 callIndex;

        for (uint256 i; i < marketCount; ++i) {
            report.timelockBatch.targets[callIndex] = params.marketRegistry;
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(IMarketRegistry.removeBorrowMarket, (params.borrowMarkets[i]));
            ++callIndex;
        }
        for (uint256 i; i < marketCount; ++i) {
            report.timelockBatch.targets[callIndex] = params.altoAdapter;
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(AdapterContractApproval.revokeContract, (params.borrowMarkets[i]));
            ++callIndex;
        }
        for (uint256 i; i < marketCount; ++i) {
            AltoLeverage leverage = AltoLeverage(params.leverages[i]);
            IAltoLeverageSwapper leverageSwapper = leverage.swapper();

            report.timelockBatch.targets[callIndex] = address(leverage);
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(AltoLeverage.setMarket, (params.borrowMarkets[i], false));
            ++callIndex;

            report.timelockBatch.targets[callIndex] = params.borrowMarkets[i];
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(IMarketBase.setAuthorizedCallback, (address(leverage), false));
            ++callIndex;

            report.timelockBatch.targets[callIndex] = address(leverageSwapper);
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(IAltoLeverageSwapper.setWhitelisted, (address(leverage), false));
            ++callIndex;
        }
        for (uint256 i; i < marketCount; ++i) {
            report.timelockBatch.targets[callIndex] = params.liquidationPeriphery;
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(ILiquidationPeripheryBase.setSupportedMarket, (params.borrowMarkets[i], false));
            ++callIndex;

            report.timelockBatch.targets[callIndex] = params.borrowMarkets[i];
            report.timelockBatch.payloads[callIndex] =
                abi.encodeCall(IMarketBase.setAuthorizedLiquidationPeriphery, (params.liquidationPeriphery, false));
            ++callIndex;
        }
        assert(callIndex == report.timelockBatch.targets.length);
    }

    function _writeReport(
        BorrowMarketOffboardingPhase phase,
        address timelock,
        BorrowMarketOffboardingReport memory report
    ) private {
        vm.createDir(ERP_OUTPUT_DIR, true);

        if (phase == BorrowMarketOffboardingPhase.BATCH_A_CONTAIN) {
            _writeSafeBatch(
                "batch-a-freeze-safe.json", "ERP-OFFBOARD-02 - Batch A Freeze Borrow Markets", report.freezerBatch
            );
            _writeSafeBatch(
                "batch-a-vault-curator-safe.json",
                "ERP-OFFBOARD-02 - Batch A Zero Borrow Market Caps",
                report.vaultCuratorBatch
            );
            return;
        }

        if (phase == BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM) {
            _writeTimelockPair(
                "batch-b-fixed-rate-irm",
                "ERP-OFFBOARD-02 - Batch B Deploy and Attach Fixed-Rate IRMs",
                timelock,
                report
            );
            return;
        }

        if (phase == BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV) {
            _writeTimelockPair(
                "batch-b-irm-and-ltv-update",
                "ERP-OFFBOARD-02 - Batch B Update IRM Rates and Reduce LTVs by Five Percentage Points",
                timelock,
                report
            );
            return;
        }

        _writeTimelockPair(
            "batch-c-final-removal",
            "ERP-OFFBOARD-02 - Batch C Final Registry and Integration Removal",
            timelock,
            report
        );
    }

    function _writeTimelockPair(
        string memory fileStem,
        string memory name,
        address timelock,
        BorrowMarketOffboardingReport memory report
    ) private {
        BorrowMarketOffboardingBatch memory calls = report.timelockBatch;
        _validateBatch(calls);

        bytes32 predecessor;
        bytes32 salt;
        bytes memory scheduleData = abi.encodeCall(
            TimelockController.scheduleBatch,
            (calls.targets, calls.values, calls.payloads, predecessor, salt, report.timelockDelay)
        );
        bytes memory executeData = abi.encodeCall(
            TimelockController.executeBatch, (calls.targets, calls.values, calls.payloads, predecessor, salt)
        );

        _writeSingleTransactionSafeBatch(
            string.concat(fileStem, "-schedule.json"),
            string.concat(name, " - Schedule"),
            calls.safe,
            timelock,
            scheduleData
        );
        _writeSingleTransactionSafeBatch(
            string.concat(fileStem, "-execute.json"),
            string.concat(name, " - Execute"),
            calls.safe,
            timelock,
            executeData
        );
    }

    function _writeSingleTransactionSafeBatch(
        string memory fileName,
        string memory name,
        address safe,
        address target,
        bytes memory payload
    ) private {
        BorrowMarketOffboardingBatch memory batch;
        batch.safe = safe;
        batch.targets = new address[](1);
        batch.values = new uint256[](1);
        batch.payloads = new bytes[](1);
        batch.targets[0] = target;
        batch.payloads[0] = payload;
        _writeSafeBatch(fileName, name, batch);
    }

    function _writeSafeBatch(string memory fileName, string memory name, BorrowMarketOffboardingBatch memory batch)
        private
    {
        _validateBatch(batch);
        require(batch.safe != address(0), "ERP: zero Safe");

        string memory transactions;
        for (uint256 i; i < batch.targets.length; ++i) {
            transactions = string.concat(
                transactions,
                i == 0 ? "" : ",",
                '{"to":"',
                vm.toString(batch.targets[i]),
                '","value":"',
                vm.toString(batch.values[i]),
                '","data":"',
                vm.toString(batch.payloads[i]),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        vm.writeFile(
            string.concat(ERP_OUTPUT_DIR, "/", fileName),
            string.concat(
                '{"version":"1.0","chainId":"',
                vm.toString(block.chainid),
                '","meta":{"name":"',
                name,
                '","txBuilderVersion":"1.16.5","createdFromSafeAddress":"',
                vm.toString(batch.safe),
                '"},"transactions":[',
                transactions,
                "]}"
            )
        );

        console2.log("Safe Transaction Builder JSON written:", fileName);
        console2.log("Submit from Safe:", batch.safe);
    }

    function _validateBatch(BorrowMarketOffboardingBatch memory batch) private pure {
        uint256 callCount = batch.targets.length;
        require(callCount != 0, "ERP: empty batch");
        require(batch.values.length == callCount, "ERP: target/value length mismatch");
        require(batch.payloads.length == callCount, "ERP: target/payload length mismatch");
    }

    /// @dev Current activation placeholders. Replace the named contracts for a different approved market manifest.
    function _borrowMarkets(BorrowMarketOffboardingContracts memory contracts)
        private
        pure
        returns (address[] memory markets)
    {
        markets = new address[](5);
        markets[0] = contracts.wbtcBorrowMarket;
        markets[1] = contracts.cbbtcBorrowMarket;
        markets[2] = contracts.susdeBorrowMarket;
        markets[3] = contracts.syrupUsdcBorrowMarket;
        markets[4] = contracts.paxgBorrowMarket;
    }

    function _affectedVaults(BorrowMarketOffboardingContracts memory contracts)
        private
        pure
        returns (address[] memory vaults)
    {
        vaults = new address[](1);
        vaults[0] = contracts.dusdVault;
    }

    function _leverages(BorrowMarketOffboardingContracts memory contracts)
        private
        pure
        returns (address[] memory leverages)
    {
        leverages = new address[](5);
        leverages[0] = contracts.wbtcBorrowLeverage;
        leverages[1] = contracts.cbbtcBorrowLeverage;
        leverages[2] = contracts.susdeBorrowLeverage;
        leverages[3] = contracts.syrupUsdcBorrowLeverage;
        leverages[4] = contracts.paxgBorrowLeverage;
    }

    /// @dev Explicit, aligned T0 rate placeholders. Replace each rate with its approved value before activation.
    function _fixedRateIrmMarkets(BorrowMarketOffboardingContracts memory contracts)
        private
        pure
        returns (BorrowMarketRateParams[] memory markets)
    {
        markets = new BorrowMarketRateParams[](5);
        markets[0] =
            BorrowMarketRateParams({market: contracts.wbtcBorrowMarket, borrowRateSpy: 0.1 ether / uint256(365 days)});
        markets[1] =
            BorrowMarketRateParams({market: contracts.cbbtcBorrowMarket, borrowRateSpy: 0.1 ether / uint256(365 days)});
        markets[2] =
            BorrowMarketRateParams({market: contracts.susdeBorrowMarket, borrowRateSpy: 0.1 ether / uint256(365 days)});
        markets[3] = BorrowMarketRateParams({
            market: contracts.syrupUsdcBorrowMarket,
            borrowRateSpy: 0.1 ether / uint256(365 days)
        });
        markets[4] =
            BorrowMarketRateParams({market: contracts.paxgBorrowMarket, borrowRateSpy: 0.1 ether / uint256(365 days)});
    }

    /// @dev Explicit, aligned correction-rate placeholders. Replace each rate for every approved schedule step.
    function _rateAndLtvReductionMarkets(BorrowMarketOffboardingContracts memory contracts)
        private
        pure
        returns (BorrowMarketRateParams[] memory markets)
    {
        markets = new BorrowMarketRateParams[](5);
        markets[0] =
            BorrowMarketRateParams({market: contracts.wbtcBorrowMarket, borrowRateSpy: 0.2 ether / uint256(365 days)});
        markets[1] =
            BorrowMarketRateParams({market: contracts.cbbtcBorrowMarket, borrowRateSpy: 0.2 ether / uint256(365 days)});
        markets[2] =
            BorrowMarketRateParams({market: contracts.susdeBorrowMarket, borrowRateSpy: 0.2 ether / uint256(365 days)});
        markets[3] = BorrowMarketRateParams({
            market: contracts.syrupUsdcBorrowMarket,
            borrowRateSpy: 0.2 ether / uint256(365 days)
        });
        markets[4] =
            BorrowMarketRateParams({market: contracts.paxgBorrowMarket, borrowRateSpy: 0.2 ether / uint256(365 days)});
    }

    function _validateBorrowMarketsRegistered(address marketRegistry, address[] memory borrowMarkets) private view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            require(IMarketRegistry(marketRegistry).isBorrowMarket(borrowMarkets[i]), "ERP: market not registered");
        }
    }

    function _validateFrozenMarket(address market) private view {
        require(IMarketBase(market).paused(FROZEN_TYPE), "Batch B: market not frozen");
        require(!IMarketBase(market).paused(PAUSE_TYPE), "Batch B: market paused");
    }

    function _validateRecoveryConfiguration(BatchCRecoverParams memory params) private pure {
        uint256 marketCount = params.borrowMarkets.length;
        require(marketCount == params.leverages.length, "Batch C: market/leverage length mismatch");
        require(params.affectedVaults.length != 0, "Batch C: no affected Vaults");
        require(params.marketRegistry != address(0), "Batch C: zero registry");
        require(params.altoAdapter != address(0), "Batch C: zero adapter");
        require(params.liquidationPeriphery != address(0), "Batch C: zero liquidation periphery");

        for (uint256 i; i < marketCount; ++i) {
            require(params.leverages[i] != address(0), "Batch C: zero leverage");
        }
        for (uint256 i; i < params.affectedVaults.length; ++i) {
            require(params.affectedVaults[i] != address(0), "Batch C: zero Vault");
            for (uint256 j; j < i; ++j) {
                require(params.affectedVaults[i] != params.affectedVaults[j], "Batch C: duplicate Vault");
            }
        }
    }

    function _validateZeroDebt(address[] memory borrowMarkets) private view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            Balance memory borrowed = IMarket(borrowMarkets[i]).totalBorrowed();
            require(borrowed.assets == 0 && borrowed.shares == 0, "Batch C: market debt remains");
        }
    }

    function _validateVaultRemovalComplete(address[] memory borrowMarkets, address[] memory affectedVaults)
        private
        view
    {
        for (uint256 vaultIndex; vaultIndex < affectedVaults.length; ++vaultIndex) {
            IAltoVault vault = IAltoVault(affectedVaults[vaultIndex]);

            for (uint256 marketIndex; marketIndex < borrowMarkets.length; ++marketIndex) {
                address market = borrowMarkets[marketIndex];
                MarketConfig memory vaultConfig = vault.config(market);
                PendingUint192 memory pendingCap = vault.pendingCap(market);

                require(
                    IMarket(market).position(address(vault)).supplyShares == 0, "Batch C: Vault market supply remains"
                );
                require(vault.quarantinedAssets(market) == 0, "Batch C: Vault market assets quarantined");
                require(vaultConfig.cap == 0, "Batch C: Vault cap remains");
                require(!vaultConfig.enabled, "Batch C: Vault market still enabled");
                require(vaultConfig.removableAt == 0, "Batch C: pending Vault removal remains");
                require(pendingCap.validAt == 0, "Batch C: pending Vault cap remains");
                require(!_isInSupplyQueue(vault, market), "Batch C: market remains in supply queue");
                require(!_isInWithdrawQueue(vault, market), "Batch C: market remains in withdraw queue");
            }
        }
    }

    function _validateFinalRemovalState(BatchCRecoverParams memory params) private view {
        require(Ownable(params.marketRegistry).owner() == params.timelock, "Batch C: Timelock does not own registry");
        require(Ownable(params.altoAdapter).owner() == params.timelock, "Batch C: Timelock does not own adapter");

        for (uint256 i; i < params.borrowMarkets.length; ++i) {
            IMarket market = IMarket(params.borrowMarkets[i]);
            AltoLeverage leverage = AltoLeverage(params.leverages[i]);
            IAltoLeverageSwapper leverageSwapper = leverage.swapper();

            require(market.paused(FROZEN_TYPE), "Batch C: market not frozen");
            require(!market.paused(PAUSE_TYPE), "Batch C: market paused");
            require(market.oracle() != address(0), "Batch C: market oracle unavailable");
            require(Ownable(address(market)).owner() == params.timelock, "Batch C: Timelock does not own market");
            require(Ownable(address(leverage)).owner() == params.timelock, "Batch C: Timelock does not own leverage");
            require(address(leverageSwapper) != address(0), "Batch C: zero leverage swapper");
            require(
                Ownable(address(leverageSwapper)).owner() == params.timelock,
                "Batch C: Timelock does not own leverage swapper"
            );
            require(IMarketRegistry(params.marketRegistry).isBorrowMarket(address(market)), "Batch C: not registered");
            require(
                AdapterContractApproval(params.altoAdapter).isApprovedContract(address(market)),
                "Batch C: not adapter-approved"
            );
            require(leverage.supportedMarkets(address(market)), "Batch C: leverage support already disabled");
            require(market.authorizedCallbacks(address(leverage)), "Batch C: leverage callback already revoked");
            require(leverageSwapper.isWhitelisted(address(leverage)), "Batch C: leverage whitelist already revoked");
            require(
                ILiquidationPeripheryBase(params.liquidationPeriphery).supportedMarkets(address(market)),
                "Batch C: liquidation periphery support already disabled"
            );
            require(
                market.authorizedLiquidationPeriphery(params.liquidationPeriphery),
                "Batch C: liquidation periphery already revoked"
            );

            _requireNoLeverageResidue(market, address(leverage), address(leverageSwapper));
        }
    }

    function _requireNoLeverageResidue(IMarket market, address leverage, address leverageSwapper) private view {
        IERC20 borrowToken = IERC20(market.borrowToken());
        IERC20 collateralToken = IERC20(market.collateralToken());

        require(borrowToken.balanceOf(leverage) == 0, "Batch C: leverage borrow-token residue");
        require(collateralToken.balanceOf(leverage) == 0, "Batch C: leverage collateral residue");
        require(borrowToken.balanceOf(leverageSwapper) == 0, "Batch C: swapper borrow-token residue");
        require(collateralToken.balanceOf(leverageSwapper) == 0, "Batch C: swapper collateral residue");
        require(borrowToken.allowance(leverage, address(market)) == 0, "Batch C: leverage market borrow approval");
        require(
            collateralToken.allowance(leverage, address(market)) == 0, "Batch C: leverage market collateral approval"
        );
        require(borrowToken.allowance(leverage, leverageSwapper) == 0, "Batch C: leverage swapper borrow approval");
        require(
            collateralToken.allowance(leverage, leverageSwapper) == 0, "Batch C: leverage swapper collateral approval"
        );
    }

    function _isInSupplyQueue(IAltoVaultBase vault, address market) private view returns (bool) {
        for (uint256 i; i < vault.supplyQueueLength(); ++i) {
            if (vault.supplyQueue(i) == market) return true;
        }
        return false;
    }

    function _isInWithdrawQueue(IAltoVaultBase vault, address market) private view returns (bool) {
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            if (vault.withdrawQueue(i) == market) return true;
        }
        return false;
    }

    function _newBatch(address safe, uint256 callCount)
        private
        pure
        returns (BorrowMarketOffboardingBatch memory batch)
    {
        batch.safe = safe;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);
    }
}

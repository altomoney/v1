// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    AltoEthereumMainnetInput,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {
    CURVE_STABLESWAP_NG_FACTORY_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_IMPLEMENTATION_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    FRXUSD_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {
    OwnerPegResponsiveExponentialIrmFactory
} from "@alto/deployments/ethereum-mainnet/OwnerPegResponsiveExponentialIrmFactory.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketBase, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {
    IPegResponsiveExponentialIrm,
    PegResponsiveExponentialIrmConfig
} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {DusdPegCurveOracle} from "@alto/oracles/DusdPegCurveOracle/DusdPegCurveOracle.sol";
import {IDusdPegOracle} from "@alto/oracles/interfaces/IDusdPegOracle.sol";
import {
    DusdPegCurveOracleRuntimeConfig,
    DusdPegCurveOracleValidationConfig
} from "@alto/oracles/interfaces/IDusdPegCurveOracle.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

struct PegResponsiveIrmBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

library PegResponsiveIrmDeployment {
    uint256 private constant ACTIVE_MINT_MARKET_COUNT = 6;
    uint256 private constant IRM_VERSION = 1;
    uint256 private constant YEAR = 365 days;
    uint48 private constant MAX_ORACLE_AGE = 12 hours;
    string private constant SAFE_BATCH_NAME = "mint-market-peg-responsive-irm";

    function generate(AltoEthereumMainnetInput memory input) internal returns (AltoEthereumMainnetInput memory) {
        address timelock = input.contracts.timelock;
        require(timelock != address(0), "Invalid timelock");

        DusdPegCurveOracleRuntimeConfig memory oracleConfig = _oracleRuntimeConfig();
        PegResponsiveExponentialIrmConfig[] memory irmConfigs = _irmConfigs();

        if (input.contracts.dusdPegCurveOracle == address(0)) {
            input.contracts.dusdPegCurveOracle = address(
                new DusdPegCurveOracle(
                    FRXUSD_DUSD_CURVE_POOL_MAINNET,
                    oracleConfig,
                    DusdPegCurveOracleValidationConfig({
                        curveFactory: CURVE_STABLESWAP_NG_FACTORY_MAINNET,
                        expectedCurvePoolImplementation: FRXUSD_DUSD_CURVE_POOL_IMPLEMENTATION_MAINNET,
                        dusd: input.contracts.dusd,
                        quoteToken: FRXUSD_MAINNET
                    }),
                    timelock
                )
            );
        }

        if (input.contracts.ownerPegResponsiveExponentialIrmFactory == address(0)) {
            input.contracts.ownerPegResponsiveExponentialIrmFactory =
                address(new OwnerPegResponsiveExponentialIrmFactory(timelock, input.contracts.dusdPegCurveOracle));
        }

        MarketContracts[] memory markets = _activeMintMarkets(input);
        _validateFactoryAndOracle(input, oracleConfig);
        _validateOracleObservation(input.contracts.dusdPegCurveOracle, MAX_ORACLE_AGE);
        _validateInitialMarkets(input, markets, irmConfigs);

        PegResponsiveIrmBatch memory batch = _buildBatch(input, markets, irmConfigs);
        SafeTransactionBuilder.writeTimelockBatch(
            SAFE_BATCH_NAME,
            timelock,
            batch.targets,
            batch.values,
            batch.payloads,
            TimelockController(payable(timelock)).getMinDelay()
        );

        return input;
    }

    function preflight(AltoEthereumMainnetInput memory input) internal view {
        PegResponsiveExponentialIrmConfig[] memory irmConfigs = _irmConfigs();
        MarketContracts[] memory markets = _activeMintMarkets(input);

        _validateFactoryAndOracle(input, _oracleRuntimeConfig());
        _validateOracleObservation(input.contracts.dusdPegCurveOracle, MAX_ORACLE_AGE);
        _validateInitialMarkets(input, markets, irmConfigs);

        PegResponsiveIrmBatch memory batch = _buildBatch(input, markets, irmConfigs);
        TimelockController timelock = TimelockController(payable(input.contracts.timelock));
        bytes32 operationId =
            timelock.hashOperationBatch(batch.targets, batch.values, batch.payloads, bytes32(0), bytes32(0));
        require(timelock.isOperationReady(operationId), "Timelock not ready");
    }

    function reconcile(AltoEthereumMainnetInput memory input) internal view returns (AltoEthereumMainnetInput memory) {
        PegResponsiveExponentialIrmConfig[] memory irmConfigs = _irmConfigs();
        _validateFactoryAndOracle(input, _oracleRuntimeConfig());

        MarketContracts[] memory markets = _activeMintMarkets(input);
        address[] memory expectedIrms = _predictedIrms(input, markets, irmConfigs);
        for (uint256 i; i < markets.length; ++i) {
            _validateFinalMarket(input, markets[i].market, expectedIrms[i], irmConfigs[i]);
            markets[i].marketIrm = expectedIrms[i];
        }
        return input;
    }

    function _buildBatch(
        AltoEthereumMainnetInput memory input,
        MarketContracts[] memory markets,
        PegResponsiveExponentialIrmConfig[] memory irmConfigs
    ) private view returns (PegResponsiveIrmBatch memory batch) {
        uint256 callCount = markets.length * 3;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);

        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        for (uint256 i; i < markets.length; ++i) {
            uint256 callIndex = i * 3;
            address market = markets[i].market;
            address irm = factory.predictIrmAddress(market, IRM_VERSION, irmConfigs[i]);

            batch.targets[callIndex] = address(factory);
            batch.payloads[callIndex] =
                abi.encodeCall(OwnerPegResponsiveExponentialIrmFactory.deploy, (market, IRM_VERSION, irmConfigs[i]));

            batch.targets[callIndex + 1] = market;
            batch.payloads[callIndex + 1] = abi.encodeCall(IMarketBase.setIrm, (irm, false));

            batch.targets[callIndex + 2] = market;
            batch.payloads[callIndex + 2] = abi.encodeCall(IMarketBase.accrueInterest, ());
        }
    }

    function _validateFactoryAndOracle(
        AltoEthereumMainnetInput memory input,
        DusdPegCurveOracleRuntimeConfig memory oracleConfig
    ) private view {
        address timelock = input.contracts.timelock;
        address factoryAddress = input.contracts.ownerPegResponsiveExponentialIrmFactory;
        address oracleAddress = input.contracts.dusdPegCurveOracle;

        require(
            factoryAddress.codehash == keccak256(type(OwnerPegResponsiveExponentialIrmFactory).runtimeCode),
            "Wrong factory code"
        );
        require(Ownable(factoryAddress).owner() == timelock, "Wrong factory owner");
        require(AltoOwnable2Step(factoryAddress).pendingOwner() == address(0), "Unexpected pending factory owner");
        require(
            OwnerPegResponsiveExponentialIrmFactory(factoryAddress).pegOracle() == oracleAddress, "Wrong factory oracle"
        );

        // DusdPegCurveOracle has an immutable pool address, so Solidity does not expose its unpatched runtimeCode.
        // Validate code presence plus every externally observable deployment invariant instead.
        require(oracleAddress.code.length != 0, "Missing oracle code");
        require(Ownable(oracleAddress).owner() == timelock, "Wrong oracle owner");
        require(AltoOwnable2Step(oracleAddress).pendingOwner() == address(0), "Unexpected pending oracle owner");

        DusdPegCurveOracle oracle = DusdPegCurveOracle(oracleAddress);
        require(oracle.curvePool() == FRXUSD_DUSD_CURVE_POOL_MAINNET, "Wrong Curve pool");
        (uint256 maExpTime, uint256 aPrecise) = oracle.runtimeConfig();
        require(
            maExpTime == oracleConfig.expectedMaExpTime && aPrecise == oracleConfig.expectedAPrecise,
            "Wrong oracle config"
        );
    }

    function _validateOracleObservation(address oracleAddress, uint48 maxOracleAge) private view {
        (uint256 priceWad, uint48 observedAt, bool valid) = IDusdPegOracle(oracleAddress).getPrice();
        require(
            valid && priceWad != 0 && observedAt != 0 && uint256(observedAt) <= block.timestamp, "Invalid peg price"
        );
        require(block.timestamp - uint256(observedAt) <= maxOracleAge, "Stale peg price");
    }

    function _validateInitialMarkets(
        AltoEthereumMainnetInput memory input,
        MarketContracts[] memory markets,
        PegResponsiveExponentialIrmConfig[] memory irmConfigs
    ) private view {
        require(markets.length == ACTIVE_MINT_MARKET_COUNT, "Expected six mint markets");

        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        for (uint256 i; i < markets.length; ++i) {
            address market = markets[i].market;
            require(market != address(0), "Invalid mint market");
            for (uint256 j; j < i; ++j) {
                require(markets[j].market != market, "Duplicate mint market");
            }

            IMarketBase marketContract = IMarketBase(market);
            require(
                market.code.length != 0 && Ownable(market).owner() == input.contracts.timelock, "Wrong market owner"
            );
            require(marketContract.MARKET_TYPE() == MarketType.MINT, "Wrong market type");
            require(!IPausable(market).paused(PAUSE_TYPE), "Market fully paused");

            address currentIrm = marketContract.irm();
            require(
                currentIrm.code.length != 0 && Ownable(currentIrm).owner() == input.contracts.timelock,
                "Wrong IRM owner"
            );
            require(IIrm(currentIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Wrong current IRM type");
            require(FixedRateIrm(currentIrm).market() == market, "Wrong current IRM binding");

            (address deployed,,) = factory.deployments(market, IRM_VERSION);
            require(deployed == address(0), "IRM already deployed");
            address predicted = factory.predictIrmAddress(market, IRM_VERSION, irmConfigs[i]);
            require(predicted.code.length == 0, "Predicted IRM already deployed");
        }
    }

    function _validateFinalMarket(
        AltoEthereumMainnetInput memory input,
        address market,
        address expectedIrm,
        PegResponsiveExponentialIrmConfig memory irmConfig
    ) private view {
        require(IMarketBase(market).irm() == expectedIrm, "Wrong market IRM");
        require(expectedIrm.codehash == keccak256(type(PegResponsiveExponentialIrm).runtimeCode), "Wrong IRM code");
        require(Ownable(expectedIrm).owner() == input.contracts.timelock, "Wrong IRM owner");
        require(AltoOwnable2Step(expectedIrm).pendingOwner() == address(0), "Unexpected pending IRM owner");
        require(IIrm(expectedIrm).IRM_TYPE() == IRMType.PEG_RESPONSIVE_EXPONENTIAL, "Wrong IRM type");

        IPegResponsiveExponentialIrm irm = IPegResponsiveExponentialIrm(expectedIrm);
        require(irm.market() == market, "Wrong IRM binding");
        require(irm.pegOracle() == input.contracts.dusdPegCurveOracle, "Wrong peg oracle");
        require(keccak256(abi.encode(irm.irmConfig())) == keccak256(abi.encode(irmConfig)), "Wrong IRM config");

        (address deployed, address irmOwner, address pegOracle) = OwnerPegResponsiveExponentialIrmFactory(
                input.contracts.ownerPegResponsiveExponentialIrmFactory
            ).deployments(market, IRM_VERSION);
        require(deployed == expectedIrm && irmOwner == input.contracts.timelock, "Wrong factory deployment");
        require(pegOracle == input.contracts.dusdPegCurveOracle, "Wrong factory oracle");
    }

    function _predictedIrms(
        AltoEthereumMainnetInput memory input,
        MarketContracts[] memory markets,
        PegResponsiveExponentialIrmConfig[] memory irmConfigs
    ) private view returns (address[] memory irms) {
        irms = new address[](markets.length);
        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = factory.predictIrmAddress(markets[i].market, IRM_VERSION, irmConfigs[i]);
        }
    }

    /// @dev Entries reference the input structs so reconciliation updates the returned input.
    function _activeMintMarkets(AltoEthereumMainnetInput memory input)
        private
        pure
        returns (MarketContracts[] memory markets)
    {
        markets = new MarketContracts[](ACTIVE_MINT_MARKET_COUNT);
        markets[0] = input.contracts.refreshWethMarket;
        markets[1] = input.contracts.refreshWstethMarket;
        markets[2] = input.contracts.refreshRethMarket;
        markets[3] = input.contracts.refreshSusdeMintMarket;
        markets[4] = input.contracts.refreshSyrupUsdcMintMarket;
        markets[5] = input.contracts.refreshFrxUsdMarket;
    }

    /// @dev Values from the peg IRM "Deployment Parameters and Setup" specification. Risk must approve
    /// them before mainnet deployment.
    function _oracleRuntimeConfig() private pure returns (DusdPegCurveOracleRuntimeConfig memory config) {
        config = DusdPegCurveOracleRuntimeConfig({expectedMaExpTime: 866, expectedAPrecise: 100_000});
    }

    /// @dev Values from the peg IRM "Deployment Parameters and Setup" specification. Risk must approve
    /// them before mainnet deployment. Entries follow `_activeMintMarkets` order. Rates are APRs
    /// converted to per-second rates, rounded down over a 365-day year.
    function _irmConfigs() private pure returns (PegResponsiveExponentialIrmConfig[] memory configs) {
        configs = new PegResponsiveExponentialIrmConfig[](ACTIVE_MINT_MARKET_COUNT);
        configs[0] = _irmConfig(0.035e18 / YEAR, 0.07e18 / YEAR, 5.2e18 / YEAR); // WETH
        configs[1] = _irmConfig(0.0415e18 / YEAR, 0.083e18 / YEAR, 2.3e18 / YEAR); // wstETH
        configs[2] = _irmConfig(0.0503e18 / YEAR, 0.1005e18 / YEAR, 2.3e18 / YEAR); // rETH
        configs[3] = _irmConfig(0.0425e18 / YEAR, 0.085e18 / YEAR, 2.8e18 / YEAR); // sUSDe
        configs[4] = _irmConfig(0.0445e18 / YEAR, 0.089e18 / YEAR, 1.1e18 / YEAR); // syrupUSDC
        configs[5] = _irmConfig(0, 0.0894e18 / YEAR, 0.9e18 / YEAR); // frxUSD
    }

    function _irmConfig(uint256 baseRate, uint256 stressRate, uint256 maxRate)
        private
        pure
        returns (PegResponsiveExponentialIrmConfig memory config)
    {
        config = PegResponsiveExponentialIrmConfig({
            recoveryPrice: 0.999e18,
            stressPrice: 0.995e18,
            baseRate: baseRate,
            stressRate: stressRate,
            maxRate: maxRate,
            doublingDistance: 0.0025e18,
            recoveryDelay: 6 hours,
            maxOracleAge: MAX_ORACLE_AGE
        });
    }
}

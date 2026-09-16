// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AltoEthereumMainnetInput} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
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
    uint256 private constant YEAR = 365 days;
    string private constant SAFE_BATCH_NAME = "mint-market-peg-responsive-irm";

    function generate(AltoEthereumMainnetInput memory input) internal returns (AltoEthereumMainnetInput memory) {
        address timelock = input.contracts.timelock;
        require(timelock != address(0), "Invalid timelock");

        DusdPegCurveOracleRuntimeConfig memory oracleConfig = _oracleRuntimeConfig();
        PegResponsiveExponentialIrmConfig memory irmConfig = _irmConfig();

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

        address[] memory markets = _activeMintMarkets(input);
        address[] memory storedIrms = _storedMintIrms(input);
        _validateFactoryAndOracle(input, oracleConfig);
        _validateInitialMarkets(input, markets, storedIrms, irmConfig);

        PegResponsiveIrmBatch memory batch = _buildBatch(input, markets, irmConfig);
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
        PegResponsiveExponentialIrmConfig memory irmConfig = _irmConfig();
        address[] memory markets = _activeMintMarkets(input);
        address[] memory storedIrms = _storedMintIrms(input);

        _validateFactoryAndOracle(input, _oracleRuntimeConfig());
        _validateInitialMarkets(input, markets, storedIrms, irmConfig);

        PegResponsiveIrmBatch memory batch = _buildBatch(input, markets, irmConfig);
        TimelockController timelock = TimelockController(payable(input.contracts.timelock));
        bytes32 operationId =
            timelock.hashOperationBatch(batch.targets, batch.values, batch.payloads, bytes32(0), bytes32(0));
        require(timelock.isOperationReady(operationId), "Timelock not ready");
    }

    function reconcile(AltoEthereumMainnetInput memory input) internal view returns (AltoEthereumMainnetInput memory) {
        PegResponsiveExponentialIrmConfig memory irmConfig = _irmConfig();
        _validateFactoryAndOracle(input, _oracleRuntimeConfig());

        address[] memory markets = _activeMintMarkets(input);
        address[] memory expectedIrms = _predictedIrms(input, markets, irmConfig);
        for (uint256 i; i < markets.length; ++i) {
            _validateFinalMarket(input, markets[i], expectedIrms[i], irmConfig);
        }

        input.contracts.refreshWethMarket.marketIrm = expectedIrms[0];
        input.contracts.refreshWstethMarket.marketIrm = expectedIrms[1];
        input.contracts.refreshRethMarket.marketIrm = expectedIrms[2];
        input.contracts.refreshSusdeMintMarket.marketIrm = expectedIrms[3];
        input.contracts.refreshSyrupUsdcMintMarket.marketIrm = expectedIrms[4];
        input.contracts.refreshFrxUsdMarket.marketIrm = expectedIrms[5];
        return input;
    }

    function _buildBatch(
        AltoEthereumMainnetInput memory input,
        address[] memory markets,
        PegResponsiveExponentialIrmConfig memory irmConfig
    ) private view returns (PegResponsiveIrmBatch memory batch) {
        uint256 callCount = markets.length * 2;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);

        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        for (uint256 i; i < markets.length; ++i) {
            uint256 callIndex = i * 2;
            address irm = factory.predictIrmAddress(markets[i], irmConfig);

            batch.targets[callIndex] = address(factory);
            batch.payloads[callIndex] =
                abi.encodeCall(OwnerPegResponsiveExponentialIrmFactory.deploy, (markets[i], irmConfig));

            batch.targets[callIndex + 1] = markets[i];
            batch.payloads[callIndex + 1] = abi.encodeCall(IMarketBase.setIrm, (irm, false));
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

        (uint256 priceWad, uint48 observedAt, bool valid) = IDusdPegOracle(oracleAddress).getPrice();
        require(
            valid && priceWad != 0 && observedAt != 0 && uint256(observedAt) <= block.timestamp, "Invalid peg price"
        );
    }

    function _validateInitialMarkets(
        AltoEthereumMainnetInput memory input,
        address[] memory markets,
        address[] memory storedIrms,
        PegResponsiveExponentialIrmConfig memory irmConfig
    ) private view {
        require(markets.length == ACTIVE_MINT_MARKET_COUNT, "Expected six mint markets");
        require(storedIrms.length == markets.length, "Invalid stored IRM count");

        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        for (uint256 i; i < markets.length; ++i) {
            address market = markets[i];
            require(market != address(0), "Invalid mint market");
            for (uint256 j; j < i; ++j) {
                require(markets[j] != market, "Duplicate mint market");
            }

            IMarketBase marketContract = IMarketBase(market);
            require(
                market.code.length != 0 && Ownable(market).owner() == input.contracts.timelock, "Wrong market owner"
            );
            require(marketContract.MARKET_TYPE() == MarketType.MINT, "Wrong market type");
            require(!IPausable(market).paused(PAUSE_TYPE), "Market fully paused");

            address currentIrm = marketContract.irm();
            require(currentIrm == storedIrms[i], "Stored IRM mismatch");
            require(
                currentIrm.code.length != 0 && Ownable(currentIrm).owner() == input.contracts.timelock,
                "Wrong IRM owner"
            );
            require(IIrm(currentIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Wrong current IRM type");
            require(FixedRateIrm(currentIrm).market() == market, "Wrong current IRM binding");

            (address deployed,,) = factory.deployments(market);
            require(deployed == address(0), "IRM already deployed");
            address predicted = factory.predictIrmAddress(market, irmConfig);
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
            ).deployments(market);
        require(deployed == expectedIrm && irmOwner == input.contracts.timelock, "Wrong factory deployment");
        require(pegOracle == input.contracts.dusdPegCurveOracle, "Wrong factory oracle");
    }

    function _predictedIrms(
        AltoEthereumMainnetInput memory input,
        address[] memory markets,
        PegResponsiveExponentialIrmConfig memory irmConfig
    ) private view returns (address[] memory irms) {
        irms = new address[](markets.length);
        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = factory.predictIrmAddress(markets[i], irmConfig);
        }
    }

    function _activeMintMarkets(AltoEthereumMainnetInput memory input) private pure returns (address[] memory markets) {
        markets = new address[](ACTIVE_MINT_MARKET_COUNT);
        markets[0] = input.contracts.refreshWethMarket.market;
        markets[1] = input.contracts.refreshWstethMarket.market;
        markets[2] = input.contracts.refreshRethMarket.market;
        markets[3] = input.contracts.refreshSusdeMintMarket.market;
        markets[4] = input.contracts.refreshSyrupUsdcMintMarket.market;
        markets[5] = input.contracts.refreshFrxUsdMarket.market;
    }

    function _storedMintIrms(AltoEthereumMainnetInput memory input) private pure returns (address[] memory irms) {
        irms = new address[](ACTIVE_MINT_MARKET_COUNT);
        irms[0] = input.contracts.refreshWethMarket.marketIrm;
        irms[1] = input.contracts.refreshWstethMarket.marketIrm;
        irms[2] = input.contracts.refreshRethMarket.marketIrm;
        irms[3] = input.contracts.refreshSusdeMintMarket.marketIrm;
        irms[4] = input.contracts.refreshSyrupUsdcMintMarket.marketIrm;
        irms[5] = input.contracts.refreshFrxUsdMarket.marketIrm;
    }

    /// @dev TENTATIVE DEPLOYMENT PARAMETERS: review and update every value before mainnet deployment.
    function _oracleRuntimeConfig() private pure returns (DusdPegCurveOracleRuntimeConfig memory config) {
        config = DusdPegCurveOracleRuntimeConfig({
            expectedMaExpTime: 866, // TENTATIVE: review and update before mainnet deployment.
            expectedAPrecise: 100_000 // TENTATIVE: review and update before mainnet deployment.
        });
    }

    /// @dev TENTATIVE DEPLOYMENT PARAMETERS: review and update every value before mainnet deployment.
    function _irmConfig() private pure returns (PegResponsiveExponentialIrmConfig memory config) {
        config = PegResponsiveExponentialIrmConfig({
            recoveryPrice: 1.001e18, // TENTATIVE: review and update before mainnet deployment.
            stressPrice: 1e18, // TENTATIVE: review and update before mainnet deployment.
            baseRate: 0.05e18 / YEAR, // TENTATIVE: review and update before mainnet deployment.
            stressRate: 0.075e18 / YEAR, // TENTATIVE: review and update before mainnet deployment.
            maxRate: 8e18 / YEAR, // TENTATIVE: review and update before mainnet deployment.
            doublingDistance: 0.0025e18, // TENTATIVE: review and update before mainnet deployment.
            recoveryDelay: 6 hours, // TENTATIVE: review and update before mainnet deployment.
            maxOracleAge: 30 minutes // TENTATIVE: review and update before mainnet deployment.
        });
    }
}

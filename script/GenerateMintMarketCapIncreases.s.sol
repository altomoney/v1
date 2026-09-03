// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {Balance, IMarket, IMarketBase, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

interface IMintMarketCapAdmin {
    function badDebtAssets() external view returns (uint128);
    function setDebtCeiling(uint256 debtCeiling) external;
}

struct MintMarketCapConfig {
    string symbol;
    address deprecatedMarket;
    address replacementMarket;
    uint256 deploymentCeiling;
}

struct MintMarketCapPlan {
    MintMarketCapConfig config;
    uint256 oldStoredDebt;
    uint256 oldVirtualInterest;
    uint256 oldBadDebt;
    uint256 oldEffectiveExposure;
    uint256 currentDebtCeiling;
    uint256 currentMinterCeiling;
    uint256 targetDebtCeiling;
    uint256 targetMinterCeiling;
    uint256 aggregateBuffer;
    bool currentlyOverCap;
    bool shouldIncrease;
}

library MintMarketCapIncreaseMath {
    uint256 internal constant MINTER_MULTIPLIER = 1.05 ether;

    function calculateTarget(
        uint256 deploymentCeiling,
        uint256 oldEffectiveExposure,
        uint256 currentDebtCeiling,
        bool exposureCanGrow,
        uint256 roundingUnit,
        uint256 executionBuffer
    ) internal pure returns (uint256 targetDebtCeiling, uint256 maximumAvailable, bool currentlyOverCap) {
        require(deploymentCeiling != 0, "zero deployment ceiling");
        require(roundingUnit != 0, "zero rounding unit");

        currentlyOverCap =
            oldEffectiveExposure > deploymentCeiling || currentDebtCeiling > deploymentCeiling - oldEffectiveExposure;

        if (oldEffectiveExposure >= deploymentCeiling) return (0, 0, currentlyOverCap);

        maximumAvailable = deploymentCeiling - oldEffectiveExposure;
        if (oldEffectiveExposure == 0) return (deploymentCeiling, maximumAvailable, currentlyOverCap);

        uint256 bufferedAvailable = maximumAvailable;
        if (exposureCanGrow) {
            if (bufferedAvailable <= executionBuffer) return (0, maximumAvailable, currentlyOverCap);
            bufferedAvailable -= executionBuffer;
        }

        targetDebtCeiling = bufferedAvailable / roundingUnit * roundingUnit;
    }

    function calculateMinterCeiling(uint256 debtCeiling, uint256 maxLiquidationLtv) internal pure returns (uint256) {
        require(maxLiquidationLtv != 0, "zero liquidation LTV");
        return debtCeiling * MINTER_MULTIPLIER / maxLiquidationLtv;
    }
}

/// @notice Generates matching Safe Transaction Builder JSON files that schedule and execute safe Mint Market cap
/// increases as deprecated-market debt unwinds.
/// @dev Run without --broadcast against Ethereum mainnet:
/// forge script script/GenerateMintMarketCapIncreases.s.sol:GenerateMintMarketCapIncreasesScript --rpc-url <RPC> -vv
contract GenerateMintMarketCapIncreasesScript is Script {
    address public constant OWNER_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address public constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address public constant MARKET_REGISTRY = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;

    uint256 public constant ROUNDING_UNIT = 1_000 ether;
    uint256 public constant EXECUTION_BUFFER = 1_000 ether;

    function run() public {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(Ownable(DUSD).owner() == TIMELOCK, "wrong DUSD owner");
        require(Ownable(MARKET_REGISTRY).owner() == TIMELOCK, "wrong registry owner");

        MintMarketCapConfig[] memory configs = _configs();
        MintMarketCapPlan[] memory plans = new MintMarketCapPlan[](configs.length);
        uint256 increaseCount;

        for (uint256 i; i < configs.length; ++i) {
            plans[i] = _plan(configs[i]);
            _log(plans[i]);
            if (plans[i].shouldIncrease) ++increaseCount;
        }

        console.log("Snapshot block:", block.number);
        if (increaseCount == 0) {
            console.log("No safe Mint Market ceiling increases are currently available");
            return;
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildTimelockBatch(plans, increaseCount);
        uint256 delay = TimelockController(payable(TIMELOCK)).getMinDelay();

        _simulateAndRevert(plans, targets, values, payloads, delay);
        _writeSafeJsons(targets, values, payloads, delay);
    }

    function _plan(MintMarketCapConfig memory config) internal view returns (MintMarketCapPlan memory plan) {
        plan.config = config;

        IMarket replacementMarket = IMarket(config.replacementMarket);
        require(config.replacementMarket.code.length != 0, "replacement market has no code");
        require(Ownable(config.replacementMarket).owner() == TIMELOCK, "wrong replacement market owner");
        require(replacementMarket.MARKET_TYPE() == MarketType.MINT, "replacement is not a Mint Market");
        require(!IPausable(config.replacementMarket).paused(PAUSE_TYPE), "replacement market is paused");
        require(!IPausable(config.replacementMarket).paused(FROZEN_TYPE), "replacement market is frozen");
        require(IMarketRegistry(MARKET_REGISTRY).isMintMarket(config.replacementMarket), "replacement not active");
        require(IDUSD(DUSD).allowedMinter(config.replacementMarket), "replacement is not a DUSD minter");
        require(IDUSD(DUSD).allowedBurner(config.replacementMarket), "replacement is not a DUSD burner");

        Balance memory replacementSupply = replacementMarket.totalSupply();
        plan.currentDebtCeiling = replacementSupply.assets;
        (, plan.currentMinterCeiling) = IDUSD(DUSD).minterConfig(config.replacementMarket);
        require(plan.currentDebtCeiling <= config.deploymentCeiling, "replacement ceiling above deployment maximum");

        bool exposureCanGrow;
        if (config.deprecatedMarket != address(0)) {
            IMarket deprecatedMarket = IMarket(config.deprecatedMarket);
            require(config.deprecatedMarket.code.length != 0, "deprecated market has no code");
            require(Ownable(config.deprecatedMarket).owner() == TIMELOCK, "wrong deprecated market owner");
            require(deprecatedMarket.MARKET_TYPE() == MarketType.MINT, "deprecated market is not a Mint Market");
            require(IPausable(config.deprecatedMarket).paused(FROZEN_TYPE), "deprecated market is not frozen");
            require(!IPausable(config.deprecatedMarket).paused(PAUSE_TYPE), "deprecated market is paused");

            (plan.oldStoredDebt, plan.oldVirtualInterest, plan.oldBadDebt, exposureCanGrow) =
                _deprecatedExposure(config.deprecatedMarket);
            plan.oldEffectiveExposure = plan.oldStoredDebt + plan.oldVirtualInterest + plan.oldBadDebt;
        }

        (plan.targetDebtCeiling,, plan.currentlyOverCap) = MintMarketCapIncreaseMath.calculateTarget(
            config.deploymentCeiling,
            plan.oldEffectiveExposure,
            plan.currentDebtCeiling,
            exposureCanGrow,
            ROUNDING_UNIT,
            EXECUTION_BUFFER
        );

        uint256 maxLiquidationLtv = IAltoLiquidationEngine(replacementMarket.liquidationEngine()).minLltv();
        plan.targetMinterCeiling =
            MintMarketCapIncreaseMath.calculateMinterCeiling(plan.targetDebtCeiling, maxLiquidationLtv);
        plan.shouldIncrease = plan.targetDebtCeiling > plan.currentDebtCeiling;

        if (
            plan.oldEffectiveExposure <= config.deploymentCeiling
                && plan.targetDebtCeiling <= config.deploymentCeiling - plan.oldEffectiveExposure
        ) {
            plan.aggregateBuffer = config.deploymentCeiling - plan.oldEffectiveExposure - plan.targetDebtCeiling;
        }

        if (plan.shouldIncrease) {
            (uint256 minted,) = IDUSD(DUSD).minterConfig(config.replacementMarket);
            require(plan.targetMinterCeiling >= plan.currentMinterCeiling, "minter ceiling would decrease");
            require(plan.targetMinterCeiling >= minted, "minter ceiling below minted amount");
        }
    }

    function _buildTimelockBatch(MintMarketCapPlan[] memory plans, uint256 increaseCount)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](increaseCount * 2);
        values = new uint256[](increaseCount * 2);
        payloads = new bytes[](increaseCount * 2);

        uint256 callIndex;
        for (uint256 i; i < plans.length; ++i) {
            if (!plans[i].shouldIncrease) continue;

            targets[callIndex] = plans[i].config.replacementMarket;
            payloads[callIndex] = abi.encodeCall(IMintMarketCapAdmin.setDebtCeiling, (plans[i].targetDebtCeiling));
            ++callIndex;

            targets[callIndex] = DUSD;
            payloads[callIndex] = abi.encodeCall(
                IDUSD.setMinterCeiling, (plans[i].config.replacementMarket, plans[i].targetMinterCeiling)
            );
            ++callIndex;
        }
    }

    function _simulateAndRevert(
        MintMarketCapPlan[] memory plans,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal {
        uint256 snapshot = vm.snapshotState();
        TimelockController timelock = TimelockController(payable(TIMELOCK));

        vm.prank(OWNER_SAFE);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), delay);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(OWNER_SAFE);
        timelock.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));

        for (uint256 i; i < plans.length; ++i) {
            if (!plans[i].shouldIncrease) continue;
            require(
                IMarket(plans[i].config.replacementMarket).totalSupply().assets == plans[i].targetDebtCeiling,
                "debt ceiling simulation mismatch"
            );
            (, uint256 minterCeiling) = IDUSD(DUSD).minterConfig(plans[i].config.replacementMarket);
            require(minterCeiling == plans[i].targetMinterCeiling, "minter ceiling simulation mismatch");

            (uint256 storedDebt, uint256 virtualInterest, uint256 badDebt,) =
                _deprecatedExposure(plans[i].config.deprecatedMarket);
            uint256 effectiveExposureAtExecution = storedDebt + virtualInterest + badDebt;
            require(
                effectiveExposureAtExecution <= plans[i].config.deploymentCeiling
                    && plans[i].targetDebtCeiling <= plans[i].config.deploymentCeiling - effectiveExposureAtExecution,
                "aggregate ceiling unsafe at execution"
            );
        }

        require(vm.revertToState(snapshot), "failed to revert simulation");
    }

    function _deprecatedExposure(address market)
        internal
        view
        returns (uint256 storedDebt, uint256 virtualInterest, uint256 badDebt, bool exposureCanGrow)
    {
        if (market == address(0)) return (0, 0, 0, false);

        Balance memory supply = IMarket(market).totalSupply();
        Balance memory borrowed = IMarket(market).totalBorrowed();
        storedDebt = borrowed.assets;
        badDebt = IMintMarketCapAdmin(market).badDebtAssets();
        exposureCanGrow = storedDebt != 0;
        if (exposureCanGrow) {
            (virtualInterest,) = IIrm(IMarket(market).irm()).updateInterestRateView(supply.assets, storedDebt);
        }
    }

    function _writeSafeJsons(address[] memory targets, uint256[] memory values, bytes[] memory payloads, uint256 delay)
        internal
    {
        bytes memory scheduleData = abi.encodeCall(
            TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), bytes32(0), delay)
        );
        bytes memory executeData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), bytes32(0)));

        string memory name = string.concat("mint-market-cap-increase-", vm.toString(block.number));
        _writeSingleSafeTransaction(string.concat(name, "-schedule"), scheduleData);
        _writeSingleSafeTransaction(string.concat(name, "-execute"), executeData);
    }

    function _writeSingleSafeTransaction(string memory name, bytes memory data) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        targets[0] = TIMELOCK;
        payloads[0] = data;
        SafeTransactionBuilder.writeDirectBatch(name, OWNER_SAFE, targets, values, payloads);
    }

    function _log(MintMarketCapPlan memory plan) internal pure {
        console.log(plan.config.symbol);
        console.log("  deployment ceiling:", plan.config.deploymentCeiling);
        console.log("  deprecated effective exposure:", plan.oldEffectiveExposure);
        console.log("  current replacement ceiling:", plan.currentDebtCeiling);
        console.log("  calculated target ceiling:", plan.targetDebtCeiling);
        console.log("  remaining aggregate buffer:", plan.aggregateBuffer);
        if (plan.currentlyOverCap) console.log("  WARNING: current aggregate ceiling is above the deployment maximum");
        if (plan.shouldIncrease) console.log("  included in generated Safe batch");
    }

    function _configs() internal pure returns (MintMarketCapConfig[] memory configs) {
        configs = new MintMarketCapConfig[](6);
        configs[0] = MintMarketCapConfig({
            symbol: "WETH",
            deprecatedMarket: 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff,
            replacementMarket: 0x81b2CcE73052f67312eD9994385f62D413eE566e,
            deploymentCeiling: 60_000 ether
        });
        configs[1] = MintMarketCapConfig({
            symbol: "wstETH",
            deprecatedMarket: 0xfd8c25047f4397dC5461B919999585a2a3EaC2eF,
            replacementMarket: 0x4Ad5AC62542164A74fF88a2BCDd0142126c1E3A3,
            deploymentCeiling: 60_000 ether
        });
        configs[2] = MintMarketCapConfig({
            symbol: "rETH",
            deprecatedMarket: 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf,
            replacementMarket: 0x12C219BaCc90E87Fe11E34288454728E1D8C8Dcf,
            deploymentCeiling: 20_000 ether
        });
        configs[3] = MintMarketCapConfig({
            symbol: "sUSDe",
            deprecatedMarket: 0x210bF54092B66443FddFec0f3F156e74B04CD2a2,
            replacementMarket: 0xD2D7F7db33C647D5bF02937A3742C5Ad28197C3E,
            deploymentCeiling: 31_394 ether
        });
        configs[4] = MintMarketCapConfig({
            symbol: "syrupUSDC",
            deprecatedMarket: 0xD2eA320713158a7b7eaE46025B8Ad4CBF3cdc87e,
            replacementMarket: 0xD5EFF65DEC6BdF835B4041e862d6D54eA2CAb45a,
            deploymentCeiling: 54_000 ether
        });
        configs[5] = MintMarketCapConfig({
            symbol: "frxUSD",
            deprecatedMarket: address(0),
            replacementMarket: 0x37Ab044Cce4eE2cC659B887e0868BaBe097BE9b1,
            deploymentCeiling: 30_000 ether
        });
    }
}

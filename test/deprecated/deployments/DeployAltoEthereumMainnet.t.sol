// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MarketType} from "@alto/lending/interfaces/IMarket.sol";

import {
    DeployAltoEthereumMainnet,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeploymentPhase,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {
    IDcfDlbPriorityLiquidationEngineStaticTypes
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract DeployAltoEthereumMainnetTest is Test {
    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    address immutable MULTISIG_TIMELOCK_ADMIN = makeAddr("TIMELLOCK_ADMIN");
    address immutable MULTISIG_FREEZER_PAUSER = makeAddr("MULTISIG_FREEZER_PAUSER");
    address immutable STAKING_URD = makeAddr("STAKING_URD");
    address immutable MERKLE_ROOT_UPDATER = makeAddr("MERKLE_ROOT_UPDATER");
    address DEPLOYER;

    bytes32 immutable CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 immutable SWAP_FREEZER_ROLE = keccak256("SWAP_FREEZER_ROLE");
    bytes32 immutable TOKEN_RESCUER_ROLE = keccak256("TOKEN_RESCUER_ROLE");
    bytes32 immutable LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 immutable SWAPPER_ROLE = keccak256("SWAPPER_ROLE");
    bytes32 immutable DEFAULT_ADMIN_ROLE = bytes32(0);

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        DEPLOYER = address(this);

        params = AltoEthereumMainnetParams({
            timelockAdmin: MULTISIG_TIMELOCK_ADMIN,
            timelockDelay: 2 days,
            freezer: MULTISIG_FREEZER_PAUSER,
            deployer: DEPLOYER,
            phase: DeploymentPhase.CORE,
            useUnsafeUpgrades: true,
            treasuryMultisig: address(1), // TODO: Set to actual treasury multisig address
            updater: MERKLE_ROOT_UPDATER,
            deployerHasOwnership: true // Deployer has ownership in tests, execute directly
        });
    }

    function _deployPrerequisites(DeploymentPhase targetPhase) internal {
        // Ensure CORE is deployed (needed for DUSD and all other phases)
        if (targetPhase != DeploymentPhase.CORE) {
            params.phase = DeploymentPhase.CORE;
            input = DeployAltoEthereumMainnet.deploy(params, input);
        }

        if (targetPhase != DeploymentPhase.DUSD) {
            params.phase = DeploymentPhase.DUSD;
            input = DeployAltoEthereumMainnet.deploy(params, input);
        }

        // All other phases depend on CORE, DUSD and REGISTRY
        if (targetPhase != DeploymentPhase.REGISTRY) {
            params.phase = DeploymentPhase.REGISTRY;
            input = DeployAltoEthereumMainnet.deploy(params, input);
        }
    }

    function _verifyMarketContracts(MarketContracts memory market) internal view {
        string memory s = IERC20Metadata(IMarket(market.market).collateralToken()).symbol();
        MarketType marketType = IMarket(market.market).MARKET_TYPE();
        MarketRegistry marketRegistry = MarketRegistry(input.contracts.marketRegistry);

        if (marketType == MarketType.MINT) {
            assertTrue(marketRegistry.isMintMarket(market.market), "Market should be registered as mint market");
        } else if (marketType == MarketType.BORROW) {
            assertTrue(marketRegistry.isBorrowMarket(market.market), "Market should be registered as borrow market");
        }

        _verifyDeployed(market.market, "market");
        _verifyDeployed(market.marketImplementation, "implementation");
        _verifyDeployed(market.marketIrm, "irm");
        _verifyDeployed(market.marketOracle, "oracle");
        _verifyDeployed(market.liquidationEngine, "liquidationEngine");
        _verifyDeployed(market.leverageSwapper, "leverageSwapper");
        _verifyDeployed(market.leverage, "leverage");

        _verifyOwner(market.market, "market");
        _verifyOwner(market.marketIrm, "irm");
        _verifyOwner(market.marketOracle, "oracle");
        _verifyOwner(market.liquidationEngine, "liquidationEngine");
        _verifyOwner(market.leverageSwapper, "leverageSwapper");
        _verifyOwner(market.leverage, "leverage");

        _verifyPauser(market.market, "market");
        _verifyFreezer(market.market, "market");

        _verifyApprovedByAdapter(market.market, "market");

        assertTrue(
            AltoLeverage(payable(market.leverage)).supportedMarkets(market.market), "Leverage should support market"
        );
        assertTrue(
            AltoLeverageSwapper(payable(market.leverageSwapper)).isWhitelisted(market.leverage),
            "Leverage should be whitelisted"
        );
        assertTrue(
            IMarket(market.market).authorizedCallbacks(market.leverage), "Market should authorize leverage callback"
        );

        assertEq(
            IAltoLiquidationEngine(market.liquidationEngine).market(),
            market.market,
            "Liquidation engine should have correct market"
        );
    }

    function _verifyDeployed(address addr, string memory name) internal view {
        assertTrue(addr != address(0) && addr.code.length > 0, string.concat(name, " not deployed"));
    }

    function _verifyOwner(address addr, string memory name) internal view {
        assertEq(Ownable(addr).owner(), input.contracts.timelock, string.concat(name, " owner mismatch"));
    }

    function _verifyPauser(address addr, string memory name) internal view {
        assertTrue(Pausable(addr).pausers(MULTISIG_FREEZER_PAUSER, PAUSE_TYPE), string.concat(name, " pauser mismatch"));
    }

    function _verifyFreezer(address addr, string memory name) internal view {
        assertTrue(
            Pausable(addr).pausers(MULTISIG_FREEZER_PAUSER, FROZEN_TYPE), string.concat(name, " freezer mismatch")
        );
    }

    function _verifyApprovedByAdapter(address addr, string memory name) internal view {
        assertTrue(
            AltoAdapter(payable(input.contracts.altoAdapter)).isApprovedContract(addr),
            string.concat(name, " approved by adapter mismatch")
        );
    }

    function _verifyMintCeilingMarket(address market, uint256 ceiling) internal view {
        uint256 maxLiquidationLtv = IAltoLiquidationEngine(IMarket(market).liquidationEngine()).minLltv();
        uint256 expectedMintCeiling = ceiling * 1.05 ether / maxLiquidationLtv;
        string memory s = IERC20Metadata(IMarket(market).collateralToken()).symbol();
        address dusd = IMarket(market).borrowToken();
        assertTrue(IDUSD(dusd).allowedMinter(market), string.concat(s, " market should be allowed minter"));
        assertTrue(IDUSD(dusd).allowedBurner(market), string.concat(s, " market should be allowed burner"));
        (uint256 minted, uint256 _ceiling) = IDUSD(dusd).minterConfig(market);
        assertEq(minted, 0, string.concat(s, " market should have 0 minted initially"));
        assertEq(_ceiling, expectedMintCeiling, string.concat(s, " market mint ceiling should be correct"));
    }

    function test_deployPhase_MINT_MARKET_WETH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_WETH);

        params.phase = DeploymentPhase.MINT_MARKET_WETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.wethMarket);
        _verifyMintCeilingMarket(input.contracts.wethMarket.market, 500_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_WSTETH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_WSTETH);

        params.phase = DeploymentPhase.MINT_MARKET_WSTETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.wstethMarket);
        _verifyMintCeilingMarket(input.contracts.wstethMarket.market, 500_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_RETH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_RETH);

        params.phase = DeploymentPhase.MINT_MARKET_RETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.rethMarket);
        _verifyMintCeilingMarket(input.contracts.rethMarket.market, 200_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_METH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_METH);

        params.phase = DeploymentPhase.MINT_MARKET_METH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.methMarket);
        _verifyMintCeilingMarket(input.contracts.methMarket.market, 200_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_TBTC() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_TBTC);

        params.phase = DeploymentPhase.MINT_MARKET_TBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.tbtcMarket);
        _verifyMintCeilingMarket(input.contracts.tbtcMarket.market, 200_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_BORROW_MARKET_WBTC() public {
        _deployPrerequisites(DeploymentPhase.BORROW_MARKET_WBTC);

        params.phase = DeploymentPhase.BORROW_MARKET_WBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.wbtcBorrowMarket);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_BORROW_MARKET_CBBTC() public {
        _deployPrerequisites(DeploymentPhase.BORROW_MARKET_CBBTC);

        params.phase = DeploymentPhase.BORROW_MARKET_CBBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.cbbtcBorrowMarket);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_BORROW_MARKET_SUSDE() public {
        _deployPrerequisites(DeploymentPhase.BORROW_MARKET_SUSDE);

        params.phase = DeploymentPhase.BORROW_MARKET_SUSDE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.susdeBorrowMarket);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_BORROW_MARKET_SYRUP_USDC() public {
        _deployPrerequisites(DeploymentPhase.BORROW_MARKET_SYRUP_USDC);

        params.phase = DeploymentPhase.BORROW_MARKET_SYRUP_USDC;
        params.deployerHasOwnership = false;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Manual post-deployment steps (requires owner)
        MarketRegistry(input.contracts.marketRegistry).addBorrowMarket(input.contracts.syrupUsdcBorrowMarket.market);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.syrupUsdcBorrowMarket.market);

        _verifyMarketContracts(input.contracts.syrupUsdcBorrowMarket);
        _verifySyrupBorrowMarketParams(input.contracts.syrupUsdcBorrowMarket);
    }

    function _verifySyrupBorrowMarketParams(MarketContracts memory market) internal view {
        // Verify maxLtv
        assertEq(IMarket(market.market).maxLtv(), 0.8 ether, "maxLtv should be 80%");

        // Verify oracle is deployed
        assertTrue(IMarket(market.market).oracle() != address(0), "oracle should be deployed");

        // Split into separate functions to avoid stack too deep
        _verifySyrupLiquidationConfig(market.liquidationEngine);
        _verifySyrupIrmConfig(market.marketIrm);
    }

    function _verifySyrupLiquidationConfig(address liquidationEngine) internal view {
        (
            uint256 maxLiquidationLtv,
            uint256 dynamicBonusFeeStart,
            uint256 ltvForCompleteLiquidation,
            uint256 dynamicBonusFeeDecaySteepness,
            uint256 liquidationBaseFee,
            uint256 minPenaltyPercentage,
            uint256 protocolFeePercentage,
            bool isEnabledPriorityLiquidation,,,,
        ) = IDcfDlbPriorityLiquidationEngineStaticTypes(liquidationEngine).liquidationConfiguration();

        assertEq(maxLiquidationLtv, 0.85 ether, "LLTV should be 85%");
        assertEq(dynamicBonusFeeStart, 0.01 ether, "dynamicBonusFeeStart should be 1%");
        assertEq(ltvForCompleteLiquidation, 0.93 ether, "tLLTV should be 93%");
        assertEq(dynamicBonusFeeDecaySteepness, 5 ether, "DLB steepness should be 5");
        assertEq(liquidationBaseFee, 0.06 ether, "liquidationBaseFee should be 6%");
        assertEq(minPenaltyPercentage, 0.005 ether, "maxDLB should be 0.5%");
        assertEq(protocolFeePercentage, 0.07 ether, "protocolFee should be 7%");
        assertFalse(isEnabledPriorityLiquidation, "priority liquidation should be disabled");
    }

    function _verifySyrupIrmConfig(address irm) internal view {
        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = AdaptiveCurveIrm(irm).irmConfig();

        assertEq(curveSteepness, 4 ether, "curveSteepness should be 4");
        assertEq(adjustmentSpeed, 50 ether / int256(365 days), "adjustmentSpeed should be 50/year");
        assertEq(targetUtilization, 0.9 ether, "targetUtilization should be 90%");
        assertEq(initialRateAtTarget, 0.1 ether / int256(365 days), "initialRateAtTarget should be 10%/year");
        assertEq(minRateAtTarget, 0.001 ether / int256(365 days), "minRateAtTarget should be 0.1%/year");
        assertEq(maxRateAtTarget, 2 ether / int256(365 days), "maxRateAtTarget should be 200%/year");
    }

    function _verifyMintCeiling(address contractAddress, uint256 ceiling) internal view {
        string memory contractAddressString = Strings.toHexString(uint256(uint160(contractAddress)), 20);
        assertTrue(
            IDUSD(input.contracts.dusd).allowedMinter(contractAddress),
            string.concat(contractAddressString, " should be allowed minter")
        );
        assertTrue(
            IDUSD(input.contracts.dusd).allowedBurner(contractAddress),
            string.concat(contractAddressString, " should be allowed burner")
        );
        (uint256 minted, uint256 _ceiling) = IDUSD(input.contracts.dusd).minterConfig(contractAddress);
        assertEq(minted, 0, string.concat(contractAddressString, " should have 0 minted initially"));
        assertEq(_ceiling, ceiling, string.concat(contractAddressString, " mint ceiling should be correct"));
    }

    function _verifyHasRole(address _address, address _owner, bytes32 role, string memory name) internal view {
        if (role == DEFAULT_ADMIN_ROLE) {
            assertTrue(
                AccessControl(_address).hasRole(role, _owner), string.concat(name, " should have DEFAULT_ADMIN_ROLE")
            );
        } else if (role == CONFIGURATOR_ROLE) {
            assertTrue(
                AccessControl(_address).hasRole(role, _owner), string.concat(name, " should have CONFIGURATOR_ROLE")
            );
        } else if (role == SWAP_FREEZER_ROLE) {
            assertTrue(
                AccessControl(_address).hasRole(role, _owner), string.concat(name, " should have SWAP_FREEZER_ROLE")
            );
        } else if (role == TOKEN_RESCUER_ROLE) {
            assertTrue(
                AccessControl(_address).hasRole(role, _owner), string.concat(name, " should have TOKEN_RESCUER_ROLE")
            );
        } else if (role == LIQUIDATOR_ROLE) {
            assertTrue(
                AccessControl(_address).hasRole(role, _owner), string.concat(name, " should have LIQUIDATOR_ROLE")
            );
        } else if (role == SWAPPER_ROLE) {
            assertTrue(AccessControl(_address).hasRole(role, _owner), string.concat(name, " should have SWAPPER_ROLE"));
        } else {
            revert(string.concat(name, " invalid role"));
        }
    }
}


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
import {IUsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {DeployAltoEthereumMainnetTestBase, OUTPUT_DIR} from "@alto-test/deployments/DeployAltoEthereumMainnet.t.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {DirectionAccess} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {IAdvancedPermissionsUsm} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {SimpleLiquidator} from "@alto-test/lending/liquidation/helpers/SimpleLiquidator.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";
import {
    ZEROX_SWAP_TARGET_MAINNET,
    ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET,
    BUNDLER3_MAINNET,
    USDC_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IAltoVault, IAltoVaultBase, IAltoVaultStaticTypes} from "@alto/lending/interfaces/IAltoVault.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {IMarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {UniversalRewardsDistributor} from "@alto/utils/UniversalRewardsDistributor.sol";
import {IMerkleRootManager} from "@alto/utils/interfaces/IMerkleRootManager.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {EmergencyController} from "@alto/utils/EmergencyController.sol";

interface ISafeOwners {
    function getOwners() external view returns (address[] memory);
}

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
            treasuryMultisig: address(1), // TODO: Set to actual treasury multisig address
            updater: MERKLE_ROOT_UPDATER,
            deployerHasOwnership: true // Deployer has ownership in tests, execute directly
        });
        input.contracts.emergencyController = makeAddr("EMERGENCY_CONTROLLER");
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

    function test_deployPhase_PERMISSIONED_FRXUSD_USM() public {
        _deployPrerequisites(DeploymentPhase.PERMISSIONED_FRXUSD_USM);

        params.phase = DeploymentPhase.PERMISSIONED_FRXUSD_USM;
        params.deployerHasOwnership = false;
        params.treasuryMultisig = address(0xA1148A1b94262540994Cf9Aa431A13ad39764228);
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address usm = input.contracts.permissionedFrxusdUsm.dusdUsm;
        uint256 mintCeiling = 5_000_000_000 ether;

        vm.startPrank(input.contracts.timelock);
        IDUSD(input.contracts.dusd).setMinterStatus(usm, true);
        IDUSD(input.contracts.dusd).setMinterCeiling(usm, mintCeiling);
        IDUSD(input.contracts.dusd).setBurnerStatus(usm, true);
        IUsmRegistry(input.contracts.usmRegistry).addUsm(usm);
        vm.stopPrank();

        address impl = input.contracts.permissionedFrxusdUsm.dusdUsmImplementation;
        address priceStrategy = input.contracts.permissionedFrxusdUsm.fixedPriceStrategy;
        address feeStrategy = input.contracts.permissionedFrxusdUsm.fixedFeeStrategy;
        address timelock = input.contracts.timelock;

        _verifyDeployed(usm, "frxUSD USM proxy");
        _verifyDeployed(impl, "frxUSD USM implementation");
        _verifyDeployed(priceStrategy, "frxUSD FixedPriceStrategy");
        assertEq(feeStrategy, address(0), "permissioned USM should have no fee strategy");

        assertEq(
            uint256(IUsm(usm).getAccessMode()), uint256(AccessMode.PERMISSIONED), "access mode should be PERMISSIONED"
        );

        assertEq(IUsm(usm).priceStrategy(), priceStrategy, "price strategy mismatch");
        assertEq(
            AccessControl(priceStrategy).hasRole(DEFAULT_ADMIN_ROLE, timelock),
            true,
            "timelock should own price strategy"
        );

        _verifyHasRole(usm, timelock, DEFAULT_ADMIN_ROLE, "frxUSD USM");
        _verifyHasRole(usm, timelock, CONFIGURATOR_ROLE, "frxUSD USM");
        _verifyHasRole(usm, MULTISIG_FREEZER_PAUSER, SWAP_FREEZER_ROLE, "frxUSD USM");
        _verifyHasRole(usm, params.treasuryMultisig, SWAPPER_ROLE, "frxUSD USM");

        assertFalse(
            AccessControl(usm).hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER),
            "deployer should not retain DEFAULT_ADMIN_ROLE on USM"
        );
        assertFalse(
            AccessControl(usm).hasRole(CONFIGURATOR_ROLE, DEPLOYER),
            "deployer should not retain CONFIGURATOR_ROLE on USM"
        );
        assertEq(IUsm(usm).UNDERLYING_ASSET(), FRXUSD_MAINNET, "underlying asset should be frxUSD");
        assertEq(IUsm(usm).getExposureCap(), mintCeiling, "exposure cap mismatch");

        _verifyMintCeiling(usm, mintCeiling);
        assertTrue(IUsmRegistry(input.contracts.usmRegistry).isUsm(usm), "USM not registered in UsmRegistry");
    }
}

abstract contract DeployAltoEthereumMainnetDeprecatedTestBase is DeployAltoEthereumMainnetTestBase {
    function _assertTresuryPSMMigration() internal {
        address frxUsdPsm = input.contracts.permissionedFrxusdUsm.dusdUsm;
        assertTrue(frxUsdPsm != address(0), "permissioned frxUSD USM required from addresses.json");

        address treasury = params.treasuryMultisig;
        IERC4626 fraxCustodian = IERC4626(0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c);
        address usdcPsm = input.contracts.permissionedUsm.dusdUsm;

        uint256 usdcAmount = 200_000e6;

        uint256 usdcPsmExposureBefore = IUsm(usdcPsm).getAvailableLiquidity();

        deal(USDC_MAINNET, treasury, usdcAmount);

        vm.startPrank(treasury);

        IERC20Metadata(USDC_MAINNET).approve(address(fraxCustodian), usdcAmount);

        uint256 frxUsdReceived = fraxCustodian.deposit(usdcAmount, treasury);

        assertEq(frxUsdReceived, 200_000 ether, "frxUSD received mismatch");

        IERC20Metadata(FRXUSD_MAINNET).approve(frxUsdPsm, frxUsdReceived);
        (uint256 assetAmount, uint256 dusdBought) = IUsm(frxUsdPsm).sellAsset(frxUsdReceived, treasury);
        assertEq(assetAmount, frxUsdReceived, "asset amount mismatch");
        assertEq(dusdBought, 200_000 ether, "dusd bought mismatch");

        IERC20Metadata(input.contracts.dusd).approve(usdcPsm, dusdBought);
        IUsm(usdcPsm).buyAsset(usdcAmount, treasury);

        vm.stopPrank();

        uint256 frxUsdPsmExposure = IUsm(frxUsdPsm).getAvailableLiquidity();
        assertEq(frxUsdPsmExposure, 200_000 ether, "frxUSD PSM exposure mismatch");

        uint256 usdcPsmExposureAfter = IUsm(usdcPsm).getAvailableLiquidity();
        assertEq(usdcPsmExposureBefore - usdcPsmExposureAfter, usdcAmount, "USDC PSM exposure reduction mismatch");
    }

    /// @dev Exercises `DeploymentPhase.ADAPTER` / `_deployAdapterAndApproval` against addresses loaded from
    ///      a prior deployment (requires `DEPLOYMENT_ID_TO_LOAD` and a valid `addresses.json`).
    function _assertDeployAdapterAndApproval() internal {
        address previousAdapter = input.contracts.altoAdapter;
        assertTrue(
            previousAdapter != address(0) && previousAdapter.code.length > 0,
            "need prior altoAdapter from addresses.json"
        );

        params.phase = DeploymentPhase.ADAPTER;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address adapter = input.contracts.altoAdapter;
        assertTrue(adapter != previousAdapter, "adapter should be redeployed");
        assertEq(Ownable(adapter).owner(), input.contracts.timelock, "adapter owner should be timelock");
        assertEq(address(AltoAdapter(payable(adapter)).WRAPPED_NATIVE()), WETH_MAINNET, "WETH");
        assertEq(AltoAdapter(payable(adapter)).BUNDLER3(), BUNDLER3_MAINNET, "Bundler3");

        address[] memory candidates = new address[](17);
        candidates[0] = input.contracts.wethMarket.market;
        candidates[1] = input.contracts.wstethMarket.market;
        candidates[2] = input.contracts.rethMarket.market;
        candidates[3] = input.contracts.methMarket.market;
        candidates[4] = input.contracts.tbtcMarket.market;
        candidates[5] = input.contracts.wbtcBorrowMarket.market;
        candidates[6] = input.contracts.cbbtcBorrowMarket.market;
        candidates[7] = input.contracts.susdeBorrowMarket.market;
        candidates[8] = input.contracts.syrupUsdcBorrowMarket.market;
        candidates[9] = input.contracts.paxgBorrowMarket.market;
        candidates[10] = input.contracts.susdeMintMarket.market;
        candidates[11] = input.contracts.syrupUsdcMintMarket.market;
        candidates[12] = input.contracts.permissionlessUsm.dusdUsm;
        candidates[13] = input.contracts.permissionedUsm.dusdUsm;
        candidates[14] = input.contracts.permissionedFrxusdUsm.dusdUsm;
        candidates[15] = input.contracts.permissionlessFrxusdUsm.dusdUsm;
        candidates[16] = input.contracts.referralAdapter;

        for (uint256 i; i < candidates.length; ++i) {
            address candidate = candidates[i];
            if (candidate == address(0)) continue;

            bool previousApproval = AltoAdapter(payable(previousAdapter)).isApprovedContract(candidate);
            bool newApproval = AltoAdapter(payable(adapter)).isApprovedContract(candidate);

            assertEq(
                newApproval,
                previousApproval,
                string.concat("adapter approval mismatch for ", Strings.toHexString(uint256(uint160(candidate)), 20))
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DUSD_VAULT
    // ─────────────────────────────────────────────────────────────────────────

    // NOTE: @dev remove this test once frxUSD is deployed on-chain
    //       @dev move this test to deprecated folder
    function _assertDeployDusdVault() internal {
        deal(input.contracts.dusd, DEPLOYER, 1 ether);

        params.phase = DeploymentPhase.DUSD_VAULT;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address vault = input.contracts.dusdVault;
        address timelock = input.contracts.timelock;

        _verifyDeployed(vault, "dusdVault");

        assertEq(IERC20Metadata(vault).name(), "Alto DUSD Vault", "vault name mismatch");
        assertEq(IERC20Metadata(vault).symbol(), "aDUSD", "vault symbol mismatch");
        assertEq(IERC4626(vault).asset(), input.contracts.dusd, "vault asset mismatch");

        assertEq(Ownable(vault).owner(), timelock, "vault owner should be timelock");

        assertEq(IAltoVaultBase(vault).curator(), MULTISIG_TIMELOCK_ADMIN, "curator mismatch");
        assertTrue(IAltoVaultBase(vault).isAllocator(MERKLE_ROOT_UPDATER), "allocator mismatch");
        assertEq(IAltoVaultBase(vault).guardian(), MULTISIG_FREEZER_PAUSER, "guardian mismatch");

        assertEq(IAltoVaultBase(vault).fee(), 0, "fee should be zero");
        assertEq(IAltoVaultBase(vault).feeRecipient(), input.contracts.feeRecipient, "feeRecipient mismatch");
        assertEq(IAltoVaultBase(vault).skimRecipient(), params.treasuryMultisig, "skimRecipient mismatch");

        assertEq(IAltoVaultBase(vault).timelock(), 1 days, "vault timelock mismatch");

        address[5] memory expectedMarkets = [
            input.contracts.syrupUsdcBorrowMarket.market,
            input.contracts.susdeBorrowMarket.market,
            input.contracts.paxgBorrowMarket.market,
            input.contracts.wbtcBorrowMarket.market,
            input.contracts.cbbtcBorrowMarket.market
        ];

        assertEq(IAltoVaultBase(vault).supplyQueueLength(), 5, "supply queue length mismatch");
        for (uint256 i; i < 5; ++i) {
            assertEq(IAltoVaultBase(vault).supplyQueue(i), expectedMarkets[i], "supply queue order mismatch");
            if (i < 3) {
                assertEq(IAltoVault(vault).config(expectedMarkets[i]).cap, 62_000 ether, "market cap mismatch");
            } else {
                assertEq(IAltoVault(vault).config(expectedMarkets[i]).cap, 10_000 ether, "market cap mismatch");
            }
        }
    }

    // NOTE: @dev remove this test once vault registry is deployed on-chain
    //       @dev move this test to deprecated folder
    function _assertDeployVaultRegistry() internal {
        _assertDeployDusdVault();

        params.phase = DeploymentPhase.VAULT_REGISTRY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address vaultRegistry = input.contracts.vaultRegistry;
        address timelock = input.contracts.timelock;

        _verifyDeployed(vaultRegistry, "vaultRegistry");

        assertEq(Ownable(vaultRegistry).owner(), timelock, "vaultRegistry owner should be timelock");

        assertEq(VaultRegistry(vaultRegistry).isVault(input.contracts.dusdVault), true, "vault should be registered");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PERMISSIONLESS_FRXUSD_USM
    // ─────────────────────────────────────────────────────────────────────────

    function _deployPermissionlessFrxUsdPsm() internal {
        input.contracts.emergencyController = FUTURE_EMERGENCY_CONTROLLER;
        params.phase = DeploymentPhase.PERMISSIONLESS_FRXUSD_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address usm = input.contracts.permissionlessFrxusdUsm.dusdUsm;
        uint256 mintCeiling = 500_000 ether;

        vm.startPrank(input.contracts.timelock);
        IDUSD(input.contracts.dusd).setMinterStatus(usm, true);
        IDUSD(input.contracts.dusd).setMinterCeiling(usm, mintCeiling);
        IDUSD(input.contracts.dusd).setBurnerStatus(usm, true);
        IUsmRegistry(input.contracts.usmRegistry).addUsm(usm);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(usm);
        vm.stopPrank();
    }

    function _assertDeployPermissionlessFrxUsdPsm() internal {
        _deployPermissionlessFrxUsdPsm();

        address usm = input.contracts.permissionlessFrxusdUsm.dusdUsm;
        address impl = input.contracts.permissionlessFrxusdUsm.dusdUsmImplementation;
        address priceStrategy = input.contracts.permissionlessFrxusdUsm.fixedPriceStrategy;
        address feeStrategy = input.contracts.permissionlessFrxusdUsm.fixedFeeStrategy;
        address timelock = input.contracts.timelock;

        _verifyDeployed(usm, "permissionless frxUSD USM proxy");
        _verifyDeployed(impl, "permissionless frxUSD USM implementation");
        _verifyDeployed(priceStrategy, "permissionless frxUSD FixedPriceStrategy");
        _verifyDeployed(feeStrategy, "permissionless frxUSD FixedFeeStrategy");

        assertEq(
            uint256(IUsm(usm).getAccessMode()),
            uint256(AccessMode.PERMISSIONLESS),
            "access mode should be PERMISSIONLESS"
        );

        assertEq(IUsm(usm).priceStrategy(), priceStrategy, "price strategy mismatch");
        assertEq(
            AccessControl(priceStrategy).hasRole(DEFAULT_ADMIN_ROLE, timelock),
            true,
            "timelock should own price strategy"
        );

        _verifyHasRole(usm, timelock, DEFAULT_ADMIN_ROLE, "permissionless frxUSD USM");
        _verifyHasRole(usm, timelock, CONFIGURATOR_ROLE, "permissionless frxUSD USM");
        _verifyHasRole(usm, MULTISIG_FREEZER_PAUSER, SWAP_FREEZER_ROLE, "permissionless frxUSD USM");
        _verifyHasRole(
            usm,
            FUTURE_EMERGENCY_CONTROLLER,
            IUsm(usm).SWAP_FREEZER_ROLE(),
            "permissionless frxUSD USM emergency controller"
        );

        // Deployer must have revoked its own admin and configurator roles
        assertFalse(
            AccessControl(usm).hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER),
            "deployer should not retain DEFAULT_ADMIN_ROLE on USM"
        );
        assertFalse(
            AccessControl(usm).hasRole(CONFIGURATOR_ROLE, DEPLOYER),
            "deployer should not retain CONFIGURATOR_ROLE on USM"
        );

        assertEq(IUsm(usm).UNDERLYING_ASSET(), FRXUSD_MAINNET, "underlying asset should be frxUSD");
        assertEq(IUsm(usm).getExposureCap(), 500_000 ether, "exposure cap should be 500,000 frxUSD");

        _verifyMintCeiling(usm, 500_000 ether);
        assertTrue(IUsmRegistry(input.contracts.usmRegistry).isUsm(usm), "USM not registered in UsmRegistry");
    }

    function _assertPermissionlessFrxUsdUsmBuyAndSell() internal {
        _deployPermissionlessFrxUsdPsm();

        address usm = input.contracts.permissionlessFrxusdUsm.dusdUsm;
        address randomUser = makeAddr("randomUser");
        uint256 frxUsdAmount = 1_000 ether;

        // Fund random user with frxUSD and have them sell it into the USM (receive DUSD)
        deal(FRXUSD_MAINNET, randomUser, frxUsdAmount);

        vm.startPrank(randomUser);
        IERC20Metadata(FRXUSD_MAINNET).approve(usm, frxUsdAmount);
        (uint256 assetSold, uint256 dusdReceived) = IUsm(usm).sellAsset(frxUsdAmount, randomUser);
        vm.stopPrank();

        assertEq(assetSold, frxUsdAmount, "asset sold mismatch");
        assertEq(dusdReceived, 999.5 ether, "DUSD received should be 0.05% less than frxUSD sold");
        assertEq(IERC20Metadata(FRXUSD_MAINNET).balanceOf(randomUser), 0, "user should have no frxUSD left");
        assertEq(IERC20Metadata(input.contracts.dusd).balanceOf(randomUser), dusdReceived, "user DUSD balance mismatch");
    }
}

contract DeployPermissionlessFrxUsdPsmTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployPermissionlessFrxUsdPsm() public {
        _assertDeployPermissionlessFrxUsdPsm();
    }

    function test_permissionlessFrxUsdUsmBuyAndSell() public {
        _assertPermissionlessFrxUsdUsmBuyAndSell();
    }
}

contract TresuryPSMMigrationTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_TresuryPSMMigration() public {
        _assertTresuryPSMMigration();
    }
}

contract DeployAdapterPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployAdapterAndApproval() public {
        _assertDeployAdapterAndApproval();
    }
}

contract DeployLeverageSwapperMultiTargetPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployLeverageSwapperMultiTarget() public {
        _assertDeployLeverageSwapperMultiTarget();
    }

    function _assertDeployLeverageSwapperMultiTarget() internal {
        assertTrue(input.contracts.timelock != address(0), "need timelock from addresses.json");
        assertTrue(input.contracts.wethMarket.leverage != address(0), "need weth leverage from addresses.json");

        MarketContracts[12] memory marketsBefore = _allMarkets();
        address[] memory oldSwappers = new address[](marketsBefore.length);
        for (uint256 i; i < marketsBefore.length; ++i) {
            assertTrue(marketsBefore[i].leverage != address(0), "market leverage missing");
            assertTrue(marketsBefore[i].leverageSwapper != address(0), "market leverageSwapper missing");
            oldSwappers[i] = marketsBefore[i].leverageSwapper;
        }

        params.phase = DeploymentPhase.ALTO_LEVERAGE_SWAPPER_MULTI_TARGET;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        for (uint256 i; i < marketsBefore.length; ++i) {
            MarketContracts memory market = _marketByLeverage(marketsBefore[i].leverage);
            address newSwapper = market.leverageSwapper;
            address leverage = marketsBefore[i].leverage;

            assertTrue(newSwapper != oldSwappers[i], "swapper should be redeployed");
            assertTrue(newSwapper.code.length > 0, "new swapper should have code");

            AltoLeverageSwapperMultiTarget swapper = AltoLeverageSwapperMultiTarget(newSwapper);
            assertEq(Ownable(newSwapper).owner(), input.contracts.timelock, "swapper owner should be timelock");
            assertTrue(swapper.isWhitelisted(leverage), "leverage should be whitelisted on swapper");
            _verifyValidSwapTargets(swapper);

            assertEq(
                address(AltoLeverage(leverage).swapper()),
                oldSwappers[i],
                "AltoLeverage swapper unchanged until timelock executes setSwapper"
            );
        }

        assertTrue(
            vm.exists(
                "contracts/deployments/ethereum-mainnet/output/safe-tx-leverage-swapper-set-swapper-schedule.json"
            ),
            "schedule json should be written"
        );
        assertTrue(
            vm.exists(
                "contracts/deployments/ethereum-mainnet/output/safe-tx-leverage-swapper-set-swapper-execute.json"
            ),
            "execute json should be written"
        );
    }

    function _allMarkets() internal view returns (MarketContracts[12] memory markets) {
        markets = [
            input.contracts.wethMarket,
            input.contracts.wstethMarket,
            input.contracts.rethMarket,
            input.contracts.methMarket,
            input.contracts.tbtcMarket,
            input.contracts.wbtcBorrowMarket,
            input.contracts.cbbtcBorrowMarket,
            input.contracts.susdeBorrowMarket,
            input.contracts.syrupUsdcBorrowMarket,
            input.contracts.paxgBorrowMarket,
            input.contracts.susdeMintMarket,
            input.contracts.syrupUsdcMintMarket
        ];
    }

    function _marketByLeverage(address leverage) internal view returns (MarketContracts memory market) {
        MarketContracts[12] memory markets = _allMarkets();
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i].leverage == leverage) {
                return _getMarketByIndex(i);
            }
        }
        revert("market not found");
    }

    function _getMarketByIndex(uint256 index) internal view returns (MarketContracts memory market) {
        if (index == 0) return input.contracts.wethMarket;
        if (index == 1) return input.contracts.wstethMarket;
        if (index == 2) return input.contracts.rethMarket;
        if (index == 3) return input.contracts.methMarket;
        if (index == 4) return input.contracts.tbtcMarket;
        if (index == 5) return input.contracts.wbtcBorrowMarket;
        if (index == 6) return input.contracts.cbbtcBorrowMarket;
        if (index == 7) return input.contracts.susdeBorrowMarket;
        if (index == 8) return input.contracts.syrupUsdcBorrowMarket;
        if (index == 9) return input.contracts.paxgBorrowMarket;
        if (index == 10) return input.contracts.susdeMintMarket;
        if (index == 11) return input.contracts.syrupUsdcMintMarket;
        revert("invalid market index");
    }
}

contract DeployLiquidationPeripheryPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployLiquidationPeriphery() public {
        _assertDeployLiquidationPeriphery();
    }

    function _assertDeployLiquidationPeriphery() internal {
        assertTrue(input.contracts.timelock != address(0), "need timelock from addresses.json");
        assertTrue(input.contracts.dusd != address(0), "need dusd from addresses.json");
        assertTrue(input.contracts.usmRegistry != address(0), "need usmRegistry from addresses.json");
        if (input.contracts.liquidationPeriphery.code.length > 0) {
            return;
        }

        MarketContracts[12] memory marketsBefore = _allMarkets();

        params.phase = DeploymentPhase.LIQUIDATION_PERIPHERY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address periphery = input.contracts.liquidationPeriphery;
        assertTrue(periphery != address(0), "periphery should be deployed");
        assertTrue(periphery.code.length > 0, "periphery should have code");

        LiquidationPeriphery peripheryContract = LiquidationPeriphery(periphery);
        assertEq(Ownable(periphery).owner(), input.contracts.timelock, "periphery owner should be timelock");
        assertEq(peripheryContract.BORROW_TOKEN(), input.contracts.dusd, "borrow token should be DUSD");
        assertEq(peripheryContract.usmRegistry(), input.contracts.usmRegistry, "usm registry mismatch");
        assertEq(peripheryContract.treasury(), params.treasuryMultisig, "treasury mismatch");

        for (uint256 i; i < marketsBefore.length; ++i) {
            assertTrue(
                peripheryContract.supportedMarkets(marketsBefore[i].market), "market should be supported on periphery"
            );
        }
    }

    function _allMarkets() internal view returns (MarketContracts[12] memory markets) {
        markets = [
            input.contracts.wethMarket,
            input.contracts.wstethMarket,
            input.contracts.rethMarket,
            input.contracts.methMarket,
            input.contracts.tbtcMarket,
            input.contracts.wbtcBorrowMarket,
            input.contracts.cbbtcBorrowMarket,
            input.contracts.susdeBorrowMarket,
            input.contracts.syrupUsdcBorrowMarket,
            input.contracts.paxgBorrowMarket,
            input.contracts.susdeMintMarket,
            input.contracts.syrupUsdcMintMarket
        ];
    }
}

contract DeployAdvancedPermissionsFrxUsdUsmPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    bytes32 internal constant BUY_SWAPPER_ROLE = keccak256("BUY_SWAPPER_ROLE");
    bytes32 internal constant SELL_SWAPPER_ROLE = keccak256("SELL_SWAPPER_ROLE");

    uint256 internal constant BUY_FEE_BPS = 5; // 0.05%
    uint256 internal constant SELL_FEE_BPS = 0;

    function test_deployAdvancedPermissionsFrxUsdUsm() public {
        _assertDeployAdvancedPermissionsFrxUsdUsm();
    }

    function _assertDeployAdvancedPermissionsFrxUsdUsm() internal {
        _ensureLiquidationPeripheryDeployed();
        input.contracts.advancedPermissionsFrxusdUsm.dusdUsm = address(0);
        input.contracts.emergencyController = FUTURE_EMERGENCY_CONTROLLER;

        params.phase = DeploymentPhase.ADVANCED_PERMISSIONS_FRXUSD_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address usm = input.contracts.advancedPermissionsFrxusdUsm.dusdUsm;
        address impl = input.contracts.advancedPermissionsFrxusdUsm.dusdUsmImplementation;
        address priceStrategy = input.contracts.advancedPermissionsFrxusdUsm.fixedPriceStrategy;
        address feeStrategy = input.contracts.advancedPermissionsFrxusdUsm.advancedPermissionsFeeStrategy;
        address timelock = input.contracts.timelock;
        address periphery = input.contracts.liquidationPeriphery;
        uint256 mintCeiling = 5_000_000_000 ether;

        _verifyDeployed(usm, "advanced permissions frxUSD USM proxy");
        _verifyDeployed(impl, "advanced permissions frxUSD USM implementation");
        _verifyDeployed(priceStrategy, "advanced permissions frxUSD FixedPriceStrategy");
        _verifyDeployed(feeStrategy, "advanced permissions frxUSD FeeStrategy");

        DUSDAdvancedPermissionsUsm usmContract = DUSDAdvancedPermissionsUsm(usm);
        assertEq(
            uint256(usmContract.getBuyAccess()),
            uint256(DirectionAccess.PERMISSIONLESS),
            "buy access should be permissionless"
        );
        assertEq(
            uint256(usmContract.getSellAccess()),
            uint256(DirectionAccess.PERMISSIONED),
            "sell access should be permissioned"
        );
        assertEq(usmContract.UNDERLYING_ASSET(), FRXUSD_MAINNET, "underlying asset should be frxUSD");
        assertEq(usmContract.getExposureCap(), mintCeiling, "exposure cap mismatch");
        assertEq(FixedPriceStrategy(priceStrategy).priceRatio(), 1 ether, "price ratio should be 1:1 with DUSD");
        assertEq(FixedPriceStrategy(priceStrategy).UNDERLYING_ASSET(), FRXUSD_MAINNET, "price strategy underlying");
        assertEq(usmContract.getFeeStrategy(), feeStrategy, "fee strategy mismatch");
        assertEq(usmContract.getFeeRecipient(), input.contracts.feeRecipient, "fee recipient mismatch");

        _verifyHasRole(usm, timelock, DEFAULT_ADMIN_ROLE, "advanced permissions frxUSD USM");
        _verifyHasRole(usm, timelock, CONFIGURATOR_ROLE, "advanced permissions frxUSD USM");
        _verifyHasRole(usm, MULTISIG_FREEZER_PAUSER, SWAP_FREEZER_ROLE, "advanced permissions frxUSD USM");
        _verifyHasRole(
            usm,
            FUTURE_EMERGENCY_CONTROLLER,
            usmContract.SWAP_FREEZER_ROLE(),
            "advanced permissions frxUSD USM emergency controller"
        );
        _verifyHasRole(priceStrategy, timelock, DEFAULT_ADMIN_ROLE, "advanced permissions frxUSD price strategy");
        _verifyHasRole(feeStrategy, timelock, DEFAULT_ADMIN_ROLE, "advanced permissions frxUSD fee strategy");
        _verifyHasRole(feeStrategy, timelock, CONFIGURATOR_ROLE, "advanced permissions frxUSD fee strategy");

        assertTrue(usmContract.hasRole(SELL_SWAPPER_ROLE, periphery), "periphery should have sell swapper role");
        assertFalse(usmContract.hasRole(BUY_SWAPPER_ROLE, periphery), "periphery should not have buy swapper role");

        AdvancedPermissionsFeeStrategy strategy = AdvancedPermissionsFeeStrategy(feeStrategy);
        assertEq(strategy.getDefaultBuyFee(), BUY_FEE_BPS, "default buy fee mismatch");
        assertEq(strategy.getDefaultSellFee(), SELL_FEE_BPS, "default sell fee mismatch");

        address randomUser = makeAddr("randomUser");
        assertEq(strategy.getBuyFeeForUser(randomUser), BUY_FEE_BPS, "random user buy fee mismatch");
        assertEq(strategy.getSellFeeForUser(randomUser), SELL_FEE_BPS, "random user sell fee mismatch");
        assertEq(strategy.getSellFeeForUser(periphery), 0, "periphery sell fee should be zero");
        assertEq(strategy.getUserBuyFeeRole(periphery), bytes32(0), "periphery should have no buy fee role");
        assertEq(strategy.getUserSellFeeRole(periphery), bytes32(0), "periphery should have no sell fee role");

        assertTrue(
            vm.exists(
                "contracts/deployments/ethereum-mainnet/output/safe-tx-frxusd-advanced-permissions-usm-registry-schedule.json"
            ),
            "schedule json should be written"
        );
        assertTrue(
            vm.exists(
                "contracts/deployments/ethereum-mainnet/output/safe-tx-frxusd-advanced-permissions-usm-registry-execute.json"
            ),
            "execute json should be written"
        );

        vm.startPrank(timelock);
        IDUSD(input.contracts.dusd).setMinterStatus(usm, true);
        IDUSD(input.contracts.dusd).setMinterCeiling(usm, mintCeiling);
        IDUSD(input.contracts.dusd).setBurnerStatus(usm, true);
        IUsmRegistry(input.contracts.usmRegistry).addUsm(usm);
        vm.stopPrank();

        _verifyMintCeiling(usm, mintCeiling);
        assertTrue(IUsmRegistry(input.contracts.usmRegistry).isUsm(usm), "USM not registered in UsmRegistry");
    }

    function test_liquidateViaPeriphery_afterAdvancedPermissionsFrxUsdUsmDeployment() public {
        _deployPeripheryAndAdvancedPermissionsFrxUsdUsm();
        _assertLiquidationViaPeripheryOnFork();
    }

    function _ensureLiquidationPeripheryDeployed() internal {
        if (input.contracts.liquidationPeriphery.code.length == 0) {
            params.phase = DeploymentPhase.LIQUIDATION_PERIPHERY;
            input = DeployAltoEthereumMainnet.deploy(params, input);
        }
        assertTrue(input.contracts.liquidationPeriphery != address(0), "need liquidation periphery");
    }

    function _deployPeripheryAndAdvancedPermissionsFrxUsdUsm() internal {
        _ensureLiquidationPeripheryDeployed();
        _deployAndFinalizeAdvancedPermissionsFrxUsdUsm();
    }

    function _deployAndFinalizeAdvancedPermissionsFrxUsdUsm() internal {
        assertTrue(input.contracts.liquidationPeriphery != address(0), "need liquidation periphery from addresses.json");

        input.contracts.emergencyController = FUTURE_EMERGENCY_CONTROLLER;
        params.phase = DeploymentPhase.ADVANCED_PERMISSIONS_FRXUSD_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address usm = input.contracts.advancedPermissionsFrxusdUsm.dusdUsm;
        uint256 mintCeiling = 5_000_000_000 ether;

        vm.startPrank(input.contracts.timelock);
        IDUSD(input.contracts.dusd).setMinterStatus(usm, true);
        IDUSD(input.contracts.dusd).setMinterCeiling(usm, mintCeiling);
        IDUSD(input.contracts.dusd).setBurnerStatus(usm, true);
        IUsmRegistry(input.contracts.usmRegistry).addUsm(usm);
        vm.stopPrank();
    }

    function _assertLiquidationViaPeripheryOnFork() internal {
        address market = input.contracts.wethMarket.market;
        address periphery = input.contracts.liquidationPeriphery;
        address usm = input.contracts.advancedPermissionsFrxusdUsm.dusdUsm;
        address borrower = makeAddr("LiquidationBorrower");
        address liquidatorEoa = makeAddr("LiquidationEoa");

        assertTrue(LiquidationPeriphery(periphery).supportedMarkets(market), "weth market should be supported");
        assertTrue(IUsmRegistry(input.contracts.usmRegistry).isUsm(usm), "USM should be registered");

        _upgradeMintMarketAndAuthorizePeriphery(market, periphery);

        MockSwapper swapper = new MockSwapper();
        SimpleLiquidator simpleLiquidator = new SimpleLiquidator(periphery, usm, address(swapper));

        _setupInsolventWethMintPosition(market, borrower);

        uint256 repayBound = 10_000 ether;
        (uint256 assetAmount,,,) = IAdvancedPermissionsUsm(usm).getAssetAmountForSellAsset(repayBound, periphery);
        deal(FRXUSD_MAINNET, address(simpleLiquidator), assetAmount);
        vm.prank(address(simpleLiquidator));
        IERC20(FRXUSD_MAINNET).approve(periphery, type(uint256).max);

        vm.prank(liquidatorEoa);
        (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee) =
            simpleLiquidator.liquidateMarket(market, borrower, usm, "", "");

        assertGt(seizedCollateral, 0, "seized collateral");
        assertGt(repaidBorrow, 0, "repaid borrow");
        assertGt(protocolFee, 0, "protocol fee");
        assertGt(seizedCollateral, protocolFee, "liquidator receives net collateral");

        assertEq(IERC20(input.contracts.dusd).balanceOf(address(periphery)), 0, "periphery DUSD dust");
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(periphery)), 0, "periphery frxUSD dust");
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(periphery)), 0, "periphery WETH dust");
        assertEq(IERC20(input.contracts.dusd).allowance(periphery, market), 0, "periphery borrow approval reset");
        assertEq(IERC20(FRXUSD_MAINNET).allowance(periphery, usm), 0, "periphery frxUSD approval to USM reset");
    }

    function _upgradeMintMarketAndAuthorizePeriphery(address market, address periphery) internal {
        address marketOwner = Ownable(market).owner();

        vm.startPrank(marketOwner);
        UnsafeUpgrades.upgradeProxy(market, address(new AltoMintMarket()), "");
        IMarket(market).setAuthorizedLiquidationPeriphery(periphery, true);
        vm.stopPrank();
    }

    function _setupInsolventWethMintPosition(address market, address borrower) internal {
        IMarket wethMarket = IMarket(market);

        deal(WETH_MAINNET, borrower, 10 ether);

        vm.startPrank(borrower);
        IERC20(WETH_MAINNET).approve(market, type(uint256).max);
        wethMarket.setAuthorization(address(this), true);
        wethMarket.addCollateral(2 ether, borrower);
        wethMarket.borrow(2000 ether, 0, borrower, borrower, "");
        vm.stopPrank();

        wethMarket.accrueInterest();

        address oracle = wethMarket.oracle();
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(ILendingOracle.getPrice.selector),
            abi.encode(1000 * LENDING_ORACLE_PRICE_PRECISION)
        );
    }
}

contract DeployUpgradeMarketsLiquidationPeripheryPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    string internal constant UPGRADE_SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-upgrade-liquidation-periphery-schedule.json";
    string internal constant UPGRADE_EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-upgrade-liquidation-periphery-execute.json";
    string internal constant AUTHORIZE_SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-authorize-liquidation-periphery-schedule.json";
    string internal constant AUTHORIZE_EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-authorize-liquidation-periphery-execute.json";

    function test_upgradeMarketsForLiquidationPeriphery() public {
        _assertUpgradeMarketsForLiquidationPeriphery();
    }

    function _assertUpgradeMarketsForLiquidationPeriphery() internal {
        assertTrue(input.contracts.timelock != address(0), "need timelock from addresses.json");

        MarketContracts[12] memory marketsBefore = _allMarkets();
        for (uint256 i; i < marketsBefore.length; ++i) {
            assertTrue(marketsBefore[i].market != address(0), "market should be deployed");
            assertTrue(marketsBefore[i].marketImplementation != address(0), "market impl should be set");
        }

        if (input.contracts.liquidationPeriphery == address(0)) {
            params.phase = DeploymentPhase.LIQUIDATION_PERIPHERY;
            input = DeployAltoEthereumMainnet.deploy(params, input);
        }
        assertTrue(input.contracts.liquidationPeriphery != address(0), "need liquidation periphery");

        params.phase = DeploymentPhase.UPGRADE_MARKETS_LIQUIDATION_PERIPHERY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address[] memory registryMarkets = _allRegistryMarkets();
        assertEq(registryMarkets.length, marketsBefore.length, "registry market count mismatch");

        MarketContracts[12] memory marketsAfter = _allMarkets();
        address mintImplementation;
        address borrowImplementation;
        for (uint256 i; i < marketsBefore.length; ++i) {
            address newImpl = marketsAfter[i].marketImplementation;
            assertTrue(newImpl != address(0), "market impl should be set");
            assertTrue(newImpl.code.length > 0, "market impl should have code");
            assertTrue(newImpl != marketsBefore[i].marketImplementation, "market impl should be new");

            MarketType marketType = IMarket(marketsAfter[i].market).MARKET_TYPE();
            if (marketType == MarketType.MINT) {
                if (mintImplementation == address(0)) {
                    mintImplementation = newImpl;
                }
                assertEq(newImpl, mintImplementation, "mint markets should share impl");
            } else if (marketType == MarketType.BORROW) {
                if (borrowImplementation == address(0)) {
                    borrowImplementation = newImpl;
                }
                assertEq(newImpl, borrowImplementation, "borrow markets should share impl");
            } else {
                revert("unsupported market type");
            }
        }
        assertTrue(mintImplementation != address(0), "mint impl should be deployed");
        assertTrue(borrowImplementation != address(0), "borrow impl should be deployed");
        assertTrue(mintImplementation != borrowImplementation, "mint and borrow impls should differ");

        for (uint256 i; i < registryMarkets.length; ++i) {
            address market = registryMarkets[i];
            address oldImpl = _marketImplementationFromInput(marketsBefore, market);
            assertEq(UnsafeUpgrades.getImplementationAddress(market), oldImpl, "pre-upgrade on-chain impl");
        }

        _executeSafeTimelockBatch(UPGRADE_SCHEDULE_JSON, UPGRADE_EXECUTE_JSON);

        for (uint256 i; i < registryMarkets.length; ++i) {
            address market = registryMarkets[i];
            address expectedImpl = _marketImplementationFromInput(marketsAfter, market);
            assertEq(UnsafeUpgrades.getImplementationAddress(market), expectedImpl, "post-upgrade on-chain impl");
        }

        _executeSafeTimelockBatch(AUTHORIZE_SCHEDULE_JSON, AUTHORIZE_EXECUTE_JSON);

        address periphery = input.contracts.liquidationPeriphery;
        for (uint256 i; i < registryMarkets.length; ++i) {
            assertTrue(
                IMarket(registryMarkets[i]).authorizedLiquidationPeriphery(periphery),
                "periphery should be authorized on market"
            );
        }
    }

    function _allRegistryMarkets() internal view returns (address[] memory markets) {
        IMarketRegistry registry = IMarketRegistry(input.contracts.marketRegistry);
        address[] memory mintMarkets = registry.getMintMarkets();
        address[] memory borrowMarkets = registry.getBorrowMarkets();
        markets = new address[](mintMarkets.length + borrowMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            markets[i] = mintMarkets[i];
        }
        for (uint256 i; i < borrowMarkets.length; ++i) {
            markets[mintMarkets.length + i] = borrowMarkets[i];
        }
    }

    function _marketImplementationFromInput(MarketContracts[12] memory markets, address market)
        internal
        pure
        returns (address implementation)
    {
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i].market == market) return markets[i].marketImplementation;
        }
        revert("market not found in input");
    }

    function _allMarkets() internal view returns (MarketContracts[12] memory markets) {
        markets = [
            input.contracts.wethMarket,
            input.contracts.wstethMarket,
            input.contracts.rethMarket,
            input.contracts.methMarket,
            input.contracts.tbtcMarket,
            input.contracts.wbtcBorrowMarket,
            input.contracts.cbbtcBorrowMarket,
            input.contracts.susdeBorrowMarket,
            input.contracts.syrupUsdcBorrowMarket,
            input.contracts.paxgBorrowMarket,
            input.contracts.susdeMintMarket,
            input.contracts.syrupUsdcMintMarket
        ];
    }
}

contract DeployUniversalRewardsDistributorPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployUniversalRewardsDistributor() public {
        _assertDeployUniversalRewardsDistributor();
    }

    function _assertDeployUniversalRewardsDistributor() internal {
        assertTrue(input.contracts.timelock != address(0), "need timelock from addresses.json");

        if (input.contracts.universalRewardsDistributor.code.length > 0) {
            return;
        }

        params.phase = DeploymentPhase.UNIVERSAL_REWARDS_DISTRIBUTOR;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address distributor = input.contracts.universalRewardsDistributor;
        assertTrue(distributor != address(0), "distributor should be deployed");
        assertTrue(distributor.code.length > 0, "distributor should have code");

        assertEq(Ownable(distributor).owner(), input.contracts.timelock, "owner should be timelock");
        assertTrue(
            IMerkleRootManager(distributor).isMerkleRootUpdater(params.updater), "updater should be merkle root updater"
        );
        assertTrue(
            UniversalRewardsDistributor(distributor).pausers(params.freezer, PAUSE_TYPE),
            "freezer should be PAUSE_TYPE pauser"
        );
        assertEq(IMerkleRootManager(distributor).merkleRootTimelock(), 1 days, "merkle root timelock should be 1 day");
    }
}

contract DeployDusdVaultPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployDusdVault() public {
        _assertDeployDusdVault();
    }
}

contract DeployVaultRegistryPhaseTest is DeployAltoEthereumMainnetDeprecatedTestBase {
    function test_deployVaultRegistry() public {
        _assertDeployVaultRegistry();
    }
}

contract DeployMarketDeprecationPhase0Test is DeployAltoEthereumMainnetDeprecatedTestBase {
    uint256 internal constant SOURCE_BLOCK = 25_782_397;
    uint256 internal constant T0_RATE_SPY = 0.1 ether / uint256(365 days);
    address internal constant PRODUCTION_FREEZER = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;

    function test_marketDeprecationPhase0GeneratedCalldataExecutesAndSetsExpectedState() public {
        address[] memory borrowMarkets = _borrowMarkets();
        address[] memory oldBorrowIrms = _currentIrms(borrowMarkets);

        _preparePhase0();
        _assertGeneratedPayloads(borrowMarkets);

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
        address[] memory newBorrowIrms = _predictedIrms(factory, borrowMarkets);
        for (uint256 i; i < newBorrowIrms.length; ++i) {
            assertEq(newBorrowIrms[i].code.length, 0, "fixed IRM deployed before Timelock execution");
        }

        _executeGeneratedBatch(_safeTxPath("schedule"), MAINNET_TIMELOCK_ADMIN);
        vm.warp(block.timestamp + TimelockController(payable(input.contracts.timelock)).getMinDelay() + 1);
        _freezeMarketsThroughEmergencyController();

        DeployAltoEthereumMainnet.preflightMarketDeprecationPhase0(params, input);
        _executeGeneratedBatch(_safeTxPath("execute"), MAINNET_TIMELOCK_ADMIN);
        input = DeployAltoEthereumMainnet.reconcileMarketDeprecationPhase0(params, input);

        _assertFinalState(borrowMarkets, oldBorrowIrms, newBorrowIrms);
    }

    function test_marketDeprecationPhase0GeneratesAtPinnedSourceBlock() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), SOURCE_BLOCK);
        _preparePhase0();

        assertTrue(vm.exists(_safeTxPath("schedule")), "schedule JSON missing");
        assertTrue(vm.exists(_safeTxPath("execute")), "execute JSON missing");
    }

    function _preparePhase0() internal {
        params.timelockAdmin = MAINNET_TIMELOCK_ADMIN;
        params.freezer = PRODUCTION_FREEZER;

        params.phase = DeploymentPhase.OWNER_FIXED_RATE_IRM_FACTORY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MARKET_DEPRECATION_PHASE_0;
        input = DeployAltoEthereumMainnet.deploy(params, input);
    }

    function _assertGeneratedPayloads(address[] memory borrowMarkets) internal view {
        string memory scheduleJson = vm.readFile(_safeTxPath("schedule"));
        _assertTransaction(scheduleJson, 0, input.contracts.timelock, TimelockController.scheduleBatch.selector);
        assertFalse(vm.keyExistsJson(scheduleJson, ".transactions[1]"), "unexpected schedule transaction");

        string memory executeJson = vm.readFile(_safeTxPath("execute"));
        for (uint256 i; i < borrowMarkets.length; ++i) {
            string memory dataPath = string.concat(".transactions[", vm.toString(i), "].data");
            _assertTransaction(executeJson, i, input.contracts.dusdVault, IAltoVaultBase.submitCap.selector);
            assertEq(
                vm.parseJsonBytes(executeJson, dataPath),
                abi.encodeCall(IAltoVaultBase.submitCap, (borrowMarkets[i], 0)),
                "wrong submitCap call"
            );
        }
        _assertTransaction(executeJson, 5, input.contracts.timelock, TimelockController.executeBatch.selector);
        assertFalse(vm.keyExistsJson(executeJson, ".transactions[6]"), "unexpected execute transaction");
    }

    function _freezeMarketsThroughEmergencyController() internal {
        address controllerAddress = input.contracts.emergencyController;
        address[] memory borrowMarkets = _borrowMarkets();
        address[] memory mintMarkets = _mintMarkets();

        vm.startPrank(input.contracts.timelock);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            Pausable(borrowMarkets[i]).setPauser(controllerAddress, FROZEN_TYPE, true);
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            Pausable(mintMarkets[i]).setPauser(controllerAddress, FROZEN_TYPE, true);
        }
        vm.stopPrank();

        EmergencyController controller = EmergencyController(controllerAddress);
        address[] memory safeOwners = ISafeOwners(address(controller.pauserSafe())).getOwners();
        vm.startPrank(safeOwners[0]);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            controller.freeze(borrowMarkets[i]);
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            controller.freeze(mintMarkets[i]);
        }
        vm.stopPrank();
    }

    function _assertTransaction(string memory json, uint256 index, address target, bytes4 selector) internal view {
        string memory prefix = string.concat(".transactions[", vm.toString(index), "]");
        assertEq(vm.parseJsonAddress(json, string.concat(prefix, ".to")), target, "wrong transaction target");
        assertEq(bytes4(vm.parseJsonBytes(json, string.concat(prefix, ".data"))), selector, "wrong selector");
    }

    function _executeGeneratedBatch(string memory path, address safe) internal {
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), safe, "wrong Safe");

        vm.startPrank(safe);
        for (uint256 i; vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]")); ++i) {
            string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
            (bool success,) = target.call(data);
            assertTrue(success, "generated call failed");
        }
        vm.stopPrank();
    }

    function _assertFinalState(
        address[] memory borrowMarkets,
        address[] memory oldBorrowIrms,
        address[] memory newBorrowIrms
    ) internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertEq(IMarket(borrowMarkets[i]).irm(), newBorrowIrms[i], "borrow IRM");
            assertEq(FixedRateIrm(newBorrowIrms[i]).market(), borrowMarkets[i], "borrow IRM binding");
            assertEq(FixedRateIrm(oldBorrowIrms[i]).market(), borrowMarkets[i], "old IRM binding");
            (uint256 rate,) = FixedRateIrm(newBorrowIrms[i]).irState();
            assertEq(rate, T0_RATE_SPY, "borrow rate");

            (uint184 cap,,) = IAltoVaultStaticTypes(input.contracts.dusdVault).config(borrowMarkets[i]);
            assertEq(cap, 0, "vault cap");
            assertEq(_storedBorrowIrm(i), newBorrowIrms[i], "stored IRM");
        }

        address[] memory mintMarkets = _mintMarkets();
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertFixedRateAndFrozen(mintMarkets[i]);
        }
        address[] memory alreadyDeprecated = _alreadyDeprecatedMintMarkets();
        for (uint256 i; i < alreadyDeprecated.length; ++i) {
            _assertFixedRateAndFrozen(alreadyDeprecated[i]);
        }
    }

    function _assertFixedRateAndFrozen(address market) internal view {
        assertTrue(IPausable(market).paused(FROZEN_TYPE), "market not frozen");
        assertFalse(IPausable(market).paused(PAUSE_TYPE), "market fully paused");
        (uint256 rate,) = FixedRateIrm(IMarket(market).irm()).irState();
        assertEq(rate, T0_RATE_SPY, "mint rate");
    }

    function _storedBorrowIrm(uint256 index) internal view returns (address) {
        if (index == 0) return input.contracts.wbtcBorrowMarket.marketIrm;
        if (index == 1) return input.contracts.cbbtcBorrowMarket.marketIrm;
        if (index == 2) return input.contracts.susdeBorrowMarket.marketIrm;
        if (index == 3) return input.contracts.syrupUsdcBorrowMarket.marketIrm;
        return input.contracts.paxgBorrowMarket.marketIrm;
    }

    function _predictedIrms(OwnerFixedRateIrmFactory factory, address[] memory markets)
        internal
        view
        returns (address[] memory irms)
    {
        irms = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = factory.predictIrmAddress(markets[i], 1, T0_RATE_SPY);
        }
    }

    function _currentIrms(address[] memory markets) internal view returns (address[] memory irms) {
        irms = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = IMarket(markets[i]).irm();
        }
    }

    function _safeTxPath(string memory action) internal pure returns (string memory) {
        return string.concat(OUTPUT_DIR, "/safe-tx-market-deprecation-phase-0-", action, ".json");
    }

    function _borrowMarkets() internal view returns (address[] memory markets) {
        markets = new address[](5);
        markets[0] = input.contracts.wbtcBorrowMarket.market;
        markets[1] = input.contracts.cbbtcBorrowMarket.market;
        markets[2] = input.contracts.susdeBorrowMarket.market;
        markets[3] = input.contracts.syrupUsdcBorrowMarket.market;
        markets[4] = input.contracts.paxgBorrowMarket.market;
    }

    function _mintMarkets() internal view returns (address[] memory markets) {
        markets = new address[](5);
        markets[0] = input.contracts.susdeMintMarket.market;
        markets[1] = input.contracts.syrupUsdcMintMarket.market;
        markets[2] = input.contracts.wethMarket.market;
        markets[3] = input.contracts.wstethMarket.market;
        markets[4] = input.contracts.rethMarket.market;
    }

    function _alreadyDeprecatedMintMarkets() internal view returns (address[] memory markets) {
        markets = new address[](2);
        markets[0] = input.contracts.methMarket.market;
        markets[1] = input.contracts.tbtcMarket.market;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Balance, IMarket, IMarketBase, MarketType} from "@alto/lending/interfaces/IMarket.sol";

import {
    DeployAltoEthereumMainnet,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeploymentPhase,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {MarketDeprecationCorrectionParams} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {
    ERC4626RatioChainlinkOracleRETH,
    IReth
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleRETH.sol";
import {
    ERC4626RatioChainlinkOracleSUSDE
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSUSDE.sol";
import {
    ERC4626RatioChainlinkOracleSYRUPUSDC,
    ISyrupAsset
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSYRUPUSDC.sol";
import {ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
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
    KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET,
    VELORA_AUGUSTUS_MAINNET,
    NORDSTERN_ROUTER_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IMarketRegistry, MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {IUsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {
    BUNDLER3_MAINNET,
    FRXUSD_MAINNET,
    USDC_MAINNET,
    WETH_MAINNET,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SUSDE_MAINNET,
    SYRUPUSDC_MAINNET,
    CHAINLINK_ETH_USD_PRICE_FEED,
    CHAINLINK_USDE_USD_PRICE_FEED,
    CHAINLINK_USDC_USD_PRICE_FEED,
    CHAINLINK_FRXUSD_USD_PRICE_FEED
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IAltoVault, IAltoVaultBase, IAltoVaultStaticTypes} from "@alto/lending/interfaces/IAltoVault.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {UniversalRewardsDistributor} from "@alto/utils/UniversalRewardsDistributor.sol";
import {IMerkleRootManager} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {MarketDeprecationDeployment} from "@alto/deployments/ethereum-mainnet/MarketDeprecationDeployment.sol";

/// @dev Set to a non-zero deployment timestamp to load a real deployment's addresses.json
///      and skip re-deploying prerequisites. The file must be at:
///      contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-<DEPLOYMENT_ID>/addresses.json
uint256 constant DEPLOYMENT_ID_TO_LOAD = 1765364975;
string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

struct ExpectedMarketParams {
    MarketType marketType;
    address collateralToken;
    uint256 maxLtv;
    uint256 borrowOpeningFee;
    uint256 capacity;
    uint256 maxLiquidationLtv;
    uint256 dynamicBonusFeeStart;
    uint256 ltvForCompleteLiquidation;
    uint256 liquidationBaseFee;
}

abstract contract DeployAltoEthereumMainnetTestBase is Test {
    address internal constant MAINNET_TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;

    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    address immutable MULTISIG_TIMELOCK_ADMIN = makeAddr("TIMELLOCK_ADMIN");
    address immutable MULTISIG_FREEZER_PAUSER = makeAddr("MULTISIG_FREEZER_PAUSER");
    address immutable STAKING_URD = makeAddr("STAKING_URD");
    address immutable MERKLE_ROOT_UPDATER = makeAddr("MERKLE_ROOT_UPDATER");
    address immutable FUTURE_EMERGENCY_CONTROLLER = makeAddr("FUTURE_EMERGENCY_CONTROLLER");
    address DEPLOYER;

    bytes32 immutable CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 immutable SWAP_FREEZER_ROLE = keccak256("SWAP_FREEZER_ROLE");
    bytes32 immutable TOKEN_RESCUER_ROLE = keccak256("TOKEN_RESCUER_ROLE");
    bytes32 immutable LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 immutable SWAPPER_ROLE = keccak256("SWAPPER_ROLE");
    bytes32 immutable DEFAULT_ADMIN_ROLE = bytes32(0);

    function setUp() public virtual {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        DEPLOYER = address(this);

        params = AltoEthereumMainnetParams({
            timelockAdmin: MULTISIG_TIMELOCK_ADMIN,
            timelockDelay: 2 days,
            freezer: MULTISIG_FREEZER_PAUSER,
            deployer: DEPLOYER,
            phase: DeploymentPhase.CORE,
            treasuryMultisig: address(0xA1148A1b94262540994Cf9Aa431A13ad39764228),
            updater: MERKLE_ROOT_UPDATER,
            deployerHasOwnership: false
        });

        _loadCurrentChainInput();
        if (input.contracts.emergencyController == address(0)) {
            input.contracts.emergencyController = FUTURE_EMERGENCY_CONTROLLER;
        }
    }

    function _executeSafeTimelockBatch(string memory schedulePath, string memory executePath) internal {
        TimelockController timelock = TimelockController(payable(input.contracts.timelock));
        uint256 minDelay = timelock.getMinDelay();

        bytes memory scheduleData = _readSafeTxData(schedulePath);
        bytes memory executeData = _readSafeTxData(executePath);

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool scheduled,) = address(timelock).call(scheduleData);
        assertTrue(scheduled, "timelock schedule failed");

        vm.warp(block.timestamp + minDelay + 1);

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool executed,) = address(timelock).call(executeData);
        assertTrue(executed, "timelock execute failed");
    }

    function _readSafeTxData(string memory path) internal view returns (bytes memory) {
        return vm.parseJsonBytes(vm.readFile(path), ".transactions[0].data");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // JSON input loading (mirrors DeployAltoEthereumMainnetScript)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev When DEPLOYMENT_ID_TO_LOAD != 0, loads addresses.json from a previous
    ///      deployment so the test runs the next phase against real on-chain contracts
    ///      instead of re-deploying everything from scratch.
    function _loadCurrentChainInput() internal {
        if (DEPLOYMENT_ID_TO_LOAD == 0) return;

        string memory deploymentFolder = string.concat(
            OUTPUT_DIR, "/ethereum-mainnet-", vm.toString(block.chainid), "-", vm.toString(DEPLOYMENT_ID_TO_LOAD)
        );
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");
        _loadInputFromJson(fileName);
        console.log("Loaded deployment input from:", fileName);
    }

    function _loadInputFromJson(string memory fileName) internal {
        string memory json = vm.readFile(fileName);
        AltoEthereumMainnetInput memory loaded;

        loaded.contracts.timelock = _tryParseAddress(json, ".contracts.timelock");
        loaded.contracts.altoAdapter = _tryParseAddress(json, ".contracts.altoAdapter");
        loaded.contracts.feeRecipient = _tryParseAddress(json, ".contracts.feeRecipient");
        loaded.contracts.feeRecipientMintMarkets = _tryParseAddress(json, ".contracts.feeRecipientMintMarkets");
        loaded.contracts.dusd = _tryParseAddress(json, ".contracts.dusd");
        loaded.contracts.dusdFlashMinter = _tryParseAddress(json, ".contracts.dusdFlashMinter");
        loaded.contracts.marketRegistry = _tryParseAddress(json, ".contracts.marketRegistry");
        loaded.contracts.usmRegistry = _tryParseAddress(json, ".contracts.usmRegistry");
        loaded.contracts.vaultRegistry = _tryParseAddress(json, ".contracts.vaultRegistry");
        loaded.contracts.emergencyController = _tryParseAddress(json, ".contracts.emergencyController");
        loaded.contracts.emergencyControllerImplementation =
            _tryParseAddress(json, ".contracts.emergencyControllerImplementation");
        loaded.contracts.referralAdapter = _tryParseAddress(json, ".contracts.referralAdapter");

        loaded.contracts.wethMarket = _loadMarketContracts(json, "weth");
        loaded.contracts.wstethMarket = _loadMarketContracts(json, "wsteth");
        loaded.contracts.rethMarket = _loadMarketContracts(json, "reth");
        loaded.contracts.methMarket = _loadMarketContracts(json, "meth");
        loaded.contracts.tbtcMarket = _loadMarketContracts(json, "tbtc");
        loaded.contracts.wbtcBorrowMarket = _loadMarketContracts(json, "wbtcBorrow");
        loaded.contracts.cbbtcBorrowMarket = _loadMarketContracts(json, "cbbtcBorrow");
        loaded.contracts.susdeBorrowMarket = _loadMarketContracts(json, "susdeBorrow");
        loaded.contracts.syrupUsdcBorrowMarket = _loadMarketContracts(json, "syrupUsdcBorrow");
        loaded.contracts.paxgBorrowMarket = _loadMarketContracts(json, "paxgBorrow");
        loaded.contracts.susdeMintMarket = _loadMarketContracts(json, "susdeMint");
        loaded.contracts.syrupUsdcMintMarket = _loadMarketContracts(json, "syrupUsdcMint");
        loaded.contracts.frxUsdMarket = _loadMarketContracts(json, "frxUsd");

        loaded.contracts.permissionedUsm.dusdUsm = _tryParseAddress(json, ".contracts.permissionedUsm");
        loaded.contracts.permissionedUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionedUsmImplementation");
        loaded.contracts.permissionedUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionedUsmFixedPriceStrategy");
        loaded.contracts.permissionedUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionedUsmFixedFeeStrategy");

        loaded.contracts.permissionlessUsm.dusdUsm = _tryParseAddress(json, ".contracts.permissionlessUsm");
        loaded.contracts.permissionlessUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionlessUsmImplementation");
        loaded.contracts.permissionlessUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionlessUsmFixedPriceStrategy");
        loaded.contracts.permissionlessUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionlessUsmFixedFeeStrategy");

        loaded.contracts.permissionedFrxusdUsm.dusdUsm = _tryParseAddress(json, ".contracts.permissionedFrxUsdUsm");
        loaded.contracts.permissionedFrxusdUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionedFrxUsdUsmImplementation");
        loaded.contracts.permissionedFrxusdUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionedFrxUsdUsmFixedPriceStrategy");
        loaded.contracts.permissionedFrxusdUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionedFrxUsdUsmFixedFeeStrategy");

        loaded.contracts.dusdVault = _tryParseAddress(json, ".contracts.dusdVault");
        loaded.contracts.liquidationPeriphery = _tryParseAddress(json, ".contracts.liquidationPeriphery");
        loaded.contracts.advancedPermissionsFrxusdUsm.dusdUsm =
            _tryParseAddress(json, ".contracts.advancedPermissionsFrxusdUsm");
        loaded.contracts.advancedPermissionsFrxusdUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.advancedPermissionsFrxusdUsmImplementation");
        loaded.contracts.advancedPermissionsFrxusdUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.advancedPermissionsFrxusdUsmFixedPriceStrategy");
        loaded.contracts.advancedPermissionsFrxusdUsm.advancedPermissionsFeeStrategy =
            _tryParseAddress(json, ".contracts.advancedPermissionsFrxusdUsmFeeStrategy");
        loaded.contracts.universalRewardsDistributor = _tryParseAddress(json, ".contracts.universalRewardsDistributor");

        input = loaded;
    }

    function _tryParseAddress(string memory json, string memory path) internal returns (address) {
        try vm.parseJsonAddress(json, path) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    function _loadMarketContracts(string memory json, string memory prefix) internal returns (MarketContracts memory) {
        MarketContracts memory market;
        market.market = _tryParseAddress(json, string.concat(".contracts.", prefix, "Market"));
        market.marketImplementation =
            _tryParseAddress(json, string.concat(".contracts.", prefix, "MarketImplementation"));
        market.marketIrm = _tryParseAddress(json, string.concat(".contracts.", prefix, "MarketIrm"));
        market.marketOracle = _tryParseAddress(json, string.concat(".contracts.", prefix, "MarketOracle"));
        market.liquidationEngine = _tryParseAddress(json, string.concat(".contracts.", prefix, "LiquidationEngine"));
        market.leverageSwapper = _tryParseAddress(json, string.concat(".contracts.", prefix, "LeverageSwapper"));
        market.leverage = _tryParseAddress(json, string.concat(".contracts.", prefix, "Leverage"));
        return market;
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
        AltoLeverageSwapperMultiTarget leverageSwapper = AltoLeverageSwapperMultiTarget(market.leverageSwapper);
        assertTrue(leverageSwapper.isWhitelisted(market.leverage), "Leverage should be whitelisted");
        _verifyValidSwapTargets(leverageSwapper);
        assertTrue(
            IMarket(market.market).authorizedCallbacks(market.leverage), "Market should authorize leverage callback"
        );

        assertEq(
            IAltoLiquidationEngine(market.liquidationEngine).market(),
            market.market,
            "Liquidation engine should have correct market"
        );
    }

    function _verifyValidSwapTargets(AltoLeverageSwapperMultiTarget swapper) internal view {
        assertTrue(swapper.isValidSwapTarget(ZEROX_SWAP_TARGET_MAINNET), "0x should be valid swap target");
        assertTrue(
            swapper.isValidSwapTarget(ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET), "1inch should be valid swap target"
        );
        assertTrue(
            swapper.isValidSwapTarget(KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET),
            "KyberSwap should be valid swap target"
        );
        assertTrue(swapper.isValidSwapTarget(VELORA_AUGUSTUS_MAINNET), "Velora should be valid swap target");
        assertTrue(swapper.isValidSwapTarget(NORDSTERN_ROUTER_MAINNET), "Nordstern should be valid swap target");
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

    // ─────────────────────────────────────────────────────────────────────────
    // PERMISSIONED_FRXUSD_USM
    // ─────────────────────────────────────────────────────────────────────────

    // NOTE: @dev remove this test once frxUSD is deployed on-chain
    //       @dev move this test to deprecated folder
    function _deployPermissionedFrxUsdPsm() internal {
        input.contracts.emergencyController = FUTURE_EMERGENCY_CONTROLLER;
        params.phase = DeploymentPhase.PERMISSIONED_FRXUSD_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address usm = input.contracts.permissionedFrxusdUsm.dusdUsm;
        uint256 mintCeiling = 5_000_000_000 ether;

        vm.startPrank(input.contracts.timelock);
        IDUSD(input.contracts.dusd).setMinterStatus(usm, true);
        IDUSD(input.contracts.dusd).setMinterCeiling(usm, mintCeiling);
        IDUSD(input.contracts.dusd).setBurnerStatus(usm, true);
        IUsmRegistry(input.contracts.usmRegistry).addUsm(usm);
        vm.stopPrank();
    }

    function _assertDeployPermissionedFrxUsdPsm() internal {
        _deployPermissionedFrxUsdPsm();

        address usm = input.contracts.permissionedFrxusdUsm.dusdUsm;
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

        // Deployer (batch) must have revoked its own admin and configurator roles
        assertFalse(
            AccessControl(usm).hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER),
            "deployer should not retain DEFAULT_ADMIN_ROLE on USM"
        );
        assertFalse(
            AccessControl(usm).hasRole(CONFIGURATOR_ROLE, DEPLOYER),
            "deployer should not retain CONFIGURATOR_ROLE on USM"
        );
        assertEq(IUsm(usm).UNDERLYING_ASSET(), FRXUSD_MAINNET, "underlying asset should be frxUSD");

        assertEq(IUsm(usm).getExposureCap(), 5_000_000_000 ether, "exposure cap mismatch");

        _verifyMintCeiling(usm, 5_000_000_000 ether);
        assertTrue(IUsmRegistry(input.contracts.usmRegistry).isUsm(usm), "USM not registered in UsmRegistry");
    }

    // NOTE: @dev remove this test once DUSD Vault is deployed on-chain
    //       @dev move this test to deprecated folder
    function _assertTresuryPSMMigration() internal {
        // frxUSD USM should be deployed first
        _deployPermissionedFrxUsdPsm();

        address treasury = params.treasuryMultisig;
        IERC4626 fraxCustodian = IERC4626(0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c);
        address frxUsdPsm = input.contracts.permissionedFrxusdUsm.dusdUsm;
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
    function test_deployDusdVault() public {
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
    function test_deployVaultRegistry() public {
        test_deployDusdVault();

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

abstract contract DeployMarketPhaseTestBase is DeployAltoEthereumMainnetTestBase {
    address internal constant PRODUCTION_FREEZER = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;
    address internal constant TREASURY_MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address internal constant PRODUCTION_UPDATER = 0x7db7C14533a4186EcC07950F78835859320835Be;

    function _deployMarket(DeploymentPhase phase) internal {
        input.contracts.emergencyController = FUTURE_EMERGENCY_CONTROLLER;
        params = AltoEthereumMainnetParams({
            timelockAdmin: MAINNET_TIMELOCK_ADMIN,
            timelockDelay: 1 hours,
            freezer: PRODUCTION_FREEZER,
            deployer: msg.sender,
            phase: phase,
            treasuryMultisig: TREASURY_MULTISIG,
            updater: PRODUCTION_UPDATER,
            deployerHasOwnership: false
        });

        vm.startBroadcast();
        input = DeployAltoEthereumMainnet.deploy(params, input);
        vm.stopBroadcast();
    }

    function _assertMintMarketParams(
        MarketContracts memory deployed,
        ExpectedMarketParams memory expected,
        uint256 expectedBorrowRate
    ) internal view {
        _assertCommonMarketParams(deployed, expected);

        IMarket market = IMarket(deployed.market);
        Balance memory totalSupply = market.totalSupply();
        assertEq(totalSupply.assets, expected.capacity, "debt ceiling");
        assertEq(market.feeRecipient(), input.contracts.feeRecipientMintMarkets, "fee recipient");

        FixedRateIrm irm = FixedRateIrm(deployed.marketIrm);
        (uint256 borrowRate,) = irm.irState();
        assertEq(borrowRate, expectedBorrowRate, "borrow rate");
        assertEq(irm.market(), deployed.market, "IRM market");
    }

    function _assertBorrowMarketParams(
        MarketContracts memory deployed,
        ExpectedMarketParams memory expected,
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory expectedIrmConfig,
        uint256 expectedInterestFee
    ) internal view {
        _assertCommonMarketParams(deployed, expected);

        AltoBorrowMarket market = AltoBorrowMarket(deployed.market);
        assertEq(market.supplyCapAssets(), expected.capacity, "supply cap");
        assertEq(market.interestFee(), expectedInterestFee, "interest fee");
        assertEq(market.feeRecipient(), input.contracts.feeRecipient, "fee recipient");

        AdaptiveCurveIrm irm = AdaptiveCurveIrm(deployed.marketIrm);
        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = irm.irmConfig();
        assertEq(curveSteepness, expectedIrmConfig.curveSteepness, "curve steepness");
        assertEq(adjustmentSpeed, expectedIrmConfig.adjustmentSpeed, "adjustment speed");
        assertEq(targetUtilization, expectedIrmConfig.targetUtilization, "target utilization");
        assertEq(initialRateAtTarget, expectedIrmConfig.initialRateAtTarget, "initial target rate");
        assertEq(minRateAtTarget, expectedIrmConfig.minRateAtTarget, "minimum target rate");
        assertEq(maxRateAtTarget, expectedIrmConfig.maxRateAtTarget, "maximum target rate");
        assertEq(irm.market(), deployed.market, "IRM market");
    }

    function _assertCommonMarketParams(MarketContracts memory deployed, ExpectedMarketParams memory expected)
        private
        view
    {
        IMarket market = IMarket(deployed.market);
        assertEq(uint256(market.MARKET_TYPE()), uint256(expected.marketType), "market type");
        assertEq(market.borrowToken(), input.contracts.dusd, "borrow token");
        assertEq(market.collateralToken(), expected.collateralToken, "collateral token");
        assertEq(market.irm(), deployed.marketIrm, "IRM");
        assertEq(market.oracle(), deployed.marketOracle, "oracle");
        assertEq(market.liquidationEngine(), deployed.liquidationEngine, "liquidation engine");
        assertEq(market.maxLtv(), expected.maxLtv, "max LTV");
        assertEq(market.borrowOpeningFee(), expected.borrowOpeningFee, "borrow opening fee");

        LiquidationConfiguration memory config =
            IDcfDlbPriorityLiquidationEngine(deployed.liquidationEngine).liquidationConfiguration();
        assertEq(config.maxLiquidationLtv, expected.maxLiquidationLtv, "max liquidation LTV");
        assertEq(config.dynamicBonusFeeStart, expected.dynamicBonusFeeStart, "dynamic bonus fee start");
        assertEq(config.ltvForCompleteLiquidation, expected.ltvForCompleteLiquidation, "complete liquidation LTV");
        assertEq(config.liquidationBaseFee, expected.liquidationBaseFee, "liquidation base fee");
    }

    function _assertAndExecuteMarketGovernance(
        MarketContracts memory deployed,
        ExpectedMarketParams memory expected,
        string memory schedulePath,
        string memory executePath
    ) internal {
        _assertMarketGovernanceState(deployed.market, expected, false);
        _assertSafeJson(schedulePath, TimelockController.scheduleBatch.selector);
        _assertSafeJson(executePath, TimelockController.executeBatch.selector);
        _executeSafeTimelockBatch(schedulePath, executePath);
        _assertMarketGovernanceState(deployed.market, expected, true);
        _assertMarketWiring(deployed);
    }

    function _assertMarketGovernanceState(address market, ExpectedMarketParams memory expected, bool enabled)
        private
        view
    {
        IMarketRegistry registry = IMarketRegistry(input.contracts.marketRegistry);
        bool isMintMarket = expected.marketType == MarketType.MINT;
        assertEq(
            isMintMarket ? registry.isMintMarket(market) : registry.isBorrowMarket(market), enabled, "registry status"
        );
        assertEq(
            AltoAdapter(payable(input.contracts.altoAdapter)).isApprovedContract(market), enabled, "adapter approval"
        );
        assertEq(
            ILiquidationPeripheryBase(input.contracts.liquidationPeriphery).supportedMarkets(market),
            enabled,
            "liquidation periphery support"
        );
        assertEq(
            IMarket(market).authorizedLiquidationPeriphery(input.contracts.liquidationPeriphery),
            enabled,
            "market liquidation periphery authorization"
        );

        if (isMintMarket) {
            IDUSD dusd = IDUSD(input.contracts.dusd);
            assertEq(dusd.allowedMinter(market), enabled, "DUSD minter status");
            assertEq(dusd.allowedBurner(market), enabled, "DUSD burner status");
            (uint256 minted, uint256 ceiling) = dusd.minterConfig(market);
            assertEq(minted, 0, "initial minted amount");
            assertEq(
                ceiling,
                enabled ? expected.capacity * 1.05 ether / expected.maxLiquidationLtv : 0,
                "DUSD minter ceiling"
            );
        }
    }

    function _assertSafeJson(string memory path, bytes4 expectedSelector) private view {
        assertTrue(vm.exists(path), "Safe JSON must be written");
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), input.contracts.timelock, "Safe target");
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "0", "Safe value");
        assertEq(bytes4(vm.parseJsonBytes(json, ".transactions[0].data")), expectedSelector, "Safe selector");
    }

    function _assertMarketWiring(MarketContracts memory deployed) private view {
        assertTrue(deployed.marketImplementation.code.length > 0, "market implementation");
        assertEq(Ownable(deployed.market).owner(), input.contracts.timelock, "market owner");
        assertEq(Ownable(deployed.marketIrm).owner(), input.contracts.timelock, "IRM owner");
        assertEq(Ownable(deployed.marketOracle).owner(), input.contracts.timelock, "oracle owner");
        assertEq(Ownable(deployed.liquidationEngine).owner(), input.contracts.timelock, "liquidation engine owner");
        assertEq(Ownable(deployed.leverageSwapper).owner(), input.contracts.timelock, "leverage swapper owner");
        assertEq(Ownable(deployed.leverage).owner(), input.contracts.timelock, "leverage owner");
        assertTrue(Pausable(deployed.market).pausers(PRODUCTION_FREEZER, PAUSE_TYPE), "production pauser");
        assertTrue(Pausable(deployed.market).pausers(PRODUCTION_FREEZER, FROZEN_TYPE), "production freezer");
        assertTrue(Pausable(deployed.market).pausers(FUTURE_EMERGENCY_CONTROLLER, PAUSE_TYPE), "controller pauser");
        assertTrue(Pausable(deployed.market).pausers(FUTURE_EMERGENCY_CONTROLLER, FROZEN_TYPE), "controller freezer");
        assertFalse(Pausable(deployed.market).pausers(params.deployer, PAUSE_TYPE), "deployer pauser");
        assertFalse(Pausable(deployed.market).pausers(params.deployer, FROZEN_TYPE), "deployer freezer");
        assertTrue(IMarket(deployed.market).authorizedCallbacks(deployed.leverage), "leverage callback");
        assertTrue(AltoLeverage(payable(deployed.leverage)).supportedMarkets(deployed.market), "leverage market");
        assertTrue(
            AltoLeverageSwapperMultiTarget(deployed.leverageSwapper).isWhitelisted(deployed.leverage),
            "swapper whitelist"
        );
    }
}

contract DeployFutureMarketEmergencyControllerTest is DeployMarketPhaseTestBase {
    function test_futureMintMarketAuthorizesEmergencyController() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_SUSDE);
        _assertEmergencyControllerPermissions(input.contracts.susdeMintMarket.market);
    }

    function test_futureBorrowMarketAuthorizesEmergencyController() public {
        _deployMarket(DeploymentPhase.BORROW_MARKET_PAXG);
        _assertEmergencyControllerPermissions(input.contracts.paxgBorrowMarket.market);
    }

    function _assertEmergencyControllerPermissions(address market) private view {
        assertTrue(Pausable(market).pausers(FUTURE_EMERGENCY_CONTROLLER, PAUSE_TYPE), "controller pauser");
        assertTrue(Pausable(market).pausers(FUTURE_EMERGENCY_CONTROLLER, FROZEN_TYPE), "controller freezer");
    }
}

contract DeployPermissionedFrxUsdPsmTest is DeployAltoEthereumMainnetTestBase {
    function test_deployPermissionedFrxUsdPsm() public {
        _assertDeployPermissionedFrxUsdPsm();
    }
}

contract DeployPermissionlessFrxUsdPsmTest is DeployAltoEthereumMainnetTestBase {
    function test_deployPermissionlessFrxUsdPsm() public {
        _assertDeployPermissionlessFrxUsdPsm();
    }

    function test_permissionlessFrxUsdUsmBuyAndSell() public {
        _assertPermissionlessFrxUsdUsmBuyAndSell();
    }
}

contract TresuryPSMMigrationTest is DeployAltoEthereumMainnetTestBase {
    function test_TresuryPSMMigration() public {
        _assertTresuryPSMMigration();
    }
}

contract DeployWethMintMarketPhaseTest is DeployMarketPhaseTestBase {
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-WETH-mint-market-registry-and-authorize-liquidation-periphery-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-WETH-mint-market-registry-and-authorize-liquidation-periphery-execute.json";

    function test_deployWethMintMarketAndExecuteTimelockTransactions() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_WETH);

        MarketContracts memory deployed = input.contracts.wethMarket;
        ExpectedMarketParams memory expected = ExpectedMarketParams({
            marketType: MarketType.MINT,
            collateralToken: WETH_MAINNET,
            maxLtv: 0.76 ether,
            borrowOpeningFee: 0.0005 ether,
            capacity: 60_000 ether,
            maxLiquidationLtv: 0.81 ether,
            dynamicBonusFeeStart: 0.02 ether,
            ltvForCompleteLiquidation: 0.86 ether,
            liquidationBaseFee: 0.07 ether
        });

        _assertMintMarketParams(deployed, expected, 0.02134 ether / uint256(365 days));
        _assertAndExecuteMarketGovernance(deployed, expected, SCHEDULE_JSON, EXECUTE_JSON);
    }
}

contract DeployWstethMintMarketPhaseTest is DeployMarketPhaseTestBase {
    function test_deployWstethMintMarketParameters() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_WSTETH);

        _assertMintMarketParams(
            input.contracts.wstethMarket,
            ExpectedMarketParams({
                marketType: MarketType.MINT,
                collateralToken: WSTETH_MAINNET,
                maxLtv: 0.75 ether,
                borrowOpeningFee: 0.0015 ether,
                capacity: 60_000 ether,
                maxLiquidationLtv: 0.78 ether,
                dynamicBonusFeeStart: 0.02 ether,
                ltvForCompleteLiquidation: 0.815 ether,
                liquidationBaseFee: 0.07 ether
            }),
            0.02295163663 ether / uint256(365 days)
        );
    }
}

contract DeployRethMintMarketPhaseTest is DeployMarketPhaseTestBase {
    function test_deployRethMintMarketParameters() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_RETH);

        MarketContracts memory deployed = input.contracts.rethMarket;
        _assertMintMarketParams(
            deployed,
            ExpectedMarketParams({
                marketType: MarketType.MINT,
                collateralToken: RETH_MAINNET,
                maxLtv: 0.75 ether,
                borrowOpeningFee: 0.0016 ether,
                capacity: 20_000 ether,
                maxLiquidationLtv: 0.78 ether,
                dynamicBonusFeeStart: 0.02 ether,
                ltvForCompleteLiquidation: 0.81 ether,
                liquidationBaseFee: 0.07 ether
            }),
            0.02333714138 ether / uint256(365 days)
        );
        _assertRethOracleConfiguration(deployed.marketOracle);
    }

    function _assertRethOracleConfiguration(address oracleAddress) internal view {
        ERC4626RatioChainlinkOracleRETH oracle = ERC4626RatioChainlinkOracleRETH(oracleAddress);
        assertEq(oracle.RETH(), RETH_MAINNET, "ratio source");

        (uint256 initialRatio,, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, IReth(RETH_MAINNET).getExchangeRate() * 1005 / 1000, "initial ratio");
        assertEq(maxYearlyGrowthRatioWad, 0.07 ether, "maximum yearly ratio growth");

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), CHAINLINK_ETH_USD_PRICE_FEED, "ETH/USD feed");
        assertEq(uint256(direction), uint256(ConversionDirection.IN_TO_OUT), "conversion direction");
        assertEq(stalePeriod, 3900, "stale period");
        assertEq(inDecimals, 18, "input decimals");
        assertEq(outDecimals, 36, "output decimals");
        assertEq(feedDecimals, 8, "feed decimals");
    }
}

contract DeploySusdeMintMarketPhaseTest is DeployMarketPhaseTestBase {
    function test_deploySusdeMintMarketParameters() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_SUSDE);

        MarketContracts memory deployed = input.contracts.susdeMintMarket;
        _assertMintMarketParams(
            deployed,
            ExpectedMarketParams({
                marketType: MarketType.MINT,
                collateralToken: SUSDE_MAINNET,
                maxLtv: 0.7 ether,
                borrowOpeningFee: 0.001 ether,
                capacity: 31_394 ether,
                maxLiquidationLtv: 0.72 ether,
                dynamicBonusFeeStart: 0.015 ether,
                ltvForCompleteLiquidation: 0.73 ether,
                liquidationBaseFee: 0.04 ether
            }),
            0.0216426871 ether / uint256(365 days)
        );
        _assertSusdeOracleConfiguration(deployed.marketOracle);
    }

    function _assertSusdeOracleConfiguration(address oracleAddress) internal view {
        ERC4626RatioChainlinkOracleSUSDE oracle = ERC4626RatioChainlinkOracleSUSDE(oracleAddress);
        assertEq(oracle.SUSDE(), SUSDE_MAINNET, "ratio source");

        (uint256 initialRatio,, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, IERC4626(SUSDE_MAINNET).convertToAssets(1 ether) * 1015 / 1000, "initial ratio");
        assertEq(maxYearlyGrowthRatioWad, 0.185 ether, "maximum yearly ratio growth");

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), CHAINLINK_USDE_USD_PRICE_FEED, "USDe/USD feed");
        assertEq(uint256(direction), uint256(ConversionDirection.IN_TO_OUT), "conversion direction");
        assertEq(stalePeriod, 83100, "stale period");
        assertEq(inDecimals, 18, "input decimals");
        assertEq(outDecimals, 36, "output decimals");
        assertEq(feedDecimals, 8, "feed decimals");
    }
}

contract DeploySusdeBorrowMarketPhaseTest is DeployMarketPhaseTestBase {
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sUSDe-borrow-market-registry-and-authorize-liquidation-periphery-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sUSDe-borrow-market-registry-and-authorize-liquidation-periphery-execute.json";

    function test_deploySusdeBorrowMarketAndExecuteTimelockTransactions() public {
        _deployMarket(DeploymentPhase.BORROW_MARKET_SUSDE);

        MarketContracts memory deployed = input.contracts.susdeBorrowMarket;
        ExpectedMarketParams memory expected = ExpectedMarketParams({
            marketType: MarketType.BORROW,
            collateralToken: SUSDE_MAINNET,
            maxLtv: 0.7 ether,
            borrowOpeningFee: 0.001 ether,
            capacity: uint128(70300.1222 ether),
            maxLiquidationLtv: 0.72 ether,
            dynamicBonusFeeStart: 0.015 ether,
            ltvForCompleteLiquidation: 0.73 ether,
            liquidationBaseFee: 0.04 ether
        });
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory expectedIrmConfig = AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 2 ether,
            adjustmentSpeed: 25 ether / int256(365 days),
            targetUtilization: 0.8298099174 ether,
            initialRateAtTarget: 0.08099633377 ether / int256(365 days),
            minRateAtTarget: 0.06479706701 ether / int256(365 days),
            maxRateAtTarget: 4 ether / int256(365 days)
        });

        _assertBorrowMarketParams(deployed, expected, expectedIrmConfig, 0.1 ether);
        _assertAndExecuteMarketGovernance(deployed, expected, SCHEDULE_JSON, EXECUTE_JSON);
    }
}

contract DeploySyrupUsdcBorrowMarketPhaseTest is DeployMarketPhaseTestBase {
    function test_deploySyrupUsdcBorrowMarketParameters() public {
        _deployMarket(DeploymentPhase.BORROW_MARKET_SYRUP_USDC);

        _assertBorrowMarketParams(
            input.contracts.syrupUsdcBorrowMarket,
            ExpectedMarketParams({
                marketType: MarketType.BORROW,
                collateralToken: SYRUPUSDC_MAINNET,
                maxLtv: 0.7 ether,
                borrowOpeningFee: 0.0015 ether,
                capacity: uint128(105269.0051 ether),
                maxLiquidationLtv: 0.71 ether,
                dynamicBonusFeeStart: 0.015 ether,
                ltvForCompleteLiquidation: 0.72 ether,
                liquidationBaseFee: 0.04 ether
            }),
            AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                curveSteepness: 2 ether,
                adjustmentSpeed: 25 ether / int256(365 days),
                targetUtilization: 0.7553719008 ether,
                initialRateAtTarget: 0.08661776418 ether / int256(365 days),
                minRateAtTarget: 0.06929421135 ether / int256(365 days),
                maxRateAtTarget: 4 ether / int256(365 days)
            }),
            0.1 ether
        );
    }
}

contract DeploySyrupUsdcMintMarketPhaseTest is DeployMarketPhaseTestBase {
    function test_deploySyrupUsdcMintMarketParameters() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_SYRUPUSDC);

        MarketContracts memory deployed = input.contracts.syrupUsdcMintMarket;
        _assertMintMarketParams(
            deployed,
            ExpectedMarketParams({
                marketType: MarketType.MINT,
                collateralToken: SYRUPUSDC_MAINNET,
                maxLtv: 0.7 ether,
                borrowOpeningFee: 0.0015 ether,
                capacity: 54_000 ether,
                maxLiquidationLtv: 0.71 ether,
                dynamicBonusFeeStart: 0.015 ether,
                ltvForCompleteLiquidation: 0.72 ether,
                liquidationBaseFee: 0.04 ether
            }),
            0.02271416921 ether / uint256(365 days)
        );
        _assertSyrupUsdcOracleConfiguration(deployed.marketOracle);
    }

    function _assertSyrupUsdcOracleConfiguration(address oracleAddress) internal view {
        ERC4626RatioChainlinkOracleSYRUPUSDC oracle = ERC4626RatioChainlinkOracleSYRUPUSDC(oracleAddress);
        assertEq(oracle.SYRUP_USDC(), SYRUPUSDC_MAINNET, "ratio source");

        (uint256 initialRatio,, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, ISyrupAsset(SYRUPUSDC_MAINNET).convertToExitAssets(1e6) * 1005 / 1000, "initial ratio");
        assertEq(maxYearlyGrowthRatioWad, 0.12 ether, "maximum yearly ratio growth");

        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), CHAINLINK_USDC_USD_PRICE_FEED, "USDC/USD feed");
        assertEq(uint256(direction), uint256(ConversionDirection.IN_TO_OUT), "conversion direction");
        assertEq(stalePeriod, 86700, "stale period");
        assertEq(inDecimals, 6, "input decimals");
        assertEq(outDecimals, 48, "output decimals");
        assertEq(feedDecimals, 8, "feed decimals");
    }
}

contract DeployFrxUsdMintMarketPhaseTest is DeployMarketPhaseTestBase {
    function test_deployFrxUsdMintMarketParameters() public {
        _deployMarket(DeploymentPhase.MINT_MARKET_FRXUSD);

        MarketContracts memory deployed = input.contracts.frxUsdMarket;
        _assertMintMarketParams(
            deployed,
            ExpectedMarketParams({
                marketType: MarketType.MINT,
                collateralToken: FRXUSD_MAINNET,
                maxLtv: 0.8 ether,
                borrowOpeningFee: 0.0017 ether,
                capacity: 30_000 ether,
                maxLiquidationLtv: 0.81 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.82 ether,
                liquidationBaseFee: 0.03 ether
            }),
            0
        );
        _assertFrxUsdOracleConfiguration(deployed.marketOracle);
    }

    function _assertFrxUsdOracleConfiguration(address oracleAddress) internal view {
        (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        ) = AltoMultiChainlinkLendingOracle(oracleAddress).chainlinkNodes(0);
        assertEq(address(feed), CHAINLINK_FRXUSD_USD_PRICE_FEED, "frxUSD/USD feed");
        assertEq(uint256(direction), uint256(ConversionDirection.IN_TO_OUT), "conversion direction");
        assertEq(stalePeriod, 86700, "stale period");
        assertEq(inDecimals, 18, "input decimals");
        assertEq(outDecimals, 36, "output decimals");
        assertEq(feedDecimals, 8, "feed decimals");
    }
}

contract DeployAdapterPhaseTest is DeployAltoEthereumMainnetTestBase {
    function test_deployAdapterAndApproval() public {
        _assertDeployAdapterAndApproval();
    }
}

contract DeployLeverageSwapperMultiTargetPhaseTest is DeployAltoEthereumMainnetTestBase {
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

contract DeployLiquidationPeripheryPhaseTest is DeployAltoEthereumMainnetTestBase {
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

contract DeployAdvancedPermissionsFrxUsdUsmPhaseTest is DeployAltoEthereumMainnetTestBase {
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

contract DeployUpgradeMarketsLiquidationPeripheryPhaseTest is DeployAltoEthereumMainnetTestBase {
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

contract DeployUniversalRewardsDistributorPhaseTest is DeployAltoEthereumMainnetTestBase {
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

contract DeployRequiredAddressesTest is DeployAltoEthereumMainnetTestBase {
    function deployExternal(
        AltoEthereumMainnetParams memory deploymentParams,
        AltoEthereumMainnetInput memory deploymentInput
    ) external returns (AltoEthereumMainnetInput memory) {
        return DeployAltoEthereumMainnet.deploy(deploymentParams, deploymentInput);
    }

    function test_deploymentRequiresFreezer() public {
        params.freezer = address(0);

        vm.expectRevert("Freezer must be set");
        this.deployExternal(params, input);
    }

    function test_deploymentRequiresEmergencyController() public {
        input.contracts.emergencyController = address(0);

        vm.expectRevert("Emergency controller must be set");
        this.deployExternal(params, input);
    }
}

contract DeployMarketDeprecationPhase0Test is DeployAltoEthereumMainnetTestBase {
    uint256 internal constant T0_RATE_SPY = 0.1 ether / uint256(365 days);
    // NOTE: These fixed placeholders make Phase X exercise real state changes instead of replaying current values.
    // TODO(Risk): Replace each market entry below with its approved Phase X parameters once finalized.
    uint256 internal constant PHASE_X_DEFAULT_RATE_SPY = 0.2 ether / uint256(365 days);
    uint256 internal constant PHASE_X_DEFAULT_MAX_LTV = 0.6 ether;
    uint256 internal constant PHASE_X_DEFAULT_LIQUIDATION_LTV = 0.75 ether;
    uint256 internal constant PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV = 0.85 ether;

    address internal constant PRODUCTION_FREEZER = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;

    function test_marketDeprecationPhase0GeneratedCalldataExecutesAndSetsExpectedState() public {
        address[] memory borrowMarkets = _borrowMarkets();
        address[] memory mintMarkets = _mintMarkets();
        address[] memory oldBorrowIrms = _currentIrms(borrowMarkets);
        address[] memory mintIrms = _currentIrms(mintMarkets);
        address[] memory alreadyDeprecatedMintMarkets = _alreadyDeprecatedMintMarkets();
        address[] memory alreadyDeprecatedMintIrms = _currentIrms(alreadyDeprecatedMintMarkets);

        _assertInitialState(borrowMarkets, oldBorrowIrms, mintMarkets, mintIrms);
        _assertAlreadyDeprecatedInitialState(alreadyDeprecatedMintMarkets, alreadyDeprecatedMintIrms);

        params.phase = DeploymentPhase.MARKET_DEPRECATION_PHASE_0;
        params.freezer = PRODUCTION_FREEZER;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
        address[] memory newBorrowIrms = _predictedIrms(factory, borrowMarkets.length);

        assertTrue(address(factory).code.length > 0, "factory not deployed");
        assertEq(factory.owner(), input.contracts.timelock, "factory owner");
        assertEq(factory.pendingOwner(), address(0), "factory pending owner");
        assertEq(factory.nonce(), 0, "factory nonce before Timelock execution");
        for (uint256 i; i < newBorrowIrms.length; ++i) {
            assertEq(newBorrowIrms[i].code.length, 0, "fixed IRM deployed before Timelock execution");
        }

        _executeTimelockCalldata(
            _safeTxPath("market-deprecation-phase-0", "schedule"), TimelockController.scheduleBatch.selector
        );
        vm.warp(block.timestamp + TimelockController(payable(input.contracts.timelock)).getMinDelay() + 1);

        _executeFreezerCalldata(borrowMarkets, mintMarkets);
        _assertFrozenWithExpectedIrms(borrowMarkets, oldBorrowIrms);
        _assertFrozenWithExpectedIrms(mintMarkets, mintIrms);

        _executeTimelockCalldata(
            _safeTxPath("market-deprecation-phase-0", "execute"), TimelockController.executeBatch.selector
        );
        _executeVaultCapCalldata(borrowMarkets);

        assertEq(factory.nonce(), borrowMarkets.length, "factory nonce after Timelock execution");
        _assertBorrowMarketFinalState(borrowMarkets, oldBorrowIrms, newBorrowIrms);
        _assertMintMarketFinalState(mintMarkets, mintIrms);
        _assertMintMarketFinalState(alreadyDeprecatedMintMarkets, alreadyDeprecatedMintIrms);
        _assertVaultCapFinalState(borrowMarkets);
    }

    function test_marketDeprecationCorrectionPlaceholderBatchesAreGenerated() public {
        DeploymentPhase[3] memory correctionPhases = [
            DeploymentPhase.MARKET_DEPRECATION_PHASE_X,
            DeploymentPhase.MARKET_DEPRECATION_PHASE_Y,
            DeploymentPhase.MARKET_DEPRECATION_PHASE_Z
        ];
        string[3] memory batchNames = [
            string("market-deprecation-phase-x"),
            string("market-deprecation-phase-y"),
            string("market-deprecation-phase-z")
        ];

        for (uint256 i; i < correctionPhases.length; ++i) {
            params.phase = correctionPhases[i];
            input = DeployAltoEthereumMainnet.deploy(params, input);

            _assertAndReadTimelockTransaction(
                _safeTxPath(batchNames[i], "schedule"), TimelockController.scheduleBatch.selector
            );
            _assertAndReadTimelockTransaction(
                _safeTxPath(batchNames[i], "execute"), TimelockController.executeBatch.selector
            );
        }
    }

    function test_marketDeprecationPhaseXGeneratedCalldataExecutesWithValidValues() public {
        test_marketDeprecationPhase0GeneratedCalldataExecutesAndSetsExpectedState();

        address[] memory markets = _allDeprecatedMarkets();
        MarketDeprecationCorrectionParams[] memory correctionParams = _phaseXTestCorrectionParams(markets);
        address[] memory expectedIrms = new address[](markets.length);
        address[] memory expectedLiquidationEngines = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            expectedIrms[i] = IMarket(markets[i]).irm();
            expectedLiquidationEngines[i] = IMarket(markets[i]).liquidationEngine();
        }

        input = MarketDeprecationDeployment.deployCorrection(
            correctionParams, DeploymentPhase.MARKET_DEPRECATION_PHASE_X, input
        );

        _executeTimelockCalldata(
            _safeTxPath("market-deprecation-phase-x", "schedule"), TimelockController.scheduleBatch.selector
        );
        vm.warp(block.timestamp + TimelockController(payable(input.contracts.timelock)).getMinDelay() + 1);

        _executeTimelockCalldata(
            _safeTxPath("market-deprecation-phase-x", "execute"), TimelockController.executeBatch.selector
        );

        _assertMarketDeprecationCorrectionFinalState(correctionParams, expectedIrms, expectedLiquidationEngines);
    }

    function _allDeprecatedMarkets() internal view returns (address[] memory markets) {
        address[] memory borrowMarkets = _borrowMarkets();
        address[] memory mintMarkets = _mintMarkets();
        address[] memory alreadyDeprecatedMintMarkets = _alreadyDeprecatedMintMarkets();

        markets = new address[](borrowMarkets.length + mintMarkets.length + alreadyDeprecatedMintMarkets.length);
        uint256 marketIndex;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            markets[marketIndex++] = borrowMarkets[i];
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            markets[marketIndex++] = mintMarkets[i];
        }
        for (uint256 i; i < alreadyDeprecatedMintMarkets.length; ++i) {
            markets[marketIndex++] = alreadyDeprecatedMintMarkets[i];
        }
    }

    function _phaseXTestCorrectionParams(address[] memory markets)
        internal
        pure
        returns (MarketDeprecationCorrectionParams[] memory correctionParams)
    {
        correctionParams = new MarketDeprecationCorrectionParams[](12);

        correctionParams[0] = MarketDeprecationCorrectionParams({
            market: markets[0], // WBTC borrow market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[1] = MarketDeprecationCorrectionParams({
            market: markets[1], // cbBTC borrow market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[2] = MarketDeprecationCorrectionParams({
            market: markets[2], // sUSDe borrow market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[3] = MarketDeprecationCorrectionParams({
            market: markets[3], // syrupUSDC borrow market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[4] = MarketDeprecationCorrectionParams({
            market: markets[4], // PAXG borrow market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[5] = MarketDeprecationCorrectionParams({
            market: markets[5], // sUSDe mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[6] = MarketDeprecationCorrectionParams({
            market: markets[6], // syrupUSDC mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[7] = MarketDeprecationCorrectionParams({
            market: markets[7], // WETH mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[8] = MarketDeprecationCorrectionParams({
            market: markets[8], // wstETH mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[9] = MarketDeprecationCorrectionParams({
            market: markets[9], // rETH mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[10] = MarketDeprecationCorrectionParams({
            market: markets[10], // already-deprecated mETH mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
        correctionParams[11] = MarketDeprecationCorrectionParams({
            market: markets[11], // already-deprecated tBTC mint market
            irmBorrowRate: PHASE_X_DEFAULT_RATE_SPY,
            maxLtv: PHASE_X_DEFAULT_MAX_LTV,
            liquidationLtv: PHASE_X_DEFAULT_LIQUIDATION_LTV,
            completeLiquidationLtv: PHASE_X_DEFAULT_COMPLETE_LIQUIDATION_LTV
        });
    }

    function _assertMarketDeprecationCorrectionFinalState(
        MarketDeprecationCorrectionParams[] memory correctionParams,
        address[] memory expectedIrms,
        address[] memory expectedLiquidationEngines
    ) internal view {
        for (uint256 i; i < correctionParams.length; ++i) {
            MarketDeprecationCorrectionParams memory correction = correctionParams[i];
            address market = correction.market;
            address irm = IMarket(market).irm();
            address liquidationEngine = IMarket(market).liquidationEngine();

            assertEq(irm, expectedIrms[i], "Phase X changed market IRM");
            assertEq(liquidationEngine, expectedLiquidationEngines[i], "Phase X changed liquidation engine");
            assertTrue(IPausable(market).paused(FROZEN_TYPE), "Phase X market not frozen");
            assertFalse(IPausable(market).paused(PAUSE_TYPE), "Phase X market paused");
            assertEq(Ownable(market).owner(), input.contracts.timelock, "Phase X market owner");
            assertEq(IMarket(market).maxLtv(), correction.maxLtv, "Phase X max LTV");

            assertEq(Ownable(irm).owner(), input.contracts.timelock, "Phase X IRM owner");
            assertEq(FixedRateIrm(irm).market(), market, "Phase X IRM market binding");
            (uint256 borrowRate,) = FixedRateIrm(irm).irState();
            assertEq(borrowRate, correction.irmBorrowRate, "Phase X IRM borrow rate");

            assertEq(Ownable(liquidationEngine).owner(), input.contracts.timelock, "Phase X engine owner");
            LiquidationConfiguration memory liquidationConfiguration =
                IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
            assertEq(liquidationConfiguration.maxLiquidationLtv, correction.liquidationLtv, "Phase X liquidation LTV");
            assertEq(
                liquidationConfiguration.ltvForCompleteLiquidation,
                correction.completeLiquidationLtv,
                "Phase X complete liquidation LTV"
            );
        }
    }

    function _assertInitialState(
        address[] memory borrowMarkets,
        address[] memory oldBorrowIrms,
        address[] memory mintMarkets,
        address[] memory mintIrms
    ) internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketState(borrowMarkets[i], oldBorrowIrms[i], MarketType.BORROW, false);
            _assertIrmState(oldBorrowIrms[i], borrowMarkets[i], IRMType.ADAPTIVE_CURVE, 0, false);
        }

        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertMarketState(mintMarkets[i], mintIrms[i], MarketType.MINT, false);
            _assertIrmState(mintIrms[i], mintMarkets[i], IRMType.FIXED_RATE, 0, false);
        }
    }

    function _assertAlreadyDeprecatedInitialState(address[] memory markets, address[] memory irms) internal view {
        for (uint256 i; i < markets.length; ++i) {
            _assertMarketState(markets[i], irms[i], MarketType.MINT, true);
            _assertIrmState(irms[i], markets[i], IRMType.FIXED_RATE, 0, false);
            (uint256 borrowRate,) = FixedRateIrm(irms[i]).irState();
            assertTrue(borrowRate != T0_RATE_SPY, "already-deprecated IRM already at T0 rate");
        }
    }

    function _assertBorrowMarketFinalState(
        address[] memory borrowMarkets,
        address[] memory oldBorrowIrms,
        address[] memory newBorrowIrms
    ) internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketState(borrowMarkets[i], newBorrowIrms[i], MarketType.BORROW, true);
            _assertIrmState(newBorrowIrms[i], borrowMarkets[i], IRMType.FIXED_RATE, T0_RATE_SPY, true);

            assertEq(FixedRateIrm(oldBorrowIrms[i]).market(), borrowMarkets[i], "old IRM binding changed");
            assertEq(
                uint256(FixedRateIrm(oldBorrowIrms[i]).IRM_TYPE()),
                uint256(IRMType.ADAPTIVE_CURVE),
                "old IRM type changed"
            );
            assertEq(Ownable(oldBorrowIrms[i]).owner(), input.contracts.timelock, "old IRM owner changed");
        }
    }

    function _assertMintMarketFinalState(address[] memory markets, address[] memory irms) internal view {
        for (uint256 i; i < markets.length; ++i) {
            _assertMarketState(markets[i], irms[i], MarketType.MINT, true);
            _assertIrmState(irms[i], markets[i], IRMType.FIXED_RATE, T0_RATE_SPY, true);
        }
    }

    function _assertMarketState(address market, address expectedIrm, MarketType expectedType, bool frozen)
        internal
        view
    {
        assertEq(IMarket(market).irm(), expectedIrm, "market IRM");
        assertEq(uint256(IMarket(market).MARKET_TYPE()), uint256(expectedType), "market type");
        assertEq(Ownable(market).owner(), input.contracts.timelock, "market owner");
        assertEq(IPausable(market).paused(FROZEN_TYPE), frozen, "market frozen state");
        assertFalse(IPausable(market).paused(PAUSE_TYPE), "market must not be paused");
        assertTrue(Pausable(market).pausers(PRODUCTION_FREEZER, FROZEN_TYPE), "Freezer role changed");
        assertFalse(Pausable(market).pausers(input.contracts.timelock, FROZEN_TYPE), "Timelock gained Freezer role");
    }

    function _assertIrmState(
        address irmAddress,
        address expectedMarket,
        IRMType expectedType,
        uint256 expectedRate,
        bool assertRate
    ) internal view {
        FixedRateIrm irm = FixedRateIrm(irmAddress);
        assertTrue(irmAddress.code.length > 0, "IRM not deployed");
        assertEq(uint256(irm.IRM_TYPE()), uint256(expectedType), "IRM type");
        assertEq(irm.market(), expectedMarket, "IRM market binding");
        assertEq(Ownable(irmAddress).owner(), input.contracts.timelock, "IRM owner");
        assertEq(AltoOwnable2Step(irmAddress).pendingOwner(), address(0), "IRM pending owner");

        if (assertRate) {
            (uint256 borrowRate, uint48 lastUpdate) = irm.irState();
            assertEq(borrowRate, expectedRate, "IRM borrow rate");
            assertEq(uint256(lastUpdate), block.timestamp, "IRM last update");
        }
    }

    function _executeTimelockCalldata(string memory path, bytes4 expectedSelector) internal {
        bytes memory data = _assertAndReadTimelockTransaction(path, expectedSelector);
        _callFrom(MAINNET_TIMELOCK_ADMIN, input.contracts.timelock, data, "Timelock calldata failed");
    }

    function _executeFreezerCalldata(address[] memory borrowMarkets, address[] memory mintMarkets) internal {
        string memory path = _safeTxPath("market-deprecation-phase-0", "freezer");
        assertTrue(vm.exists(path), "Freezer JSON not written");
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), PRODUCTION_FREEZER, "Freezer Safe address");

        uint256 callCount = borrowMarkets.length + mintMarkets.length;
        for (uint256 i; i < callCount; ++i) {
            string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
            address expectedMarket = i < borrowMarkets.length ? borrowMarkets[i] : mintMarkets[i - borrowMarkets.length];
            address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));

            assertEq(target, expectedMarket, "Freezer target/order");
            assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "Freezer call value");
            assertEq(bytes4(data), IPausable.pause.selector, "Freezer selector");
            _callFrom(PRODUCTION_FREEZER, target, data, "Freezer calldata failed");
        }
        assertFalse(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(callCount), "]")),
            "unexpected extra Freezer call"
        );
    }

    function _executeVaultCapCalldata(address[] memory borrowMarkets) internal {
        string memory path = _safeTxPath("market-deprecation-phase-0", "vault-caps");
        assertTrue(vm.exists(path), "Vault caps JSON not written");
        string memory json = vm.readFile(path);
        IAltoVaultBase vault = IAltoVaultBase(input.contracts.dusdVault);
        address curator = vault.curator();
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), curator, "Vault curator Safe address");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
            bytes memory expectedData = abi.encodeCall(IAltoVaultBase.submitCap, (borrowMarkets[i], 0));

            (uint184 cap,,) = IAltoVaultStaticTypes(address(vault)).config(borrowMarkets[i]);
            assertGt(cap, 0, "Vault cap already zero");
            assertEq(target, input.contracts.dusdVault, "Vault cap target");
            assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "Vault cap call value");
            assertEq(data, expectedData, "Vault cap calldata/order");
            _callFrom(curator, target, data, "Vault cap calldata failed");
        }
        assertFalse(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(borrowMarkets.length), "]")),
            "unexpected extra Vault cap call"
        );
    }

    function _assertVaultCapFinalState(address[] memory borrowMarkets) internal view {
        IAltoVaultBase vault = IAltoVaultBase(input.contracts.dusdVault);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            (uint184 cap, bool enabled, uint64 removableAt) =
                IAltoVaultStaticTypes(address(vault)).config(borrowMarkets[i]);
            assertEq(cap, 0, "old BM Vault cap");
            assertTrue(enabled, "old BM Vault config disabled at T0");
            assertEq(removableAt, 0, "old BM removal submitted at T0");
            assertTrue(_isInWithdrawQueue(vault, borrowMarkets[i]), "old BM removed from withdrawal queue at T0");
        }
    }

    function _isInWithdrawQueue(IAltoVaultBase vault, address market) internal view returns (bool) {
        uint256 length = vault.withdrawQueueLength();
        for (uint256 i; i < length; ++i) {
            if (vault.withdrawQueue(i) == market) return true;
        }
        return false;
    }

    function _safeTxPath(string memory batchName, string memory action) internal pure returns (string memory) {
        return string.concat("contracts/deployments/ethereum-mainnet/output/safe-tx-", batchName, "-", action, ".json");
    }

    function _assertAndReadTimelockTransaction(string memory path, bytes4 expectedSelector)
        internal
        view
        returns (bytes memory data)
    {
        assertTrue(vm.exists(path), "Safe JSON not written");
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), input.contracts.timelock, "Safe target");
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "0", "Safe value");
        assertFalse(vm.keyExistsJson(json, ".transactions[1]"), "unexpected extra Safe transaction");
        data = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(bytes4(data), expectedSelector, "Safe selector");
    }

    function _callFrom(address caller, address target, bytes memory data, string memory errorMessage) internal {
        vm.prank(caller);
        (bool success,) = target.call(data);
        assertTrue(success, errorMessage);
    }

    function _assertFrozenWithExpectedIrms(address[] memory markets, address[] memory expectedIrms) internal view {
        for (uint256 i; i < markets.length; ++i) {
            assertTrue(IPausable(markets[i]).paused(FROZEN_TYPE), "market not frozen");
            assertFalse(IPausable(markets[i]).paused(PAUSE_TYPE), "market paused instead of frozen");
            assertEq(IMarket(markets[i]).irm(), expectedIrms[i], "IRM changed before Timelock execution");
        }
    }

    function _predictedIrms(OwnerFixedRateIrmFactory factory, uint256 count)
        internal
        view
        returns (address[] memory irms)
    {
        irms = new address[](count);
        for (uint256 i; i < count; ++i) {
            irms[i] = factory.predictIrmAddress(T0_RATE_SPY, input.contracts.timelock, i);
        }
    }

    function _currentIrms(address[] memory markets) internal view returns (address[] memory irms) {
        irms = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = IMarket(markets[i]).irm();
        }
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

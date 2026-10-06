// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {Balance, IMarket, IMarketBase, MarketType, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
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
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {
    IPegResponsiveExponentialIrm,
    IRState,
    PegResponsiveExponentialIrmConfig
} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {AltoCreditMarketLpOracle} from "@alto/oracles/AltoCreditMarketLpOracle/AltoCreditMarketLpOracle.sol";
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
import {DusdPegCurveOracle} from "@alto/oracles/DusdPegCurveOracle/DusdPegCurveOracle.sol";
import {IDusdPegOracle} from "@alto/oracles/interfaces/IDusdPegOracle.sol";
import {ICurveStableSwapNGOracle} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {
    OwnerPegResponsiveExponentialIrmFactory
} from "@alto/deployments/ethereum-mainnet/OwnerPegResponsiveExponentialIrmFactory.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {
    ZEROX_SWAP_TARGET_MAINNET,
    ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET,
    KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET,
    VELORA_AUGUSTUS_MAINNET,
    NORDSTERN_ROUTER_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IMarketRegistry, MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    FRXUSD_MAINNET,
    WETH_MAINNET,
    WSTETH_MAINNET,
    RETH_MAINNET,
    SUSDE_MAINNET,
    SYRUPUSDC_MAINNET,
    CHAINLINK_ETH_USD_PRICE_FEED,
    CHAINLINK_USDE_USD_PRICE_FEED,
    CHAINLINK_USDC_USD_PRICE_FEED,
    CHAINLINK_FRXUSD_USD_PRICE_FEED,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET,
    CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET,
    CONVEX_BOOSTER_MAINNET,
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET,
    WFRAX_TOKEN_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FeeSourceType} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {
    SDUSDActivationSafeBuilder,
    SDUSDActivationSafeBatch
} from "@alto/deployments/ethereum-mainnet/SDUSDActivationSafeBuilder.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";

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

struct DecodedTimelockBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
    bytes32 predecessor;
    bytes32 salt;
    uint256 delay;
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
        loaded.contracts.ownerFixedRateIrmFactory = _tryParseAddress(json, ".contracts.ownerFixedRateIrmFactory");
        loaded.contracts.ownerPegResponsiveExponentialIrmFactory =
            _tryParseAddress(json, ".contracts.ownerPegResponsiveExponentialIrmFactory");
        loaded.contracts.dusdPegCurveOracle = _tryParseAddress(json, ".contracts.dusdPegCurveOracle");

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
        loaded.contracts.refreshWethMarket = _loadMarketContracts(json, "refreshWeth");
        loaded.contracts.refreshWstethMarket = _loadMarketContracts(json, "refreshWsteth");
        loaded.contracts.refreshRethMarket = _loadMarketContracts(json, "refreshReth");
        loaded.contracts.refreshSusdeBorrowMarket = _loadMarketContracts(json, "refreshSusdeBorrow");
        loaded.contracts.refreshSyrupUsdcBorrowMarket = _loadMarketContracts(json, "refreshSyrupUsdcBorrow");
        loaded.contracts.refreshSusdeMintMarket = _loadMarketContracts(json, "refreshSusdeMint");
        loaded.contracts.refreshSyrupUsdcMintMarket = _loadMarketContracts(json, "refreshSyrupUsdcMint");
        loaded.contracts.refreshFrxUsdMarket = _loadMarketContracts(json, "refreshFrxUsd");
        loaded.contracts.convexCreditLineMarket.market = _tryParseAddress(json, ".contracts.convexCreditLineMarket");
        loaded.contracts.convexCreditLineMarket.marketImplementation =
            _tryParseAddress(json, ".contracts.convexCreditLineMarketImplementation");
        loaded.contracts.convexCreditLineMarket.marketIrm =
            _tryParseAddress(json, ".contracts.convexCreditLineMarketIrm");
        loaded.contracts.convexCreditLineMarket.marketOracle =
            _tryParseAddress(json, ".contracts.convexCreditLineMarketOracle");

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

    function _assertSafeJson(string memory path, bytes4 expectedSelector) internal view {
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
        _assertEmergencyControllerPermissions(input.contracts.refreshSusdeMintMarket.market);
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

contract DeployWethMintMarketPhaseTest is DeployMarketPhaseTestBase {
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-WETH-mint-market-registry-and-authorize-liquidation-periphery-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-WETH-mint-market-registry-and-authorize-liquidation-periphery-execute.json";

    function test_deployWethMintMarketAndExecuteTimelockTransactions() public {
        address legacyMarket = input.contracts.wethMarket.market;
        _deployMarket(DeploymentPhase.MINT_MARKET_WETH);

        MarketContracts memory deployed = input.contracts.refreshWethMarket;
        assertEq(input.contracts.wethMarket.market, legacyMarket, "legacy WETH market changed");
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
        address legacyMarket = input.contracts.wstethMarket.market;
        _deployMarket(DeploymentPhase.MINT_MARKET_WSTETH);

        assertEq(input.contracts.wstethMarket.market, legacyMarket, "legacy wstETH market changed");
        _assertMintMarketParams(
            input.contracts.refreshWstethMarket,
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
        address legacyMarket = input.contracts.rethMarket.market;
        _deployMarket(DeploymentPhase.MINT_MARKET_RETH);

        MarketContracts memory deployed = input.contracts.refreshRethMarket;
        assertEq(input.contracts.rethMarket.market, legacyMarket, "legacy rETH market changed");
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
        address legacyMarket = input.contracts.susdeMintMarket.market;
        _deployMarket(DeploymentPhase.MINT_MARKET_SUSDE);

        MarketContracts memory deployed = input.contracts.refreshSusdeMintMarket;
        assertEq(input.contracts.susdeMintMarket.market, legacyMarket, "legacy sUSDe mint market changed");
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
        address legacyMarket = input.contracts.susdeBorrowMarket.market;
        _deployMarket(DeploymentPhase.BORROW_MARKET_SUSDE);

        MarketContracts memory deployed = input.contracts.refreshSusdeBorrowMarket;
        assertEq(input.contracts.susdeBorrowMarket.market, legacyMarket, "legacy sUSDe borrow market changed");
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
        address legacyMarket = input.contracts.syrupUsdcBorrowMarket.market;
        _deployMarket(DeploymentPhase.BORROW_MARKET_SYRUP_USDC);

        assertEq(input.contracts.syrupUsdcBorrowMarket.market, legacyMarket, "legacy syrupUSDC borrow market changed");
        _assertBorrowMarketParams(
            input.contracts.refreshSyrupUsdcBorrowMarket,
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
        address legacyMarket = input.contracts.syrupUsdcMintMarket.market;
        _deployMarket(DeploymentPhase.MINT_MARKET_SYRUPUSDC);

        MarketContracts memory deployed = input.contracts.refreshSyrupUsdcMintMarket;
        assertEq(input.contracts.syrupUsdcMintMarket.market, legacyMarket, "legacy syrupUSDC mint market changed");
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
        address legacyMarket = input.contracts.frxUsdMarket.market;
        _deployMarket(DeploymentPhase.MINT_MARKET_FRXUSD);

        MarketContracts memory deployed = input.contracts.refreshFrxUsdMarket;
        assertEq(input.contracts.frxUsdMarket.market, legacyMarket, "legacy frxUSD market changed");
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

contract DeployConvexCreditLineMarketPhaseTest is DeployMarketPhaseTestBase {
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-frxusd-dusd-convex-credit-line-market-registry-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-frxusd-dusd-convex-credit-line-market-registry-execute.json";

    function test_deployConvexCreditLineMarketAndExecuteTimelockTransactions() public {
        _deployMarket(DeploymentPhase.CONVEX_CREDIT_LINE_MARKET);

        AltoConvexCreditLineMarket market = AltoConvexCreditLineMarket(input.contracts.convexCreditLineMarket.market);
        FixedRateIrm irm = FixedRateIrm(input.contracts.convexCreditLineMarket.marketIrm);

        assertTrue(address(market).code.length > 0, "market");
        address marketImplementation = input.contracts.convexCreditLineMarket.marketImplementation;
        assertTrue(marketImplementation.code.length > 0, "implementation");
        assertNotEq(address(market), marketImplementation, "proxy and implementation");
        assertEq(Upgrades.getImplementationAddress(address(market)), marketImplementation, "proxy implementation");
        address marketOracle = input.contracts.convexCreditLineMarket.marketOracle;
        assertTrue(marketOracle.code.length > 0, "oracle");
        assertEq(
            keccak256(marketOracle.code), keccak256(type(AltoCreditMarketLpOracle).runtimeCode), "oracle implementation"
        );
        assertEq(AltoCreditMarketLpOracle(marketOracle).getPrice(), 1e36, "oracle price");
        assertEq(uint256(market.MARKET_TYPE()), uint256(MarketType.CREDIT_MINT), "market type");
        assertEq(market.borrowToken(), input.contracts.dusd, "borrow token");
        assertEq(market.collateralToken(), FRXUSD_DUSD_CURVE_POOL_MAINNET, "collateral token");
        assertEq(market.irm(), address(irm), "IRM");
        assertEq(market.oracle(), marketOracle, "oracle");
        assertEq(market.liquidationEngine(), address(0), "liquidation engine");
        assertEq(market.maxLtv(), 0.8 ether, "max LTV");
        assertEq(market.foreclosureLtv(), 0.9 ether, "foreclosure LTV");
        assertEq(market.borrowOpeningFee(), 0, "borrow opening fee");
        assertEq(market.creditAccount(), TREASURY_MULTISIG, "credit account");
        assertEq(market.feeRecipient(), input.contracts.feeRecipientMintMarkets, "fee recipient");

        Balance memory supply = IMarket(address(market)).totalSupply();
        Balance memory borrowed = IMarket(address(market)).totalBorrowed();
        assertEq(supply.assets, 1_000_000 ether, "credit limit");
        Position memory creditPosition = IMarket(address(market)).position(TREASURY_MULTISIG);
        assertEq(creditPosition.supplyShares, 0, "credit-account supply shares");
        assertEq(creditPosition.borrowShares, 0, "credit-account borrow shares");
        assertEq(creditPosition.collateralAssets, 0, "credit-account collateral");
        assertEq(supply.shares, 0, "supply shares");
        assertEq(borrowed.assets, 0, "borrowed assets");
        assertEq(borrowed.shares, 0, "borrowed shares");
        assertEq(market.claimableFeesAssets(), 0, "claimable fees");
        assertEq(market.badDebtAssets(), 0, "bad debt");

        assertEq(market.convexBooster(), CONVEX_BOOSTER_MAINNET, "Convex Booster");
        assertEq(market.convexPoolId(), POOL_ID_FRXUSD_DUSD_CURVE_POOL_MAINNET, "Convex pool id");
        assertEq(market.convexRewardPool(), CONVEX_REWARD_POOL_CVX_FRXUSD_DUSD_MAINNET, "Convex reward pool");
        assertTrue(market.convexActive(), "Convex strategy active");
        assertEq(market.rewardRecipient(), TREASURY_MULTISIG, "reward recipient");
        assertEq(market.rewardToken(0), CRV_TOKEN_MAINNET, "CRV reward");
        assertEq(market.rewardToken(1), CVX_TOKEN_MAINNET, "CVX reward");
        assertEq(market.rewardToken(2), WFRAX_TOKEN_MAINNET, "WFRAX reward");
        vm.expectRevert();
        market.rewardToken(3);

        assertEq(Ownable(address(market)).owner(), input.contracts.timelock, "market owner");
        assertEq(Ownable(address(irm)).owner(), input.contracts.timelock, "IRM owner");
        (uint256 borrowRate,) = irm.irState();
        assertEq(borrowRate, 0.04 ether / uint256(365 days), "borrow rate");
        assertEq(market.pendingOwner(), address(0), "market pending owner");
        assertEq(irm.pendingOwner(), address(0), "IRM pending owner");
        assertFalse(market.paused(PAUSE_TYPE), "market initially paused");
        assertFalse(market.paused(FROZEN_TYPE), "market initially frozen");
        assertEq(irm.market(), address(market), "IRM market");
        assertTrue(Pausable(address(market)).pausers(PRODUCTION_FREEZER, PAUSE_TYPE), "production pauser");
        assertTrue(Pausable(address(market)).pausers(PRODUCTION_FREEZER, FROZEN_TYPE), "production freezer");
        assertTrue(Pausable(address(market)).pausers(FUTURE_EMERGENCY_CONTROLLER, PAUSE_TYPE), "controller pauser");
        assertTrue(Pausable(address(market)).pausers(FUTURE_EMERGENCY_CONTROLLER, FROZEN_TYPE), "controller freezer");
        assertFalse(Pausable(address(market)).pausers(params.deployer, PAUSE_TYPE), "deployer pauser");
        assertFalse(Pausable(address(market)).pausers(params.deployer, FROZEN_TYPE), "deployer freezer");

        _assertCreditMarketGovernance(address(market), false);
        _assertSafeJson(SCHEDULE_JSON, TimelockController.scheduleBatch.selector);
        _assertSafeJson(EXECUTE_JSON, TimelockController.executeBatch.selector);
        _executeSafeTimelockBatch(SCHEDULE_JSON, EXECUTE_JSON);
        _assertCreditMarketGovernance(address(market), true);

        assertFalse(
            AltoAdapter(payable(input.contracts.altoAdapter)).isApprovedContract(address(market)),
            "credit market should not be adapter-approved"
        );
        assertFalse(
            ILiquidationPeripheryBase(input.contracts.liquidationPeriphery).supportedMarkets(address(market)),
            "credit market should not be supported by liquidation periphery"
        );
        assertFalse(
            market.authorizedLiquidationPeriphery(input.contracts.liquidationPeriphery),
            "credit market should not authorize liquidation periphery"
        );

        _assertFullyDrawnMarketCanRepayAfterInterest(market);
    }

    function test_deployConvexCreditLineMarketWithDirectFinalization() public {
        params.phase = DeploymentPhase.CONVEX_CREDIT_LINE_MARKET;
        params.deployerHasOwnership = true;

        vm.startPrank(input.contracts.timelock);
        input = DeployAltoEthereumMainnet.deploy(params, input);
        vm.stopPrank();

        AltoConvexCreditLineMarket market = AltoConvexCreditLineMarket(input.contracts.convexCreditLineMarket.market);
        _assertCreditMarketGovernance(address(market), true);
        _assertFullyDrawnMarketCanRepayAfterInterest(market);
    }

    function _assertFullyDrawnMarketCanRepayAfterInterest(AltoConvexCreditLineMarket market) private {
        uint256 creditLimit = IMarket(address(market)).totalSupply().assets;
        uint256 collateral = 2_000_000 ether;
        deal(market.collateralToken(), TREASURY_MULTISIG, collateral);

        vm.startPrank(TREASURY_MULTISIG);
        IERC20Metadata(market.collateralToken()).approve(address(market), collateral);
        market.addCollateral(collateral, TREASURY_MULTISIG);
        market.borrow(creditLimit, 0, TREASURY_MULTISIG, TREASURY_MULTISIG, "");
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);
        market.accrueInterest();
        uint256 interest = market.claimableFeesAssets();
        assertGt(interest, 0, "interest accrued above fully drawn credit limit");

        IERC20Metadata dusd = IERC20Metadata(input.contracts.dusd);
        uint256 recipientBalanceBefore = dusd.balanceOf(market.feeRecipient());
        vm.prank(TREASURY_MULTISIG);
        (uint256 repaidAssets,) = market.repay(1 ether, 0, TREASURY_MULTISIG);

        assertEq(repaidAssets, 1 ether, "repayment succeeds while debt exceeds credit limit");
        assertEq(market.claimableFeesAssets(), 0, "repayment claims interest");
        assertEq(dusd.balanceOf(market.feeRecipient()), recipientBalanceBefore + interest, "interest minted");
        (uint256 minted,) = IDUSD(input.contracts.dusd).minterConfig(address(market));
        assertEq(minted, creditLimit + interest - repaidAssets, "minted debt after repayment");
    }

    function _assertCreditMarketGovernance(address market, bool enabled) private view {
        assertEq(IMarketRegistry(input.contracts.marketRegistry).isMintMarket(market), enabled, "registry status");

        IDUSD dusd = IDUSD(input.contracts.dusd);
        assertEq(dusd.allowedMinter(market), enabled, "DUSD minter status");
        assertEq(dusd.allowedBurner(market), enabled, "DUSD burner status");
        (uint256 minted, uint256 ceiling) = dusd.minterConfig(market);
        assertEq(minted, 0, "initial minted amount");
        assertEq(ceiling, enabled ? 1_166_666_666_666_666_666_666_666 : 0, "DUSD minter ceiling");
    }
}

contract DeployPegResponsiveIrmMigrationPhaseTest is DeployAltoEthereumMainnetTestBase {
    uint256 internal constant FORK_BLOCK = 25_988_862;
    uint256 internal constant IRM_VERSION = 1;
    uint256 internal constant TEST_PEG_PRICE = 0.999e18;
    uint256 internal constant YEAR = 365 days;
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-mint-market-peg-responsive-irm-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-mint-market-peg-responsive-irm-execute.json";

    bool internal scheduleJsonExisted;
    bool internal executeJsonExisted;
    string internal scheduleJsonBefore;
    string internal executeJsonBefore;

    function setUp() public override {
        super.setUp();
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
        _loadCurrentChainInput();

        params.timelockAdmin = MAINNET_TIMELOCK_ADMIN;
        params.phase = DeploymentPhase.MINT_MARKET_PEG_RESPONSIVE_IRM;

        scheduleJsonExisted = vm.exists(SCHEDULE_JSON);
        executeJsonExisted = vm.exists(EXECUTE_JSON);
        if (scheduleJsonExisted) scheduleJsonBefore = vm.readFile(SCHEDULE_JSON);
        if (executeJsonExisted) executeJsonBefore = vm.readFile(EXECUTE_JSON);
    }

    function _restoreOutputFiles() private {
        _restoreOutputFile(SCHEDULE_JSON, scheduleJsonExisted, scheduleJsonBefore);
        _restoreOutputFile(EXECUTE_JSON, executeJsonExisted, executeJsonBefore);
    }

    function test_deployGeneratedTimelockBatchUpdatesAllActiveMintMarketIrms() public {
        address[] memory markets = _activeMintMarkets();
        address[] memory oldIrms = _currentIrms(markets);

        _mockCurveObservationTimestamp(uint48(block.timestamp));
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _assertFactoryAndOracle();

        PegResponsiveExponentialIrmConfig memory config = _expectedIrmConfig();
        address[] memory predictedIrms = _predictedIrms(markets, config);
        _assertGeneratedBatch(markets, predictedIrms, config);

        for (uint256 i; i < predictedIrms.length; ++i) {
            assertEq(predictedIrms[i].code.length, 0, "IRM deployed before timelock execution");
            assertEq(IMarketBase(markets[i]).irm(), oldIrms[i], "market IRM changed before execution");
        }

        _executeSafeFile(SCHEDULE_JSON);

        vm.expectRevert(bytes("Timelock not ready"));
        this.preflightExternal(input);

        TimelockController timelock = TimelockController(payable(input.contracts.timelock));
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        _mockOracleObservation(uint48(block.timestamp - 30 minutes));
        DeployAltoEthereumMainnet.preflightPegResponsiveIrmMigration(input);

        _mockOracleObservation(uint48(block.timestamp - 30 minutes - 1));
        vm.expectRevert(bytes("Stale peg price"));
        this.preflightExternal(input);

        _mockOracleObservation(uint48(block.timestamp));
        DeployAltoEthereumMainnet.preflightPegResponsiveIrmMigration(input);

        _executeSafeFile(EXECUTE_JSON);
        input = DeployAltoEthereumMainnet.reconcilePegResponsiveIrmMigration(input);

        _assertFinalState(markets, oldIrms, predictedIrms, config);
        _assertOperationDone(timelock);
        _restoreOutputFiles();
    }

    function _mockCurveObservationTimestamp(uint48 observedAt) private {
        vm.mockCall(
            FRXUSD_DUSD_CURVE_POOL_MAINNET,
            abi.encodeCall(ICurveStableSwapNGOracle.ma_last_time, ()),
            abi.encode(uint256(observedAt))
        );
    }

    function _mockOracleObservation(uint48 observedAt) private {
        vm.mockCall(
            input.contracts.dusdPegCurveOracle,
            abi.encodeCall(IDusdPegOracle.getPrice, ()),
            abi.encode(TEST_PEG_PRICE, observedAt, true)
        );
    }

    function preflightExternal(AltoEthereumMainnetInput memory deploymentInput) external view {
        DeployAltoEthereumMainnet.preflightPegResponsiveIrmMigration(deploymentInput);
    }

    function _assertFactoryAndOracle() private view {
        address timelock = input.contracts.timelock;
        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        DusdPegCurveOracle oracle = DusdPegCurveOracle(input.contracts.dusdPegCurveOracle);

        assertGt(address(factory).code.length, 0, "factory code");
        assertEq(factory.owner(), timelock, "factory owner");
        assertEq(factory.pendingOwner(), address(0), "factory pending owner");
        assertEq(factory.pegOracle(), address(oracle), "factory peg oracle");

        assertGt(address(oracle).code.length, 0, "oracle code");
        assertEq(oracle.owner(), timelock, "oracle owner");
        assertEq(oracle.pendingOwner(), address(0), "oracle pending owner");
        assertEq(oracle.curvePool(), FRXUSD_DUSD_CURVE_POOL_MAINNET, "oracle Curve pool");
        (uint256 maExpTime, uint256 aPrecise) = oracle.runtimeConfig();
        assertEq(maExpTime, 866, "oracle EMA time");
        assertEq(aPrecise, 100_000, "oracle precise A");
    }

    function _assertGeneratedBatch(
        address[] memory markets,
        address[] memory predictedIrms,
        PegResponsiveExponentialIrmConfig memory config
    ) private view {
        _assertSafeJson(SCHEDULE_JSON, TimelockController.scheduleBatch.selector);
        _assertSafeJson(EXECUTE_JSON, TimelockController.executeBatch.selector);

        DecodedTimelockBatch memory scheduleBatch = _decodeScheduleBatch(_readSafeTxData(SCHEDULE_JSON));
        DecodedTimelockBatch memory executeBatch = _decodeExecuteBatch(_readSafeTxData(EXECUTE_JSON));

        assertEq(scheduleBatch.targets.length, markets.length * 3, "schedule target count");
        assertEq(scheduleBatch.values.length, scheduleBatch.targets.length, "schedule value count");
        assertEq(scheduleBatch.payloads.length, scheduleBatch.targets.length, "schedule payload count");
        assertEq(scheduleBatch.predecessor, bytes32(0), "schedule predecessor");
        assertEq(scheduleBatch.salt, bytes32(0), "schedule salt");
        assertEq(
            scheduleBatch.delay, TimelockController(payable(input.contracts.timelock)).getMinDelay(), "schedule delay"
        );

        assertEq(keccak256(abi.encode(executeBatch.targets)), keccak256(abi.encode(scheduleBatch.targets)), "targets");
        assertEq(keccak256(abi.encode(executeBatch.values)), keccak256(abi.encode(scheduleBatch.values)), "values");
        assertEq(
            keccak256(abi.encode(executeBatch.payloads)), keccak256(abi.encode(scheduleBatch.payloads)), "payloads"
        );
        assertEq(executeBatch.predecessor, bytes32(0), "execute predecessor");
        assertEq(executeBatch.salt, bytes32(0), "execute salt");

        address factory = input.contracts.ownerPegResponsiveExponentialIrmFactory;
        for (uint256 i; i < markets.length; ++i) {
            uint256 callIndex = i * 3;
            assertEq(scheduleBatch.targets[callIndex], factory, "deploy target");
            assertEq(scheduleBatch.values[callIndex], 0, "deploy value");
            assertEq(
                scheduleBatch.payloads[callIndex],
                abi.encodeCall(OwnerPegResponsiveExponentialIrmFactory.deploy, (markets[i], IRM_VERSION, config)),
                "deploy payload"
            );

            assertEq(scheduleBatch.targets[callIndex + 1], markets[i], "setIrm target");
            assertEq(scheduleBatch.values[callIndex + 1], 0, "setIrm value");
            assertEq(
                scheduleBatch.payloads[callIndex + 1],
                abi.encodeCall(IMarketBase.setIrm, (predictedIrms[i], false)),
                "setIrm payload"
            );

            assertEq(scheduleBatch.targets[callIndex + 2], markets[i], "accrueInterest target");
            assertEq(scheduleBatch.values[callIndex + 2], 0, "accrueInterest value");
            assertEq(
                scheduleBatch.payloads[callIndex + 2],
                abi.encodeCall(IMarketBase.accrueInterest, ()),
                "accrueInterest payload"
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

    function _assertFinalState(
        address[] memory markets,
        address[] memory oldIrms,
        address[] memory predictedIrms,
        PegResponsiveExponentialIrmConfig memory expectedConfig
    ) private view {
        address timelock = input.contracts.timelock;
        address oracle = input.contracts.dusdPegCurveOracle;
        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);

        for (uint256 i; i < markets.length; ++i) {
            address irmAddress = predictedIrms[i];
            PegResponsiveExponentialIrm irm = PegResponsiveExponentialIrm(irmAddress);

            assertNotEq(irmAddress, oldIrms[i], "IRM must change");
            assertEq(IMarketBase(markets[i]).irm(), irmAddress, "market IRM");
            assertEq(Ownable(markets[i]).owner(), timelock, "market owner");
            assertEq(irm.owner(), timelock, "IRM owner");
            assertEq(irm.pendingOwner(), address(0), "IRM pending owner");
            assertEq(irm.market(), markets[i], "IRM market");
            assertEq(irm.pegOracle(), oracle, "IRM peg oracle");
            assertEq(uint256(irm.IRM_TYPE()), uint256(IRMType.PEG_RESPONSIVE_EXPONENTIAL), "IRM type");

            _assertPriceDerivedState(irmAddress, expectedConfig.baseRate);

            PegResponsiveExponentialIrmConfig memory actualConfig = IPegResponsiveExponentialIrm(irmAddress).irmConfig();
            assertEq(keccak256(abi.encode(actualConfig)), keccak256(abi.encode(expectedConfig)), "IRM configuration");

            (address recordedIrm, address recordedOwner, address recordedOracle) =
                factory.deployments(markets[i], IRM_VERSION);
            assertEq(recordedIrm, irmAddress, "factory IRM");
            assertEq(recordedOwner, timelock, "factory IRM owner");
            assertEq(recordedOracle, oracle, "factory IRM oracle");
            assertEq(_storedTargetIrm(i), irmAddress, "reconciled IRM");
            assertEq(FixedRateIrm(oldIrms[i]).market(), markets[i], "old IRM binding");
        }
    }

    function _assertPriceDerivedState(address irmAddress, uint256 expectedBaseRate) private view {
        PegResponsiveExponentialIrm irm = PegResponsiveExponentialIrm(irmAddress);
        IRState memory state = IPegResponsiveExponentialIrm(irmAddress).irState();
        assertEq(state.borrowRate, irm.targetBorrowRate(TEST_PEG_PRICE), "price-derived borrow rate");
        assertGt(state.borrowRate, expectedBaseRate, "depeg must increase borrow rate");
        assertEq(state.lastUpdate, block.timestamp, "IRM checkpoint timestamp");
        assertTrue(state.stressMode, "depeg must enter stress mode");
    }

    function _assertOperationDone(TimelockController timelock) private view {
        DecodedTimelockBatch memory batch = _decodeScheduleBatch(_readSafeTxData(SCHEDULE_JSON));
        bytes32 operationId =
            timelock.hashOperationBatch(batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt);
        assertTrue(timelock.isOperationDone(operationId), "timelock operation not done");
    }

    function _executeSafeFile(string memory path) private {
        string memory json = vm.readFile(path);
        address target = vm.parseJsonAddress(json, ".transactions[0].to");
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(target, input.contracts.timelock, "Safe target");

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool success,) = target.call(data);
        assertTrue(success, "generated Safe transaction failed");
    }

    function _decodeScheduleBatch(bytes memory data) private pure returns (DecodedTimelockBatch memory batch) {
        assertEq(bytes4(data), TimelockController.scheduleBatch.selector, "schedule selector");
        (batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt, batch.delay) =
            abi.decode(_removeSelector(data), (address[], uint256[], bytes[], bytes32, bytes32, uint256));
    }

    function _decodeExecuteBatch(bytes memory data) private pure returns (DecodedTimelockBatch memory batch) {
        assertEq(bytes4(data), TimelockController.executeBatch.selector, "execute selector");
        (batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt) =
            abi.decode(_removeSelector(data), (address[], uint256[], bytes[], bytes32, bytes32));
    }

    function _removeSelector(bytes memory data) private pure returns (bytes memory arguments) {
        require(data.length >= 4, "missing selector");
        arguments = new bytes(data.length - 4);
        for (uint256 i; i < arguments.length; ++i) {
            arguments[i] = data[i + 4];
        }
    }

    function _predictedIrms(address[] memory markets, PegResponsiveExponentialIrmConfig memory config)
        private
        view
        returns (address[] memory irms)
    {
        OwnerPegResponsiveExponentialIrmFactory factory =
            OwnerPegResponsiveExponentialIrmFactory(input.contracts.ownerPegResponsiveExponentialIrmFactory);
        irms = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = factory.predictIrmAddress(markets[i], IRM_VERSION, config);
        }
    }

    function _currentIrms(address[] memory markets) private view returns (address[] memory irms) {
        irms = new address[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            irms[i] = IMarketBase(markets[i]).irm();
        }
    }

    function _activeMintMarkets() private view returns (address[] memory markets) {
        markets = new address[](6);
        markets[0] = input.contracts.refreshWethMarket.market;
        markets[1] = input.contracts.refreshWstethMarket.market;
        markets[2] = input.contracts.refreshRethMarket.market;
        markets[3] = input.contracts.refreshSusdeMintMarket.market;
        markets[4] = input.contracts.refreshSyrupUsdcMintMarket.market;
        markets[5] = input.contracts.refreshFrxUsdMarket.market;
    }

    function _storedTargetIrm(uint256 index) private view returns (address) {
        if (index == 0) return input.contracts.refreshWethMarket.marketIrm;
        if (index == 1) return input.contracts.refreshWstethMarket.marketIrm;
        if (index == 2) return input.contracts.refreshRethMarket.marketIrm;
        if (index == 3) return input.contracts.refreshSusdeMintMarket.marketIrm;
        if (index == 4) return input.contracts.refreshSyrupUsdcMintMarket.marketIrm;
        return input.contracts.refreshFrxUsdMarket.marketIrm;
    }

    function _expectedIrmConfig() private pure returns (PegResponsiveExponentialIrmConfig memory) {
        return PegResponsiveExponentialIrmConfig({
            recoveryPrice: 1.001e18,
            stressPrice: 1e18,
            baseRate: 0.05e18 / YEAR,
            stressRate: 0.075e18 / YEAR,
            maxRate: 8e18 / YEAR,
            doublingDistance: 0.0025e18,
            recoveryDelay: 6 hours,
            maxOracleAge: 30 minutes
        });
    }

    function _restoreOutputFile(string memory path, bool existed, string storage previousContents) private {
        if (existed) {
            vm.writeFile(path, previousContents);
        } else if (vm.exists(path)) {
            vm.removeFile(path);
        }
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

interface ISdusdPauserSafeOwners {
    function getOwners() external view returns (address[] memory);
}

contract SDUSDMainnetDeploymentForkTest is DeployAltoEthereumMainnetTestBase {
    uint256 internal constant MAINNET_FORK_BLOCK = 26096500;
    bytes32 private _originalControllerConfiguration;
    address private _originalControllerImplementation;

    string internal constant ACTIVATION_SCHEDULE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-activation-schedule.json";
    string internal constant ACTIVATION_EXECUTE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-activation-execute.json";

    struct LegacyFeePositionSnapshot {
        uint256 supplyShares;
        uint256 collateralAssets;
    }

    struct LegacyVaultFeeSnapshot {
        address feeRecipient;
        uint256 recipientShares;
    }

    function setUp() public override {
        super.setUp();
        vm.createSelectFork(vm.rpcUrl("ethereum"), MAINNET_FORK_BLOCK);
        params.freezer = address(EmergencyController(input.contracts.emergencyController).pauserSafe());
        _originalControllerConfiguration = _controllerConfigurationHash();
        _originalControllerImplementation = Upgrades.getImplementationAddress(input.contracts.emergencyController);
    }

    function testFork_DeploySeedAndActivate() public {
        address[] memory borrowMarkets = IMarketRegistry(input.contracts.marketRegistry).getBorrowMarkets();
        address[] memory mintMarkets = IMarketRegistry(input.contracts.marketRegistry).getMintMarkets();
        address[] memory usms = IUsmRegistry(input.contracts.usmRegistry).getUsmList();
        address[] memory registeredVaults = IVaultRegistry(input.contracts.vaultRegistry).getVaultList();
        LegacyVaultFeeSnapshot[] memory vaultSnapshots = _snapshotLegacyVaultFees(registeredVaults);

        (LegacyFeePositionSnapshot[] memory borrowSnapshots, uint256 borrowCollateralMarketCount) =
            _snapshotLegacyPositions(borrowMarkets, input.contracts.feeRecipient, true);
        (LegacyFeePositionSnapshot[] memory mintSnapshots, uint256 mintCollateralMarketCount) =
            _snapshotLegacyPositions(mintMarkets, input.contracts.feeRecipientMintMarkets, false);

        assertEq(borrowCollateralMarketCount, 5, "unexpected borrow collateral market count");
        assertEq(mintCollateralMarketCount, 5, "unexpected mint collateral market count");

        address[] memory originalUsmFeeRecipients = new address[](usms.length);
        for (uint256 i; i < usms.length; ++i) {
            originalUsmFeeRecipients[i] = IStableTokenFacilitator(usms[i]).getFeeRecipient();
        }

        params.phase = DeploymentPhase.SDUSD;
        vm.recordLogs();
        input = DeployAltoEthereumMainnet.deploy(params, input);
        _assertTemporaryPausersRemoved(vm.getRecordedLogs());
        assertEq(
            Upgrades.getImplementationAddress(input.contracts.emergencyController), _originalControllerImplementation
        );

        ProtocolFeeCollector collector = ProtocolFeeCollector(input.contracts.protocolFeeCollector);
        SDUSD vault = SDUSD(input.contracts.sdusd);

        assertGt(input.contracts.protocolFeeCollectorImplementation.code.length, 0);
        assertGt(input.contracts.sdusdImplementation.code.length, 0);
        assertEq(
            Upgrades.getImplementationAddress(address(collector)),
            input.contracts.protocolFeeCollectorImplementation,
            "collector proxy implementation"
        );
        assertEq(
            Upgrades.getImplementationAddress(address(vault)),
            input.contracts.sdusdImplementation,
            "vault proxy implementation"
        );
        assertEq(collector.owner(), input.contracts.timelock);
        assertEq(vault.owner(), input.contracts.timelock);
        assertEq(vault.rewarder(), address(collector));
        assertEq(collector.treasury(), params.treasuryMultisig);
        assertEq(collector.manualSwapReceiver(), params.treasuryMultisig);
        assertEq(collector.rewardsBps(), 10_000);
        assertEq(collector.minimumRewardAmount(), 100 ether);
        assertTrue(collector.isCollateralOperator(params.treasuryMultisig));
        assertEq(vault.seedShares(), 1 ether);
        assertEq(vault.depositCap(), 250_000 ether);
        assertEq(vault.rewardDuration(), 7 days);
        assertTrue(collector.pausers(params.freezer, PAUSE_TYPE));
        assertTrue(collector.pausers(input.contracts.emergencyController, PAUSE_TYPE));
        assertTrue(vault.pausers(params.freezer, PAUSE_TYPE));
        assertTrue(vault.pausers(input.contracts.emergencyController, PAUSE_TYPE));
        assertTrue(vault.pausers(params.freezer, FROZEN_TYPE));
        assertTrue(vault.pausers(input.contracts.emergencyController, FROZEN_TYPE));
        assertFalse(vault.pausers(input.contracts.timelock, PAUSE_TYPE));
        assertFalse(vault.pausers(input.contracts.timelock, FROZEN_TYPE));
        assertFalse(collector.pausers(input.contracts.timelock, PAUSE_TYPE));
        assertFalse(
            AltoAdapter(payable(input.contracts.altoAdapter)).isApprovedContract(address(vault)),
            "sDUSD approved on AltoAdapter before activation"
        );

        deal(input.contracts.dusd, address(this), 1 ether);
        IDUSD(input.contracts.dusd).approve(address(vault), 1 ether);
        assertEq(vault.deposit(1 ether, address(1)), 1 ether, "seed must mint one share per DUSD");
        assertEq(vault.totalAssets(), 1 ether);
        assertEq(vault.depositCapUsage(), 0, "seed must not consume deposit-cap headroom");

        params.phase = DeploymentPhase.SDUSD_ACTIVATION;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _scheduleTimelockBatch(input.contracts.timelock, ACTIVATION_SCHEDULE_PATH);

        uint256 activationDelay = TimelockController(payable(input.contracts.timelock)).getMinDelay();
        vm.warp(block.timestamp + activationDelay + 1);

        _executeActivationAndAssertCreditLineRouting();

        assertEq(_controllerConfigurationHash(), _originalControllerConfiguration, "controller configuration changed");
        assertEq(
            Upgrades.getImplementationAddress(input.contracts.emergencyController),
            _originalControllerImplementation,
            "controller implementation changed"
        );
        EmergencyController controller = EmergencyController(input.contracts.emergencyController);
        assertTrue(controller.contractWhitelist(address(vault)));
        assertTrue(controller.contractWhitelist(address(collector)));
        assertTrue(
            AltoAdapter(payable(input.contracts.altoAdapter)).isApprovedContract(address(vault)),
            "sDUSD not approved on AltoAdapter"
        );
        assertEq(collector.sdusdVault(), address(vault));
        assertEq(
            address(collector.vaultRegistry()), input.contracts.vaultRegistry, "collector vault registry not configured"
        );
        assertGe(
            vault.balanceOf(address(1)), vault.seedShares(), "required seed shares must remain locked after activation"
        );
        _assertActivationPreservedLegacyPositions(
            borrowMarkets, input.contracts.feeRecipient, borrowSnapshots, address(collector), true
        );
        _assertActivationPreservedLegacyPositions(
            mintMarkets, input.contracts.feeRecipientMintMarkets, mintSnapshots, address(collector), false
        );
        _assertAncillaryFeeSourcesActivated(usms, originalUsmFeeRecipients, address(collector));
        _assertVaultFeeSourcesActivated(registeredVaults, vaultSnapshots, address(collector));
        _assertEmergencyControls(vault, collector);
    }

    function testFork_ActivationSkipsExistingAltoAdapterApproval() public {
        params.phase = DeploymentPhase.SDUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        SDUSDActivationSafeBatch memory withApproval = SDUSDActivationSafeBuilder.buildActivationBatch(input);
        assertEq(_altoAdapterApprovalCalls(withApproval), 1, "missing AltoAdapter approval");

        vm.prank(input.contracts.timelock);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.sdusd);

        SDUSDActivationSafeBatch memory withoutApproval = SDUSDActivationSafeBuilder.buildActivationBatch(input);
        assertEq(_altoAdapterApprovalCalls(withoutApproval), 0, "existing AltoAdapter approval not skipped");
        assertEq(withoutApproval.targets.length + 1, withApproval.targets.length, "unexpected call count");
    }

    function testFork_DeploymentRejectsMismatchedPauserSafe() public {
        params.phase = DeploymentPhase.SDUSD;
        params.freezer = makeAddr("wrongPauserSafe");
        vm.expectRevert("Unexpected emergency controller Pauser Safe");
        this.deploySdusdExternal();
    }

    function testFork_PauserMultisigCanPauseAndClearSdusdEmergencyControls() public {
        params.phase = DeploymentPhase.SDUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        ProtocolFeeCollector collector = ProtocolFeeCollector(input.contracts.protocolFeeCollector);
        SDUSD vault = SDUSD(input.contracts.sdusd);

        vm.startPrank(params.freezer);
        collector.pause(PAUSE_TYPE, true);
        vault.pause(PAUSE_TYPE, true);
        vault.pause(FROZEN_TYPE, true);
        vm.stopPrank();

        assertTrue(collector.paused(PAUSE_TYPE));
        assertTrue(vault.paused(PAUSE_TYPE));
        assertTrue(vault.paused(FROZEN_TYPE));

        vm.startPrank(params.freezer);
        collector.pause(PAUSE_TYPE, false);
        vault.pause(PAUSE_TYPE, false);
        vault.pause(FROZEN_TYPE, false);
        vm.stopPrank();

        assertFalse(collector.paused(PAUSE_TYPE));
        assertFalse(vault.paused(PAUSE_TYPE));
        assertFalse(vault.paused(FROZEN_TYPE));
    }

    function testFork_ActivationRejectsMissingFreezePermission() public {
        params.phase = DeploymentPhase.SDUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);
        vm.prank(input.contracts.timelock);
        SDUSD(input.contracts.sdusd).setPauser(input.contracts.emergencyController, FROZEN_TYPE, false);
        vm.expectRevert("Missing emergency controller permissions");
        this.buildActivationExternal();
    }

    function testFork_ActivationRejectsMissingSafePermission() public {
        params.phase = DeploymentPhase.SDUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);
        vm.prank(input.contracts.timelock);
        ProtocolFeeCollector(input.contracts.protocolFeeCollector).setPauser(params.freezer, PAUSE_TYPE, false);
        vm.expectRevert("Missing Pauser Safe permissions");
        this.buildActivationExternal();
    }

    function deploySdusdExternal() external {
        DeployAltoEthereumMainnet.deploy(params, input);
    }

    function buildActivationExternal() external view {
        SDUSDActivationSafeBuilder.buildActivationBatch(input);
    }

    function _altoAdapterApprovalCalls(SDUSDActivationSafeBatch memory batch) private view returns (uint256 count) {
        bytes memory expectedPayload = abi.encodeCall(AdapterContractApproval.approveContract, (input.contracts.sdusd));
        for (uint256 i; i < batch.targets.length; ++i) {
            if (batch.targets[i] != input.contracts.altoAdapter) continue;
            assertEq(batch.payloads[i], expectedPayload, "unexpected AltoAdapter call");
            ++count;
        }
    }

    function _controllerConfigurationHash() private view returns (bytes32) {
        EmergencyController controller = EmergencyController(input.contracts.emergencyController);
        return keccak256(
            abi.encode(
                controller.owner(),
                controller.pendingOwner(),
                address(controller.pauserSafe()),
                address(controller.marketRegistry()),
                address(controller.usmRegistry())
            )
        );
    }

    function _assertTemporaryPausersRemoved(Vm.Log[] memory logs) private view {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (entry.emitter != input.contracts.sdusd && entry.emitter != input.contracts.protocolFeeCollector) {
                continue;
            }
            if (entry.topics[0] != keccak256("PauserUpdated(address,bytes32,bool)")) continue;
            address pauser = address(uint160(uint256(entry.topics[1])));
            if (pauser == params.freezer || pauser == input.contracts.emergencyController) continue;
            (bytes32 pauseType,) = abi.decode(entry.data, (bytes32, bool));
            assertFalse(Pausable(entry.emitter).pausers(pauser, pauseType), "temporary pauser retained permission");
        }
    }

    function _assertEmergencyControls(SDUSD vault, ProtocolFeeCollector collector) private {
        EmergencyController controller = EmergencyController(input.contracts.emergencyController);
        address responder = ISdusdPauserSafeOwners(params.freezer).getOwners()[0];
        deal(input.contracts.dusd, address(this), 10 ether);
        IDUSD(input.contracts.dusd).approve(address(vault), type(uint256).max);
        vault.deposit(5 ether, address(this));

        vm.prank(responder);
        controller.freeze(address(vault));
        assertEq(vault.maxDeposit(address(this)), 0);
        vault.withdraw(1 ether, address(this), address(this));
        vm.startPrank(responder);
        controller.pause(address(vault));
        controller.pause(address(collector));
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, responder, PAUSE_TYPE));
        vault.pause(PAUSE_TYPE, false);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, responder, PAUSE_TYPE));
        collector.pause(PAUSE_TYPE, false);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, responder, FROZEN_TYPE));
        vault.pause(FROZEN_TYPE, false);
        vm.stopPrank();
        assertEq(vault.maxWithdraw(address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vault.redeem(1 ether, address(this), address(this));
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        collector.harvest(new FeeSourceType[](0), new address[](0));

        vm.startPrank(params.freezer);
        vault.pause(PAUSE_TYPE, false);
        assertEq(vault.maxDeposit(address(this)), 0, "freeze must survive unpause");
        vault.pause(FROZEN_TYPE, false);
        collector.pause(PAUSE_TYPE, false);
        vm.stopPrank();
        vault.deposit(1 ether, address(this));
        vault.redeem(1 ether, address(this), address(this));
        collector.harvest(new FeeSourceType[](0), new address[](0));
        assertFalse(vault.paused(PAUSE_TYPE));
        assertFalse(vault.paused(FROZEN_TYPE));
        assertFalse(collector.paused(PAUSE_TYPE));
    }

    function _snapshotLegacyPositions(address[] memory markets, address feeRecipient, bool requireSupply)
        private
        view
        returns (LegacyFeePositionSnapshot[] memory snapshots, uint256 collateralMarketCount)
    {
        snapshots = new LegacyFeePositionSnapshot[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            Position memory legacyPosition = market.position(feeRecipient);

            assertEq(market.feeRecipient(), feeRecipient, "unexpected legacy market fee recipient");
            if (requireSupply) assertGt(legacyPosition.supplyShares, 0, "legacy recipient has no supply");

            if (legacyPosition.collateralAssets != 0) ++collateralMarketCount;

            snapshots[i] = LegacyFeePositionSnapshot({
                supplyShares: legacyPosition.supplyShares, collateralAssets: legacyPosition.collateralAssets
            });
        }
    }

    function _snapshotLegacyVaultFees(address[] memory vaults)
        private
        view
        returns (LegacyVaultFeeSnapshot[] memory snapshots)
    {
        snapshots = new LegacyVaultFeeSnapshot[](vaults.length);
        for (uint256 i; i < vaults.length; ++i) {
            address feeRecipient = IAltoVaultBase(vaults[i]).feeRecipient();
            snapshots[i] = LegacyVaultFeeSnapshot({
                feeRecipient: feeRecipient, recipientShares: IERC4626(vaults[i]).balanceOf(feeRecipient)
            });
        }
    }

    function _assertActivationPreservedLegacyPositions(
        address[] memory markets,
        address legacyFeeRecipient,
        LegacyFeePositionSnapshot[] memory snapshots,
        address collector,
        bool supplyMayAccrue
    ) private view {
        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            Position memory legacyPosition = market.position(legacyFeeRecipient);

            address expectedRecipient =
                markets[i] == input.contracts.convexCreditLineMarket.market ? params.treasuryMultisig : collector;
            assertEq(market.feeRecipient(), expectedRecipient, "market fee recipient was not activated");
            if (supplyMayAccrue) {
                assertGe(
                    legacyPosition.supplyShares,
                    snapshots[i].supplyShares,
                    "activation must preserve legacy borrow supply"
                );
                snapshots[i].supplyShares = legacyPosition.supplyShares;
            } else {
                assertEq(legacyPosition.supplyShares, snapshots[i].supplyShares, "activation changed legacy supply");
            }
            assertEq(
                legacyPosition.collateralAssets,
                snapshots[i].collateralAssets,
                "activation must preserve legacy collateral"
            );
        }
    }

    /// @dev Executes the scheduled activation batch and checks that credit line interest went to Treasury.
    function _executeActivationAndAssertCreditLineRouting() private {
        uint256 treasuryDusdBefore = IDUSD(input.contracts.dusd).balanceOf(params.treasuryMultisig);
        uint256 creditLineClaimableBefore =
            AltoConvexCreditLineMarket(input.contracts.convexCreditLineMarket.market).claimableFeesAssets();
        assertGt(creditLineClaimableBefore, 0, "credit line has no accrued interest");

        vm.recordLogs();
        _executeScheduledTimelockBatch(input.contracts.timelock, ACTIVATION_EXECUTE_PATH);
        _assertCreditLineInterestSentToTreasury(vm.getRecordedLogs(), treasuryDusdBefore, creditLineClaimableBefore);
    }

    /// @dev Requires one credit line claim, sent to Treasury, covering at least the interest accrued before activation.
    function _assertCreditLineInterestSentToTreasury(
        Vm.Log[] memory logs,
        uint256 treasuryDusdBefore,
        uint256 claimableBefore
    ) private view {
        address creditLine = input.contracts.convexCreditLineMarket.market;
        uint256 claimed;
        uint256 claims;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (entry.emitter != creditLine || entry.topics[0] != keccak256("InterestClaimed(address,uint256)")) {
                continue;
            }
            assertEq(
                address(uint160(uint256(entry.topics[1]))),
                params.treasuryMultisig,
                "credit line interest not sent to Treasury"
            );
            claimed = abi.decode(entry.data, (uint256));
            ++claims;
        }
        assertEq(claims, 1, "unexpected credit line interest claims");
        assertGe(claimed, claimableBefore, "accrued credit line interest was not claimed");
        assertEq(
            IDUSD(input.contracts.dusd).balanceOf(params.treasuryMultisig) - treasuryDusdBefore,
            claimed,
            "Treasury did not receive credit line interest"
        );
        assertEq(
            AltoConvexCreditLineMarket(creditLine).claimableFeesAssets(), 0, "credit line interest remains claimable"
        );
    }

    function _assertVaultFeeSourcesActivated(
        address[] memory vaults,
        LegacyVaultFeeSnapshot[] memory snapshots,
        address collector
    ) private view {
        for (uint256 i; i < vaults.length; ++i) {
            bool isDusdVault = IERC4626(vaults[i]).asset() == input.contracts.dusd;
            address expectedRecipient = isDusdVault ? collector : snapshots[i].feeRecipient;
            assertEq(
                IAltoVaultBase(vaults[i]).feeRecipient(),
                expectedRecipient,
                "unexpected vault fee recipient after activation"
            );

            if (isDusdVault) {
                assertEq(
                    snapshots[i].feeRecipient,
                    input.contracts.feeRecipient,
                    "unexpected legacy DUSD vault fee recipient"
                );
                assertGe(
                    IERC4626(vaults[i]).balanceOf(snapshots[i].feeRecipient),
                    snapshots[i].recipientShares,
                    "activation must preserve legacy vault fee shares"
                );
            }
        }
    }

    function _assertAncillaryFeeSourcesActivated(
        address[] memory usms,
        address[] memory originalUsmFeeRecipients,
        address collector
    ) private view {
        for (uint256 i; i < usms.length; ++i) {
            address expectedRecipient = originalUsmFeeRecipients[i] == address(0) ? address(0) : collector;
            assertEq(
                IStableTokenFacilitator(usms[i]).getFeeRecipient(),
                expectedRecipient,
                "unexpected USM fee recipient after activation"
            );
        }
        assertEq(
            IStableTokenFacilitator(input.contracts.dusdFlashMinter).getFeeRecipient(),
            collector,
            "flash-minter fee recipient was not activated"
        );
    }

    function _scheduleTimelockBatch(address timelockAddress, string memory schedulePath) private {
        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool scheduled, bytes memory scheduleResult) = timelockAddress.call(_readSafeTxData(schedulePath));
        if (!scheduled) _revertWith(scheduleResult);
    }

    function _executeScheduledTimelockBatch(address timelockAddress, string memory executePath) private {
        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool executed, bytes memory executeResult) = timelockAddress.call(_readSafeTxData(executePath));
        if (!executed) _revertWith(executeResult);
    }

    function _revertWith(bytes memory revertData) private pure {
        assembly ("memory-safe") {
            revert(add(revertData, 0x20), mload(revertData))
        }
    }
}

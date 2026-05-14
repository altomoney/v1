// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
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
import {
    IDcfDlbPriorityLiquidationEngine
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {IUsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {
    BUNDLER3_MAINNET,
    FRXUSD_MAINNET,
    USDC_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";

/// @dev Minimal interface for setDebtCeiling on AltoMintMarket
interface IAltoMintMarketCap {
    function setDebtCeiling(uint256 _debtCeiling) external;
}

/// @dev Set to a non-zero deployment timestamp to load a real deployment's addresses.json
///      and skip re-deploying prerequisites. The file must be at:
///      contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-<DEPLOYMENT_ID>/addresses.json
uint256 constant DEPLOYMENT_ID_TO_LOAD = 1765364975;
string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

abstract contract DeployAltoEthereumMainnetTestBase is Test {
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
            treasuryMultisig: address(0xA1148A1b94262540994Cf9Aa431A13ad39764228),
            updater: MERKLE_ROOT_UPDATER,
            deployerHasOwnership: false
        });

        _loadCurrentChainInput();
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

contract DeployAdapterPhaseTest is DeployAltoEthereumMainnetTestBase {
    function test_deployAdapterAndApproval() public {
        _assertDeployAdapterAndApproval();
    }
}

contract UpdateMintMarketCapsTest is DeployAltoEthereumMainnetTestBase {
    uint256 constant WETH_NEW_CAP = 60_000 * 1e18;
    uint256 constant WSTETH_NEW_CAP = 60_000 * 1e18;
    uint256 constant SUSDE_NEW_CAP = 35_000 * 1e18;
    uint256 constant SYRUP_USDC_NEW_CAP = 35_000 * 1e18;
    uint256 constant TBTC_NEW_CAP = 20_000 * 1e18;
    uint256 constant METH_NEW_CAP = 20_000 * 1e18;
    uint256 constant RETH_NEW_CAP = 20_000 * 1e18;

    uint256 constant MINTER_CEILING_BUFFER = 1.05 ether;

    function _computeMinterCeiling(address liquidationEngine, uint256 newCap) internal view returns (uint256) {
        uint256 maxLiquidationLtv =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration().maxLiquidationLtv;
        return newCap * MINTER_CEILING_BUFFER / maxLiquidationLtv;
    }

    function _updateCap(address market, address liquidationEngine, uint256 newCap) internal {
        uint256 expectedMinterCeiling = _computeMinterCeiling(liquidationEngine, newCap);
        address dusd = IMarket(market).borrowToken();

        vm.startPrank(input.contracts.timelock);
        IAltoMintMarketCap(market).setDebtCeiling(newCap);
        IDUSD(dusd).setMinterCeiling(market, expectedMinterCeiling);
        vm.stopPrank();
    }

    function _assertCap(address market, address liquidationEngine, uint256 expectedCap) internal view {
        uint256 expectedMinterCeiling = _computeMinterCeiling(liquidationEngine, expectedCap);
        address dusd = IMarket(market).borrowToken();

        assertEq(IMarket(market).totalSupply().assets, expectedCap, "debt ceiling mismatch");

        (, uint256 ceiling) = IDUSD(dusd).minterConfig(market);
        assertEq(ceiling, expectedMinterCeiling, "minter ceiling mismatch");
    }

    function test_updateMintMarketCaps() public {
        // ── wETH ──────────────────────────────────────────────────────────────
        _updateCap(input.contracts.wethMarket.market, input.contracts.wethMarket.liquidationEngine, WETH_NEW_CAP);

        // ── wstETH ────────────────────────────────────────────────────────────
        _updateCap(input.contracts.wstethMarket.market, input.contracts.wstethMarket.liquidationEngine, WSTETH_NEW_CAP);

        // ── sUSDe (mint) ──────────────────────────────────────────────────────
        _updateCap(
            input.contracts.susdeMintMarket.market, input.contracts.susdeMintMarket.liquidationEngine, SUSDE_NEW_CAP
        );

        // ── syrupUSDC (mint) ──────────────────────────────────────────────────
        _updateCap(
            input.contracts.syrupUsdcMintMarket.market,
            input.contracts.syrupUsdcMintMarket.liquidationEngine,
            SYRUP_USDC_NEW_CAP
        );

        // ── tBTC ──────────────────────────────────────────────────────────────
        _updateCap(input.contracts.tbtcMarket.market, input.contracts.tbtcMarket.liquidationEngine, TBTC_NEW_CAP);

        // ── mETH ──────────────────────────────────────────────────────────────
        _updateCap(input.contracts.methMarket.market, input.contracts.methMarket.liquidationEngine, METH_NEW_CAP);

        // ── rETH ──────────────────────────────────────────────────────────────
        _updateCap(input.contracts.rethMarket.market, input.contracts.rethMarket.liquidationEngine, RETH_NEW_CAP);

        // ── Assertions ────────────────────────────────────────────────────────
        _assertCap(input.contracts.wethMarket.market, input.contracts.wethMarket.liquidationEngine, WETH_NEW_CAP);
        _assertCap(input.contracts.wstethMarket.market, input.contracts.wstethMarket.liquidationEngine, WSTETH_NEW_CAP);
        _assertCap(
            input.contracts.susdeMintMarket.market, input.contracts.susdeMintMarket.liquidationEngine, SUSDE_NEW_CAP
        );
        _assertCap(
            input.contracts.syrupUsdcMintMarket.market,
            input.contracts.syrupUsdcMintMarket.liquidationEngine,
            SYRUP_USDC_NEW_CAP
        );
        _assertCap(input.contracts.tbtcMarket.market, input.contracts.tbtcMarket.liquidationEngine, TBTC_NEW_CAP);
        _assertCap(input.contracts.methMarket.market, input.contracts.methMarket.liquidationEngine, METH_NEW_CAP);
        _assertCap(input.contracts.rethMarket.market, input.contracts.rethMarket.liquidationEngine, RETH_NEW_CAP);
    }
}


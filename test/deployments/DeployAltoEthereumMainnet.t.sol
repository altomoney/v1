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
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {
    INonfungiblePositionManager,
    MintParams,
    DecreaseLiquidityParams,
    CollectParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {DrainAndRouteDusdPoolToFrxusdScript} from "../../script/DrainAndRouteDusdPoolToFrxusd.s.sol";
import {MigrateDusdPoolToFrxusdScript} from "../../script/MigrateDusdPoolToFrxusd.s.sol";
import {DusdPoolMigrationHelper} from "../../script/helper/DusdPoolMigrationHelper.sol";

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

contract MigrateDusdPoolToFrxusdTest is DeployAltoEthereumMainnetTestBase {
    address constant UNISWAP_V3_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;
    address constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;

    uint256 constant POS1_TOKEN_ID = 1150307;
    uint256 constant POS2_TOKEN_ID = 1150308;

    // Tick offsets: identical to original — same %-bands, new base tick = 0
    int24 constant POS_1_LOWER = -7; // ≈ 0.9993
    int24 constant POS_1_UPPER = 3; // ≈ 1.0003
    int24 constant POS_2_LOWER = -304; // ≈ 0.97
    int24 constant POS_2_UPPER = 70; // ≈ 1.007

    uint256 constant MAX_REMAINING_FRXUSD = 10 ether;
    uint256 constant MIN_SWEEP_FRXUSD = 10 ether;
    /// @dev Narrow-range LP target: DUSD / frxUSD = 44 / 100 = 0.44
    uint256 constant SWEEP_DUSD_NUM = 44;
    uint256 constant SWEEP_DUSD_DEN = 100;
    uint256 constant SWEEP_SUM_DEN = 144; // SWEEP_DUSD_DEN + SWEEP_DUSD_NUM

    struct CollectedAmounts {
        uint256 pos1Dusd;
        uint256 pos1Usdc;
        uint256 pos2Dusd;
        uint256 pos2Usdc;
    }

    struct DrainScriptResult {
        uint256 pos1Dusd;
        uint256 pos1Usdc;
        uint256 pos2Dusd;
        uint256 pos2Usdc;
        uint256 usdcUsmLiquidityDrained;
    }

    struct MintResult {
        uint256 pos1Id;
        uint128 liq1;
        uint256 pos1Dusd;
        uint256 pos1FrxUsd;
        uint256 pos2Id;
        uint128 liq2;
        uint256 pos2Dusd;
        uint256 pos2FrxUsd;
    }

    struct MigrateScriptConfig {
        address nftMgrAddr;
        address dusd;
        address fraxCustodian;
        address frxUsdUsm;
        uint24 fee;
        int24 pos1Lower;
        int24 pos1Upper;
        int24 pos2Lower;
        int24 pos2Upper;
        uint256 pos1Dusd;
        uint256 pos1Usdc;
        uint256 pos2Dusd;
        uint256 pos2Usdc;
        uint256 minDusdPos1;
        uint256 minFrxUsdPos1;
        uint256 minDusdPos2;
        uint256 minFrxUsdPos2;
        uint256 dusdForLp;
        uint256 frxUsdForLp;
        uint256 frxUsdToSell;
        uint256 frxUsdToBuy;
        uint256 minDusdNarrow;
        uint256 minFrxUsdNarrow;
        uint256 collectedUsdc;
        uint160 sqrtPriceX96;
    }

    /// @dev Fork test for `DrainAndRouteDusdPoolToFrxusd.s.sol` (Tx 1-10).
    ///      Executes the script flow as treasury, then logs values for the migrate script.
    function test_drainAndRouteDusdPoolToFrxusd() public {
        DrainAndRouteDusdPoolToFrxusdScript drainScript = new DrainAndRouteDusdPoolToFrxusdScript();
        address treasury = params.treasuryMultisig;

        uint256 dusdBefore = _bal(DUSD, treasury);
        uint256 usdcBefore = _bal(USDC_MAINNET, treasury);
        uint256 frxUsdBefore = _bal(FRXUSD_MAINNET, treasury);

        vm.startPrank(treasury);
        DrainScriptResult memory result =
            _executeDrainAndRouteScript(treasury, drainScript, MigrateDusdPoolToFrxusdScript(address(0)));
        vm.stopPrank();

        console.log("Position 1 collected DUSD:", result.pos1Dusd / 1e18, "USDC:", result.pos1Usdc / 1e6);
        console.log("Position 2 collected DUSD:", result.pos2Dusd / 1e18, "USDC:", result.pos2Usdc / 1e6);
        console.log("USDC USM available liquidity before:", result.usdcUsmLiquidityDrained);

        CollectedAmounts memory collected = CollectedAmounts({
            pos1Dusd: result.pos1Dusd, pos1Usdc: result.pos1Usdc, pos2Dusd: result.pos2Dusd, pos2Usdc: result.pos2Usdc
        });
        _logDrainScriptResults(
            collected, treasury, result.usdcUsmLiquidityDrained, dusdBefore, usdcBefore, frxUsdBefore
        );
    }

    /// @dev Fork test: drain script (Tx 1-10) then migrate script (Tx 1-14).
    ///      All migrate amounts/mins are read from `MigrateDusdPoolToFrxusdScript` state vars.
    function test_migrateDusdPoolToFrxusdAfterDrainScript() public {
        DrainAndRouteDusdPoolToFrxusdScript drainScript = new DrainAndRouteDusdPoolToFrxusdScript();
        MigrateDusdPoolToFrxusdScript migrateScript = new MigrateDusdPoolToFrxusdScript();
        address treasury = params.treasuryMultisig;
        uint256 frxUsdTreasuryBefore = _bal(FRXUSD_MAINNET, treasury);

        vm.startPrank(treasury);
        DrainScriptResult memory drain = _executeDrainAndRouteScript(treasury, drainScript, migrateScript);
        vm.stopPrank();

        assertEq(drain.pos1Dusd, migrateScript.pos1DusdCollected(), "pos1 DUSD mismatch vs migrate script");
        assertEq(drain.pos1Usdc, migrateScript.pos1UsdcCollected(), "pos1 USDC mismatch vs migrate script");
        assertEq(drain.pos2Dusd, migrateScript.pos2DusdCollected(), "pos2 DUSD mismatch vs migrate script");
        assertEq(drain.pos2Usdc, migrateScript.pos2UsdcCollected(), "pos2 USDC mismatch vs migrate script");

        vm.startPrank(treasury);
        (address newPool, MintResult memory minted, uint256 sweepPosId) =
            _executeMigrateScript(treasury, migrateScript, frxUsdTreasuryBefore);
        vm.stopPrank();

        CollectedAmounts memory collected = CollectedAmounts({
            pos1Dusd: migrateScript.pos1DusdCollected(),
            pos1Usdc: migrateScript.pos1UsdcCollected(),
            pos2Dusd: migrateScript.pos2DusdCollected(),
            pos2Usdc: migrateScript.pos2UsdcCollected()
        });

        _assertFinalState(
            INonfungiblePositionManager(migrateScript.UNISWAP_V3_NFT_POSITION_MANAGER()),
            newPool,
            minted,
            uint160(migrateScript.Q96()),
            collected,
            frxUsdTreasuryBefore
        );

        console.log("=== SWAP VERIFICATION ===");
        _verifySwapRate(newPool);
    }

    /// @dev Fork test for `DusdPoolMigrationHelper.executeMigration` (full drain + migrate in one call).
    function test_dusdPoolMigrationHelper_executeMigration() public {
        address treasury = params.treasuryMultisig;
        DrainAndRouteDusdPoolToFrxusdScript drainScript = new DrainAndRouteDusdPoolToFrxusdScript();

        DusdPoolMigrationHelper helper = new DusdPoolMigrationHelper(treasury);
        _grantHelperSwapperRoles(helper);

        vm.startPrank(treasury);
        IERC721(UNISWAP_V3_NFT_POSITION_MANAGER).setApprovalForAll(address(helper), true);
        helper.executeMigration(
            DusdPoolMigrationHelper.DrainMins({
                pos1DusdMin: drainScript.drainPos1DusdMin(),
                pos1UsdcMin: drainScript.drainPos1UsdcMin(),
                pos2DusdMin: drainScript.drainPos2DusdMin(),
                pos2UsdcMin: drainScript.drainPos2UsdcMin()
            })
        );
        vm.stopPrank();

        _logMigrationHelperResults(helper, treasury);

        assertGt(helper.pos1DusdCollected(), 0, "should have collected DUSD from pos1");
        assertGt(helper.collectedUsdcFromUniswapPool(), 0, "should have collected USDC");
        assertEq(IUsm(USDC_USM).getAvailableLiquidity(), 0, "USDC USM should be drained");
        assertGt(helper.newPos1TokenId(), 0, "new position 1 should be minted");
        assertGt(helper.newPos2TokenId(), 0, "new position 2 should be minted");
        assertNotEq(helper.newPool(), address(0), "new pool should exist");
        assertGt(helper.sweepFrxUsdDeposited(), 0, "sweep should add frxUSD to narrow pos1");
        assertGt(helper.frxUsdToBuyFromPsm(), 0, "should buy frxUSD from PSM for leftover DUSD");

        IERC721 nft721 = IERC721(UNISWAP_V3_NFT_POSITION_MANAGER);
        assertEq(nft721.ownerOf(helper.newPos1TokenId()), treasury, "pos1 NFT should be on treasury");
        assertEq(nft721.ownerOf(helper.newPos2TokenId()), treasury, "pos2 NFT should be on treasury");

        INonfungiblePositionManager nftMgr = INonfungiblePositionManager(UNISWAP_V3_NFT_POSITION_MANAGER);
        (,,,,, int24 tl1, int24 tu1,,,,,) = nftMgr.positions(helper.newPos1TokenId());
        (,,,,, int24 tl2, int24 tu2,,,,,) = nftMgr.positions(helper.newPos2TokenId());
        assertEq(tl1, POS_1_LOWER, "pos1 tickLower mismatch");
        assertEq(tu1, POS_1_UPPER, "pos1 tickUpper mismatch");
        assertEq(tl2, POS_2_LOWER, "pos2 tickLower mismatch");
        assertEq(tu2, POS_2_UPPER, "pos2 tickUpper mismatch");

        console.log("=== SWAP VERIFICATION ===");
        _verifySwapRate(helper.newPool());
    }

    function _grantHelperSwapperRoles(DusdPoolMigrationHelper helper) internal {
        address timelock = input.contracts.timelock;
        vm.startPrank(timelock);
        AccessControl(USDC_USM).grantRole(SWAPPER_ROLE, address(helper));
        AccessControl(FRXUSD_USM).grantRole(SWAPPER_ROLE, address(helper));
        vm.stopPrank();
    }

    function _logMigrationHelperResults(DusdPoolMigrationHelper helper, address treasury) internal view {
        address helperAddr = address(helper);

        console.log("=== DusdPoolMigrationHelper STATE ===");
        console.log("pos1DusdCollected:", helper.pos1DusdCollected());
        console.log("pos1UsdcCollected:", helper.pos1UsdcCollected());
        console.log("pos2DusdCollected:", helper.pos2DusdCollected());
        console.log("pos2UsdcCollected:", helper.pos2UsdcCollected());
        console.log("collectedUsdcFromUniswapPool:", helper.collectedUsdcFromUniswapPool());
        console.log("usdcUsmLiquidityDrained:", helper.usdcUsmLiquidityDrained());
        console.log("newPool:", helper.newPool());
        console.log("newPos1TokenId:", helper.newPos1TokenId());
        console.log("newPos2TokenId:", helper.newPos2TokenId());
        console.log("pos1DusdDeposited:", helper.pos1DusdDeposited());
        console.log("pos1FrxUsdDeposited:", helper.pos1FrxUsdDeposited());
        console.log("pos2DusdDeposited:", helper.pos2DusdDeposited());
        console.log("pos2FrxUsdDeposited:", helper.pos2FrxUsdDeposited());
        console.log("frxUsdToSwapToDusd:", helper.frxUsdToSwapToDusd());
        console.log("frxUsdToBuyFromPsm:", helper.frxUsdToBuyFromPsm());
        console.log("remainingFrxUsdToAddToLp:", helper.remainingFrxUsdToAddToLp());
        console.log("dusdForLp:", helper.dusdForLp());
        console.log("sweepDusdDeposited:", helper.sweepDusdDeposited());
        console.log("sweepFrxUsdDeposited:", helper.sweepFrxUsdDeposited());
        console.log("");
        console.log("=== HELPER REMAINING BALANCES ===");
        console.log("DUSD:", _bal(DUSD, helperAddr) / 1e18);
        console.log("USDC:", _bal(USDC_MAINNET, helperAddr) / 1e6);
        console.log("frxUSD:", _bal(FRXUSD_MAINNET, helperAddr) / 1e18);
        console.log("Treasury DUSD:", _bal(DUSD, treasury) / 1e18);
        console.log("Treasury frxUSD:", _bal(FRXUSD_MAINNET, treasury) / 1e18);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _bal(address token, address who) internal view returns (uint256) {
        return IERC20Metadata(token).balanceOf(who);
    }

    /// @dev Fork execution of `DrainAndRouteDusdPoolToFrxusd.s.sol` Tx 1-10. Call under `vm.startPrank(treasury)`.
    function _executeDrainAndRouteScript(
        address treasury,
        DrainAndRouteDusdPoolToFrxusdScript drainScript,
        MigrateDusdPoolToFrxusdScript migrateScript
    ) internal returns (DrainScriptResult memory result) {
        uint256 deadline = block.timestamp + 3 hours;
        INonfungiblePositionManager nftMgr = INonfungiblePositionManager(UNISWAP_V3_NFT_POSITION_MANAGER);
        (,,,,,,, uint128 pos1Liquidity,,,,) = nftMgr.positions(POS1_TOKEN_ID);
        (,,,,,,, uint128 pos2Liquidity,,,,) = nftMgr.positions(POS2_TOKEN_ID);

        (uint256 pos1DusdMin, uint256 pos1UsdcMin, uint256 pos2DusdMin, uint256 pos2UsdcMin) =
            _drainDecreaseMins(drainScript, migrateScript);

        nftMgr.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: POS1_TOKEN_ID,
                liquidity: pos1Liquidity,
                amount0Min: pos1DusdMin,
                amount1Min: pos1UsdcMin,
                deadline: deadline
            })
        );
        nftMgr.decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: POS2_TOKEN_ID,
                liquidity: pos2Liquidity,
                amount0Min: pos2DusdMin,
                amount1Min: pos2UsdcMin,
                deadline: deadline
            })
        );

        (result.pos1Dusd, result.pos1Usdc) = nftMgr.collect(
            CollectParams({
                tokenId: POS1_TOKEN_ID,
                recipient: treasury,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        (result.pos2Dusd, result.pos2Usdc) = nftMgr.collect(
            CollectParams({
                tokenId: POS2_TOKEN_ID,
                recipient: treasury,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        result.usdcUsmLiquidityDrained = IUsm(USDC_USM).getAvailableLiquidity();
        if (result.usdcUsmLiquidityDrained > 0) {
            uint256 dusdBalanceBeforePsmSwaps = IERC20(DUSD).balanceOf(treasury);
            assertEq(IERC20(FRXUSD_MAINNET).balanceOf(treasury), 0, "frxUSD balance should be 0 before PSM swaps");

            IERC20Metadata(DUSD).approve(USDC_USM, result.usdcUsmLiquidityDrained * 1e12);
            IUsm(USDC_USM).buyAsset(result.usdcUsmLiquidityDrained, treasury);

            IERC20Metadata(USDC_MAINNET).approve(FRAX_CUSTODIAN, result.usdcUsmLiquidityDrained);
            IERC4626(FRAX_CUSTODIAN).deposit(result.usdcUsmLiquidityDrained, treasury);

            IERC20Metadata(FRXUSD_MAINNET).approve(FRXUSD_USM, result.usdcUsmLiquidityDrained * 1e12);
            IUsm(FRXUSD_USM).sellAsset(result.usdcUsmLiquidityDrained * 1e12, treasury);
            assertEq(
                IERC20(DUSD).balanceOf(treasury), dusdBalanceBeforePsmSwaps, "incorrect dusd balance during psm routes"
            );
            assertEq(IERC20(FRXUSD_MAINNET).balanceOf(treasury), 0, "frxUSD balance should be 0 after PSM swaps");
        }

        assertEq(IUsm(USDC_USM).getAvailableLiquidity(), 0, "usdc usm still has exposure");
    }

    /// @dev 1% slippage mins for decreaseLiquidity — from migrate script when set, else drain script.
    function _drainDecreaseMins(
        DrainAndRouteDusdPoolToFrxusdScript drainScript,
        MigrateDusdPoolToFrxusdScript migrateScript
    ) internal view returns (uint256 pos1DusdMin, uint256 pos1UsdcMin, uint256 pos2DusdMin, uint256 pos2UsdcMin) {
        if (address(migrateScript) != address(0)) {
            pos1DusdMin = migrateScript.pos1DusdCollected() * 99 / 100;
            pos1UsdcMin = migrateScript.pos1UsdcCollected() * 99 / 100;
            pos2DusdMin = migrateScript.pos2DusdCollected() * 99 / 100;
            pos2UsdcMin = migrateScript.pos2UsdcCollected() * 99 / 100;
            return (pos1DusdMin, pos1UsdcMin, pos2DusdMin, pos2UsdcMin);
        }

        return (
            drainScript.drainPos1DusdMin(),
            drainScript.drainPos1UsdcMin(),
            drainScript.drainPos2DusdMin(),
            drainScript.drainPos2UsdcMin()
        );
    }

    /// @dev Snapshot all populated migrate-script fields for fork execution.
    function _readMigrateScriptConfig(MigrateDusdPoolToFrxusdScript script)
        internal
        view
        returns (MigrateScriptConfig memory cfg)
    {
        cfg.nftMgrAddr = script.UNISWAP_V3_NFT_POSITION_MANAGER();
        cfg.dusd = script.DUSD();
        cfg.fraxCustodian = script.FRAX_CUSTODIAN();
        cfg.frxUsdUsm = script.FRXUSD_USM();
        cfg.fee = script.FEE_100();
        cfg.pos1Lower = script.POS_1_LOWER();
        cfg.pos1Upper = script.POS_1_UPPER();
        cfg.pos2Lower = script.POS_2_LOWER();
        cfg.pos2Upper = script.POS_2_UPPER();
        cfg.pos1Dusd = script.pos1DusdCollected();
        cfg.pos1Usdc = script.pos1UsdcCollected();
        cfg.pos2Dusd = script.pos2DusdCollected();
        cfg.pos2Usdc = script.pos2UsdcCollected();
        cfg.minDusdPos1 = script.minExpectedDusdDepositPos1();
        cfg.minFrxUsdPos1 = script.minExpectedUsdcDepositPos1();
        cfg.minDusdPos2 = script.minExpectedDusdDepositPos2();
        cfg.minFrxUsdPos2 = script.minExpectedUsdcDepositPos2();
        cfg.collectedUsdc = script.collectedUsdcFromUniswapPool();
        cfg.sqrtPriceX96 = uint160(script.Q96());
    }

    /// @dev Fork execution of `MigrateDusdPoolToFrxusd.s.sol` Tx 1-14. Call under `vm.startPrank(treasury)`.
    function _executeMigrateScript(address treasury, MigrateDusdPoolToFrxusdScript script, uint256 frxUsdTreasuryBefore)
        internal
        returns (address newPool, MintResult memory minted, uint256 sweepPosId)
    {
        MigrateScriptConfig memory cfg = _readMigrateScriptConfig(script);
        uint256 deadline = block.timestamp + 3 hours;
        INonfungiblePositionManager nftMgr = INonfungiblePositionManager(cfg.nftMgrAddr);

        IERC20Metadata(USDC_MAINNET).approve(cfg.fraxCustodian, cfg.collectedUsdc);
        assertEq(
            IERC4626(cfg.fraxCustodian).deposit(cfg.collectedUsdc, treasury),
            cfg.collectedUsdc * 1e12,
            "LP frxUSD should equal collected USDC * 1e12"
        );
        console.log("Pool USDC deposited to custodian:", cfg.collectedUsdc / 1e6);

        newPool = nftMgr.createAndInitializePoolIfNecessary(cfg.dusd, FRXUSD_MAINNET, cfg.fee, cfg.sqrtPriceX96);
        assertNotEq(newPool, address(0), "new pool should be created");
        console.log("New pool:", newPool);

        minted = _migrateScriptMintPositions(nftMgr, treasury, cfg, deadline);
        _setSweepAmountsFromLeftovers(cfg, minted, treasury, frxUsdTreasuryBefore);
        sweepPosId = _migrateScriptSweep(nftMgr, treasury, cfg, deadline, frxUsdTreasuryBefore);
    }

    /// @dev After pos1/pos2 mints, rebalance leftovers via frxUSD PSM and deposit to narrow LP at DUSD/frxUSD ≈ 0.44.
    function _setSweepAmountsFromLeftovers(
        MigrateScriptConfig memory cfg,
        MintResult memory minted,
        address treasury,
        uint256 frxUsdTreasuryBefore
    ) internal view {
        uint256 leftoverDusd = cfg.pos1Dusd + cfg.pos2Dusd - minted.pos1Dusd - minted.pos2Dusd;
        uint256 leftoverFrxUsd = _bal(FRXUSD_MAINNET, treasury) - frxUsdTreasuryBefore;

        (cfg.dusdForLp, cfg.frxUsdForLp, cfg.frxUsdToSell, cfg.frxUsdToBuy) =
            _computeSweepAmounts(leftoverDusd, leftoverFrxUsd);

        // Sweep amounts are derived from live leftovers; use 0 mins (same as on-chain helper).
        cfg.minDusdNarrow = 0;
        cfg.minFrxUsdNarrow = 0;

        console.log("=== Computed sweep (DUSD/frxUSD target 0.44) ===");
        console.log("leftoverDusd:", leftoverDusd / 1e18);
        console.log("leftoverFrxUsd:", leftoverFrxUsd / 1e18);
        console.log("dusdForLp:", cfg.dusdForLp / 1e18);
        console.log("frxUsdForLp:", cfg.frxUsdForLp / 1e18);
        console.log("frxUsdToSell (PSM):", cfg.frxUsdToSell / 1e18);
        console.log("frxUsdToBuy (PSM):", cfg.frxUsdToBuy / 1e18);
    }

    /// @dev At 1:1 PSM, split total leftovers into LP amounts with dusdForLp / frxUsdForLp = 44/100.
    ///      Rebalance via sellAsset (excess frxUSD) or buyAsset (deficit frxUSD).
    function _computeSweepAmounts(uint256 leftoverDusd, uint256 leftoverFrxUsd)
        internal
        pure
        returns (uint256 dusdForLp, uint256 frxUsdForLp, uint256 frxUsdToSell, uint256 frxUsdToBuy)
    {
        uint256 total = leftoverDusd + leftoverFrxUsd;
        if (total < MIN_SWEEP_FRXUSD) return (0, 0, 0, 0);

        dusdForLp = total * SWEEP_DUSD_NUM / SWEEP_SUM_DEN;
        frxUsdForLp = total * SWEEP_DUSD_DEN / SWEEP_SUM_DEN;

        if (dusdForLp == 0 || frxUsdForLp == 0) return (0, 0, 0, 0);

        if (leftoverFrxUsd < frxUsdForLp) {
            frxUsdToBuy = frxUsdForLp - leftoverFrxUsd;
        } else if (leftoverFrxUsd > frxUsdForLp) {
            frxUsdToSell = leftoverFrxUsd - frxUsdForLp;
        }
    }

    function _migrateScriptMintPositions(
        INonfungiblePositionManager nftMgr,
        address treasury,
        MigrateScriptConfig memory cfg,
        uint256 deadline
    ) internal returns (MintResult memory m) {
        IERC20Metadata(cfg.dusd).approve(cfg.nftMgrAddr, cfg.pos1Dusd);
        IERC20Metadata(FRXUSD_MAINNET).approve(cfg.nftMgrAddr, cfg.pos1Usdc * 1e12);
        (m.pos1Id, m.liq1, m.pos1Dusd, m.pos1FrxUsd) = nftMgr.mint(
            MintParams({
                token0: cfg.dusd,
                token1: FRXUSD_MAINNET,
                fee: cfg.fee,
                tickLower: cfg.pos1Lower,
                tickUpper: cfg.pos1Upper,
                amount0Desired: cfg.pos1Dusd,
                amount1Desired: cfg.pos1Usdc * 1e12,
                amount0Min: cfg.minDusdPos1,
                amount1Min: cfg.minFrxUsdPos1,
                recipient: treasury,
                deadline: deadline
            })
        );

        IERC20Metadata(cfg.dusd).approve(cfg.nftMgrAddr, cfg.pos2Dusd);
        IERC20Metadata(FRXUSD_MAINNET).approve(cfg.nftMgrAddr, cfg.pos2Usdc * 1e12);
        (m.pos2Id, m.liq2, m.pos2Dusd, m.pos2FrxUsd) = nftMgr.mint(
            MintParams({
                token0: cfg.dusd,
                token1: FRXUSD_MAINNET,
                fee: cfg.fee,
                tickLower: cfg.pos2Lower,
                tickUpper: cfg.pos2Upper,
                amount0Desired: cfg.pos2Dusd,
                amount1Desired: cfg.pos2Usdc * 1e12,
                amount0Min: cfg.minDusdPos2,
                amount1Min: cfg.minFrxUsdPos2,
                recipient: treasury,
                deadline: deadline
            })
        );

        console.log("New position 1 tokenId:", m.pos1Id, "DUSD/frxUSD:", m.pos1Dusd / 1e18);
        console.log("  frxUSD deposited:", m.pos1FrxUsd / 1e18);
        console.log("New position 2 tokenId:", m.pos2Id, "DUSD/frxUSD:", m.pos2Dusd / 1e18);
        console.log("  frxUSD deposited:", m.pos2FrxUsd / 1e18);
    }

    function _migrateScriptSweep(
        INonfungiblePositionManager nftMgr,
        address treasury,
        MigrateScriptConfig memory cfg,
        uint256 deadline,
        uint256 frxUsdTreasuryBefore
    ) internal returns (uint256 sweepPosId) {
        if (cfg.dusdForLp == 0 && cfg.frxUsdForLp == 0) {
            uint256 excessFrxUsd =
                _bal(FRXUSD_MAINNET, treasury) - frxUsdTreasuryBefore;
            console.log("No sweep configured. Final frxUSD remaining:", excessFrxUsd / 1e18);
            assertLt(excessFrxUsd, MAX_REMAINING_FRXUSD, "frxUSD remaining exceeds 10 after sweep");
            return 0;
        }

        if (cfg.frxUsdToSell > 0) {
            IERC20Metadata(FRXUSD_MAINNET).approve(cfg.frxUsdUsm, cfg.frxUsdToSell);
            IUsm(cfg.frxUsdUsm).sellAsset(cfg.frxUsdToSell, treasury);
        }

        if (cfg.frxUsdToBuy > 0) {
            IERC20Metadata(cfg.dusd).approve(cfg.frxUsdUsm, cfg.frxUsdToBuy);
            IUsm(cfg.frxUsdUsm).buyAsset(cfg.frxUsdToBuy, treasury);
        }

        IERC20Metadata(cfg.dusd).approve(cfg.nftMgrAddr, cfg.dusdForLp);
        IERC20Metadata(FRXUSD_MAINNET).approve(cfg.nftMgrAddr, cfg.frxUsdForLp);

        uint256 sweepDusdDep;
        uint256 sweepFrxUsdDep;
        (sweepPosId,, sweepDusdDep, sweepFrxUsdDep) = nftMgr.mint(
            MintParams({
                token0: cfg.dusd,
                token1: FRXUSD_MAINNET,
                fee: cfg.fee,
                tickLower: cfg.pos1Lower,
                tickUpper: cfg.pos1Upper,
                amount0Desired: cfg.dusdForLp,
                amount1Desired: cfg.frxUsdForLp,
                amount0Min: cfg.minDusdNarrow,
                amount1Min: cfg.minFrxUsdNarrow,
                recipient: treasury,
                deadline: deadline
            })
        );

        console.log("Narrow range sweep mint tokenId:", sweepPosId);
        console.log("  DUSD deposited:", sweepDusdDep / 1e18, "frxUSD deposited:", sweepFrxUsdDep / 1e18);
        if (sweepFrxUsdDep > 0) {
            uint256 ratioScaled = sweepDusdDep * 1e18 / sweepFrxUsdDep;
            console.log("  LP ratio (DUSD/frxUSD scaled 1e18):", ratioScaled);
        }

        uint256 excessFrxUsd = _bal(FRXUSD_MAINNET, treasury) - frxUsdTreasuryBefore;
        console.log("Final frxUSD remaining after sweep:", excessFrxUsd / 1e18);
        assertLt(excessFrxUsd, MAX_REMAINING_FRXUSD, "frxUSD remaining exceeds 10 after sweep");
    }

    /// @dev Log values to fill in `MigrateDusdPoolToFrxusd.s.sol` after running the drain script.
    function _logDrainScriptResults(
        CollectedAmounts memory collected,
        address treasury,
        uint256 usdcUsmLiquidity,
        uint256 dusdBefore,
        uint256 usdcBefore,
        uint256 frxUsdBefore
    ) internal view {
        uint256 collectedUsdcFromUniswapPool = collected.pos1Usdc + collected.pos2Usdc;

        console.log("=== DRAIN SCRIPT RESULTS (for MigrateDusdPoolToFrxusd.s.sol) ===");
        console.log("pos1DusdCollected:", collected.pos1Dusd);
        console.log("pos1UsdcCollected:", collected.pos1Usdc);
        console.log("pos2DusdCollected:", collected.pos2Dusd);
        console.log("pos2UsdcCollected:", collected.pos2Usdc);
        console.log("collectedUsdcFromUniswapPool:", collectedUsdcFromUniswapPool);
        console.log("usdcUsmLiquidityDrained:", usdcUsmLiquidity);
        console.log("USDC USM available liquidity after:", IUsm(USDC_USM).getAvailableLiquidity());
        console.log("");
        console.log("=== TREASURY BALANCES AFTER DRAIN SCRIPT ===");
        console.log("DUSD delta:", (_bal(DUSD, treasury) - dusdBefore) / 1e18);
        console.log("USDC delta:", (_bal(USDC_MAINNET, treasury) - usdcBefore) / 1e6);
        console.log("frxUSD delta:", (_bal(FRXUSD_MAINNET, treasury) - frxUsdBefore) / 1e18);
        console.log("DUSD balance:", _bal(DUSD, treasury) / 1e18);
        console.log("USDC balance:", _bal(USDC_MAINNET, treasury) / 1e6);
        console.log("frxUSD balance:", _bal(FRXUSD_MAINNET, treasury) / 1e18);
    }

    function _assertFinalState(
        INonfungiblePositionManager nftMgr,
        address newPool,
        MintResult memory m,
        uint160 sqrtPriceX96New,
        CollectedAmounts memory collected,
        uint256 frxUsdTreasuryBefore
    ) internal view {
        // New pool has liquidity and correct price
        (uint160 newPoolSqrt,,,,,,) = IUniswapV3Pool(newPool).slot0();
        assertEq(newPoolSqrt, sqrtPriceX96New, "new pool sqrtPriceX96 mismatch");
        assertGt(IUniswapV3Pool(newPool).liquidity(), 0, "new pool should have active liquidity");

        // Both new positions use the correct tick ranges
        (,,,,, int24 tl1, int24 tu1, uint128 fl1,,,,) = nftMgr.positions(m.pos1Id);
        (,,,,, int24 tl2, int24 tu2, uint128 fl2,,,,) = nftMgr.positions(m.pos2Id);
        assertEq(tl1, POS_1_LOWER, "pos1 tickLower mismatch");
        assertEq(tu1, POS_1_UPPER, "pos1 tickUpper mismatch");
        assertEq(tl2, POS_2_LOWER, "pos2 tickLower mismatch");
        assertEq(tu2, POS_2_UPPER, "pos2 tickUpper mismatch");
        assertEq(fl1, m.liq1, "pos1 final liquidity mismatch");
        assertEq(fl2, m.liq2, "pos2 final liquidity mismatch");

        assertLe(
            m.pos1Dusd + m.pos2Dusd, collected.pos1Dusd + collected.pos2Dusd, "total DUSD deposit exceeds collected"
        );
        assertLe(
            m.pos1FrxUsd + m.pos2FrxUsd,
            (collected.pos1Usdc + collected.pos2Usdc) * 1e12,
            "total frxUSD deposit exceeds collected"
        );

        _logRemainingBalances(collected, m, frxUsdTreasuryBefore);

        uint256 excessFrxUsd = _bal(FRXUSD_MAINNET, params.treasuryMultisig) - frxUsdTreasuryBefore;
        assertLt(excessFrxUsd, MAX_REMAINING_FRXUSD, "final frxUSD dust exceeds 10");
        console.log("Migration complete. Pool liquidity:", IUniswapV3Pool(newPool).liquidity());
    }

    function _logRemainingBalances(CollectedAmounts memory collected, MintResult memory m, uint256 frxUsdTreasuryBefore)
        internal
        view
    {
        uint256 totalDusdCollected = collected.pos1Dusd + collected.pos2Dusd;
        uint256 totalDusdDeposited = m.pos1Dusd + m.pos2Dusd;
        uint256 excessFrxUsd = _bal(FRXUSD_MAINNET, params.treasuryMultisig) - frxUsdTreasuryBefore;

        console.log("=== Remaining balances not added to pool (after PSM sweep) ===");
        console.log("Total DUSD not added:", (totalDusdCollected - totalDusdDeposited) / 1e18);
        console.log("Total frxUSD not added:", excessFrxUsd / 1e18);
    }

    /// @dev Verify the new DUSD/frxUSD pool trades at ~1:1 by selling frxUSD for DUSD.
    ///      DUSD = token0, frxUSD = token1 → selling frxUSD is a token1→token0 swap (zeroForOne = false).
    function _verifySwapRate(address newPool) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(newPool);
        address swapper = makeAddr("swapper");
        uint256 swapAmount = 1000 ether; // 1000 frxUSD (18 decimals)

        deal(FRXUSD_MAINNET, swapper, swapAmount);

        SwapHelper helper = new SwapHelper(pool);

        vm.prank(swapper);
        IERC20Metadata(FRXUSD_MAINNET).transfer(address(helper), swapAmount);

        uint256 dusdBefore = _bal(DUSD, swapper);
        helper.swap(false, int256(swapAmount), swapper);
        uint256 dusdReceived = _bal(DUSD, swapper) - dusdBefore;

        // Both tokens are 18 decimals → rate = dusdReceived * 1e18 / swapAmount, ~1e18 for 1:1
        uint256 rateScaled = (dusdReceived * 1e18) / swapAmount;

        console.log("Rate (DUSD per frxUSD, scaled 1e18):", rateScaled);

        assertGt(rateScaled, 0.99e18, "Rate too low - not trading at ~1:1");
        assertLt(rateScaled, 1.01e18, "Rate too high - not trading at ~1:1");
        console.log("SUCCESS: Pool trading at ~1:1 rate");
    }
}

/// @dev Minimal Uniswap V3 swap executor for verifying pool rate.
contract SwapHelper {
    IUniswapV3Pool public immutable pool;

    constructor(IUniswapV3Pool _pool) {
        pool = _pool;
    }

    function swap(bool zeroForOne, int256 amountSpecified, address recipient) external {
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? 4295128740  // MIN_SQRT_RATIO + 1
            : 1461446703485210103287273052203988822378723970341; // MAX_SQRT_RATIO - 1
        pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, abi.encode(msg.sender));
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == address(pool), "Not pool");
        if (amount0Delta > 0) {
            IERC20Metadata(pool.token0()).transfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20Metadata(pool.token1()).transfer(msg.sender, uint256(amount1Delta));
        }
    }
}


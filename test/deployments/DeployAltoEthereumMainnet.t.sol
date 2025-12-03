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
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    WETH_MAINNET,
    WSTETH_MAINNET,
    RETH_MAINNET,
    METH_MAINNET,
    TBTC_MAINNET,
    WBTC_MAINNET,
    CBBTC_MAINNET,
    SUSDE_MAINNET,
    LAYERZERO_ENDPOINT_MAINNET,
    BUNDLER3_MAINNET,
    getMulticallOwnerAddresses
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {IMarketRegistry, MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {IUsmRegistry, UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";

contract DeployAltoEthereumMainnetTest is Test {
    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    address immutable MULTISIG_TIMELOCK_ADMIN = makeAddr("TIMELLOCK_ADMIN");
    address immutable MULTISIG_FREEZER_PAUSER = makeAddr("MULTISIG_FREEZER_PAUSER");
    address immutable STAKING_URD = makeAddr("STAKING_URD");
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
            feeReceiverAddress: STAKING_URD,
            deployer: DEPLOYER,
            phase: DeploymentPhase.CORE,
            useUnsafeUpgrades: true,
            treasuryMultisig: address(1) // TODO: Set to actual treasury multisig address
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

    function test_deployPhase_CORE() public {
        params.phase = DeploymentPhase.CORE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Verify timelock is deployed
        AltoTimelockController timelock = AltoTimelockController(payable(input.contracts.timelock));
        _verifyDeployed(input.contracts.timelock, "Timelock");
        assertEq(timelock.getMinDelay(), 0, "Timelock delay should be 0");
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), params.deployer), "Timelock proposer should be deployer");
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), params.deployer), "Timelock executor should be deployer");
        assertTrue(
            timelock.hasRole(timelock.CANCELLER_ROLE(), params.deployer), "Timelock canceller should be deployer"
        );
        assertTrue(
            timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), params.deployer), "Timelock admin should be deployer"
        );
        for (uint256 i = 0; i < getMulticallOwnerAddresses().length; i++) {
            assertTrue(
                timelock.hasRole(timelock.PROPOSER_ROLE(), getMulticallOwnerAddresses()[i]),
                "Timelock proposer should be multicall owner"
            );
            assertTrue(
                timelock.hasRole(timelock.CANCELLER_ROLE(), getMulticallOwnerAddresses()[i]),
                "Timelock canceller should be multicall owner"
            );
            assertTrue(
                timelock.hasRole(timelock.EXECUTOR_ROLE(), getMulticallOwnerAddresses()[i]),
                "Timelock executor should be multicall owner"
            );
        }

        // Verify feeRecipient is deployed
        // TODO
        _verifyDeployed(input.contracts.feeRecipient, "FeeRecipient");

        // Verify AltoAdapter is deployed
        AltoAdapter adapter = AltoAdapter(payable(input.contracts.altoAdapter));
        _verifyDeployed(input.contracts.altoAdapter, "AltoAdapter");
        assertEq(adapter.owner(), DEPLOYER, "AltoAdapter owner should be deployer");
        assertEq(adapter.BUNDLER3(), BUNDLER3_MAINNET, "AltoAdapter bundler3 should be correct");
        assertEq(address(adapter.WRAPPED_NATIVE()), WETH_MAINNET, "AltoAdapter wNative should be correct");
    }

    function test_deployPhase_REGISTRY() public {
        _deployPrerequisites(DeploymentPhase.REGISTRY);

        params.phase = DeploymentPhase.REGISTRY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        MarketRegistry marketRegistry = MarketRegistry(input.contracts.marketRegistry);
        UsmRegistry usmRegistry = UsmRegistry(input.contracts.usmRegistry);

        // Verify MarketRegistry is deployed
        _verifyDeployed(address(marketRegistry), "MarketRegistry");
        assertEq(marketRegistry.owner(), DEPLOYER, "MarketRegistry owner should be deployer");

        // Verify UsmRegistry is deployed
        _verifyDeployed(address(usmRegistry), "UsmRegistry");
        assertEq(usmRegistry.owner(), DEPLOYER, "UsmRegistry owner should be deployer");
    }

    function test_deployPhase_DUSD() public {
        _deployPrerequisites(DeploymentPhase.DUSD);

        params.phase = DeploymentPhase.DUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Verify DUSD is deployed
        DUSD dusd = DUSD(input.contracts.dusd);
        _verifyDeployed(input.contracts.dusd, "DUSD");
        assertEq(address(dusd.endpoint()), LAYERZERO_ENDPOINT_MAINNET, "DUSD endpoint should be correct");
        assertEq(dusd.owner(), DEPLOYER, "DUSD owner should be deployer");
        _verifyPauser(input.contracts.dusd, "DUSD");

        // Verify DUSDFlashMinter is deployed
        DUSDFlashMinter flashMinter = DUSDFlashMinter(input.contracts.dusdFlashMinter);
        _verifyDeployed(input.contracts.dusdFlashMinter, "DUSDFlashMinter");
        assertEq(flashMinter.owner(), input.contracts.timelock, "DUSDFlashMinter owner should be timelock");

        // Verify parameters
        assertEq(address(flashMinter.DUSD()), input.contracts.dusd, "DUSDFlashMinter DUSD should be correct");
        (uint128 minFlashFee, uint128 maxFlashFee) = flashMinter.flashMintFee();
        assertEq(minFlashFee, 5e14, "DUSDFlashMinter min flash fee should be correct");
        assertEq(maxFlashFee, 1e16, "DUSDFlashMinter max flash fee should be correct");

        // Verify flash minter configuration
        assertTrue(dusd.allowedMinter(input.contracts.dusdFlashMinter), "FlashMinter should be allowed minter");
        assertTrue(dusd.allowedBurner(input.contracts.dusdFlashMinter), "FlashMinter should be allowed burner");
        (uint256 minted, uint256 ceiling) = dusd.minterConfig(input.contracts.dusdFlashMinter);
        assertEq(ceiling, 750_000 ether, "Flash mint ceiling should be correct");
        assertEq(minted, 0, "Flash minter should have 0 minted initially");
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
        _verifyMintCeilingMarket(input.contracts.wethMarket.market, 300_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_WSTETH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_WSTETH);

        params.phase = DeploymentPhase.MINT_MARKET_WSTETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.wstethMarket);
        _verifyMintCeilingMarket(input.contracts.wstethMarket.market, 300_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_RETH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_RETH);

        params.phase = DeploymentPhase.MINT_MARKET_RETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.rethMarket);
        _verifyMintCeilingMarket(input.contracts.rethMarket.market, 300_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_METH() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_METH);

        params.phase = DeploymentPhase.MINT_MARKET_METH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.methMarket);
        _verifyMintCeilingMarket(input.contracts.methMarket.market, 300_000 ether);

        // TODO verify other parameters - base, liquidation engine, IRM, oracle...
    }

    function test_deployPhase_MINT_MARKET_TBTC() public {
        _deployPrerequisites(DeploymentPhase.MINT_MARKET_TBTC);

        params.phase = DeploymentPhase.MINT_MARKET_TBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.tbtcMarket);
        _verifyMintCeilingMarket(input.contracts.tbtcMarket.market, 300_000 ether);

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

    function test_deployPhase_USDC_USM() public {
        _deployPrerequisites(DeploymentPhase.USDC_USM);

        params.phase = DeploymentPhase.USDC_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Verify USDC USM contracts are deployed
        _verifyDeployed(input.contracts.permissionedUsm.dusdUsm, "DUSD USM Permissioned");
        _verifyDeployed(input.contracts.permissionedUsm.dusdUsmImplementation, "DUSD USM implementation Permissioned");
        _verifyDeployed(input.contracts.permissionedUsm.fixedPriceStrategy, "Fixed price strategy Permissioned");
        assertEq(
            input.contracts.permissionedUsm.fixedFeeStrategy,
            address(0),
            "Fixed fee strategy for permissionless USM should be 0"
        );

        _verifyDeployed(input.contracts.permissionlessUsm.dusdUsm, "DUSD USM Permissionless");
        _verifyDeployed(
            input.contracts.permissionlessUsm.dusdUsmImplementation, "DUSD USM implementation Permissionless"
        );
        _verifyDeployed(input.contracts.permissionlessUsm.fixedFeeStrategy, "Fixed fee strategy Permissionless");
        _verifyDeployed(input.contracts.permissionlessUsm.fixedPriceStrategy, "Fixed price strategy Permissionless");

        _verifyMintCeiling(input.contracts.permissionedUsm.dusdUsm, 5_000_000_000 ether);
        _verifyMintCeiling(input.contracts.permissionlessUsm.dusdUsm, 5_000_000_000 ether);

        UsmRegistry usmRegistry = UsmRegistry(input.contracts.usmRegistry);
        assertTrue(
            usmRegistry.isUsm(input.contracts.permissionedUsm.dusdUsm), "DUSD USM Permissioned should be registered"
        );
        assertTrue(
            usmRegistry.isUsm(input.contracts.permissionlessUsm.dusdUsm), "DUSD USM Permissionless should be registered"
        );

        assertTrue(
            IUsm(input.contracts.permissionedUsm.dusdUsm).getAccessMode() == AccessMode.PERMISSIONED,
            "DUSD USM Permissioned should be permissioned"
        );
        assertTrue(
            IUsm(input.contracts.permissionlessUsm.dusdUsm).getAccessMode() == AccessMode.PERMISSIONLESS,
            "DUSD USM Permissionless should be permissionless"
        );

        // TODO verify other parameters - fees, exposure cap, etc.

        _verifyHasRole(
            input.contracts.permissionedUsm.dusdUsm,
            input.contracts.timelock,
            DEFAULT_ADMIN_ROLE,
            "DUSD USM Permissioned"
        );
        _verifyHasRole(
            input.contracts.permissionedUsm.dusdUsm,
            input.contracts.timelock,
            CONFIGURATOR_ROLE,
            "DUSD USM Permissioned"
        );
        _verifyHasRole(
            input.contracts.permissionedUsm.dusdUsm, MULTISIG_FREEZER_PAUSER, SWAP_FREEZER_ROLE, "DUSD USM Permissioned"
        );

        _verifyHasRole(
            input.contracts.permissionlessUsm.dusdUsm,
            input.contracts.timelock,
            DEFAULT_ADMIN_ROLE,
            "DUSD USM Permissionless"
        );
        _verifyHasRole(
            input.contracts.permissionlessUsm.dusdUsm,
            input.contracts.timelock,
            CONFIGURATOR_ROLE,
            "DUSD USM Permissionless"
        );
        _verifyHasRole(
            input.contracts.permissionlessUsm.dusdUsm,
            MULTISIG_FREEZER_PAUSER,
            SWAP_FREEZER_ROLE,
            "DUSD USM Permissionless"
        );

        _verifyHasRole(
            input.contracts.permissionlessUsm.fixedPriceStrategy,
            input.contracts.timelock,
            DEFAULT_ADMIN_ROLE,
            "Fixed price strategy Permissionless"
        );
        _verifyHasRole(
            input.contracts.permissionlessUsm.fixedPriceStrategy,
            input.contracts.timelock,
            CONFIGURATOR_ROLE,
            "Fixed price strategy Permissionless"
        );
        _verifyHasRole(
            input.contracts.permissionlessUsm.fixedFeeStrategy,
            input.contracts.timelock,
            DEFAULT_ADMIN_ROLE,
            "Fixed fee strategy Permissionless"
        );
        _verifyHasRole(
            input.contracts.permissionlessUsm.fixedFeeStrategy,
            input.contracts.timelock,
            CONFIGURATOR_ROLE,
            "Fixed fee strategy Permissionless"
        );

        _verifyHasRole(
            input.contracts.permissionedUsm.fixedPriceStrategy,
            input.contracts.timelock,
            DEFAULT_ADMIN_ROLE,
            "Fixed price strategy Permissioned"
        );
        _verifyHasRole(
            input.contracts.permissionedUsm.fixedPriceStrategy,
            input.contracts.timelock,
            CONFIGURATOR_ROLE,
            "Fixed price strategy Permissioned"
        );
        _verifyHasRole(
            input.contracts.permissionedUsm.dusdUsm, params.treasuryMultisig, SWAPPER_ROLE, "DUSD USM permissioned"
        );
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

    function _verifyHasAllRolesTimelock(address _address, string memory name) internal view {
        AltoTimelockController timelock = AltoTimelockController(payable(input.contracts.timelock));
        assertTrue(
            timelock.hasRole(timelock.PROPOSER_ROLE(), _address), string.concat(name, " should have PROPOSER_ROLE")
        );
        assertTrue(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), _address), string.concat(name, " should have EXECUTOR_ROLE")
        );
        assertTrue(
            timelock.hasRole(timelock.CANCELLER_ROLE(), _address), string.concat(name, " should have CANCELLER_ROLE")
        );
        assertTrue(
            timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), _address),
            string.concat(name, " should have DEFAULT_ADMIN_ROLE")
        );
    }

    function _verifyHasNoRolesTimelock(address _address, string memory name) internal view {
        AltoTimelockController timelock = AltoTimelockController(payable(input.contracts.timelock));
        assertFalse(
            timelock.hasRole(timelock.PROPOSER_ROLE(), _address), string.concat(name, " should not have PROPOSER_ROLE")
        );
        assertFalse(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), _address), string.concat(name, " should not have EXECUTOR_ROLE")
        );
        assertFalse(
            timelock.hasRole(timelock.CANCELLER_ROLE(), _address),
            string.concat(name, " should not have CANCELLER_ROLE")
        );
        assertFalse(
            timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), _address),
            string.concat(name, " should not have DEFAULT_ADMIN_ROLE")
        );
    }

    function test_deployPhase_POST() public {
        _deployPrerequisites(DeploymentPhase.USDC_USM);

        params.phase = DeploymentPhase.USDC_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.POST;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _revokeTimelockRolesFromDeployer();

        _verifyOwner(input.contracts.altoAdapter, "AltoAdapter");
        _verifyOwner(input.contracts.dusd, "DUSD");
        _verifyOwner(input.contracts.marketRegistry, "MarketRegistry");
        _verifyOwner(input.contracts.usmRegistry, "UsmRegistry");
        _verifyHasAllRolesTimelock(MULTISIG_TIMELOCK_ADMIN, "multisig admin");
        _verifyHasNoRolesTimelock(params.deployer, "deployer");
        for (uint256 i = 0; i < getMulticallOwnerAddresses().length; i++) {
            _verifyHasNoRolesTimelock(
                getMulticallOwnerAddresses()[i], string.concat("multicall owner ", Strings.toString(i))
            );
        }
    }

    function _revokeTimelockRolesFromDeployer() internal {
        vm.warp(block.timestamp + params.timelockDelay);

        AltoTimelockController timelockContract = AltoTimelockController(payable(input.contracts.timelock));

        bytes32[] memory roles = new bytes32[](4);
        roles[0] = timelockContract.PROPOSER_ROLE();
        roles[1] = timelockContract.EXECUTOR_ROLE();
        roles[2] = timelockContract.CANCELLER_ROLE();
        roles[3] = timelockContract.DEFAULT_ADMIN_ROLE();

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);

        for (uint256 i = 0; i < 4; i++) {
            targets[i] = address(timelockContract);
            values[i] = 0;
            payloads[i] = abi.encodeWithSelector(AccessControl.revokeRole.selector, roles[i], DEPLOYER);
        }

        timelockContract.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));
    }

    function test_deployAllPhasesSequentially() public {
        params.phase = DeploymentPhase.CORE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.REGISTRY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.DUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_WETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_WSTETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_RETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_METH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_TBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.BORROW_MARKET_WBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.BORROW_MARKET_CBBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.BORROW_MARKET_SUSDE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.USDC_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.POST;
        input = DeployAltoEthereumMainnet.deploy(params, input);
    }
}


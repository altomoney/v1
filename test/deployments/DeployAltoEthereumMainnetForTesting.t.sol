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
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnetForTesting.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    WETH_MAINNET,
    WBTC_MAINNET,
    USDC_MAINNET,
    LAYERZERO_ENDPOINT_MAINNET,
    BUNDLER3_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {IMarketRegistry, MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@alto-test/oracles/interfaces/ISwapRouter.sol";

contract DeployAltoEthereumMainnetForTestingTest is Test {
    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    address immutable MULTISIG_FREEZER_PAUSER = makeAddr("MULTISIG_FREEZER_PAUSER");
    address DEPLOYER;

    ISwapRouter constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        DEPLOYER = address(this);

        params = AltoEthereumMainnetParams({
            timelockAdmin: address(0), // Not used in ForTesting
            timelockDelay: 0, // Not used in ForTesting
            freezer: MULTISIG_FREEZER_PAUSER,
            deployer: DEPLOYER,
            phase: DeploymentPhase.CORE,
            useUnsafeUpgrades: true,
            treasuryMultisig: address(0), // Not used in ForTesting
            uniswapV3NonFungiblePositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
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

        // Deploy MarketRegistry if not already deployed (needed for markets)
        // Note: ForTesting deployment doesn't deploy registries, so we deploy them here for testing
        if (input.contracts.marketRegistry == address(0)) {
            input.contracts.marketRegistry = address(new MarketRegistry(DEPLOYER));
        }
    }

    function test_deployPhase_CORE() public {
        params.phase = DeploymentPhase.CORE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Verify AltoAdapter is deployed
        AltoAdapter adapter = AltoAdapter(payable(input.contracts.altoAdapter));
        _verifyDeployed(input.contracts.altoAdapter, "AltoAdapter");
        assertEq(adapter.owner(), DEPLOYER, "AltoAdapter owner should be deployer");
        assertEq(adapter.BUNDLER3(), BUNDLER3_MAINNET, "AltoAdapter bundler3 should be correct");
        assertEq(address(adapter.WRAPPED_NATIVE()), WETH_MAINNET, "AltoAdapter wNative should be correct");
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
        assertEq(flashMinter.owner(), DEPLOYER, "DUSDFlashMinter owner should be deployer");

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
        IMarketRegistry marketRegistry = IMarketRegistry(input.contracts.marketRegistry);

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
        assertEq(Ownable(addr).owner(), DEPLOYER, string.concat(name, " owner mismatch"));
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
    }

    function test_deployPhase_BORROW_MARKET_WBTC() public {
        _deployPrerequisites(DeploymentPhase.BORROW_MARKET_WBTC);

        params.phase = DeploymentPhase.BORROW_MARKET_WBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        _verifyMarketContracts(input.contracts.wbtcBorrowMarket);
    }

    function test_deployPhase_POST() public {
        _deployPrerequisites(DeploymentPhase.POST);

        // Give test account USDC and approve for Uniswap position manager before POST phase
        IERC20Metadata usdc = IERC20Metadata(USDC_MAINNET);
        deal(USDC_MAINNET, DEPLOYER, 1000 * 10 ** 6); // 1000 USDC
        usdc.approve(params.uniswapV3NonFungiblePositionManager, type(uint256).max);

        // Approve DUSD for Uniswap position manager as well
        DUSD dusd = DUSD(input.contracts.dusd);
        dusd.approve(params.uniswapV3NonFungiblePositionManager, type(uint256).max);

        params.phase = DeploymentPhase.POST;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Verify deployer can mint DUSD
        assertTrue(dusd.allowedMinter(DEPLOYER), "Deployer should be allowed minter");
        (uint256 minted, uint256 ceiling) = dusd.minterConfig(DEPLOYER);
        assertEq(ceiling, type(uint128).max, "Deployer mint ceiling should be max");
        // Deployer should have close to 1M DUSD (some was used for Uniswap position)
        assertGe(dusd.balanceOf(DEPLOYER), 999_000 ether, "Deployer should have at least 999k DUSD");

        // Verify Uniswap pool is created
        _verifyDeployed(input.contracts.uniswapPool, "UniswapPool");
        IUniswapV3Pool pool = IUniswapV3Pool(input.contracts.uniswapPool);
        assertEq(
            pool.token0(),
            address(USDC_MAINNET) < input.contracts.dusd ? address(USDC_MAINNET) : input.contracts.dusd,
            "Pool token0 should be correct"
        );
        assertEq(
            pool.token1(),
            address(USDC_MAINNET) < input.contracts.dusd ? input.contracts.dusd : address(USDC_MAINNET),
            "Pool token1 should be correct"
        );
        assertEq(pool.fee(), 100, "Pool fee should be 100");

        // Verify 1:1 peg by swapping 10 USDC for DUSD
        uint256 usdcAmount = 10 * 10 ** 6; // 10 USDC (6 decimals)
        uint256 dusdBalanceBefore = dusd.balanceOf(DEPLOYER);

        // Ensure we have enough USDC
        deal(USDC_MAINNET, DEPLOYER, usdcAmount);
        usdc.approve(address(SWAP_ROUTER), usdcAmount);

        // Perform swap: 10 USDC -> DUSD
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC_MAINNET,
            tokenOut: input.contracts.dusd,
            fee: 100,
            recipient: DEPLOYER,
            deadline: block.timestamp + 1 hours,
            amountIn: usdcAmount,
            amountOutMinimum: 0, // Allow some slippage for testing
            sqrtPriceLimitX96: 0
        });

        uint256 dusdReceived = SWAP_ROUTER.exactInputSingle(swapParams);
        uint256 dusdBalanceAfter = dusd.balanceOf(DEPLOYER);

        uint256 expectedDusdMin = (usdcAmount * 1e12 * 98) / 100; // Convert USDC to DUSD decimals, allow 2% slippage
        assertGe(
            dusdReceived,
            expectedDusdMin,
            "Should receive at least 9.8 DUSD for 10 USDC (accounting for fees and price impact)"
        );
        assertLe(dusdReceived, usdcAmount * 1e12, "Should not receive more than 10 DUSD");
        assertEq(dusdBalanceAfter - dusdBalanceBefore, dusdReceived, "DUSD balance should increase by amount received");
    }

    function test_deployAllPhasesSequentially() public {
        params.phase = DeploymentPhase.CORE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Deploy MarketRegistry before markets (needed for market registration)
        if (input.contracts.marketRegistry == address(0)) {
            input.contracts.marketRegistry = address(new MarketRegistry(DEPLOYER));
        }

        params.phase = DeploymentPhase.DUSD;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_WETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.BORROW_MARKET_WBTC;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // Give test account USDC and approve for Uniswap position manager before POST phase
        IERC20Metadata usdc = IERC20Metadata(USDC_MAINNET);
        deal(USDC_MAINNET, DEPLOYER, 1000 * 10 ** 6); // 1000 USDC
        usdc.approve(params.uniswapV3NonFungiblePositionManager, type(uint256).max);

        // Approve DUSD for Uniswap position manager as well
        DUSD dusd = DUSD(input.contracts.dusd);
        dusd.approve(params.uniswapV3NonFungiblePositionManager, type(uint256).max);

        params.phase = DeploymentPhase.POST;
        input = DeployAltoEthereumMainnet.deploy(params, input);
    }
}


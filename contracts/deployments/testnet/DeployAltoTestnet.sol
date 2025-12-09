// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {ERC20Testnet} from "@alto/deployments/testnet/contracts/ERC20Testnet.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {
    TestnetBorrowMarketBatch,
    TestnetBorrowMarketBatchParams
} from "@alto/deployments/testnet/TestnetBorrowMarketBatch.sol";
import {
    TestnetMintMarketBatch,
    TestnetMintMarketBatchParams
} from "@alto/deployments/testnet/TestnetMintMarketBatch.sol";
import {TestnetMarketBatchReport} from "@alto/deployments/testnet/ITestnetMarketBatch.sol";
import {MultiTokenSender} from "@alto/deployments/testnet/contracts/MultiTokenSender.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";

import {
    TestnetRewardsBatch,
    TestnetRewardsBatchReport,
    TestnetRewardsBatchParams
} from "@alto/deployments/testnet/TestnetRewardsBatch.sol";
import {
    TestnetStakingBatch,
    TestnetStakingBatchParams,
    TestnetStakingBatchReport
} from "@alto/deployments/testnet/TestnetStakingBatch.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    MULTI_TOKEN_SENDER_MINT_TOKENS,
    BACKEND_TESTNET_ADDRESS,
    ALTO_TOKEN_TOTAL_SUPPLY,
    DUSD_TOKEN_SUPPLY_TO_CONTRACTS
} from "@alto/deployments/testnet/Constants.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {getMulticallOwnerAddresses} from "@alto/deployments/testnet/Constants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    INonfungiblePositionManager,
    MintParams
} from "@alto/deployments/testnet/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {
    TestnetUsmBatch,
    TestnetUsmBatchParams,
    TestnetUsmBatchReport
} from "@alto/deployments/testnet/TestnetUsmBatch.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";

struct AltoTestnetInput {
    TestnetTokens tokens;
    Contracts contracts;
}

struct Contracts {
    address altoMulticall;
    address multiTokenSender;
    address mockSwapper;
    address altoLeverage;
    address bundler3;
    address altoAdapter;
    address marketRegistry;
    address usmRegistry;
    TestnetMarketBatchReport wethMarketBatch;
    TestnetMarketBatchReport wstethMarketBatch;
    TestnetMarketBatchReport rethMarketBatch;
    TestnetMarketBatchReport methMarketBatch;
    TestnetMarketBatchReport tbtcMarketBatch;
    TestnetMarketBatchReport wbtcMarketBatch;
    TestnetMarketBatchReport cbbtcMarketBatch;
    TestnetMarketBatchReport susdeMarketBatch;
    TestnetStakingBatchReport stakingBatch;
    TestnetRewardsBatchReport rewardsBatch;
    TestnetUsmBatchReport usdcUsmBatch;
}

struct TestnetTokens {
    address alto;
    address dusd;
    // Rewards Payment Token
    address usdc;
    // Market Tokens
    // Mint
    address weth;
    address wsteth;
    address reth;
    address meth;
    address tbtc;
    // Borrow
    address wbtc;
    address cbbtc;
    address susde;
}

struct AltoTestnetParams {
    bool skipLendingDeployment;
    address lzEndpoint;
    address wrappedNativeToken;
    address uniswapV3NonFungiblePositionManager;
    address deployer;
}

library DeployAltoTestnet {
    using SafeERC20 for IERC20;

    function deploy(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input = _deployMulticall(params, input);
        input = _deployLending(params, input);
        input = _deployRegistry(params, input);
        input = _deployStaking(params, input);
        input = _deployRewards(params, input);
        input = _deployUniswapPools(params, input);

        _transferOwnership(params, input);

        IERC20(input.tokens.dusd)
            .safeTransfer(input.contracts.stakingBatch.universalRewardsDistributor, DUSD_TOKEN_SUPPLY_TO_CONTRACTS);

        IERC20(input.tokens.alto)
            .safeTransfer(input.contracts.rewardsBatch.rewardsDistributor, ALTO_TOKEN_TOTAL_SUPPLY / 2);

        return input;
    }

    function _deployMulticall(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input.contracts.altoMulticall = address(new AltoMulticallTestnet(getMulticallOwnerAddresses()));
        return input;
    }

    function _deployRegistry(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input.contracts.marketRegistry = address(new MarketRegistry(params.deployer));
        IMarketRegistry(input.contracts.marketRegistry).addMintMarket(input.contracts.wethMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addMintMarket(input.contracts.wstethMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addMintMarket(input.contracts.rethMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addMintMarket(input.contracts.methMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addMintMarket(input.contracts.tbtcMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addBorrowMarket(input.contracts.wbtcMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addBorrowMarket(input.contracts.cbbtcMarketBatch.market);
        IMarketRegistry(input.contracts.marketRegistry).addBorrowMarket(input.contracts.susdeMarketBatch.market);

        input.contracts.usmRegistry = address(new UsmRegistry(params.deployer));
        IUsmRegistry(input.contracts.usmRegistry).addUsm(input.contracts.usdcUsmBatch.dusdUsm);

        address contractOwner = input.contracts.altoMulticall;
        AltoOwnable2Step(input.contracts.marketRegistry).transferOwnershipSkip2Step(contractOwner);
        AltoOwnable2Step(input.contracts.usmRegistry).transferOwnershipSkip2Step(contractOwner);
        return input;
    }

    function _deployLending(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        address contractOwner = input.contracts.altoMulticall;

        if (params.skipLendingDeployment) {
            return input;
        }

        // deploy bundler3 and alto adapter
        input.contracts.bundler3 = address(new Bundler3());
        input.contracts.altoAdapter =
            address(new AltoAdapter(input.contracts.bundler3, params.wrappedNativeToken, params.deployer));

        // deploy multi token sender
        input.contracts.multiTokenSender = address(new MultiTokenSender(params.deployer));
        MultiTokenSender(input.contracts.multiTokenSender).updateWhitelist(BACKEND_TESTNET_ADDRESS, true);
        Ownable(input.contracts.multiTokenSender).transferOwnership(contractOwner);

        // deploy leverage and mock swapper
        input.contracts.mockSwapper = address(new SwapperSimpleMock(params.deployer));
        input.contracts.altoLeverage = address(new AltoLeverage(input.contracts.mockSwapper, params.deployer));
        SwapperSimpleMock(payable(input.contracts.mockSwapper))
            .setWhitelisted(address(input.contracts.altoLeverage), true);
        Ownable(input.contracts.mockSwapper).transferOwnership(contractOwner);

        // deploy and mint tokens to the owner
        input = _deployMintFundTokens(params, input);

        // Mint Markets
        input.contracts.wethMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.weth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4100 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 500_000 ether,
                    fixedRateIrmInterestRate: 0.035 ether / uint256(365 days),
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wethMarketBatch.market, true);

        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.wethMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.wethMarketBatch.market, _calculateMinterCeiling(input.contracts.wethMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.wethMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.wethMarketBatch.market);

        input.contracts.wstethMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.wsteth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 5000 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 300_000 ether,
                    fixedRateIrmInterestRate: 0.035 ether / uint256(365 days),
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wstethMarketBatch.market, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.wstethMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.wstethMarketBatch.market, _calculateMinterCeiling(input.contracts.wstethMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.wstethMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.wstethMarketBatch.market);

        input.contracts.rethMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.reth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4700 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 100_000 ether,
                    fixedRateIrmInterestRate: 0.04 ether / uint256(365 days),
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.rethMarketBatch.market, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.rethMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.rethMarketBatch.market, _calculateMinterCeiling(input.contracts.rethMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.rethMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.rethMarketBatch.market);

        input.contracts.methMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.meth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4700 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 100_000 ether,
                    fixedRateIrmInterestRate: 0.04 ether / uint256(365 days),
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.methMarketBatch.market, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.methMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.methMarketBatch.market, _calculateMinterCeiling(input.contracts.methMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.methMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.methMarketBatch.market);

        input.contracts.tbtcMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.tbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 112000 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 100_000 ether,
                    fixedRateIrmInterestRate: 0.04 ether / uint256(365 days),
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.tbtcMarketBatch.market, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.tbtcMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.tbtcMarketBatch.market, _calculateMinterCeiling(input.contracts.tbtcMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.tbtcMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.tbtcMarketBatch.market);

        // Borrow Markets
        input.contracts.wbtcMarketBatch = (new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.wbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 100_000 * LENDING_ORACLE_PRICE_PRECISION * 1e10,
                    maxLtv: 0.75 ether,
                    supplyCapAssets: 0,
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wbtcMarketBatch.market, true);

        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.wbtcMarketBatch.market);

        input.contracts.cbbtcMarketBatch = (new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.cbbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 100_000 * LENDING_ORACLE_PRICE_PRECISION * 1e10,
                    maxLtv: 0.75 ether,
                    supplyCapAssets: 1_000_000 ether,
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.cbbtcMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.cbbtcMarketBatch.market);

        input.contracts.susdeMarketBatch = (new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: contractOwner,
                    collateralToken: address(input.tokens.susde),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 1.2 ether * LENDING_ORACLE_PRICE_PRECISION / 1 ether,
                    maxLtv: 0.75 ether,
                    supplyCapAssets: 0,
                    leverageAddress: input.contracts.altoLeverage
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.susdeMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.susdeMarketBatch.market);

        AltoOwnable2Step(input.contracts.altoLeverage).transferOwnershipSkip2Step(contractOwner);

        input.contracts.usdcUsmBatch = (new TestnetUsmBatch(
                        TestnetUsmBatchParams({
                            owner: contractOwner,
                            dusd: input.tokens.dusd,
                            underlyingAsset: input.tokens.usdc,
                            buyFee: 0.005e4, // 0.5%
                            sellFee: 0.005e4, // 0.5%
                            exposureCap: 100_000 * 10 ** 6, // 100,000 USDC
                            feeRecipient: params.deployer // Use deployer as feeRecipient, separate from owner (stableTokenTreasury)
                        })
                    )).getReport();

        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.usdcUsmBatch.dusdUsm, true);
        DUSD(input.tokens.dusd).setMinterCeiling(input.contracts.usdcUsmBatch.dusdUsm, 100_000 ether);
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.usdcUsmBatch.dusdUsm, true);

        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.usdcUsmBatch.dusdUsm);

        return input;
    }

    function _deployMintFundTokens(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        address contractOwner = input.contracts.altoMulticall;
        input.tokens.alto = address(new AltoToken(params.lzEndpoint, params.deployer));
        Ownable(input.tokens.alto).transferOwnership(contractOwner);

        // all ALTO is already minted to the owner in the constructor
        input.tokens.dusd = address(new DUSD(params.lzEndpoint, params.deployer));
        DUSD(input.tokens.dusd).setMinterStatus(params.deployer, true);
        DUSD(input.tokens.dusd).setMinterCeiling(params.deployer, type(uint128).max);
        // we can't mint uint256 max as markets need to be able to mint during borrow/repay
        DUSD(input.tokens.dusd).mint(params.deployer, type(uint128).max);
        DUSD(input.tokens.dusd).setMinterStatus(params.deployer, false);

        // Reward Payment Token
        input.tokens.usdc = address(new ERC20Testnet("USDC", 6, params.deployer));
        ERC20Testnet(input.tokens.usdc).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.usdc).transferOwnership(contractOwner);

        // Mint
        input.tokens.weth = address(new ERC20Testnet("WETH", 18, params.deployer));
        ERC20Testnet(input.tokens.weth).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.weth).transferOwnership(contractOwner);

        input.tokens.wsteth = address(new ERC20Testnet("wstETH", 18, params.deployer));
        ERC20Testnet(input.tokens.wsteth).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.wsteth).transferOwnership(contractOwner);

        input.tokens.reth = address(new ERC20Testnet("rETH", 18, params.deployer));
        ERC20Testnet(input.tokens.reth).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.reth).transferOwnership(contractOwner);

        input.tokens.meth = address(new ERC20Testnet("mETH", 18, params.deployer));
        ERC20Testnet(input.tokens.meth).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.meth).transferOwnership(contractOwner);

        input.tokens.tbtc = address(new ERC20Testnet("tBTC", 18, params.deployer));
        ERC20Testnet(input.tokens.tbtc).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.tbtc).transferOwnership(contractOwner);

        // Borrow

        input.tokens.wbtc = address(new ERC20Testnet("wBTC", 8, params.deployer));
        ERC20Testnet(input.tokens.wbtc).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.wbtc).transferOwnership(contractOwner);

        input.tokens.cbbtc = address(new ERC20Testnet("cbBTC", 8, params.deployer));
        ERC20Testnet(input.tokens.cbbtc).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.cbbtc).transferOwnership(contractOwner);

        input.tokens.susde = address(new ERC20Testnet("sUSDe", 18, params.deployer));
        ERC20Testnet(input.tokens.susde).mint(params.deployer, type(uint256).max);
        Ownable(input.tokens.susde).transferOwnership(contractOwner);

        // fund tokens to the multi token sender
        IERC20(input.tokens.dusd).safeTransfer(input.contracts.multiTokenSender, DUSD_TOKEN_SUPPLY_TO_CONTRACTS);
        IERC20(input.tokens.alto).safeTransfer(input.contracts.multiTokenSender, ALTO_TOKEN_TOTAL_SUPPLY / 4);

        IERC20(input.tokens.weth).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.usdc).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.wsteth).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.reth).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.meth).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.tbtc).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.wbtc).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.cbbtc).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.susde).safeTransfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);

        // fund tokens to swapper
        IERC20(input.tokens.dusd).safeTransfer(input.contracts.mockSwapper, DUSD_TOKEN_SUPPLY_TO_CONTRACTS);

        IERC20(input.tokens.usdc).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.weth).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.wsteth).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.reth).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.meth).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.tbtc).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.wbtc).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.cbbtc).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.susde).safeTransfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);

        return input;
    }

    function _deployStaking(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        address contractOwner = input.contracts.altoMulticall;
        input.contracts.stakingBatch = (new TestnetStakingBatch(
                TestnetStakingBatchParams({
                    owner: contractOwner,
                    rewardToken: address(input.tokens.alto),
                    epochDuration: 3 days,
                    universalRewardsDistributorTimelock: 1 minutes
                })
            ))
        .getStakingContractReport();

        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.stakingBatch.stakingContract);
        AltoAdapter(payable(input.contracts.altoAdapter))
            .approveContract(input.contracts.stakingBatch.universalRewardsDistributor);

        return input;
    }

    function _deployRewards(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        address[] memory paymentTokens = new address[](2);
        paymentTokens[0] = address(input.tokens.usdc);
        paymentTokens[1] = address(input.tokens.dusd);
        uint256[] memory paymentUsdOraclePrices = new uint256[](2);
        paymentUsdOraclePrices[0] = 1 * USD_ORACLE_PRICE_PRECISION;
        paymentUsdOraclePrices[1] = 1 * USD_ORACLE_PRICE_PRECISION;

        address contractOwner = input.contracts.altoMulticall;

        input.contracts.rewardsBatch = (new TestnetRewardsBatch(
                TestnetRewardsBatchParams({
                    owner: contractOwner,
                    rewardToken: address(input.tokens.alto),
                    merkleRootTimelock: 1 minutes,
                    paymentTokens: paymentTokens,
                    paymentUsdOraclePrices: paymentUsdOraclePrices,
                    rewardTokenUsdOraclePrice: 1.5 ether * USD_ORACLE_PRICE_PRECISION / 1 ether,
                    lockBonusDiscount: 0.15 ether,
                    stakingContract: input.contracts.stakingBatch.stakingContract
                })
            ))
        .getRewardsDistributorReport();

        AltoAdapter(payable(input.contracts.altoAdapter))
            .approveContract(input.contracts.rewardsBatch.rewardsDistributor);

        return input;
    }

    function _deployUniswapPools(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        IERC20(input.tokens.reth).approve(address(params.uniswapV3NonFungiblePositionManager), type(uint256).max);
        IERC20(input.tokens.weth).approve(address(params.uniswapV3NonFungiblePositionManager), type(uint256).max);
        IERC20(input.tokens.usdc).approve(address(params.uniswapV3NonFungiblePositionManager), type(uint256).max);
        IERC20(input.tokens.dusd).approve(address(params.uniswapV3NonFungiblePositionManager), type(uint256).max);
        IERC20(input.tokens.wbtc).approve(address(params.uniswapV3NonFungiblePositionManager), type(uint256).max);
        {
            MintParams memory mintParams = MintParams({
                token0: address(input.tokens.reth),
                token1: address(input.tokens.weth),
                fee: 100,
                tickLower: -887272,
                tickUpper: 887272,
                amount0Desired: 1_000_000 ether,
                amount1Desired: 1_000_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: params.deployer,
                deadline: block.timestamp + 1 days
            });

            // initial price of 1 rETH = 1.1465 WETH
            if (input.tokens.reth < input.tokens.weth) {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.reth), address(input.tokens.weth), 100, 84832472985249386653488423004
                    );
                mintParams.token0 = address(input.tokens.reth);
                mintParams.token1 = address(input.tokens.weth);
            } else {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.weth), address(input.tokens.reth), 100, 73990391685604699676039109455
                    );
                mintParams.token0 = address(input.tokens.weth);
                mintParams.token1 = address(input.tokens.reth);
            }

            INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager).mint(mintParams);
        }

        {
            MintParams memory mintParams = MintParams({
                token0: address(input.tokens.usdc),
                token1: address(input.tokens.weth),
                fee: 500,
                tickLower: -887270,
                tickUpper: 887270,
                amount0Desired: 100_000_000 * 10 ** 6,
                amount1Desired: 1_000_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: params.deployer,
                deadline: block.timestamp + 1 days
            });

            // initial price of 1 weth = 3200 USDC
            if (input.tokens.usdc < input.tokens.weth) {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.usdc), address(input.tokens.weth), 500, 1417745249090387378668354381283328
                    );
                mintParams.token0 = address(input.tokens.usdc);
                mintParams.amount0Desired = 100_000_000 * 10 ** 6;
                mintParams.token1 = address(input.tokens.weth);
                mintParams.amount1Desired = 1_000_000 ether;
            } else {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.weth), address(input.tokens.usdc), 500, 4425601977833494958990786
                    );
                mintParams.token0 = address(input.tokens.weth);
                mintParams.amount0Desired = 1_000_000 ether;
                mintParams.token1 = address(input.tokens.usdc);
                mintParams.amount1Desired = 100_000_000 * 10 ** 6;
            }

            INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager).mint(mintParams);
        }

        {
            MintParams memory mintParams = MintParams({
                token0: address(input.tokens.usdc),
                token1: address(input.tokens.dusd),
                fee: 100,
                tickLower: -887272,
                tickUpper: 887272,
                amount0Desired: 1_500_000 * 10 ** 6,
                amount1Desired: 1_500_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: params.deployer,
                deadline: block.timestamp + 1 days
            });

            // initial price of 1 dusd = 1 USDC
            if (input.tokens.usdc < input.tokens.dusd) {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.usdc), address(input.tokens.dusd), 100, 79226131514347940073696838322079733
                    );
                mintParams.token0 = address(input.tokens.usdc);
                mintParams.amount0Desired = 1_500_000 * 10 ** 6;
                mintParams.token1 = address(input.tokens.dusd);
                mintParams.amount1Desired = 1_500_000 ether;
            } else {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.dusd), address(input.tokens.usdc), 100, 79226398639705836713598
                    );
                mintParams.token0 = address(input.tokens.dusd);
                mintParams.amount0Desired = 1_500_000 ether;
                mintParams.token1 = address(input.tokens.usdc);
                mintParams.amount1Desired = 1_500_000 * 10 ** 6;
            }

            INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager).mint(mintParams);
        }

        {
            MintParams memory mintParams = MintParams({
                token0: address(input.tokens.wbtc),
                token1: address(input.tokens.usdc),
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: 1000 * 10 ** 8,
                amount1Desired: 1_000_000 * 10 ** 6,
                amount0Min: 0,
                amount1Min: 0,
                recipient: params.deployer,
                deadline: block.timestamp + 1 days
            });

            // initial price of 1 wbtc = 91300 USDC
            if (input.tokens.wbtc < input.tokens.usdc) {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.wbtc), address(input.tokens.usdc), 3000, 2390522350476481540566216842177
                    );
                mintParams.token0 = address(input.tokens.wbtc);
                mintParams.amount0Desired = 1000 * 10 ** 8;
                mintParams.token1 = address(input.tokens.usdc);
                mintParams.amount1Desired = 100_000_000 * 10 ** 6;
            } else {
                INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager)
                    .createAndInitializePoolIfNecessary(
                        address(input.tokens.usdc), address(input.tokens.wbtc), 3000, 2625828507370166000000000000
                    );
                mintParams.token0 = address(input.tokens.usdc);
                mintParams.amount0Desired = 100_000_000 * 10 ** 6;
                mintParams.token1 = address(input.tokens.wbtc);
                mintParams.amount1Desired = 1000 * 10 ** 8;
            }

            INonfungiblePositionManager(params.uniswapV3NonFungiblePositionManager).mint(mintParams);
        }

        return input;
    }

    function _transferOwnership(AltoTestnetParams memory params, AltoTestnetInput memory input) internal {
        AltoOwnable2Step(input.tokens.dusd).transferOwnershipSkip2Step(input.contracts.altoMulticall);
        Ownable(input.contracts.altoAdapter).transferOwnership(input.contracts.altoMulticall);
    }

    function _calculateMinterCeiling(TestnetMarketBatchReport memory marketBatchReport)
        internal
        view
        returns (uint256)
    {
        IMarket market = IMarket(marketBatchReport.market);

        uint256 debtCeiling = market.totalSupply().assets;

        uint256 maxLiquidationLtv = IAltoLiquidationEngine(market.liquidationEngine()).minLltv();

        return debtCeiling * 1.05 ether / maxLiquidationLtv;
    }
}

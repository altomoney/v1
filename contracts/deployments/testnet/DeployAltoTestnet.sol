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
import {IMarket, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
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
    address owner;
    bool skipLendingDeployment;
    address lzEndpoint;
    address wrappedNativeToken;
    address uniswapV3NonFungiblePositionManager;
}

library DeployAltoTestnet {
    using SafeERC20 for IERC20;

    function deploy(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input = _deployMulticall(params, input);
        input = _deployLending(params, input);
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
        input.contracts.altoMulticall = address(new AltoMulticallTestnet());
        address[] memory ownerAddresses = getMulticallOwnerAddresses();
        for (uint256 i = 0; i < ownerAddresses.length; i++) {
            AltoMulticallTestnet(payable(input.contracts.altoMulticall)).setOwner(ownerAddresses[i], true);
        }
        return input;
    }

    function _deployLending(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        if (params.skipLendingDeployment) {
            return input;
        }

        // deploy bundler3 and alto adapter
        input.contracts.bundler3 = address(new Bundler3());
        input.contracts.altoAdapter =
            address(new AltoAdapter(input.contracts.bundler3, params.wrappedNativeToken, params.owner));

        // deploy multi token sender
        input.contracts.multiTokenSender = address(new MultiTokenSender(params.owner));
        MultiTokenSender(input.contracts.multiTokenSender).updateWhitelist(BACKEND_TESTNET_ADDRESS, true);

        // deploy leverage and mock swapper
        input.contracts.mockSwapper = address(new SwapperSimpleMock(params.owner));
        input.contracts.altoLeverage = address(new AltoLeverage(input.contracts.mockSwapper, params.owner));
        SwapperSimpleMock(payable(input.contracts.mockSwapper))
            .setWhitelisted(address(input.contracts.altoLeverage), true);

        // deploy and mint tokens to the owner
        input = _deployMintFundTokens(params, input);

        // Mint Markets
        input.contracts.wethMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.weth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4100 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 500_000 ether,
                    fixedRateIrmInterestRate: 0.035 ether / uint256(365 days)
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wethMarketBatch.market, true);
        IMarket(input.contracts.wethMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.wethMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.wethMarketBatch.market, _calculateMinterCeiling(input.contracts.wethMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.wethMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.wethMarketBatch.market);

        input.contracts.wstethMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.wsteth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 5000 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 300_000 ether,
                    fixedRateIrmInterestRate: 0.035 ether / uint256(365 days)
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wstethMarketBatch.market, true);
        IMarket(input.contracts.wstethMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.wstethMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.wstethMarketBatch.market, _calculateMinterCeiling(input.contracts.wstethMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.wstethMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.wstethMarketBatch.market);

        input.contracts.rethMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.reth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4700 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 100_000 ether,
                    fixedRateIrmInterestRate: 0.04 ether / uint256(365 days)
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.rethMarketBatch.market, true);
        IMarket(input.contracts.rethMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.rethMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.rethMarketBatch.market, _calculateMinterCeiling(input.contracts.rethMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.rethMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.rethMarketBatch.market);

        input.contracts.methMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.meth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4700 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 100_000 ether,
                    fixedRateIrmInterestRate: 0.04 ether / uint256(365 days)
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.methMarketBatch.market, true);
        IMarket(input.contracts.methMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.methMarketBatch.market, true);
        DUSD(input.tokens.dusd)
            .setMinterCeiling(
                input.contracts.methMarketBatch.market, _calculateMinterCeiling(input.contracts.methMarketBatch)
            );
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.methMarketBatch.market, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.methMarketBatch.market);

        input.contracts.tbtcMarketBatch = (new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.tbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 112000 * LENDING_ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 100_000 ether,
                    fixedRateIrmInterestRate: 0
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.tbtcMarketBatch.market, true);
        IMarket(input.contracts.tbtcMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
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
                    owner: params.owner,
                    collateralToken: address(input.tokens.wbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 100_000 ether * LENDING_ORACLE_PRICE_PRECISION / 1 ether,
                    maxLtv: 0.75 ether
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wbtcMarketBatch.market, true);
        IMarket(input.contracts.wbtcMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.wbtcMarketBatch.market);

        input.contracts.cbbtcMarketBatch = (new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.cbbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 100_000 ether * LENDING_ORACLE_PRICE_PRECISION / 1 ether,
                    maxLtv: 0.75 ether
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.cbbtcMarketBatch.market, true);
        IMarket(input.contracts.cbbtcMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.cbbtcMarketBatch.market);

        input.contracts.susdeMarketBatch = (new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.susde),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 1.2 ether * LENDING_ORACLE_PRICE_PRECISION / 1 ether,
                    maxLtv: 0.75 ether
                })
            ))
        .getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.susdeMarketBatch.market, true);
        IMarket(input.contracts.susdeMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        AltoAdapter(payable(input.contracts.altoAdapter)).approveContract(input.contracts.susdeMarketBatch.market);

        return input;
    }

    function _deployMintFundTokens(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input.tokens.alto = address(new AltoToken(params.lzEndpoint, params.owner));
        // all ALTO is already minted to the owner in the constructor
        input.tokens.dusd = address(new DUSD(params.lzEndpoint, params.owner));
        DUSD(input.tokens.dusd).setMinterStatus(params.owner, true);
        DUSD(input.tokens.dusd).setMinterCeiling(params.owner, type(uint128).max);
        // we can't mint uint256 max as markets need to be able to mint during borrow/repay
        DUSD(input.tokens.dusd).mint(params.owner, type(uint128).max);
        DUSD(input.tokens.dusd).setMinterStatus(params.owner, false);

        // Reward Payment Token
        input.tokens.usdc = address(new ERC20Testnet("USDC", 6, params.owner));
        ERC20Testnet(input.tokens.usdc).mint(params.owner, type(uint256).max);

        // Mint
        input.tokens.weth = address(new ERC20Testnet("WETH", 18, params.owner));
        ERC20Testnet(input.tokens.weth).mint(params.owner, type(uint256).max);

        input.tokens.wsteth = address(new ERC20Testnet("wstETH", 18, params.owner));
        ERC20Testnet(input.tokens.wsteth).mint(params.owner, type(uint256).max);

        input.tokens.reth = address(new ERC20Testnet("rETH", 18, params.owner));
        ERC20Testnet(input.tokens.reth).mint(params.owner, type(uint256).max);

        input.tokens.meth = address(new ERC20Testnet("mETH", 18, params.owner));
        ERC20Testnet(input.tokens.meth).mint(params.owner, type(uint256).max);

        input.tokens.tbtc = address(new ERC20Testnet("tBTC", 18, params.owner));
        ERC20Testnet(input.tokens.tbtc).mint(params.owner, type(uint256).max);

        // Borrow

        input.tokens.wbtc = address(new ERC20Testnet("wBTC", 8, params.owner));
        ERC20Testnet(input.tokens.wbtc).mint(params.owner, type(uint256).max);

        input.tokens.cbbtc = address(new ERC20Testnet("cbBTC", 8, params.owner));
        ERC20Testnet(input.tokens.cbbtc).mint(params.owner, type(uint256).max);

        input.tokens.susde = address(new ERC20Testnet("sUSDe", 18, params.owner));
        ERC20Testnet(input.tokens.susde).mint(params.owner, type(uint256).max);

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
        input.contracts.stakingBatch = (new TestnetStakingBatch(
                TestnetStakingBatchParams({
                    owner: params.owner,
                    rewardToken: address(input.tokens.alto),
                    epochDuration: 3 days,
                    universalRewardsDistributorTimelock: 1 minutes
                })
            ))
        .getStakingContractReport();

        Ownable2Step(input.contracts.stakingBatch.stakingContract).acceptOwnership();
        Ownable2Step(input.contracts.stakingBatch.universalRewardsDistributor).acceptOwnership();
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

        input.contracts.rewardsBatch = (new TestnetRewardsBatch(
                TestnetRewardsBatchParams({
                    owner: params.owner,
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
        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).acceptOwnership();
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
                recipient: params.owner,
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
                recipient: params.owner,
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
                recipient: params.owner,
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
                recipient: params.owner,
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
        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](22);

        address altoMulticall = input.contracts.altoMulticall;

        Ownable(input.contracts.multiTokenSender).transferOwnership(altoMulticall);
        Ownable(input.contracts.mockSwapper).transferOwnership(altoMulticall);
        Ownable2Step(input.contracts.altoLeverage).transferOwnership(altoMulticall);
        calls[0] = AltoMulticallTestnet.Call({
            target: input.contracts.altoLeverage,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        // Mint Markets
        // WETH
        Ownable2Step(input.contracts.wethMarketBatch.market).transferOwnership(altoMulticall);
        calls[1] = AltoMulticallTestnet.Call({
            target: input.contracts.wethMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.wethMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[2] = AltoMulticallTestnet.Call({
            target: input.contracts.wethMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.wethMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // WSTETH
        Ownable2Step(input.contracts.wstethMarketBatch.market).transferOwnership(altoMulticall);
        calls[3] = AltoMulticallTestnet.Call({
            target: input.contracts.wstethMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.wstethMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[4] = AltoMulticallTestnet.Call({
            target: input.contracts.wstethMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.wstethMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // RETH
        Ownable2Step(input.contracts.rethMarketBatch.market).transferOwnership(altoMulticall);
        calls[5] = AltoMulticallTestnet.Call({
            target: input.contracts.rethMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.rethMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[6] = AltoMulticallTestnet.Call({
            target: input.contracts.rethMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.rethMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // METH
        Ownable2Step(input.contracts.methMarketBatch.market).transferOwnership(altoMulticall);
        calls[7] = AltoMulticallTestnet.Call({
            target: input.contracts.methMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.methMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[8] = AltoMulticallTestnet.Call({
            target: input.contracts.methMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.methMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // TBTC
        Ownable2Step(input.contracts.tbtcMarketBatch.market).transferOwnership(altoMulticall);
        calls[9] = AltoMulticallTestnet.Call({
            target: input.contracts.tbtcMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.tbtcMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[10] = AltoMulticallTestnet.Call({
            target: input.contracts.tbtcMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.tbtcMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // Borrow Markets

        // WBTC
        Ownable2Step(input.contracts.wbtcMarketBatch.market).transferOwnership(altoMulticall);
        calls[11] = AltoMulticallTestnet.Call({
            target: input.contracts.wbtcMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.wbtcMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[12] = AltoMulticallTestnet.Call({
            target: input.contracts.wbtcMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.wbtcMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // CBBTC
        Ownable2Step(input.contracts.cbbtcMarketBatch.market).transferOwnership(altoMulticall);
        calls[13] = AltoMulticallTestnet.Call({
            target: input.contracts.cbbtcMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.cbbtcMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[14] = AltoMulticallTestnet.Call({
            target: input.contracts.cbbtcMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.cbbtcMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // SUSDE
        Ownable2Step(input.contracts.susdeMarketBatch.market).transferOwnership(altoMulticall);
        calls[15] = AltoMulticallTestnet.Call({
            target: input.contracts.susdeMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.susdeMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[16] = AltoMulticallTestnet.Call({
            target: input.contracts.susdeMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.susdeMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // Rewards
        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).transferOwnership(altoMulticall);
        calls[17] = AltoMulticallTestnet.Call({
            target: input.contracts.rewardsBatch.rewardsDistributor,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        for (uint256 i = 0; i < input.contracts.rewardsBatch.paymentOracles.length; i++) {
            Ownable(input.contracts.rewardsBatch.paymentOracles[i]).transferOwnership(altoMulticall);
        }
        Ownable(input.contracts.rewardsBatch.rewardOracle).transferOwnership(altoMulticall);

        Ownable2Step(input.contracts.stakingBatch.stakingContract).transferOwnership(altoMulticall);
        calls[18] = AltoMulticallTestnet.Call({
            target: input.contracts.stakingBatch.stakingContract,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        Ownable2Step(input.contracts.stakingBatch.universalRewardsDistributor).transferOwnership(altoMulticall);
        calls[19] = AltoMulticallTestnet.Call({
            target: input.contracts.stakingBatch.universalRewardsDistributor,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        Ownable2Step(input.tokens.alto).transferOwnership(altoMulticall);
        calls[20] = AltoMulticallTestnet.Call({
            target: input.tokens.alto,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.tokens.dusd).transferOwnership(altoMulticall);
        calls[21] = AltoMulticallTestnet.Call({
            target: input.tokens.dusd,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.tokens.usdc).transferOwnership(altoMulticall);
        Ownable(input.tokens.weth).transferOwnership(altoMulticall);
        Ownable(input.tokens.wsteth).transferOwnership(altoMulticall);
        Ownable(input.tokens.tbtc).transferOwnership(altoMulticall);
        // Ownable(input.tokens.sbold).transferOwnership(altoMulticall);
        Ownable(input.tokens.reth).transferOwnership(altoMulticall);
        Ownable(input.tokens.susde).transferOwnership(altoMulticall);

        AltoMulticallTestnet(payable(altoMulticall)).multicall(calls);
    }

    function _calculateMinterCeiling(TestnetMarketBatchReport memory marketBatchReport)
        internal
        view
        returns (uint256)
    {
        IMarket market = IMarket(marketBatchReport.market);

        uint256 debtCeiling = market.totalSupply().assets;

        LiquidationConfiguration memory config = market.liquidationConfiguration();
        uint256 maxLiquidationLtv = config.maxLiquidationLtv;

        return debtCeiling * 1.05 ether / maxLiquidationLtv;
    }
}

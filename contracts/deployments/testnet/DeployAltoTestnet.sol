// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {ERC20Testnet} from "@alto/deployments/testnet/contracts/ERC20Testnet.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {
    TestnetBorrowMarketBatch,
    TestnetBorrowMarketBatchParams
} from "@alto/deployments/testnet/TestnetBorrowMarketBatch.sol";
import {
    TestnetMintMarketBatch, TestnetMintMarketBatchParams
} from "@alto/deployments/testnet/TestnetMintMarketBatch.sol";
import {ITestnetMarketBatch, TestnetMarketBatchReport} from "@alto/deployments/testnet/ITestnetMarketBatch.sol";
import {MultiTokenSender} from "@alto/deployments/testnet/contracts/MultiTokenSender.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {console} from "forge-std/console.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Vm} from "forge-std/Vm.sol";
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
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {
    MULTI_TOKEN_SENDER_MINT_TOKENS,
    BACKEND_TESTNET_ADDRESS,
    ALTO_TOKEN_TOTAL_SUPPLY,
    DUSD_TOKEN_SUPPLY_TO_CONTRACTS
} from "@alto/deployments/testnet/Constants.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {getMulticallOwnerAddresses} from "@alto/deployments/testnet/Constants.sol";

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
    TestnetMarketBatchReport tbtcMarketBatch;
    TestnetMarketBatchReport sboldMarketBatch;
    TestnetMarketBatchReport rethMarketBatch;
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
    // Borrow
    address weth;
    address wsteth;
    address tbtc;
    address sbold;
    address reth;
    // Mint
    address susde;
}

struct AltoTestnetParams {
    address owner;
    bool skipLendingDeployment;
    address lzEndpoint;
    address wrappedNativeToken;
}

library DeployAltoTestnet {
    function deploy(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input = _deployMulticall(params, input);
        input = _deployLending(params, input);
        input = _deployStaking(params, input);
        input = _deployRewards(params, input);

        _transferOwnership(params, input);

        IERC20(input.tokens.dusd).transfer(
            input.contracts.stakingBatch.universalRewardsDistributor, DUSD_TOKEN_SUPPLY_TO_CONTRACTS
        );

        IERC20(input.tokens.alto).transfer(input.contracts.rewardsBatch.rewardsDistributor, ALTO_TOKEN_TOTAL_SUPPLY / 2);

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
        input.contracts.altoAdapter = address(new AltoAdapter(input.contracts.bundler3, params.wrappedNativeToken));

        // deploy multi token sender
        input.contracts.multiTokenSender = address(new MultiTokenSender(params.owner));
        MultiTokenSender(input.contracts.multiTokenSender).updateWhitelist(BACKEND_TESTNET_ADDRESS, true);

        // deploy leverage and mock swapper
        input.contracts.mockSwapper = address(new SwapperSimpleMock(params.owner));
        input.contracts.altoLeverage = address(new AltoLeverage(input.contracts.mockSwapper, params.owner));
        SwapperSimpleMock(payable(input.contracts.mockSwapper)).setWhitelisted(
            address(input.contracts.altoLeverage), true
        );

        // deploy and mint tokens to the owner
        input = _deployMintFundTokens(params, input);

        input.contracts.wethMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.weth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4100 * ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wethMarketBatch.market, true);
        IMarket(input.contracts.wethMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        input.contracts.wstethMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.wsteth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 5000 * ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.wstethMarketBatch.market, true);
        IMarket(input.contracts.wstethMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        input.contracts.tbtcMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.tbtc),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 112000 * ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.tbtcMarketBatch.market, true);
        IMarket(input.contracts.tbtcMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        input.contracts.sboldMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.sbold),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 1.05 ether * ORACLE_PRICE_PRECISION / 1 ether,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.sboldMarketBatch.market, true);
        IMarket(input.contracts.sboldMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        input.contracts.rethMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.reth),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 4700 * ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.rethMarketBatch.market, true);
        IMarket(input.contracts.rethMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        // Mint Markets
        input.contracts.susdeMarketBatch = (
            new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.susde),
                    borrowToken: address(input.tokens.dusd),
                    marketOraclePrice: 1.2 ether * ORACLE_PRICE_PRECISION / 1 ether,
                    maxLtv: 0.75 ether,
                    debtCeiling: 3_000_000 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.susdeMarketBatch.market, true);
        IMarket(input.contracts.susdeMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        DUSD(input.tokens.dusd).setMinterStatus(input.contracts.susdeMarketBatch.market, true);
        DUSD(input.tokens.dusd).setBurnerStatus(input.contracts.susdeMarketBatch.market, true);

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
        // we can't mint uint256 max as markets need to be able to mint during borrow/repay
        DUSD(input.tokens.dusd).mint(params.owner, type(uint128).max);
        DUSD(input.tokens.dusd).setMinterStatus(params.owner, false);

        // Reward Payment Token
        input.tokens.usdc = address(new ERC20Testnet("USDC", 6, params.owner));
        ERC20Testnet(input.tokens.usdc).mint(params.owner, type(uint256).max);

        // Borrow
        input.tokens.weth = address(new ERC20Testnet("WETH", 18, params.owner));
        ERC20Testnet(input.tokens.weth).mint(params.owner, type(uint256).max);

        input.tokens.wsteth = address(new ERC20Testnet("wstETH", 18, params.owner));
        ERC20Testnet(input.tokens.wsteth).mint(params.owner, type(uint256).max);

        input.tokens.tbtc = address(new ERC20Testnet("tBTC", 18, params.owner));
        ERC20Testnet(input.tokens.tbtc).mint(params.owner, type(uint256).max);

        input.tokens.sbold = address(new ERC20Testnet("sBOLD", 18, params.owner));
        ERC20Testnet(input.tokens.sbold).mint(params.owner, type(uint256).max);

        input.tokens.reth = address(new ERC20Testnet("rETH", 18, params.owner));
        ERC20Testnet(input.tokens.reth).mint(params.owner, type(uint256).max);

        // Mint
        input.tokens.susde = address(new ERC20Testnet("sUSDe", 18, params.owner));
        ERC20Testnet(input.tokens.susde).mint(params.owner, type(uint256).max);

        // fund tokens to the multi token sender
        IERC20(input.tokens.dusd).transfer(input.contracts.multiTokenSender, DUSD_TOKEN_SUPPLY_TO_CONTRACTS);
        IERC20(input.tokens.alto).transfer(input.contracts.multiTokenSender, ALTO_TOKEN_TOTAL_SUPPLY / 4);

        IERC20(input.tokens.weth).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.usdc).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.wsteth).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.tbtc).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.sbold).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.reth).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.susde).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);

        // fund tokens to swapper
        IERC20(input.tokens.dusd).transfer(input.contracts.mockSwapper, DUSD_TOKEN_SUPPLY_TO_CONTRACTS);

        IERC20(input.tokens.usdc).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.weth).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.wsteth).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.tbtc).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.sbold).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.reth).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.susde).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);

        return input;
    }

    function _deployStaking(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input.contracts.stakingBatch = (
            new TestnetStakingBatch(
                TestnetStakingBatchParams({
                    owner: params.owner,
                    rewardToken: address(input.tokens.alto),
                    epochDuration: 3 days,
                    universalRewardsDistributorTimelock: 1 minutes
                })
            )
        ).getStakingContractReport();

        Ownable2Step(input.contracts.stakingBatch.stakingContract).acceptOwnership();
        Ownable2Step(input.contracts.stakingBatch.universalRewardsDistributor).acceptOwnership();

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

        input.contracts.rewardsBatch = (
            new TestnetRewardsBatch(
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
            )
        ).getRewardsDistributorReport();
        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).acceptOwnership();

        return input;
    }

    function _transferOwnership(AltoTestnetParams memory params, AltoTestnetInput memory input) internal {
        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](18);

        address altoMulticall = input.contracts.altoMulticall;

        Ownable(input.contracts.multiTokenSender).transferOwnership(altoMulticall);
        Ownable(input.contracts.mockSwapper).transferOwnership(altoMulticall);
        Ownable2Step(input.contracts.altoLeverage).transferOwnership(altoMulticall);
        calls[0] = AltoMulticallTestnet.Call({
            target: input.contracts.altoLeverage,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        // Borrow Markets
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

        // TBTC
        Ownable2Step(input.contracts.tbtcMarketBatch.market).transferOwnership(altoMulticall);
        calls[5] = AltoMulticallTestnet.Call({
            target: input.contracts.tbtcMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.tbtcMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[6] = AltoMulticallTestnet.Call({
            target: input.contracts.tbtcMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.tbtcMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // sBOLD
        Ownable2Step(input.contracts.sboldMarketBatch.market).transferOwnership(altoMulticall);
        calls[7] = AltoMulticallTestnet.Call({
            target: input.contracts.sboldMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.sboldMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[8] = AltoMulticallTestnet.Call({
            target: input.contracts.sboldMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.sboldMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // rETH
        Ownable2Step(input.contracts.rethMarketBatch.market).transferOwnership(altoMulticall);
        calls[9] = AltoMulticallTestnet.Call({
            target: input.contracts.rethMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.rethMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[10] = AltoMulticallTestnet.Call({
            target: input.contracts.rethMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.rethMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // Mint Markets
        // sUSDe
        Ownable2Step(input.contracts.susdeMarketBatch.market).transferOwnership(altoMulticall);
        calls[11] = AltoMulticallTestnet.Call({
            target: input.contracts.susdeMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.susdeMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[12] = AltoMulticallTestnet.Call({
            target: input.contracts.susdeMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.susdeMarketBatch.marketOracle).transferOwnership(altoMulticall);

        // Rewards
        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).transferOwnership(altoMulticall);
        calls[13] = AltoMulticallTestnet.Call({
            target: input.contracts.rewardsBatch.rewardsDistributor,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        for (uint256 i = 0; i < input.contracts.rewardsBatch.paymentOracles.length; i++) {
            Ownable(input.contracts.rewardsBatch.paymentOracles[i]).transferOwnership(altoMulticall);
        }
        Ownable(input.contracts.rewardsBatch.rewardOracle).transferOwnership(altoMulticall);

        Ownable2Step(input.contracts.stakingBatch.stakingContract).transferOwnership(altoMulticall);
        calls[14] = AltoMulticallTestnet.Call({
            target: input.contracts.stakingBatch.stakingContract,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        Ownable2Step(input.contracts.stakingBatch.universalRewardsDistributor).transferOwnership(altoMulticall);
        calls[15] = AltoMulticallTestnet.Call({
            target: input.contracts.stakingBatch.universalRewardsDistributor,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        Ownable2Step(input.tokens.alto).transferOwnership(altoMulticall);
        calls[16] = AltoMulticallTestnet.Call({
            target: input.tokens.alto,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.tokens.dusd).transferOwnership(altoMulticall);
        calls[17] = AltoMulticallTestnet.Call({
            target: input.tokens.dusd,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.tokens.usdc).transferOwnership(altoMulticall);
        Ownable(input.tokens.weth).transferOwnership(altoMulticall);
        Ownable(input.tokens.wsteth).transferOwnership(altoMulticall);
        Ownable(input.tokens.tbtc).transferOwnership(altoMulticall);
        Ownable(input.tokens.sbold).transferOwnership(altoMulticall);
        Ownable(input.tokens.reth).transferOwnership(altoMulticall);
        Ownable(input.tokens.susde).transferOwnership(altoMulticall);

        AltoMulticallTestnet(payable(altoMulticall)).multicall(calls);
    }
}

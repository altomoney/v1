// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {ERC20Testnet} from "@alto/deployments/testnet/contracts/ERC20Testnet.sol";
import {USDO} from "@alto/tokens/USDO.sol";
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
    USDO_TOKEN_SUPPLY_TO_CONTRACTS
} from "@alto/deployments/testnet/Constants.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {IUniversalRewardsDistributorBase} from
    "@morpho-org/universal-rewards-distributor/interfaces/IUniversalRewardsDistributor.sol";

struct AltoTestnetInput {
    TestnetTokens tokens;
    Contracts contracts;
}

struct Contracts {
    address multiTokenSender;
    address mockSwapper;
    address altoLeverage;
    address bundler3;
    address altoAdapter;
    TestnetMarketBatchReport borrowMarketBatch;
    TestnetMarketBatchReport mintMarketBatch;
    TestnetStakingBatchReport stakingBatch;
    TestnetRewardsBatchReport rewardsBatch;
}

struct TestnetTokens {
    address alto;
    address usdo;
    address usdc;
    address weth;
}

struct AltoTestnetParams {
    address owner;
    bool skipLendingDeployment;
    address lzEndpoint;
    address wrappedNativeToken;
    address universalRewardsDistributor;
    address altoMulticall;
}

library DeployAltoTestnet {
    function deploy(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input = _deployLending(params, input);
        input = _deployStaking(params, input);
        input = _deployRewards(params, input);

        _transferOwnership(params, input);

        if (input.contracts.stakingBatch.universalRewardsDistributor != address(0)) {
            IERC20(input.tokens.usdo).transfer(
                input.contracts.stakingBatch.universalRewardsDistributor, USDO_TOKEN_SUPPLY_TO_CONTRACTS
            );
        }

        IERC20(input.tokens.alto).transfer(input.contracts.rewardsBatch.rewardsDistributor, ALTO_TOKEN_TOTAL_SUPPLY / 2);

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

        input.contracts.borrowMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.usdc),
                    borrowToken: address(input.tokens.usdo),
                    marketOraclePrice: 1e48,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.borrowMarketBatch.market, true);
        IMarket(input.contracts.borrowMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        input.contracts.mintMarketBatch = (
            new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: params.owner,
                    collateralToken: address(input.tokens.weth),
                    borrowToken: address(input.tokens.usdo),
                    marketOraclePrice: 4000 * ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 3_000_000 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.mintMarketBatch.market, true);
        IMarket(input.contracts.mintMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        USDO(input.tokens.usdo).setMinterStatus(input.contracts.mintMarketBatch.market, true);
        USDO(input.tokens.usdo).setBurnerStatus(input.contracts.mintMarketBatch.market, true);

        return input;
    }

    function _deployMintFundTokens(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input.tokens.alto = address(new AltoToken(params.lzEndpoint, params.owner));
        // all ALTO is already minted to the owner in the constructor
        input.tokens.usdo = address(new USDO(params.lzEndpoint, params.owner));
        USDO(input.tokens.usdo).setMinterStatus(params.owner, true);
        // we can't mint uint256 max as markets need to be able to mint during borrow/repay
        USDO(input.tokens.usdo).mint(params.owner, type(uint128).max);
        USDO(input.tokens.usdo).setMinterStatus(params.owner, false);

        input.tokens.weth = address(new ERC20Testnet("WETH", 18, params.owner));
        ERC20Testnet(input.tokens.weth).mint(params.owner, type(uint256).max);
        input.tokens.usdc = address(new ERC20Testnet("USDC", 6, params.owner));
        ERC20Testnet(input.tokens.usdc).mint(params.owner, type(uint256).max);

        // fund tokens to the multi token sender
        IERC20(input.tokens.usdo).transfer(input.contracts.multiTokenSender, USDO_TOKEN_SUPPLY_TO_CONTRACTS);
        IERC20(input.tokens.alto).transfer(input.contracts.multiTokenSender, ALTO_TOKEN_TOTAL_SUPPLY / 4);

        IERC20(input.tokens.weth).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.usdc).transfer(input.contracts.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);

        // fund tokens to swapper
        IERC20(input.tokens.usdo).transfer(input.contracts.mockSwapper, USDO_TOKEN_SUPPLY_TO_CONTRACTS);

        IERC20(input.tokens.weth).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.usdc).transfer(input.contracts.mockSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);

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
                    epochDuration: 1 days,
                    universalRewardsDistributorTimelock: 1 days
                })
            )
        ).getStakingContractReport();
        input.contracts.stakingBatch.universalRewardsDistributor = params.universalRewardsDistributor;
        Ownable2Step(input.contracts.stakingBatch.stakingContract).acceptOwnership();

        return input;
    }

    function _deployRewards(AltoTestnetParams memory params, AltoTestnetInput memory input)
        internal
        returns (AltoTestnetInput memory)
    {
        input.contracts.rewardsBatch = (
            new TestnetRewardsBatch(
                TestnetRewardsBatchParams({
                    owner: params.owner,
                    rewardToken: address(input.tokens.alto),
                    merkleRootTimelock: 1 days,
                    paymentToken: address(input.tokens.usdc),
                    paymentUsdOraclePrice: 1 * USD_ORACLE_PRICE_PRECISION,
                    rewardTokenUsdOraclePrice: 1.2 ether * ORACLE_PRICE_PRECISION / 1 ether,
                    lockBonusDiscount: 0.15 ether,
                    stakingContract: input.contracts.stakingBatch.stakingContract
                })
            )
        ).getRewardsDistributorReport();
        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).acceptOwnership();

        return input;
    }

    function _transferOwnership(AltoTestnetParams memory params, AltoTestnetInput memory input) internal {
        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](9);

        address altoMulticall = params.altoMulticall;

        Ownable(input.contracts.multiTokenSender).transferOwnership(altoMulticall);
        Ownable(input.contracts.mockSwapper).transferOwnership(altoMulticall);
        Ownable2Step(input.contracts.altoLeverage).transferOwnership(altoMulticall);
        calls[0] = AltoMulticallTestnet.Call({
            target: input.contracts.altoLeverage,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });

        Ownable2Step(input.contracts.borrowMarketBatch.market).transferOwnership(altoMulticall);
        calls[1] = AltoMulticallTestnet.Call({
            target: input.contracts.borrowMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.borrowMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[2] = AltoMulticallTestnet.Call({
            target: input.contracts.borrowMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.borrowMarketBatch.marketOracle).transferOwnership(altoMulticall);

        Ownable2Step(input.contracts.mintMarketBatch.market).transferOwnership(altoMulticall);
        calls[3] = AltoMulticallTestnet.Call({
            target: input.contracts.mintMarketBatch.market,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.contracts.mintMarketBatch.marketIrm).transferOwnership(altoMulticall);
        calls[4] = AltoMulticallTestnet.Call({
            target: input.contracts.mintMarketBatch.marketIrm,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.mintMarketBatch.marketOracle).transferOwnership(altoMulticall);

        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).transferOwnership(altoMulticall);
        calls[5] = AltoMulticallTestnet.Call({
            target: input.contracts.rewardsBatch.rewardsDistributor,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.contracts.rewardsBatch.paymentOracle).transferOwnership(altoMulticall);
        Ownable(input.contracts.rewardsBatch.rewardOracle).transferOwnership(altoMulticall);

        Ownable2Step(input.contracts.stakingBatch.stakingContract).transferOwnership(altoMulticall);
        calls[6] = AltoMulticallTestnet.Call({
            target: input.contracts.stakingBatch.stakingContract,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        if (input.contracts.stakingBatch.universalRewardsDistributor != address(0)) {
            IUniversalRewardsDistributorBase(input.contracts.stakingBatch.universalRewardsDistributor).setOwner(
                altoMulticall
            );
        }

        Ownable2Step(input.tokens.alto).transferOwnership(altoMulticall);
        calls[7] = AltoMulticallTestnet.Call({
            target: input.tokens.alto,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable2Step(input.tokens.usdo).transferOwnership(altoMulticall);
        calls[8] = AltoMulticallTestnet.Call({
            target: input.tokens.usdo,
            callData: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            allowFailure: false
        });
        Ownable(input.tokens.usdc).transferOwnership(altoMulticall);
        Ownable(input.tokens.weth).transferOwnership(altoMulticall);

        AltoMulticallTestnet(payable(altoMulticall)).multicall(calls);
    }
}

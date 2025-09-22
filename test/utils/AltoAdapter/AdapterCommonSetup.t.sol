// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {IMarket, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {MarketInstance} from "./MarketInstance.sol";
import {RewardsDistributorInstance} from "./RewardsDistributorInstance.sol";
import {StakingInstance} from "./StakingInstance.sol";
import {IRewardsDistributor} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IAltoStaking, Container} from "@alto/staking/interfaces/IAltoStaking.sol";
import {MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

import {AdapterCommon} from "./AdapterCommon.t.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {IUniversalRewardsDistributor} from "@alto/utils/interfaces/IUniversalRewardsDistributor.sol";

import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {FlashBorrowLeverageData} from "@alto/lending/leverage/AltoLeverage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UniversalRewardsDistributorInstance} from "./UniversalRewardsDistributorInstance.sol";

import "forge-std/Test.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract AdapterCommonSetup is AdapterCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    //using stdStorage for StdStorage;

    ERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;

    IMarket internal market;
    SwapperSimpleMock swapper;
    AltoLeverage leverage;

    uint256 internal constant LTV = 0.75 ether;

    IRewardsDistributor internal rewardsDistributor;
    ERC20Mock internal rewardToken;
    ERC20Mock internal paymentToken;

    IAltoStaking internal stakingContract;
    IUniversalRewardsDistributor internal universalRewardsDistributor;

    // Constants for reward testing
    uint256 public constant USER_AVAILABLE = 1000 ether;
    uint256 public constant BASE_DISCOUNT = 0.25 ether; // 25%
    uint256 public constant LOCK_DISCOUNT = 0.15 ether; // 15%

    function setUp() public virtual override {
        super.setUp();

        borrowToken = new ERC20Mock("borrow", "B");
        vm.label(address(borrowToken), "borrowToken");
        collateralToken = new ERC20Mock("collateral", "C");
        vm.label(address(collateralToken), "collateralToken");

        rewardToken = new ERC20Mock("reward", "R");
        vm.label(address(rewardToken), "rewardToken");
        paymentToken = new ERC20Mock("payment", "P");
        vm.label(address(paymentToken), "paymentToken");

        vm.startPrank(OWNER);

        _setupStakingContract();
        _setupRewardsDistributor();
        _setupUniversalRewardsDistributor();

        swapper = new SwapperSimpleMock(address(OWNER));
        leverage = new AltoLeverage(address(swapper), address(OWNER));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));

        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            market = IMarket(
                Upgrades.deployUUPSProxy(
                    "MarketInstance.sol",
                    abi.encodeCall(
                        MarketInstance.initialize,
                        (
                            address(borrowToken),
                            address(collateralToken),
                            address(irm),
                            address(OWNER),
                            address(oracle),
                            LTV,
                            0,
                            address(this),
                            LiquidationConfiguration({
                                maxLiquidationLtv: 0.8 ether,
                                dynamicBonusFeeStart: 0.03 ether,
                                ltvForCompleteLiquidation: 0.9 ether,
                                dynamicBonusFeeDecaySteepness: 5 ether,
                                liquidationBaseFee: 0.05 ether,
                                minPenaltyPercentage: 0.01 ether,
                                protocolFeePercentage: 0.075 ether,
                                isEnabledPriorityLiquidation: true,
                                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                                priorityLiquidationGracePeriod: 5 minutes,
                                taggerLiquidationGracePeriod: 2 minutes,
                                liquidationWindowTag: 3 days
                            })
                        )
                    )
                )
            );
        } else {
            market = IMarket(
                UnsafeUpgrades.deployUUPSProxy(
                    address(new MarketInstance()),
                    abi.encodeCall(
                        MarketInstance.initialize,
                        (
                            address(borrowToken),
                            address(collateralToken),
                            address(irm),
                            address(OWNER),
                            address(oracle),
                            LTV,
                            0,
                            address(this),
                            LiquidationConfiguration({
                                maxLiquidationLtv: 0.8 ether,
                                dynamicBonusFeeStart: 0.03 ether,
                                ltvForCompleteLiquidation: 0.9 ether,
                                dynamicBonusFeeDecaySteepness: 5 ether,
                                liquidationBaseFee: 0.05 ether,
                                minPenaltyPercentage: 0.01 ether,
                                protocolFeePercentage: 0.075 ether,
                                isEnabledPriorityLiquidation: true,
                                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                                priorityLiquidationGracePeriod: 5 minutes,
                                taggerLiquidationGracePeriod: 2 minutes,
                                liquidationWindowTag: 3 days
                            })
                        )
                    )
                )
            );
        }

        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);
        swapper.setWhitelisted(address(leverage), true);
        market.setAuthorizedCallback(address(leverage), true);
        leverage.setMarket(address(market), true);

        vm.stopPrank();

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.startPrank(SUPPLIER);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.setAuthorization(address(this), true);

        vm.stopPrank();

        vm.prank(USER);
        // So tests can borrow/withdraw on behalf of USER without pranking it.
        market.setAuthorization(address(this), true);
    }

    function _setupStakingContract() internal {
        Container[] memory containers = new Container[](2);
        containers[0] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 2}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 2, max: 12}),
            maxRateDifferenceEpochs: 10,
            currentDurationEpochs: 0,
            isActive: false
        });
        containers[1] = Container({
            growthRate: MinMaxEpochs({min: 1, max: 2}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 1, max: 8}),
            maxRateDifferenceEpochs: 4,
            currentDurationEpochs: 0,
            isActive: false
        });

        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 0.6 ether;
        multipliers[1] = 0.3 ether;

        stakingContract = IAltoStaking(
            address(new StakingInstance(address(rewardToken), address(OWNER), 1 days, containers, multipliers))
        );

        stakingContract.activateContainer(1);
        stakingContract.activateContainer(2);
        stakingContract.startEpoch();

        // tokens are already dealt in _setupRewardsDistributor
    }

    function _setupRewardsDistributor() internal {
        rewardsDistributor =
            IRewardsDistributor(address(new RewardsDistributorInstance(address(OWNER), 1 days, address(rewardToken))));

        // Setup payment token oracle
        AltoRewardsDistributor(address(rewardsDistributor)).setPaymentToken(address(paymentToken), address(oracle));

        // Setup reward token USD oracle
        AltoRewardsDistributor(address(rewardsDistributor)).setRewardTokenUsdOracle(address(oracle));

        // Setup lock bonus discount
        AltoRewardsDistributor(address(rewardsDistributor)).setLockBonusDiscount(LOCK_DISCOUNT);
        AltoRewardsDistributor(address(rewardsDistributor)).setLockContract(address(stakingContract));

        // Setup a dummy merkle root (will be replaced by individual tests)
        bytes32 dummyRoot = keccak256("dummy_root");
        AltoRewardsDistributor(address(rewardsDistributor)).submitNewPendingRoot(dummyRoot, bytes32(0));
        AltoRewardsDistributor(address(rewardsDistributor)).acceptPendingRoot(dummyRoot);

        // Fund distributor with reward tokens
        deal(address(rewardToken), address(rewardsDistributor), 10000 ether);
    }

    function _setupUniversalRewardsDistributor() internal {
        universalRewardsDistributor =
            IUniversalRewardsDistributor(address(new UniversalRewardsDistributorInstance(address(OWNER), 1 days)));

        // Setup distributor
        bytes32 dummyRoot = keccak256("dummy_root");

        UniversalRewardsDistributorInstance(address(universalRewardsDistributor)).submitNewPendingRoot(
            dummyRoot, bytes32(0)
        );
        UniversalRewardsDistributorInstance(address(universalRewardsDistributor)).acceptPendingRoot(dummyRoot);
    }

    function _marketPrepareLeverageData(uint256 minAmountOut, bytes memory swapData)
        internal
        view
        returns (bytes memory)
    {
        // Prepare FlashBorrowLeverageData
        FlashBorrowLeverageData memory leverageData =
            FlashBorrowLeverageData({minAmountOut: minAmountOut, swapData: swapData});
        return abi.encode(leverageData);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IMarket, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
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
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AltoLiquidationEngine} from "@alto/lending/AltoLiquidationEngine.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {UniversalRewardsDistributorInstance} from "./UniversalRewardsDistributorInstance.sol";
import {VestingInstance} from "./VestingInstance.sol";
import {DUSDUsmInstance} from "./DUSDUsmInstance.sol";
import {IAltoVesting} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract AdapterCommonSetup is AdapterCommon, TestHelperOz5 {
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
    IAltoVesting internal vestingContract;
    IUsm internal usmContract;
    DUSD internal dusdToken;
    ERC20MockMintableDecimals internal underlyingToken;

    // Constants for reward testing
    uint256 public constant USER_AVAILABLE = 1000 ether;
    uint256 public constant BASE_DISCOUNT = 0.25 ether; // 25%
    uint256 public constant LOCK_DISCOUNT = 0.15 ether; // 15%

    // Constants for vesting testing
    uint256 public constant VESTING_DURATION = 1000;

    function setUp() public virtual override(AdapterCommon, TestHelperOz5) {
        AdapterCommon.setUp();
        TestHelperOz5.setUp();

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
        _setupVestingContract();

        swapper = new SwapperSimpleMock(address(OWNER));
        leverage = new AltoLeverage(address(swapper), address(OWNER));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));

        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
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
        });

        // Create liquidation engine before market deployment
        address liquidationEngine = address(new AltoLiquidationEngine(address(OWNER)));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: address(OWNER),
            oracle: address(oracle),
            maxLtv: LTV,
            feeRecipient: address(this),
            liquidationEngine: liquidationEngine
        });

        if (shouldUseSafeProxy) {
            market = IMarket(
                Upgrades.deployUUPSProxy(
                    "MarketInstance.sol", abi.encodeCall(MarketInstance.initialize, (baseMarketInitParams, 0))
                )
            );
        } else {
            market = IMarket(
                UnsafeUpgrades.deployUUPSProxy(
                    address(new MarketInstance()), abi.encodeCall(MarketInstance.initialize, (baseMarketInitParams, 0))
                )
            );
        }

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        AltoLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

        // Approve conract to be used in the adapter
        altoAdapter.approveContract(address(market));

        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);
        swapper.setWhitelisted(address(leverage), true);
        market.setAuthorizedCallback(address(leverage), true);
        leverage.setMarket(address(market), true);

        vm.stopPrank();

        // Setup USM contract (needs to be after stopping prank)
        _setupUsmContract();

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

        // Approve conract to be used in the adapter
        altoAdapter.approveContract(address(stakingContract));

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

        // Approve conract to be used in the adapter
        altoAdapter.approveContract(address(rewardsDistributor));

        // Fund distributor with reward tokens
        deal(address(rewardToken), address(rewardsDistributor), 10000 ether);
    }

    function _setupUniversalRewardsDistributor() internal {
        universalRewardsDistributor =
            IUniversalRewardsDistributor(address(new UniversalRewardsDistributorInstance(address(OWNER), 1 days)));

        // Setup distributor
        bytes32 dummyRoot = keccak256("dummy_root");

        UniversalRewardsDistributorInstance(address(universalRewardsDistributor))
            .submitNewPendingRoot(dummyRoot, bytes32(0));
        UniversalRewardsDistributorInstance(address(universalRewardsDistributor)).acceptPendingRoot(dummyRoot);

        // Approve conract to be used in the adapter
        altoAdapter.approveContract(address(universalRewardsDistributor));
    }

    function _setupVestingContract() internal {
        bytes32 dummyRoot = keccak256("dummy_root");

        vestingContract = IAltoVesting(
            address(new VestingInstance(address(OWNER), 1 days, true, address(rewardToken), dummyRoot, bytes32(0)))
        );

        VestingInstance(address(vestingContract)).acceptPendingRoot(dummyRoot);

        // Approve conract to be used in the adapter
        altoAdapter.approveContract(address(vestingContract));
    }

    function _setupUsmContract() internal {
        // Setup LayerZero endpoints for DUSD
        setUpEndpoints(1, LibraryType.UltraLightNode);

        vm.startPrank(address(OWNER));

        // Create DUSD token
        dusdToken = new DUSD(address(endpoints[1]), address(OWNER));
        underlyingToken = new ERC20MockMintableDecimals("Underlying", "UND", 6);

        // Create price and fee strategies
        FixedPriceStrategy priceStrategy = new FixedPriceStrategy(1e18, address(underlyingToken), address(OWNER));
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(0, 100, address(OWNER)); // 1% sell fee

        // Deploy DUSDUsm instance
        DUSDUsmInstance usmInstance = new DUSDUsmInstance(address(dusdToken), address(underlyingToken));

        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            usmContract = IUsm(
                Upgrades.deployUUPSProxy(
                    "DUSDUsmInstance.sol",
                    abi.encodeCall(
                        DUSDUsm.initialize,
                        (address(OWNER), address(OWNER), uint128(100_000_000e6), address(priceStrategy))
                    )
                )
            );
        } else {
            usmContract = IUsm(
                UnsafeUpgrades.deployUUPSProxy(
                    address(usmInstance),
                    abi.encodeCall(
                        DUSDUsm.initialize,
                        (address(OWNER), address(OWNER), uint128(100_000_000e6), address(priceStrategy))
                    )
                )
            );
        }

        // Update fee strategy
        usmContract.updateFeeStrategy(address(feeStrategy));

        // Setup DUSD token permissions
        dusdToken.setMinterStatus(address(usmContract), true);
        dusdToken.setMinterCeiling(address(usmContract), 100_000_000e18);
        dusdToken.setBurnerStatus(address(usmContract), true);

        vm.stopPrank();

        // Approve contract to be used in the adapter (OWNER is the owner of altoAdapter)
        vm.prank(address(OWNER));
        altoAdapter.approveContract(address(usmContract));
    }

    function _marketPrepareLeverageData(uint256 minAmountOut, bytes memory swapData)
        internal
        view
        returns (bytes memory)
    {
        // Prepare SwapParams
        SwapParams memory leverageData = SwapParams({minAmountOut: minAmountOut, swapData: swapData});
        return abi.encode(leverageData);
    }
}

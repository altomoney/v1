// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {
    FeeSourceType,
    IProtocolFeeCollectorEvents,
    ProtocolFeeCollectorInitParams
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IMarket, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

/// @dev End-to-end mainnet-fork coverage for the live Alto fee sources feeding freshly deployed
/// ProtocolFeeCollector and SDUSD proxies, using fees already present at the pinned block and liquidation fees
/// generated after the collector becomes the markets' fee recipient.
contract ProtocolFeeCollectorSDUSDForkTest is Test {
    using SafeERC20 for IERC20;

    uint256 internal constant SEED_ASSETS = 1 ether;
    uint256 internal constant USER_DEPOSIT = 10_000 ether;
    uint256 internal constant REWARD_DURATION = 7 days;
    uint256 internal constant REWARDS_BPS = 3_000;
    uint256 internal constant BORROW_MARKET_INTEREST_FEE = 0.1 ether;
    uint128 internal constant FLASH_LOAN_FEE_RATE = 0.01 ether;

    address internal constant DUSD_MAINNET = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant MARKET_REGISTRY_MAINNET = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;
    address internal constant USM_REGISTRY_MAINNET = 0xAD5620e10C33918E2C6A2E8E53325bf98c548E5e;
    address internal constant ADVANCED_PERMISSIONS_FRXUSD_USM_MAINNET = 0xEb7518311543fB6152f31F3C5075CFcB835c95c7;
    address internal constant FLASH_MINTER_MAINNET = 0x8b7448877E292b8422608d1dCbf066E484461948;
    address internal constant SEED_RECEIVER = address(1);

    address internal ADMIN = makeAddr("Admin");
    address internal PAUSER = makeAddr("Pauser");
    address internal COLLATERAL_OPERATOR = makeAddr("CollateralOperator");
    address internal TREASURY = makeAddr("Treasury");
    address internal USER_ONE = makeAddr("UserOne");
    address internal USER_TWO = makeAddr("UserTwo");
    address internal USER_THREE = makeAddr("UserThree");
    address internal USER_FOUR = makeAddr("UserFour");
    address internal HARVEST_CALLER = makeAddr("HarvestCaller");
    address internal DISTRIBUTION_CALLER = makeAddr("DistributionCaller");
    address internal LIQUIDATION_BORROWER = makeAddr("LiquidationBorrower");
    address internal LIQUIDATOR = makeAddr("Liquidator");

    IDUSD internal dusd;
    IMarketRegistry internal marketRegistry;
    IUsm internal advancedPermissionsFrxusdUsm;
    DUSDFlashMinter internal flashMinter;

    ProtocolFeeCollector internal collector;
    SDUSD internal sdusd;

    address[] internal borrowMarkets;
    address[] internal mintMarkets;
    address[] internal allMarkets;
    address[] internal liquidationFeeMarkets;
    uint256[] internal liquidationFeeAmounts;
    uint256[] internal marketOraclePrices;
    uint256[] internal treasuryCollateralBalancesBefore;

    uint256 internal initialUserShares;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 25688451);

        dusd = IDUSD(DUSD_MAINNET);
        marketRegistry = IMarketRegistry(MARKET_REGISTRY_MAINNET);
        advancedPermissionsFrxusdUsm = IUsm(ADVANCED_PERMISSIONS_FRXUSD_USM_MAINNET);
        flashMinter = DUSDFlashMinter(FLASH_MINTER_MAINNET);

        borrowMarkets = marketRegistry.getBorrowMarkets();
        mintMarkets = marketRegistry.getMintMarkets();
        assertEq(borrowMarkets.length, 5, "unexpected borrow-market count");
        assertEq(mintMarkets.length, 7, "unexpected mint-market count");
        _cacheAllMarkets();

        _configureTestDusdMinter();
        _deployCollectorAndVault();
        _seedVaultAndCreateInitialPositions();
        _configureAllFeeRecipients();
        _createAndCacheLiquidationFeeCollateral();
        _assertDeploymentConfiguration();
    }

    function testFork_HarvestDistributeAndReleaseRewardsLinearly() public {
        uint256 harvested = _harvestEveryFeeSource();
        uint256 liquidationFeeValue = _withdrawLiquidationFeesAndReturnDusd();

        uint256 collected = IERC20(DUSD_MAINNET).balanceOf(address(collector));
        assertEq(collected, harvested + liquidationFeeValue, "collector balance does not conserve harvested fees");
        assertGt(collected, 0, "nothing collected");

        uint256 expectedReward = Math.mulDiv(collected, REWARDS_BPS, collector.PERCENTAGE_PRECISION());
        uint256 expectedTreasury = collected - expectedReward;
        uint256 vaultAccountedBefore = sdusd.accountedAssets();
        uint256 vaultTotalAssetsBefore = sdusd.totalAssets();
        uint256 vaultSupplyBefore = sdusd.totalSupply();
        uint256 vaultDusdBefore = IERC20(DUSD_MAINNET).balanceOf(address(sdusd));
        uint256 treasuryDusdBefore = IERC20(DUSD_MAINNET).balanceOf(TREASURY);
        uint256 periodStart = block.timestamp;

        vm.prank(DISTRIBUTION_CALLER);
        collector.distribute();

        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(collector)), 0, "collector retains DUSD");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(TREASURY), treasuryDusdBefore + expectedTreasury);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(sdusd)), vaultDusdBefore + expectedReward);
        assertEq(IERC20(DUSD_MAINNET).allowance(address(collector), address(sdusd)), 0);
        assertEq(sdusd.accountedAssets(), vaultAccountedBefore + expectedReward);
        assertEq(sdusd.rewardsForPeriod(), expectedReward);
        assertEq(sdusd.periodStart(), periodStart);
        assertEq(sdusd.rewardPeriodFinish(), periodStart + REWARD_DURATION);
        assertEq(sdusd.rewardDuration(), REWARD_DURATION);
        assertEq(sdusd.lockedRewardsRemaining(), expectedReward);
        assertEq(sdusd.totalAssets(), vaultTotalAssetsBefore, "exchange rate spiked at notification");
        assertEq(sdusd.totalSupply(), vaultSupplyBefore, "notification minted shares");

        // Rewards are fully locked at the start, so a third equal deposit receives exactly the same shares.
        uint256 userThreeShares = _depositFor(USER_THREE, USER_DEPOSIT);
        assertEq(userThreeShares, initialUserShares);
        assertEq(sdusd.totalAssets(), vaultTotalAssetsBefore + USER_DEPOSIT);
        assertEq(sdusd.accountedAssets(), vaultAccountedBefore + expectedReward + USER_DEPOSIT);

        // At the midpoint, half the reward is unlocked. The same deposit must now mint fewer shares.
        vm.warp(periodStart + REWARD_DURATION / 2);
        uint256 expectedUnlocked = Math.mulDiv(expectedReward, REWARD_DURATION / 2, REWARD_DURATION);
        uint256 totalAssetsAtMidpoint = vaultTotalAssetsBefore + USER_DEPOSIT + expectedUnlocked;

        assertEq(sdusd.lockedRewardsRemaining(), expectedReward - expectedUnlocked);
        assertEq(sdusd.totalAssets(), totalAssetsAtMidpoint);
        assertEq(sdusd.periodStart(), periodStart);
        assertEq(sdusd.rewardPeriodFinish(), periodStart + REWARD_DURATION);

        uint256 expectedUserFourShares = sdusd.previewDeposit(USER_DEPOSIT);
        assertLt(expectedUserFourShares, initialUserShares, "unlocked rewards did not increase share value");

        uint256 userFourShares = _depositFor(USER_FOUR, USER_DEPOSIT);
        assertEq(userFourShares, expectedUserFourShares);
        assertLt(userFourShares, userThreeShares);
        assertEq(sdusd.accountedAssets(), vaultAccountedBefore + expectedReward + USER_DEPOSIT * 2);
        assertEq(sdusd.totalAssets(), totalAssetsAtMidpoint + USER_DEPOSIT);
    }

    function _configureTestDusdMinter() internal {
        address dusdOwner = Ownable(DUSD_MAINNET).owner();
        vm.startPrank(dusdOwner);
        dusd.setMinterStatus(address(this), true);
        dusd.setMinterCeiling(address(this), 10_000_000 ether);
        vm.stopPrank();
    }

    function _deployCollectorAndVault() internal {
        ProtocolFeeCollector collectorImplementation = new ProtocolFeeCollector();
        ProtocolFeeCollectorInitParams memory collectorParams = ProtocolFeeCollectorInitParams({
            admin: ADMIN,
            collateralOperator: COLLATERAL_OPERATOR,
            pauser: PAUSER,
            dusd: DUSD_MAINNET,
            marketRegistry: MARKET_REGISTRY_MAINNET,
            usmRegistry: USM_REGISTRY_MAINNET,
            flashMinter: FLASH_MINTER_MAINNET,
            treasury: TREASURY,
            manualSwapReceiver: TREASURY,
            rewardsBps: REWARDS_BPS,
            minimumRewardAmount: 100 ether
        });
        collector = ProtocolFeeCollector(
            address(
                new ERC1967Proxy(
                    address(collectorImplementation), abi.encodeCall(ProtocolFeeCollector.initialize, (collectorParams))
                )
            )
        );

        SDUSD vaultImplementation = new SDUSD();
        SDUSDInitParams memory vaultParams = SDUSDInitParams({
            admin: ADMIN,
            pauser: PAUSER,
            dusd: DUSD_MAINNET,
            rewarder: address(collector),
            seedShares: SEED_ASSETS,
            depositCap: 115_000 ether,
            rewardDuration: REWARD_DURATION
        });
        sdusd = SDUSD(
            address(new ERC1967Proxy(address(vaultImplementation), abi.encodeCall(SDUSD.initialize, (vaultParams))))
        );

        vm.prank(ADMIN);
        collector.setSdusdVault(address(sdusd));
    }

    function _seedVaultAndCreateInitialPositions() internal {
        _mintDusd(address(this), SEED_ASSETS);
        IERC20(DUSD_MAINNET).forceApprove(address(sdusd), SEED_ASSETS);
        uint256 seedShares = sdusd.deposit(SEED_ASSETS, SEED_RECEIVER);

        uint256 userOneShares = _depositFor(USER_ONE, USER_DEPOSIT);
        uint256 userTwoShares = _depositFor(USER_TWO, USER_DEPOSIT);

        assertEq(seedShares, SEED_ASSETS);
        assertEq(sdusd.balanceOf(SEED_RECEIVER), SEED_ASSETS);
        assertEq(userOneShares, USER_DEPOSIT);
        assertEq(userTwoShares, userOneShares);
        assertEq(sdusd.balanceOf(USER_ONE), userOneShares);
        assertEq(sdusd.balanceOf(USER_TWO), userTwoShares);
        assertEq(sdusd.accountedAssets(), SEED_ASSETS + USER_DEPOSIT * 2);
        assertEq(sdusd.totalAssets(), SEED_ASSETS + USER_DEPOSIT * 2);
        assertEq(sdusd.totalSupply(), SEED_ASSETS + userOneShares + userTwoShares);

        initialUserShares = userOneShares;
    }

    function _configureAllFeeRecipients() internal {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            address marketOwner = Ownable(address(market)).owner();

            vm.startPrank(marketOwner);
            market.setFeeRecipient(address(collector));
            AltoBorrowMarket(address(market)).setInterestFee(BORROW_MARKET_INTEREST_FEE, true);
            vm.stopPrank();

            assertEq(market.feeRecipient(), address(collector));
        }

        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            vm.prank(Ownable(address(market)).owner());
            market.setFeeRecipient(address(collector));
            assertEq(market.feeRecipient(), address(collector));
        }

        bytes32 configuratorRole = advancedPermissionsFrxusdUsm.CONFIGURATOR_ROLE();
        address usmConfigurator = Ownable(USM_REGISTRY_MAINNET).owner();
        assertTrue(advancedPermissionsFrxusdUsm.hasRole(configuratorRole, usmConfigurator));
        vm.prank(usmConfigurator);
        advancedPermissionsFrxusdUsm.updateFeeRecipient(address(collector));
        assertEq(advancedPermissionsFrxusdUsm.getFeeRecipient(), address(collector));

        address flashMinterOwner = Ownable(FLASH_MINTER_MAINNET).owner();
        vm.startPrank(flashMinterOwner);
        flashMinter.updateFeeRecipient(address(collector));
        flashMinter.updateFlashMintFee(FlashFee({minFlashFee: FLASH_LOAN_FEE_RATE, maxFlashFee: FLASH_LOAN_FEE_RATE}));
        vm.stopPrank();
        assertEq(flashMinter.getFeeRecipient(), address(collector));
    }

    function _createAndCacheLiquidationFeeCollateral() internal {
        IMarket market = IMarket(borrowMarkets[0]);
        address collateral = market.collateralToken();
        address oracle = market.oracle();

        assertEq(market.feeRecipient(), address(collector));
        assertEq(market.position(address(collector)).collateralAssets, 0, "collector already owns collateral");

        uint256 collateralAmount = 10 ** IERC20Metadata(collateral).decimals();
        uint256 oraclePrice = ILendingOracle(oracle).getPrice();
        uint256 collateralValue = Math.mulDiv(collateralAmount, oraclePrice, LENDING_ORACLE_PRICE_PRECISION);
        uint256 borrowAmount = collateralValue / 2;

        // Add deterministic DUSD liquidity so the freshly created position does not depend on available fork liquidity.
        uint256 suppliedDusd = borrowAmount + 10_000 ether;
        _mintDusd(address(this), suppliedDusd);
        IERC20(DUSD_MAINNET).forceApprove(address(market), suppliedDusd);
        market.addSupply(suppliedDusd, 0, address(this));

        deal(collateral, LIQUIDATION_BORROWER, collateralAmount);
        vm.startPrank(LIQUIDATION_BORROWER);
        IERC20(collateral).forceApprove(address(market), collateralAmount);
        market.addCollateral(collateralAmount, LIQUIDATION_BORROWER);
        market.borrow(borrowAmount, 0, LIQUIDATION_BORROWER, LIQUIDATION_BORROWER, "");
        vm.stopPrank();

        // Halving the collateral price moves the position from roughly 50% LTV to above 100% after its opening fee.
        uint256 liquidationOraclePrice = oraclePrice / 2;
        vm.mockCall(oracle, abi.encodeCall(ILendingOracle.getPrice, ()), abi.encode(liquidationOraclePrice));

        _mintDusd(LIQUIDATOR, borrowAmount * 2);
        vm.startPrank(LIQUIDATOR);
        IERC20(DUSD_MAINNET).forceApprove(address(market), type(uint256).max);
        (,, uint256 protocolFee) = market.liquidate(LIQUIDATION_BORROWER, "", "");
        vm.stopPrank();

        assertGt(protocolFee, 0, "liquidation produced no protocol collateral fee");
        assertEq(
            market.position(address(collector)).collateralAssets,
            protocolFee,
            "liquidation fee was not credited to collector"
        );

        liquidationFeeMarkets.push(address(market));
        liquidationFeeAmounts.push(protocolFee);
        marketOraclePrices.push(liquidationOraclePrice);
        treasuryCollateralBalancesBefore.push(IERC20(collateral).balanceOf(TREASURY));

        assertEq(liquidationFeeMarkets.length, 1, "liquidation market was not cached");
    }

    function _harvestEveryFeeSource() internal returns (uint256 harvested) {
        uint256 sourceCount = allMarkets.length + 2;
        FeeSourceType[] memory sourceTypes = new FeeSourceType[](sourceCount);
        address[] memory sources = new address[](sourceCount);
        uint256 index;

        for (uint256 i; i < borrowMarkets.length; ++i) {
            sourceTypes[index] = FeeSourceType.BORROW_MARKET;
            sources[index++] = borrowMarkets[i];
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            sourceTypes[index] = FeeSourceType.MINT_MARKET;
            sources[index++] = mintMarkets[i];
        }
        sourceTypes[index] = FeeSourceType.USM;
        sources[index++] = ADVANCED_PERMISSIONS_FRXUSD_USM_MAINNET;
        sourceTypes[index] = FeeSourceType.FLASH_MINTER;
        sources[index] = FLASH_MINTER_MAINNET;

        uint256 balanceBefore = IERC20(DUSD_MAINNET).balanceOf(address(collector));
        vm.recordLogs();
        vm.prank(HARVEST_CALLER);
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 harvestedEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(collector) && logs[i].topics.length != 0
                    && logs[i].topics[0] == IProtocolFeeCollectorEvents.Harvested.selector
            ) {
                ++harvestedEvents;
            }
        }

        harvested = IERC20(DUSD_MAINNET).balanceOf(address(collector)) - balanceBefore;
        assertEq(harvestedEvents, sourceCount, "not every fee source was harvested");
        assertEq(advancedPermissionsFrxusdUsm.getAccruedFees(), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(FLASH_MINTER_MAINNET), 0);
        assertGt(harvested, 0);
    }

    function _withdrawLiquidationFeesAndReturnDusd() internal returns (uint256 totalDusdValue) {
        address[] memory markets = liquidationFeeMarkets;
        uint256[] memory amounts = liquidationFeeAmounts;

        assertGt(markets.length, 0, "no generated liquidation fee collateral");

        vm.prank(COLLATERAL_OPERATOR);
        collector.withdrawLiquidationFees(markets, amounts);

        for (uint256 i; i < markets.length; ++i) {
            IMarket market = IMarket(markets[i]);
            Position memory collectorPosition = market.position(address(collector));
            assertEq(collectorPosition.collateralAssets, 0, "collector collateral was not withdrawn");
            assertGe(
                IERC20(market.collateralToken()).balanceOf(TREASURY),
                treasuryCollateralBalancesBefore[i] + amounts[i],
                "treasury did not receive liquidation collateral"
            );

            totalDusdValue += Math.mulDiv(amounts[i], marketOraclePrices[i], LENDING_ORACLE_PRICE_PRECISION);
        }

        assertGt(totalDusdValue, 0, "liquidation collateral has zero DUSD value");
        _mintDusd(TREASURY, totalDusdValue);
        vm.prank(TREASURY);
        IERC20(DUSD_MAINNET).safeTransfer(address(collector), totalDusdValue);
    }

    function _assertDeploymentConfiguration() internal view {
        assertEq(sdusd.owner(), ADMIN);
        assertEq(sdusd.asset(), DUSD_MAINNET);
        assertEq(sdusd.seedShares(), SEED_ASSETS);
        assertEq(sdusd.rewarder(), address(collector));
        assertEq(sdusd.rewardDuration(), REWARD_DURATION);
        assertEq(sdusd.rewardsForPeriod(), 0);
        assertEq(sdusd.periodStart(), 0);
        assertEq(sdusd.rewardPeriodFinish(), 0);

        assertEq(collector.owner(), ADMIN);
        assertEq(collector.dusd(), DUSD_MAINNET);
        assertEq(collector.sdusdVault(), address(sdusd));
        assertEq(collector.treasury(), TREASURY);
        assertEq(collector.manualSwapReceiver(), TREASURY);
        assertEq(collector.flashMinter(), FLASH_MINTER_MAINNET);
        assertEq(address(collector.marketRegistry()), MARKET_REGISTRY_MAINNET);
        assertEq(address(collector.usmRegistry()), USM_REGISTRY_MAINNET);
        assertEq(collector.rewardsBps(), REWARDS_BPS);
        assertTrue(collector.isCollateralOperator(COLLATERAL_OPERATOR));
    }

    function _cacheAllMarkets() internal {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            allMarkets.push(borrowMarkets[i]);
        }
        for (uint256 i; i < mintMarkets.length; ++i) {
            allMarkets.push(mintMarkets[i]);
        }
        assertEq(allMarkets.length, 12);
    }

    function _depositFor(address user, uint256 assets) internal returns (uint256 shares) {
        _mintDusd(user, assets);
        vm.startPrank(user);
        IERC20(DUSD_MAINNET).forceApprove(address(sdusd), assets);
        shares = sdusd.deposit(assets, user);
        vm.stopPrank();
    }

    function _mintDusd(address receiver, uint256 amount) internal {
        dusd.mint(receiver, amount);
    }
}

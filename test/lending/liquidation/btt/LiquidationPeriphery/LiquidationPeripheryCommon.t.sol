// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {DirectionAccess} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {
    IMarket,
    BaseMarketInitParams,
    BorrowMarketInitParams,
    MintMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";
import {SimpleLiquidator} from "@alto-test/lending/liquidation/helpers/SimpleLiquidator.sol";

abstract contract LiquidationPeripheryCommon is Test, TestHelperOz5 {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");
    address internal immutable LIQUIDATOR = makeAddr("Liquidator");
    address internal immutable TAGGER = makeAddr("Tagger");
    address internal immutable OTHER_LIQUIDATOR = makeAddr("OtherLiquidator");
    address internal immutable BORROWER = makeAddr("Borrower");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable STABLE_TREASURY = makeAddr("StableTreasury");
    address internal immutable TREASURY = makeAddr("Treasury");

    uint256 internal constant ONE_TO_ONE_PRICE_RATIO = 1e18;
    uint256 internal constant EXCESS_SELL_PRICE_RATIO = 12e17;
    uint256 internal constant DEBT_CEILING = 1_000_000 ether;
    uint256 internal constant SWAPPER_UNDERLYING_LIQUIDITY = 1_000_000e6;

    bytes32 internal constant BUY_SWAPPER_ROLE = keccak256("BUY_SWAPPER_ROLE");
    bytes32 internal constant SELL_SWAPPER_ROLE = keccak256("SELL_SWAPPER_ROLE");
    uint16 internal constant MAX_USM_FEE_BPS = 4999;
    address internal constant WARMUP_SWAPPER = address(uint160(uint256(keccak256("WarmupSwapper"))));

    LiquidationPeriphery internal periphery;
    MockSwapper internal swapper;
    SimpleLiquidator internal simpleLiquidator;
    MarketRegistry internal registry;
    UsmRegistry internal usmRegistry;
    DUSDAdvancedPermissionsUsm internal usm;
    FixedPriceStrategy internal priceStrategy;

    IMarket internal borrowMarket;
    IMarket internal mintMarket;
    OracleMock internal oracle;

    DUSD internal borrowToken;
    ERC20Mock internal collateralToken;
    ERC20MockMintableDecimals internal underlyingToken;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        vm.startPrank(OWNER);
        borrowToken = new DUSD(address(endpoints[1]), OWNER);
        collateralToken = new ERC20Mock("WETH", "WETH");
        underlyingToken = new ERC20MockMintableDecimals("USDC", "USDC", 6);

        priceStrategy = new FixedPriceStrategy(ONE_TO_ONE_PRICE_RATIO, address(underlyingToken), OWNER);
        usm = _deployUsm(address(borrowToken), address(underlyingToken), ONE_TO_ONE_PRICE_RATIO);

        registry = new MarketRegistry(OWNER);
        usmRegistry = new UsmRegistry(OWNER);
        vm.startPrank(OWNER);
        usmRegistry.addUsm(address(usm));
        periphery = new LiquidationPeriphery(OWNER, address(borrowToken), address(usmRegistry), TREASURY);
        _grantPeripheryUsmSellPermission();

        swapper = new MockSwapper();
        simpleLiquidator = new SimpleLiquidator(address(periphery), address(usm), address(swapper));
        underlyingToken.mint(address(swapper), SWAPPER_UNDERLYING_LIQUIDITY);
        vm.stopPrank();

        borrowMarket = _deployBorrowMarket();
        mintMarket = _deployMintMarket();

        vm.startPrank(OWNER);
        periphery.setSupportedMarket(address(borrowMarket), true);
        periphery.setSupportedMarket(address(mintMarket), true);
        _authorizePeripheryOnMarkets();
        registry.addBorrowMarket(address(borrowMarket));
        registry.addMintMarket(address(mintMarket));
        borrowToken.setMinterStatus(address(this), true);
        borrowToken.setMinterCeiling(address(this), type(uint128).max);
        borrowToken.setMinterStatus(address(mintMarket), true);
        borrowToken.setMinterCeiling(address(mintMarket), type(uint128).max);
        borrowToken.setBurnerStatus(address(mintMarket), true);
        vm.stopPrank();
    }

    function _deployUsm(address stableToken, address underlyingAsset, uint256 initialPriceRatio)
        internal
        returns (DUSDAdvancedPermissionsUsm)
    {
        FixedPriceStrategy strategy = initialPriceRatio == ONE_TO_ONE_PRICE_RATIO
            && underlyingAsset == address(underlyingToken)
            ? priceStrategy
            : new FixedPriceStrategy(initialPriceRatio, underlyingAsset, OWNER);

        address impl = address(new DUSDAdvancedPermissionsUsm(stableToken, underlyingAsset));
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            impl,
            abi.encodeCall(
                DUSDAdvancedPermissionsUsm.initialize,
                (
                    OWNER,
                    STABLE_TREASURY,
                    uint128(100_000_000e6),
                    address(strategy),
                    DirectionAccess.PERMISSIONED,
                    DirectionAccess.PERMISSIONED
                )
            )
        );

        DUSDAdvancedPermissionsUsm deployed = DUSDAdvancedPermissionsUsm(proxy);

        vm.startPrank(OWNER);
        DUSD(stableToken).setMinterStatus(address(deployed), true);
        DUSD(stableToken).setMinterCeiling(address(deployed), type(uint128).max);
        DUSD(stableToken).setBurnerStatus(address(deployed), true);
        _configureUsmFeeStrategy(deployed);
        vm.stopPrank();

        return deployed;
    }

    function _configureUsmFeeStrategy(DUSDAdvancedPermissionsUsm deployed) internal {
        AdvancedPermissionsFeeStrategy feeStrategy = new AdvancedPermissionsFeeStrategy(10, 10, OWNER);
        feeStrategy.setSellFeeByRoleHash(
            SELL_SWAPPER_ROLE, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: 0})
        );
        deployed.updateFeeRecipient(STABLE_TREASURY);
        deployed.updateFeeStrategy(address(feeStrategy));
    }

    function _grantPeripheryUsmSellPermission() internal {
        _grantPeripheryUsmSellPermissionOn(usm);
    }

    function _grantPeripheryUsmSellPermissionOn(DUSDAdvancedPermissionsUsm target) internal {
        vm.startPrank(OWNER);
        target.grantRole(SELL_SWAPPER_ROLE, address(periphery));
        AdvancedPermissionsFeeStrategy(target.getFeeStrategy())
            .setUserSellFeeRole(address(periphery), SELL_SWAPPER_ROLE);
        vm.stopPrank();
    }

    function _liquidationConfig() internal pure returns (LiquidationConfiguration memory) {
        return LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: false,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });
    }

    function _baseMarketInitParams(address liquidationEngine) internal returns (BaseMarketInitParams memory) {
        return BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this))),
            owner: OWNER,
            emergencyAdmin: OWNER,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: makeAddr("FeeRecipient"),
            liquidationEngine: liquidationEngine
        });
    }

    function _deployBorrowMarket() internal returns (IMarket) {
        vm.startPrank(OWNER);
        oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: _baseMarketInitParams(liquidationEngine),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        IMarket deployed = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_liquidationConfig());
        vm.stopPrank();

        return deployed;
    }

    function _deployMintMarket() internal returns (IMarket) {
        vm.startPrank(OWNER);

        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));

        MintMarketInitParams memory mintMarketInitParams = MintMarketInitParams({
            baseMarketInitParams: _baseMarketInitParams(liquidationEngine),
            debtCeiling: DEBT_CEILING,
            initialBorrowOpeningFee: 0
        });

        IMarket deployed = IMarket(MarketDeployer.deployMintMarket(mintMarketInitParams));
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_liquidationConfig());
        vm.stopPrank();

        return deployed;
    }

    function _createInsolventPosition(IMarket target, bool withSupply, address borrower) internal {
        bool isMintMarket = address(target) == address(mintMarket);

        if (!isMintMarket) {
            address highIrm = address(new FixedRateIrm(8 ether / uint256(365 days), address(this)));
            vm.prank(OWNER);
            target.setIrm(highIrm, false);
        }

        _mintBorrowToken(address(this), 100 ether);
        deal(address(collateralToken), address(this), 100 ether);

        collateralToken.approve(address(target), type(uint256).max);
        borrowToken.approve(address(target), type(uint256).max);

        if (withSupply) {
            _mintBorrowToken(SUPPLIER, 100 ether);
            vm.startPrank(SUPPLIER);
            borrowToken.approve(address(target), type(uint256).max);
            target.addSupply(100 ether, 0, SUPPLIER);
            vm.stopPrank();
        }

        vm.prank(borrower);
        target.setAuthorization(address(this), true);

        target.addCollateral(1 ether, borrower);
        target.borrow(0.5 ether, 0, borrower, borrower, "");

        if (isMintMarket) {
            oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION / 4);
        } else {
            vm.warp(block.timestamp + 100 days);
        }
    }

    function _mintBorrowToken(address to, uint256 amount) internal {
        borrowToken.mint(to, amount);
    }

    function _configureUsmOneToOne() internal {
        vm.prank(OWNER);
        priceStrategy.setPriceRatio(ONE_TO_ONE_PRICE_RATIO);
    }

    function _configureUsmExcessSell() internal {
        vm.prank(OWNER);
        priceStrategy.setPriceRatio(EXCESS_SELL_PRICE_RATIO);
    }

    function _configureUsmPriceRatio(uint256 priceRatio) internal {
        vm.prank(OWNER);
        priceStrategy.setPriceRatio(priceRatio);
    }

    function _configureUsmFees(uint16 buyFeeBps, uint16 sellFeeBps) internal {
        AdvancedPermissionsFeeStrategy feeStrategy = AdvancedPermissionsFeeStrategy(usm.getFeeStrategy());
        vm.startPrank(OWNER);
        feeStrategy.setFee(buyFeeBps, sellFeeBps);
        feeStrategy.setBuyFeeByRoleHash(
            BUY_SWAPPER_ROLE, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: buyFeeBps})
        );
        feeStrategy.setSellFeeByRoleHash(
            SELL_SWAPPER_ROLE,
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: sellFeeBps})
        );
        vm.stopPrank();
    }

    function _ensureWarmupSwapperRoles() internal {
        if (usm.hasRole(BUY_SWAPPER_ROLE, WARMUP_SWAPPER)) return;

        vm.startPrank(OWNER);
        usm.grantRole(BUY_SWAPPER_ROLE, WARMUP_SWAPPER);
        usm.grantRole(SELL_SWAPPER_ROLE, WARMUP_SWAPPER);
        AdvancedPermissionsFeeStrategy(usm.getFeeStrategy()).setUserBuyFeeRole(WARMUP_SWAPPER, BUY_SWAPPER_ROLE);
        AdvancedPermissionsFeeStrategy(usm.getFeeStrategy()).setUserSellFeeRole(WARMUP_SWAPPER, SELL_SWAPPER_ROLE);
        vm.stopPrank();
    }

    function _warmupUsmSwaps(uint256 sellAmount, uint256 buyMinUnderlying, uint256 sellAmount2) internal {
        _ensureWarmupSwapperRoles();

        underlyingToken.mint(WARMUP_SWAPPER, sellAmount + sellAmount2);

        vm.startPrank(WARMUP_SWAPPER);
        underlyingToken.approve(address(usm), type(uint256).max);
        borrowToken.approve(address(usm), type(uint256).max);

        usm.sellAsset(sellAmount, WARMUP_SWAPPER);

        if (buyMinUnderlying > 0 && buyMinUnderlying <= usm.getAvailableLiquidity()) {
            (, uint256 stableForBuy,,) = usm.getStableTokenAmountForBuyAsset(buyMinUnderlying, WARMUP_SWAPPER);
            if (stableForBuy > 0) {
                vm.stopPrank();
                _mintBorrowToken(WARMUP_SWAPPER, stableForBuy);
                vm.startPrank(WARMUP_SWAPPER);
                borrowToken.approve(address(usm), type(uint256).max);
                try usm.buyAsset(buyMinUnderlying, WARMUP_SWAPPER) {} catch {}
            }
        }

        if (sellAmount2 > 0) {
            uint256 balance = underlyingToken.balanceOf(WARMUP_SWAPPER);
            sellAmount2 = sellAmount2 > balance ? balance : sellAmount2;
            if (sellAmount2 > 0) {
                try usm.sellAsset(sellAmount2, WARMUP_SWAPPER) {} catch {}
            }
        }

        vm.stopPrank();
    }

    function _invokeOnLiquidateCallback(
        address caller,
        uint256 repayAmount,
        uint256 collateralAmount,
        bytes memory callbackData
    ) internal {
        vm.prank(caller);
        periphery.onLiquidateCallback(repayAmount, collateralAmount, callbackData);
    }

    function _fundLiquidatorForDirectRepay() internal {
        _mintBorrowToken(LIQUIDATOR, 100 ether);
        vm.prank(LIQUIDATOR);
        borrowToken.approve(address(periphery), type(uint256).max);
    }

    function _assertUnderlyingApprovalResetToUsm() internal view {
        assertEq(underlyingToken.allowance(address(periphery), address(usm)), 0);
    }

    function _authorizePeripheryOnMarkets() internal {
        borrowMarket.setAuthorizedLiquidationPeriphery(address(periphery), true);
        mintMarket.setAuthorizedLiquidationPeriphery(address(periphery), true);
    }

    function _deauthorizePeripheryOnMarkets() internal {
        vm.startPrank(OWNER);
        borrowMarket.setAuthorizedLiquidationPeriphery(address(periphery), false);
        mintMarket.setAuthorizedLiquidationPeriphery(address(periphery), false);
        vm.stopPrank();
    }

    function _enablePriorityLiquidation(IMarket target) internal {
        address liquidationEngine = target.liquidationEngine();
        LiquidationConfiguration memory config =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        config.isEnabledPriorityLiquidation = true;
        vm.prank(OWNER);
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(config);
    }

    function _setPriorityLiquidator(IMarket target, address liquidator, bool status) internal {
        address liquidationEngine = target.liquidationEngine();
        vm.prank(OWNER);
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setPriorityLiquidator(liquidator, status);
    }

    function _setupBorrowMarketPriorityLiquidation() internal {
        _createInsolventPosition(borrowMarket, true, BORROWER);
        _enablePriorityLiquidation(borrowMarket);
    }

    function _fundSimpleLiquidatorForPriorityLiquidation(uint256 repayAmountBound) internal {
        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(repayAmountBound, address(periphery));
        _transferUnderlyingFromSwapperToSimpleLiquidator(assetAmount);
        vm.prank(address(simpleLiquidator));
        underlyingToken.approve(address(periphery), type(uint256).max);
    }

    function _liquidationCallbackData(address market) internal pure returns (bytes memory) {
        return abi.encode(market);
    }

    function _transferUnderlyingFromSwapperToSimpleLiquidator(uint256 amount) internal {
        vm.prank(address(swapper));
        underlyingToken.transfer(address(simpleLiquidator), amount);
    }

    function _expectedStableRefund(uint256 repayAmount) internal view returns (uint256) {
        (, uint256 stableBought,,) = usm.getAssetAmountForSellAsset(repayAmount, address(periphery));
        return stableBought - repayAmount;
    }

    function _callbackData(
        address liquidator,
        address market,
        address targetUsm,
        bytes memory liquidationPeripheryCallbackData
    ) internal pure returns (bytes memory) {
        return abi.encode(liquidator, market, targetUsm, liquidationPeripheryCallbackData);
    }
}

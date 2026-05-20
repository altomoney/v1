// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {UsmDeployer, DusdUsmInitParams} from "@alto-test/helpers/UsmDeployer.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {
    IMarket,
    BaseMarketInitParams,
    BorrowMarketInitParams,
    MintMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";

abstract contract LiquidationPeripheryCommon is Test, TestHelperOz5 {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");
    address internal immutable LIQUIDATOR = makeAddr("Liquidator");
    address internal immutable BORROWER = makeAddr("Borrower");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable STABLE_TREASURY = makeAddr("StableTreasury");

    uint256 internal constant ONE_TO_ONE_PRICE_RATIO = 1e18;
    uint256 internal constant EXCESS_SELL_PRICE_RATIO = 12e17;
    uint256 internal constant DEBT_CEILING = 1_000_000 ether;

    LiquidationPeriphery internal periphery;
    MarketRegistry internal registry;
    DUSDUsm internal usm;
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
        periphery = new LiquidationPeriphery(OWNER, address(registry), address(usm));
        vm.stopPrank();

        borrowMarket = _deployBorrowMarket();
        mintMarket = _deployMintMarket();

        vm.startPrank(OWNER);
        registry.addBorrowMarket(address(borrowMarket));
        registry.addMintMarket(address(mintMarket));
        borrowToken.setMinterStatus(address(this), true);
        borrowToken.setMinterCeiling(address(this), type(uint128).max);
        borrowToken.setMinterStatus(address(mintMarket), true);
        borrowToken.setMinterCeiling(address(mintMarket), type(uint128).max);
        borrowToken.setBurnerStatus(address(mintMarket), true);
        vm.stopPrank();
    }

    uint256 internal borrowerNonce;

    function _nextBorrower() internal returns (address) {
        borrowerNonce++;
        return makeAddr(string.concat("Borrower", vm.toString(borrowerNonce)));
    }

    function _deployUsm(address stableToken, address underlyingAsset, uint256 initialPriceRatio)
        internal
        returns (DUSDUsm)
    {
        FixedPriceStrategy strategy = initialPriceRatio == ONE_TO_ONE_PRICE_RATIO
            ? priceStrategy
            : new FixedPriceStrategy(initialPriceRatio, underlyingAsset, OWNER);

        DusdUsmInitParams memory initParams = DusdUsmInitParams({
            admin: OWNER,
            stableTokenTreasury: STABLE_TREASURY,
            exposureCap: uint128(100_000_000e6),
            priceStrategy: address(strategy),
            accessMode: AccessMode.PERMISSIONLESS
        });

        DUSDUsm deployed = DUSDUsm(UsmDeployer.deployDusdUsm(stableToken, underlyingAsset, initParams));

        vm.startPrank(OWNER);
        DUSD(stableToken).setMinterStatus(address(deployed), true);
        DUSD(stableToken).setMinterCeiling(address(deployed), type(uint128).max);
        DUSD(stableToken).setBurnerStatus(address(deployed), true);
        vm.stopPrank();

        return deployed;
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

    function _fundLiquidatorForDirectRepay() internal {
        _mintBorrowToken(LIQUIDATOR, 100 ether);
        vm.prank(LIQUIDATOR);
        borrowToken.approve(address(periphery), type(uint256).max);
    }

    function _fundLiquidatorForUsmRepay(uint256 minStableAmount) internal {
        (uint256 assetAmount,,,) = usm.getAssetAmountForSellAsset(minStableAmount);
        underlyingToken.mint(LIQUIDATOR, assetAmount * 2);
        vm.prank(LIQUIDATOR);
        underlyingToken.approve(address(periphery), type(uint256).max);
    }

    function _expectedStableRefund(uint256 repayAmount) internal view returns (uint256) {
        (, uint256 stableBought,,) = usm.getAssetAmountForSellAsset(repayAmount);
        return stableBought - repayAmount;
    }

    function _callbackData(address liquidator, bool repayViaUsm, address market) internal pure returns (bytes memory) {
        return abi.encode(liquidator, repayViaUsm, market);
    }
}

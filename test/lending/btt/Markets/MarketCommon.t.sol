// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {
    LiquidationConfiguration,
    BaseMarketInitParams,
    BorrowMarketInitParams,
    MintMarketInitParams,
    DaoMintMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.

enum MarketType {
    BORROW,
    MINT,
    DAO_MINT
}

abstract contract MarketCommon is Test {
    address internal immutable USER = makeAddr("User");
    address internal immutable USER_2 = makeAddr("User2");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable FEE_RECIPIENT = makeAddr("FeeRecipient");
    address internal immutable PAUSER = makeAddr("Pauser");
    address internal immutable RECEIVER = makeAddr("Receiver");
    address internal immutable LIQUIDATOR = makeAddr("Liquidator");

    ERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;

    IMarket internal market;
    OracleMock internal oracle;
    SwapperSimpleMock swapper;
    AltoLeverage leverage;

    uint256 internal constant LTV = 0.75 ether;

    MarketType internal marketType;

    constructor(MarketType _marketType) {
        marketType = _marketType;
    }

    function setUp() public virtual {
        borrowToken = new ERC20Mock("borrow", "B");
        vm.label(address(borrowToken), "borrowToken");
        collateralToken = new ERC20Mock("collateral", "C");
        vm.label(address(collateralToken), "collateralToken");

        vm.startPrank(OWNER);
        swapper = new SwapperSimpleMock(address(OWNER));
        leverage = new AltoLeverage(address(swapper), address(OWNER));
        oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: address(OWNER),
            oracle: address(oracle),
            maxLtv: LTV,
            feeRecipient: address(FEE_RECIPIENT),
            liquidationConfiguration: liquidationConfig
        });
        if (marketType == MarketType.BORROW) {
            BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
                baseMarketInitParams: baseMarketInitParams,
                initialBorrowOpeningFee: 0,
                supplyCapAssets: 0
            });
            market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));
        } else if (marketType == MarketType.MINT) {
            borrowToken = ERC20Mock(address(new ERC20MockMintable("borrow", "B")));
            baseMarketInitParams.borrowToken = address(borrowToken);
            MintMarketInitParams memory mintMarketInitParams = MintMarketInitParams({
                baseMarketInitParams: baseMarketInitParams, debtCeiling: 1000000 ether, initialBorrowOpeningFee: 0
            });
            market = IMarket(MarketDeployer.deployMintMarket(mintMarketInitParams));
        } else if (marketType == MarketType.DAO_MINT) {
            borrowToken = ERC20Mock(address(new ERC20MockMintable("borrow", "B")));
            baseMarketInitParams.borrowToken = address(borrowToken);
            DaoMintMarketInitParams memory daoMintMarketInitParams = DaoMintMarketInitParams({
                baseMarketInitParams: baseMarketInitParams,
                debtCeiling: 1000000 ether,
                initialBorrowOpeningFee: 0
            });
            market = IMarket(MarketDeployer.deployDaoMintMarket(daoMintMarketInitParams));
        }

        market.setPauser(PAUSER, PAUSE_TYPE, true);
        market.setPauser(PAUSER, FROZEN_TYPE, true);

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
}

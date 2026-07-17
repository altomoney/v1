// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {IConvexRewardPool} from "@alto/positions/interfaces/IConvex.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {BaseMarketInitParams, IMarket, MintMarketInitParams, Position} from "@alto/lending/interfaces/IMarket.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockConvexBooster} from "../mocks/MockConvexBooster.sol";
import {MockConvexRewardPool} from "../mocks/MockConvexRewardPool.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";

/// @notice Shared harness for the dedicated MintCurveConvexPosition BTT suite.
/// @dev The mint market mints/burns the DUSD mock directly, so the position must hold DUSD to repay.
abstract contract MintCurveConvexPositionCommon is Test {
    uint256 internal constant DEFAULT_COLLATERAL = 10_000e18;
    uint256 internal constant DEFAULT_BORROW = 1_000e18;
    uint256 internal constant MARKET_MAX_LTV = 0.75 ether;
    uint256 internal constant MARKET_DEBT_CEILING = 1_000_000 ether;

    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable FEE_RECIPIENT = makeAddr("FeeRecipient");
    address internal immutable AUTHORIZED_SPENDER = makeAddr("AuthorizedSpender");
    address internal immutable NON_AUTHORIZED = makeAddr("NonAuthorized");

    MarketRegistry internal registry;
    MintCurveConvexPositionFactory internal factory;
    MintCurveConvexPosition internal positionImplementation;
    PositionBeacon internal positionBeacon;

    ERC20MockMintable internal collateralToken;
    ERC20MockMintable internal borrowToken; // DUSD
    ERC20MockMintable internal pairToken; // second Curve coin
    ERC20MockMintable internal crv;
    ERC20MockMintable internal cvx;

    OracleMock internal oracle;
    AltoMintMarket internal mintMarket;
    MockCurvePool internal curvePool;
    MockConvexRewardPool internal convexRewardPool;
    MockConvexBooster internal convexBooster;

    MintCurveConvexPosition internal position;

    function setUp() public virtual {
        collateralToken = new ERC20MockMintable("Collateral", "COL");
        borrowToken = new ERC20MockMintable("DUSD", "DUSD");
        pairToken = new ERC20MockMintable("Pair", "PAIR");
        crv = new ERC20MockMintable("CRV", "CRV");
        cvx = new ERC20MockMintable("CVX", "CVX");

        mintMarket = _deployMintMarket();
        // DUSD is coin0 of the pool by default.
        curvePool = new MockCurvePool(address(borrowToken), address(pairToken));
        convexRewardPool = new MockConvexRewardPool(address(curvePool), address(crv), address(cvx), 1);
        convexBooster = new MockConvexBooster(address(convexRewardPool), address(curvePool));

        registry = new MarketRegistry(OWNER);
        vm.prank(OWNER);
        registry.addMintMarket(address(mintMarket));

        factory = _deployInitializedFactory();
        positionImplementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(positionImplementation), OWNER);

        vm.startPrank(OWNER);
        factory.setBeacon(address(positionBeacon));
        vm.stopPrank();

        position = _createPosition(OWNER);
    }

    function _deployMintMarket() internal returns (AltoMintMarket) {
        oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), OWNER));
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));

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

        MintMarketInitParams memory mintMarketInitParams = MintMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(borrowToken),
                collateralToken: address(collateralToken),
                irm: irm,
                owner: OWNER,
                oracle: address(oracle),
                maxLtv: MARKET_MAX_LTV,
                feeRecipient: FEE_RECIPIENT,
                liquidationEngine: liquidationEngine
            }),
            debtCeiling: MARKET_DEBT_CEILING,
            initialBorrowOpeningFee: 0
        });

        vm.startPrank(OWNER);
        AltoMintMarket deployed = AltoMintMarket(MarketDeployer.deployMintMarket(mintMarketInitParams));
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);
        vm.stopPrank();

        return deployed;
    }

    function _deployInitializedFactory() internal returns (MintCurveConvexPositionFactory) {
        MintCurveConvexPositionFactory deployed =
            MintCurveConvexPositionFactory(UnsafeUpgrades.deployUUPSProxy(address(new MintCurveConvexPositionFactory()), ""));
        deployed.initialize(
            OWNER, address(registry), _config(address(curvePool), address(convexBooster), address(convexRewardPool))
        );
        return deployed;
    }

    function _config(address pool, address booster, address rewardPool)
        internal
        view
        returns (MintCurveConvexConfig memory)
    {
        return MintCurveConvexConfig({
            curvePool: pool,
            convexBooster: booster,
            convexRewardPool: rewardPool,
            convexPid: 1,
            crv: address(crv),
            cvx: address(cvx)
        });
    }

    function _createPosition(address owner) internal returns (MintCurveConvexPosition deployed) {
        vm.prank(owner);
        deployed = MintCurveConvexPosition(factory.createPosition(address(mintMarket)));
    }

    /// @dev Deploys a fresh factory (config is fixed at initialize) and creates a position from it.
    function _createPositionWithConfig(MintCurveConvexConfig memory cfg)
        internal
        returns (MintCurveConvexPosition deployed)
    {
        MintCurveConvexPositionFactory scopedFactory =
            MintCurveConvexPositionFactory(UnsafeUpgrades.deployUUPSProxy(address(new MintCurveConvexPositionFactory()), ""));
        scopedFactory.initialize(OWNER, address(registry), cfg);

        vm.prank(OWNER);
        scopedFactory.setBeacon(address(positionBeacon));

        vm.prank(OWNER);
        deployed = MintCurveConvexPosition(scopedFactory.createPosition(address(mintMarket)));
    }

    function _authorizeSpender(address owner, address spender) internal {
        vm.prank(owner);
        position.setAuthorization(spender, true);
    }

    /// @dev Mints collateral to `account` and approves the position to pull `amount`.
    function _fundCollateral(address account, uint256 amount) internal {
        collateralToken.mint(account, amount);
        vm.prank(account);
        collateralToken.approve(address(position), amount);
    }

    /// @dev Mints DUSD to `account` and approves the position to pull `amount` (used for repay top-ups).
    function _fundDusd(address account, uint256 amount) internal {
        borrowToken.mint(account, amount);
        vm.prank(account);
        borrowToken.approve(address(position), amount);
    }

    /// @dev Mints collateral to the owner and approves the position to pull `amount`.
    function _fundOwnerCollateral(uint256 amount) internal {
        _fundCollateral(OWNER, amount);
    }

    /// @dev Mints DUSD to the owner and approves the position to pull `amount` (used for repay top-ups).
    function _fundOwnerDusd(uint256 amount) internal {
        _fundDusd(OWNER, amount);
    }

    /// @dev Posts collateral through the position as the owner.
    function _seedCollateral(uint256 amount) internal {
        _fundOwnerCollateral(amount);
        vm.prank(OWNER);
        position.addCollateral(amount);
    }

    /// @dev Opens a position with collateral and a Curve/Convex deposit funded by borrowed DUSD.
    function _openPosition(uint256 collateral, uint256 borrowAssets) internal {
        _seedCollateral(collateral);
        vm.prank(OWNER);
        position.borrowAndDepositToLp(borrowAssets, borrowAssets);
    }

    function _stakedLpBalance() internal view returns (uint256) {
        return IConvexRewardPool(address(convexRewardPool)).balanceOf(address(position));
    }

    function _marketPosition(address user) internal view returns (Position memory) {
        return IMarket(address(mintMarket)).position(user);
    }

    function _marketPosition() internal view returns (Position memory) {
        return _marketPosition(address(position));
    }

    function _borrowShares() internal view returns (uint256) {
        return _marketPosition().borrowShares;
    }

    function _fundRewards(uint256 crvAmount, uint256 cvxAmount) internal {
        crv.mint(address(convexRewardPool), crvAmount);
        cvx.mint(address(convexRewardPool), cvxAmount);
    }
}

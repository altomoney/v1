// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PositionFactory} from "@alto/positions/PositionFactory.sol";
import {PositionBeacon} from "@alto/positions/PositionBeacon.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {PositionType} from "@alto/positions/interfaces/IPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IPositionFactory.sol";
import {
    IMintCurveConvexPositionEvents,
    MintCurveConvexAddParams,
    MintCurveConvexRemoveMode,
    MintCurveConvexRemoveParams
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
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
import {MockSwapTarget} from "../mocks/MockSwapTarget.sol";

abstract contract MintCurveConvexPositionCommon is Test {
    uint256 internal constant DEFAULT_COLLATERAL = 10_000e18;
    uint256 internal constant DEFAULT_BORROW = 1_000e18;
    uint256 internal constant MARKET_MAX_LTV = 0.75 ether;
    uint256 internal constant MARKET_DEBT_CEILING = 1_000_000 ether;
    uint256 internal constant POSITION_MAPPING_SLOT = 8;

    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable FEE_RECIPIENT = makeAddr("FeeRecipient");
    address internal immutable AUTHORIZED_SPENDER = makeAddr("AuthorizedSpender");
    address internal immutable NON_AUTHORIZED = makeAddr("NonAuthorized");
    address internal immutable UNAPPROVED_SWAP_TARGET = makeAddr("UnapprovedSwapTarget");

    MarketRegistry internal registry;
    PositionFactory internal factory;
    MintCurveConvexPosition internal positionImplementation;
    PositionBeacon internal positionBeacon;

    ERC20MockMintable internal collateralToken;
    ERC20MockMintable internal borrowToken;
    ERC20MockMintable internal frxUsd;
    ERC20MockMintable internal crv;
    ERC20MockMintable internal cvx;

    OracleMock internal oracle;
    AltoMintMarket internal mintMarket;
    MockCurvePool internal curvePool;
    MockConvexRewardPool internal convexRewardPool;
    MockConvexBooster internal convexBooster;
    MockSwapTarget internal swapTarget;

    MintCurveConvexPosition internal position;

    function setUp() public virtual {
        collateralToken = new ERC20MockMintable("Collateral", "COL");
        borrowToken = new ERC20MockMintable("DUSD", "DUSD");
        frxUsd = new ERC20MockMintable("frxUSD", "frxUSD");
        crv = new ERC20MockMintable("CRV", "CRV");
        cvx = new ERC20MockMintable("CVX", "CVX");

        mintMarket = _deployMintMarket();
        curvePool = new MockCurvePool(address(borrowToken), address(frxUsd));
        convexRewardPool = new MockConvexRewardPool(address(curvePool), address(crv), address(cvx));
        convexBooster = new MockConvexBooster(address(convexRewardPool), address(curvePool));
        swapTarget = new MockSwapTarget();

        registry = new MarketRegistry(OWNER);
        vm.prank(OWNER);
        registry.addMintMarket(address(mintMarket));

        factory = _deployInitializedFactory();
        positionImplementation = new MintCurveConvexPosition();
        positionBeacon = new PositionBeacon(address(positionImplementation), OWNER);

        vm.startPrank(OWNER);
        factory.setBeacon(PositionType.MINT_CURVE_CONVEX, address(positionBeacon));
        factory.setMintCurveConvexConfig(_validConfig());
        factory.setApprovedSwapTarget(address(swapTarget), true);
        vm.stopPrank();

        swapTarget.setSwapOutcome(false, 0);
        curvePool.setLpMintOverride(0, false);

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

    function _deployInitializedFactory() internal returns (PositionFactory) {
        PositionFactory deployed = PositionFactory(UnsafeUpgrades.deployUUPSProxy(address(new PositionFactory()), ""));
        deployed.initialize(OWNER, address(registry));
        return deployed;
    }

    function _validConfig() internal view returns (MintCurveConvexConfig memory config) {
        config = MintCurveConvexConfig({
            frxUsd: address(frxUsd),
            curvePool: address(curvePool),
            convexBooster: address(convexBooster),
            convexRewardPool: address(convexRewardPool),
            convexPid: 1,
            crv: address(crv),
            cvx: address(cvx)
        });
    }

    function _createPosition(address owner) internal returns (MintCurveConvexPosition deployed) {
        vm.prank(owner);
        address positionAddr = factory.createPosition(PositionType.MINT_CURVE_CONVEX, abi.encode(address(mintMarket)));
        deployed = MintCurveConvexPosition(positionAddr);
    }

    function _authorizeSpender(address owner, address spender) internal {
        vm.prank(owner);
        position.setAuthorization(spender, true);
    }

    function _mintCollateralToOwner(uint256 amount) internal {
        _mintCollateralFor(address(position), amount);
    }

    function _mintCollateralFor(address positionAddr, uint256 amount) internal {
        collateralToken.mint(OWNER, amount);
        vm.prank(OWNER);
        collateralToken.approve(positionAddr, amount);
    }

    function _swapDataDusdToFrx(uint256 amountIn) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            MockSwapTarget.swap.selector, address(borrowToken), address(frxUsd), amountIn
        );
    }

    function _swapDataFrxToDusd(uint256 amountIn) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            MockSwapTarget.swap.selector, address(frxUsd), address(borrowToken), amountIn
        );
    }

    function _addParams(
        uint256 collateralAmount,
        uint256 borrowAssets,
        uint256 amountIn,
        uint256 minFrxOut,
        uint256 minLpOut
    ) internal view returns (MintCurveConvexAddParams memory params) {
        params = MintCurveConvexAddParams({
            collateralAmount: collateralAmount,
            borrowAssets: borrowAssets,
            swapTarget: address(swapTarget),
            swapData: _swapDataDusdToFrx(amountIn),
            minFrxUsdOutFromDusdSwap: minFrxOut,
            minLpOutFromCurve: minLpOut
        });
    }

    /// @dev Default mocks swap 1:1 and mint LP equal to deposited token sums.
    function _expectedAddMinFrxOut(uint256 borrowAssets) internal pure returns (uint256 minFrxOut) {
        return borrowAssets / 2;
    }

    function _expectedAddMinLpOut(uint256 borrowAssets) internal pure returns (uint256 minLpOut) {
        return borrowAssets;
    }

    /// @dev Borrow leg is skipped; mins are never checked but stay explicit in encoded params.
    function _unusedAddMinOuts() internal pure returns (uint256 minFrxOut, uint256 minLpOut) {
        return (0, 0);
    }

    function _assertAddPositionLogged(
        uint256 expectedCollateral,
        uint256 expectedBorrow,
        uint256 minLpOut,
        Vm.Log[] memory logs
    ) internal {
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.AddPosition.selector) {
                (uint256 loggedCollateral, uint256 loggedBorrow, uint256 lpStaked) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));
                assertEq(loggedCollateral, expectedCollateral);
                assertEq(loggedBorrow, expectedBorrow);
                assertGe(lpStaked, minLpOut);
                found = true;
            }
        }
        assertTrue(found);
    }

    function _assertSwapLogged(
        address sellToken,
        address buyToken,
        uint256 amountIn,
        address expectedSwapTarget,
        uint256 minAmountOut,
        Vm.Log[] memory logs
    ) internal {
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.Swap.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), sellToken);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), buyToken);
                (uint256 loggedAmountIn, address loggedSwapTarget, uint256 amountOut) =
                    abi.decode(logs[i].data, (uint256, address, uint256));
                assertEq(loggedAmountIn, amountIn);
                assertEq(loggedSwapTarget, expectedSwapTarget);
                assertGe(amountOut, minAmountOut);
                found = true;
            }
        }
        assertTrue(found);
    }

    function _encodeAdd(MintCurveConvexAddParams memory params) internal pure returns (bytes memory) {
        return abi.encode(params);
    }

    function _defaultRemoveParams() internal view returns (MintCurveConvexRemoveParams memory params) {
        params = MintCurveConvexRemoveParams({
            mode: MintCurveConvexRemoveMode.NORMAL,
            convexLpAmount: 0,
            minDusdFromCurve: 0,
            minFrxUsdFromCurve: 0,
            frxUsdAmountToSwap: 0,
            swapTarget: address(swapTarget),
            swapData: _swapDataFrxToDusd(0),
            minDusdOutFromFrxUsdSwap: 0,
            repayShares: 0,
            collateralAmountToWithdraw: 0,
            claimRewards: false
        });
    }

    function _encodeRemove(MintCurveConvexRemoveParams memory params) internal pure returns (bytes memory) {
        return abi.encode(params);
    }

    function _encodeRemoveWithMode(uint256 mode, MintCurveConvexRemoveParams memory params)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            mode,
            params.convexLpAmount,
            params.minDusdFromCurve,
            params.minFrxUsdFromCurve,
            params.frxUsdAmountToSwap,
            params.swapTarget,
            params.swapData,
            params.minDusdOutFromFrxUsdSwap,
            params.repayShares,
            params.collateralAmountToWithdraw,
            params.claimRewards
        );
    }

    function _addCollateralOnly(uint256 collateralAmount) internal {
        _mintCollateralToOwner(collateralAmount);
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();
        vm.prank(OWNER);
        position.add(_encodeAdd(_addParams(collateralAmount, 0, 0, minFrxOut, minLpOut)));
    }

    function _addWithBorrow(uint256 collateralAmount, uint256 borrowAssets) internal returns (uint256 lpStaked) {
        if (collateralAmount > 0) {
            _mintCollateralToOwner(collateralAmount);
        }

        (uint128 totalBorrowedAssetsBefore,) = mintMarket.totalBorrowed();
        uint256 borrowSharesBefore = _marketPosition().borrowShares;

        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);

        vm.recordLogs();
        vm.prank(OWNER);
        position.add(_encodeAdd(_addParams(collateralAmount, borrowAssets, amountIn, minFrxOut, minLpOut)));

        (uint128 totalBorrowedAssetsAfter,) = mintMarket.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);
        assertGt(_marketPosition().borrowShares, borrowSharesBefore);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.AddPosition.selector) {
                (,, lpStaked) = abi.decode(logs[i].data, (uint256, uint256, uint256));
                break;
            }
        }
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

    function _fundRewards(uint256 crvAmount, uint256 cvxAmount) internal {
        crv.mint(address(convexRewardPool), crvAmount);
        cvx.mint(address(convexRewardPool), cvxAmount);
    }

    function _governanceLiquidatePosition(address user) internal {
        vm.prank(OWNER);
        mintMarket.governanceLiquidate(user, true);
    }

    function _zeroMarketCollateralKeepDebt(address user) internal {
        uint256 baseSlot = uint256(keccak256(abi.encode(user, POSITION_MAPPING_SLOT)));
        vm.store(address(mintMarket), bytes32(baseSlot + 1), bytes32(uint256(0)));
    }
}

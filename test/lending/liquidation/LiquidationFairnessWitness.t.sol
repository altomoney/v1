// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Fork} from "@alto-test/helpers/Fork.sol";

/// @notice Witnesses the accepted DLB/DCF fee model: the liquidation fee is charged on the
/// position's total collateral before the close factor sets how much debt is repaid, so a
/// liquidator's gain can exceed a fee computed on the repaid debt alone. The audit reports
/// document this and the team accepts it by design; these tests pin the behavior down.
import {Test} from "forge-std/Test.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {LiquidationEngineInput, LiquidationEngineResult} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {Position, Balance} from "@alto/lending/interfaces/IMarket.sol";

contract LiquidationFairnessMockMarket {
    uint256 public maxLtv;
    address public feeRecipient;
    DlbDcfPriorityLiquidationEngine public engine;

    constructor(uint256 _maxLtv, address _feeRecipient) {
        maxLtv = _maxLtv;
        feeRecipient = _feeRecipient;
    }

    function bind(DlbDcfPriorityLiquidationEngine _engine) external {
        engine = _engine;
        engine.setMarketOnce(address(this));
    }

    function prepare(LiquidationEngineInput memory input) external returns (LiquidationEngineResult memory) {
        return engine.prepareLiquidation(input);
    }
}

contract LiquidationFairnessWitnessTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant ORACLE_PREC = 1e36;

    uint256 internal constant MAX_LTV = 0.8e18;
    uint256 internal constant LLTV = 0.85e18;
    uint256 internal constant BONUS_START = 0.02e18;
    uint256 internal constant TLLTV = 0.93e18;
    uint256 internal constant STEEPNESS = 5e18;
    uint256 internal constant BASE_FEE = 0.05e18;
    uint256 internal constant MIN_PENALTY = 0.005e18;
    uint256 internal constant PROTOCOL_FEE = 0.07e18;

    uint256 internal constant MAX_FEE = BONUS_START + BASE_FEE;
    uint256 internal constant LIVE_WETH_PRICE = 1996319217840000000000000000000000000000;
    address internal constant LIVE_WETH_MARKET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address internal constant LIVE_WETH_ENGINE = 0x984E3D783E78ac5c5192CaEB562bE84306724A86;

    DlbDcfPriorityLiquidationEngine internal engine;
    LiquidationFairnessMockMarket internal market;

    function _deploy() internal {
        engine = new DlbDcfPriorityLiquidationEngine(address(this));
        market = new LiquidationFairnessMockMarket(MAX_LTV, address(0xFEE));
        market.bind(engine);

        engine.setLiquidationConfiguration(
            LiquidationConfiguration({
                maxLiquidationLtv: LLTV,
                dynamicBonusFeeStart: BONUS_START,
                ltvForCompleteLiquidation: TLLTV,
                dynamicBonusFeeDecaySteepness: STEEPNESS,
                liquidationBaseFee: BASE_FEE,
                minPenaltyPercentage: MIN_PENALTY,
                protocolFeePercentage: PROTOCOL_FEE,
                isEnabledPriorityLiquidation: false,
                disablePriorityLiquidationAbovePositionLtv: 0,
                priorityLiquidationGracePeriod: 0,
                taggerLiquidationGracePeriod: 0,
                liquidationWindowTag: 0
            })
        );
    }

    function _input(uint128 collateralAssets, uint128 borrowShares, uint256 price)
        internal
        pure
        returns (LiquidationEngineInput memory input)
    {
        input.borrower = address(0xB0B);
        input.liquidator = address(0x111D);
        input.totalBorrowed = Balance({assets: borrowShares, shares: borrowShares});
        input.totalSupply = Balance({assets: borrowShares, shares: borrowShares});
        input.position = Position({supplyShares: 0, borrowShares: borrowShares, collateralAssets: collateralAssets});
        input.maxLtv = MAX_LTV;
        input.collateralPrice = price;
    }

    function test_feeOnTotalCollateral_Witness() public {
        _deploy();

        uint128 collateral = 10e18;
        uint256 price = 2000e36;
        uint256 collateralValue = (uint256(collateral) * price) / ORACLE_PREC;
        uint256 currentLtv = 0.86e18;
        uint128 borrowShares = uint128((collateralValue * currentLtv) / WAD);

        LiquidationEngineResult memory r = market.prepare(_input(collateral, borrowShares, price));

        uint256 seizedValue = (r.seizedCollateralAssets * price) / ORACLE_PREC;
        uint256 repaidValue = r.repaidBorrowAmount;
        uint256 gross = seizedValue - repaidValue;
        uint256 repaidFeeCap = (repaidValue * MAX_FEE) / WAD;
        uint256 actualFee = collateralValue == 0 ? 0 : (gross * WAD) / collateralValue;
        uint256 feeOnRepaid = (repaidValue * actualFee) / WAD;
        uint256 excessOverRepaidFee = gross > feeOnRepaid ? gross - feeOnRepaid : 0;

        _log("collateralValue", collateralValue);
        _log("repaidValue", repaidValue);
        _log("seizedValue", seizedValue);
        _log("grossGainAboveRepaid (before split)", gross);
        _log("feeOnRepaid (repaid*actualFee)", feeOnRepaid);
        _log("excessOverRepaidFee (fee on total collateral minus fee on repaid)", excessOverRepaidFee);
        _log("repaidFeeCap (repaid*MAX_FEE)", repaidFeeCap);

        assert(gross > repaidFeeCap);
        assert(excessOverRepaidFee > 0);
    }

    function test_liveDeployedWethEngine_Witness() public {
        if (!vm.envOr("RUN_LIVE_FORK", false)) return;

        Fork.selectEthereum();

        uint128 collateral = 10e18;
        uint256 collateralValue = (uint256(collateral) * LIVE_WETH_PRICE) / ORACLE_PREC;
        uint128 borrowShares = uint128((collateralValue * 0.86e18) / WAD);

        vm.prank(LIVE_WETH_MARKET);
        LiquidationEngineResult memory r = DlbDcfPriorityLiquidationEngine(LIVE_WETH_ENGINE)
            .prepareLiquidation(_input(collateral, borrowShares, LIVE_WETH_PRICE));

        uint256 seizedValue = (r.seizedCollateralAssets * LIVE_WETH_PRICE) / ORACLE_PREC;
        uint256 repaidValue = r.repaidBorrowAmount;
        uint256 gross = seizedValue - repaidValue;
        uint256 repaidFeeCap = (repaidValue * MAX_FEE) / WAD;
        uint256 actualFee = collateralValue == 0 ? 0 : (gross * WAD) / collateralValue;
        uint256 feeOnRepaid = (repaidValue * actualFee) / WAD;
        uint256 excessOverRepaidFee = gross > feeOnRepaid ? gross - feeOnRepaid : 0;

        _log("live.repaidValue", repaidValue);
        _log("live.seizedValue", seizedValue);
        _log("live.grossGainAboveRepaid (before split)", gross);
        _log("live.feeOnRepaid", feeOnRepaid);
        _log("live.excessOverRepaidFee", excessOverRepaidFee);
        _log("live.repaidFeeCap", repaidFeeCap);

        assert(gross > repaidFeeCap);
        assert(excessOverRepaidFee > 0);
    }

    function testFuzz_liquidatorGainExceedsFeeOnRepaidForPartialLiquidations(
        uint128 collateral,
        uint256 price,
        uint256 ltvOffset
    ) public {
        _deploy();

        collateral = uint128(bound(uint256(collateral), 1e15, 1e28));
        price = bound(price, 1e34, 1e42);
        uint256 currentLtv = LLTV + bound(ltvOffset, 1e12, 1e15);

        uint256 collateralValue = (uint256(collateral) * price) / ORACLE_PREC;
        uint256 debt = (collateralValue * currentLtv) / WAD;
        uint128 borrowShares = uint128(debt);

        LiquidationEngineResult memory r = market.prepare(_input(collateral, borrowShares, price));

        uint256 seizedValue = (r.seizedCollateralAssets * price) / ORACLE_PREC;
        uint256 gain = seizedValue - r.repaidBorrowAmount;
        uint256 repaidFeeCap = (r.repaidBorrowAmount * MAX_FEE) / WAD;

        assertGt(r.repaidBorrowAmount, 0);
        assertGt(gain, repaidFeeCap);
    }

    function test_feeWithoutRepayment_Witness() public {
        _deploy();

        uint128 collateral = 2000;
        uint256 price = 5e32;
        uint128 borrowShares = 5;

        LiquidationEngineResult memory r = market.prepare(_input(collateral, borrowShares, price));

        _log("seizedCollateralAssets", r.seizedCollateralAssets);
        _log("repaidBorrowAmount", r.repaidBorrowAmount);

        assert(r.repaidBorrowAmount == 0);
        assert(r.seizedCollateralAssets > 0);
    }

    function test_fullSeizureAboveCompleteLiquidationLtv_Witness() public {
        _deploy();

        uint128 collateral = 10e18;
        uint256 price = 2000e36;
        uint256 collateralValue = (uint256(collateral) * price) / ORACLE_PREC;
        uint256 currentLtv = 0.98e18;
        uint128 borrowShares = uint128((collateralValue * currentLtv) / WAD);

        LiquidationEngineResult memory r = market.prepare(_input(collateral, borrowShares, price));

        uint256 debt = borrowShares;
        uint256 impliedBadDebt = debt > r.repaidBorrowAmount ? debt - r.repaidBorrowAmount : 0;

        _log("collateralValue", collateralValue);
        _log("debt", debt);
        _log("seizedCollateral", r.seizedCollateralAssets);
        _log("repaidValue", r.repaidBorrowAmount);
        _log("impliedSupplierBadDebt", impliedBadDebt);

        assert(collateralValue > debt);
        assert(r.seizedCollateralAssets == collateral);
        assert(impliedBadDebt > 0);
    }

    event Log(string k, uint256 v);

    function _log(string memory k, uint256 v) internal {
        emit Log(k, v);
    }
}

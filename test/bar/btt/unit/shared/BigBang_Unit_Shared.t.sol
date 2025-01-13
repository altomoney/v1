// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// external
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

// mocks
import {ZeroXSwapperMockTarget_test} from "../../mocks/ZeroXSwapperMockTarget_test.sol";
import {LeverageExecutorMock_test} from "../../mocks/LeverageExecutorMock_test.sol";
import {OracleMock_test} from "../../mocks/OracleMock_test.sol";

// Tapioca
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {BBCollateral} from "tapioca-bar/markets/bigBang/BBCollateral.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Market} from "tapioca-bar/markets/Market.sol";

import {Module} from "tap-utils/interfaces/bar/IMarket.sol";

import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IMarket} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

import {TOFTMock_test} from "../../mocks/TOFTMock_test.sol";

// tests
import {Markets_Unit_Shared} from "./Markets_Unit_Shared.t.sol";

import "forge-std/console.sol";

abstract contract BigBang_Unit_Shared is Markets_Unit_Shared {
    using RebaseLibrary for Rebase;

    // ************ //
    // *** VARS *** //
    // ************ //
    OracleMock_test assetOracle; // BigBang assets oracle (USDC <> USDO equivalent)
    BBDebtRateHelper debtHelper; // BigBang Debt rate helper

    BigBang bbMc;
    BigBang mainBB;
    BigBang secondaryBB;

    error Test_Error_Invalid_Amount();

    // ************* //
    // *** SETUP *** //
    // ************* //
    function setUp() public virtual override {
        super.setUp();

        // create default BigBang oracle
        assetOracle = _createOracle("Asset oracle");

        // create default BB master contract
        bbMc = new BigBang();
        penrose.registerBigBangMasterContract(address(bbMc), IPenrose.ContractType.lowRisk);

        // create BBDebtRateHelper
        debtHelper = new BBDebtRateHelper();

        // create main BB market
        // it handles after deployment set-up
        mainBB = BigBang(payable(_registerBBMarket(address(mainToken), true)));

        // create another BB market
        // it handles after deployment set-up
        secondaryBB = BigBang(payable(_registerBBMarket(address(randomCollateral), false)));
    }

    // ***************** //
    // *** MODIFIERS *** //
    // ***************** //
    modifier whenContractIsNotPaused() {
        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        mainBB.updatePauseAll(false);
        secondaryBB.updatePauseAll(false);
        _;
    }

    modifier whenContractIsPaused() {
        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        mainBB.updatePauseAll(true);
        secondaryBB.updatePauseAll(true);
        _;
    }

    modifier whenCollateralAmountIsValid(uint256 collateralAmount) {
        uint256 minCollateralAmount = mainBB._minCollateralAmount();
        vm.assume(collateralAmount > minCollateralAmount && collateralAmount < LARGE_AMOUNT);
        _;
    }

    modifier whenOracleRateIsEth() {
        oracle.set(5e14); // 2000$
        _;
    }

    modifier whenAssetOracleRateIsBelowMin() {
        assetOracle.set(1e18 - 1);
        _;
    }

    modifier whenAssetOracleRateIsAfterMin() {
        assetOracle.set(1e18 + 1);
        _;
    }

    // TODO Do we need to remove it?
    modifier whenHasLeverageDownApproval(address txExecutor) {
        _resetPrank(txExecutor);

        _;
    }

    modifier givenBorrowCapIsNotReachedYet() {
        // no cap
        assertEq(mainBB._totalBorrowCap(), 0);
        assertEq(secondaryBB._totalBorrowCap(), 0);
        _;
    }

    // **************** //
    // *** INTERNAL *** //
    // **************** //
    // // Takes `mainBB` CR rate into account
    function _boundBorrowAmount(uint256 borrowAmount, uint256 collateralAmount) internal view returns (uint256) {
        uint256 minBorrowAmount = mainBB._minBorrowAmount();
        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(mainBB)));
        if (minBorrowAmount > maxBorrowAmount) revert Test_Error_Invalid_Amount();
        // assure a 10% threshold for insolvency
        maxBorrowAmount = maxBorrowAmount - (maxBorrowAmount * 1e4 / 1e5);
        borrowAmount = bound(borrowAmount, minBorrowAmount + 1, maxBorrowAmount - 1);
        return borrowAmount;
    }

    function _boundLeverageDownAmount(uint256 leverageAmount, BigBang bb) internal view returns (uint256) {
        uint256 collateralShare = bb.balanceOf(address(this));
        uint256 collateralAmount = bb.convertToAssets(collateralShare);
        leverageAmount = bound(leverageAmount, 1, collateralAmount);
        return leverageAmount;
    }

    function _boundLeverageUpAmount(uint256 leverageAmount, BigBang bb) internal view returns (uint256) {
        uint256 collateralShare = bb.balanceOf(address(this));
        uint256 collateralAmount = bb.convertToAssets(collateralShare);

        uint256 borrowPart = bb._userBorrowPart(address(this));
        Rebase memory _totalBorrowed = bb._totalBorrow();
        uint256 borrowAmount = _totalBorrowed.toElastic(borrowPart, true);
        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(mainBB)));
        uint256 minBorrowAmount = bb._minBorrowAmount();

        leverageAmount = bound(leverageAmount, minBorrowAmount, maxBorrowAmount - borrowAmount);
        return leverageAmount;
    }

    function _boundRemoveCollateralAmount(uint256 removeAmount, BigBang bb) internal view returns (uint256) {
        // get collateral amount
        uint256 collateralShare = bb.balanceOf(address(this));
        uint256 collateralAmount = bb.convertToAssets(collateralShare);

        // get borrowed and max borrowable
        uint256 borrowPart = bb._userBorrowPart(address(this));
        Rebase memory _totalBorrowed = bb._totalBorrow();
        uint256 borrowAmount = _totalBorrowed.toElastic(borrowPart, true);
        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(mainBB)));

        // transform borrowable left into collateral
        (, uint256 rate) = oracle.peek("");
        uint256 remainingBorrowableAmount = maxBorrowAmount - borrowAmount;
        uint256 removableCollateral = (remainingBorrowableAmount * rate) / bb._exchangeRatePrecision();
        // assure a 10% threshold for insolvency
        removableCollateral = removableCollateral - (removableCollateral * 1e4 / 1e5);
        removeAmount = bound(removeAmount, 1, removableCollateral);
        return removeAmount;
    }

    function _boundRepayAmount(uint256 repayPart, BigBang bb) internal view returns (uint256) {
        uint256 userBorrowPart = bb._userBorrowPart(address(this));

        // assure a 10% threshold for repayment
        userBorrowPart = userBorrowPart - (userBorrowPart * 1e4 / 1e5);
        // if values are too low, method is still executed successfully, but can't really verify the results
        // repay at least `minBorrowAmount`; otherwise values might be too small to count
        repayPart = bound(repayPart, userBorrowPart / 2, userBorrowPart);
        return repayPart;
    }

    function _spawnCollateral(uint256 _collateralAmount, address _to) internal {
        deal(mainBB.collateral(), _to, _collateralAmount);
        deal(secondaryBB.collateral(), _to, _collateralAmount);
    }

    function _spawnAsset(uint256 _assetAmount, address _to) internal {
        // cannot use `deal` because it can overflow supply on `burn` in some cases
        usdo.setMinterStatus(address(this), true);
        usdo.mint(_to, _assetAmount);

        // deal(address(mainBB._asset()), _to, _assetAmount);
    }

    function _getCollateralData(uint256 _collateralAmount, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = marketHelper.addCollateral(_from, _to, _collateralAmount, 0);
    }

    function _getRemoveCollateralData(uint256 _collateralShare, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = marketHelper.removeCollateral(_from, _to, _collateralShare);
    }

    function _getBorrowData(uint256 _borrowAmount, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = marketHelper.borrow(_from, _to, _borrowAmount);
    }

    function _getRepayData(uint256 _repayPart, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = marketHelper.repay(_from, _to, _repayPart);
    }

    // uses `mainBB` to convert amount to shares
    function _getLeverageDownData(uint256 _leverageAmount, address _from)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        uint256 share = mainBB.convertToShares(_leverageAmount);
        bytes memory leverageData = abi.encode(_leverageAmount);
        (modules, calls) = marketHelper.sellCollateral(_from, share, leverageData);
    }

    function _getLeverageUpData(uint256 _borrowAmount, uint256 _supplyAmount, address _from)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        bytes memory leverageData = abi.encode(_borrowAmount);
        (modules, calls) = marketHelper.buyCollateral(_from, _borrowAmount, _supplyAmount, leverageData);
    }

    function _getLiquidateBadDebtData(
        address user,
        address from,
        address receiver,
        bytes memory liquidatorData,
        bool swapCollateral
    ) internal view returns (Module[] memory modules, bytes[] memory calls) {
        (modules, calls) = marketHelper.liquidateBadDebt(
            user, from, receiver, IMarketLiquidatorReceiver(address(liquidatorReceiver)), liquidatorData, swapCollateral
        );
    }

    function _getLiquidationData(address user, bytes memory liquidatorData, uint256 amount, uint256 liquidationBonus)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        address[] memory users = new address[](1);
        users[0] = user;

        uint256[] memory borrowParts = new uint256[](1);
        borrowParts[0] = amount;

        uint256[] memory minLiquidationBonuses = new uint256[](1);
        minLiquidationBonuses[0] = liquidationBonus;

        IMarketLiquidatorReceiver[] memory receivers = new IMarketLiquidatorReceiver[](1);
        receivers[0] = IMarketLiquidatorReceiver(address(liquidatorReceiver));

        bytes[] memory receiverData = new bytes[](1);
        receiverData[0] = liquidatorData;

        (modules, calls) = marketHelper.liquidate(users, borrowParts, minLiquidationBonuses, receivers, receiverData);
    }

    function _approveBorrow(BigBang bb, address from, address to, uint256 share) internal resetPrank(from) {
        bb.approveBorrow(to, share);
    }

    function _addCollateral(uint256 collateralAmount, BigBang bb, address executor, address from, address to)
        internal
        returns (uint256 share)
    {
        {
            // deal collateral
            _spawnCollateral(collateralAmount, from);
        }

        share = bb.convertToShares(collateralAmount);

        _resetPrank(from);
        if (executor != from) {
            _approveViaERC20(bb.collateral(), from, address(bb), collateralAmount);
            bb.approveCollateral(executor, collateralAmount);
        } else {
            _approveViaERC20(bb.collateral(), from, address(bb), collateralAmount);
        }

        // get `before` state
        uint256 bbTotalAssetsBefore = bb.totalAssets();
        uint256 userCollateralBalanceBefore = IERC20(bb.collateral()).balanceOf(address(from));
        uint256 userCollateralSharesBefore = bb.balanceOf(to);
        uint256 totalCollateralShareBefore = bb.totalSupply();

        {
            (Module[] memory modules, bytes[] memory calls) = _getCollateralData(collateralAmount, from, to);

            _resetPrank(executor);
            // it should emit 'LogAddCollateral'
            vm.expectEmit(true, true, true, false);
            emit LogAddCollateral(from, to, share);
            bb.execute(modules, calls, true);
        }

        // checks
        {
            // get `after` state
            uint256 bbTotalAssetsAfter = bb.totalAssets();
            uint256 userCollateralBalanceAfter = IERC20(bb.collateral()).balanceOf(address(from));
            // it should increase 'userCollateralShare'
            uint256 resultedCollateral = bb.balanceOf(to);
            assertEq(resultedCollateral, userCollateralSharesBefore + share, "User collateral share invalid");

            // it should increase 'totalCollateralShare'
            uint256 totalSupplyShareAfter = bb.totalSupply();
            assertEq(totalSupplyShareAfter, totalCollateralShareBefore + share, "Total supply invalid");

            // it should increase market's balance
            assertEq(bbTotalAssetsBefore + collateralAmount, bbTotalAssetsAfter, "Total assets invalid");
            // it should decrease user's balance for collateral token
            assertEq(
                userCollateralBalanceBefore - collateralAmount,
                userCollateralBalanceAfter,
                "User collateral balance invalid"
            );
        }
    }

    // to avoid stack too deep
    struct _BorrowInternal {
        Rebase totalBorrowAfter;
        Rebase totalBorrowBefore;
        uint256 userBorrowPartBefore;
        uint256 userBorrowPartAfter;
        uint256 userYieldBoxBalanceBefore;
        uint256 userYieldBoxBalanceAfter;
        uint256 usdoSupplyBefore;
        uint256 usdoSupplyAfter;
        uint256 feeAmount;
    }

    function _borrow(uint256 borrowAmount, BigBang bb, address executor, address from, address to)
        internal
        resetPrank(executor)
    {
        _BorrowInternal memory _data = _createBorrowInternal(bb, to);

        uint256 feeAmount = bb.computeVariableOpeningFee(borrowAmount);
        (Module[] memory modules, bytes[] memory calls) = _getBorrowData(borrowAmount, from, to);

        // it should emit LogBorrow
        vm.expectEmit(true, true, true, false);
        emit LogBorrow(from, to, borrowAmount, feeAmount, borrowAmount + feeAmount);
        bb.execute(modules, calls, true);

        {
            // get `after` state
            _data.totalBorrowAfter = bb._totalBorrow();
            _data.userBorrowPartAfter = bb._userBorrowPart(to);
            _data.userYieldBoxBalanceAfter = IERC20(bb.borrowableToken()).balanceOf(address(to));

            // it should increase 'userBorrowPart'
            assertGt(_data.userBorrowPartAfter, _data.userBorrowPartBefore);

            // it should increase user's YieldBox position
            assertGt(_data.userYieldBoxBalanceAfter, _data.userYieldBoxBalanceBefore);
            assertEq(_data.userYieldBoxBalanceAfter, _data.userYieldBoxBalanceBefore + borrowAmount);

            // it should increase 'totalBorrow.base'
            assertGt(_data.totalBorrowAfter.base, _data.totalBorrowBefore.base);

            // it should increase 'totalBorrow.elastic'
            assertGt(_data.totalBorrowAfter.elastic, _data.totalBorrowBefore.elastic);

            // it should increase usdo supply
            _data.usdoSupplyAfter = usdo.totalSupply();
            assertEq(_data.usdoSupplyAfter, _data.usdoSupplyBefore + borrowAmount);

            if (feeAmount == 0) {
                // accrual taken into account
                assertApproxEqRel(_data.userBorrowPartAfter, _data.userBorrowPartBefore + borrowAmount, 0.01e18);
            } else {
                // accrual taken into account
                assertApproxEqRel(
                    _data.userBorrowPartAfter, _data.userBorrowPartBefore + borrowAmount + feeAmount, 0.01e18
                );
            }
        }
    }

    struct _RemoveCollateralInternal {
        uint256 bbYieldBoxBalanceBefore;
        uint256 userYieldBoxBalanceBefore;
        uint256 userCollateralBefore;
        uint256 totalCollateralShareBefore;
        uint256 bbYieldBoxBalanceAfter;
        uint256 userYieldBoxBalanceAfter;
        uint256 userCollateralAfter;
        uint256 totalCollateralShareAfter;
    }

    function _createRemoveCollateralInternal(BigBang _bb, address _to)
        internal
        returns (_RemoveCollateralInternal memory)
    {
        _RemoveCollateralInternal memory _data;
        _data.bbYieldBoxBalanceBefore = _bb.totalAssets();
        _data.userYieldBoxBalanceBefore = IERC20(IMarket(address(_bb)).collateral()).balanceOf(address(_to));
        _data.userCollateralBefore = _bb.balanceOf(_to);
        _data.totalCollateralShareBefore = _bb._totalCollateralShare();
        return _data;
    }

    function _executeRemoveCollateral(uint256 _removeShare, BigBang _bb, address _executor, address _from, address _to)
        internal
        returns (uint256 finalRemoveShares, uint256 removeAmount)
    {
        uint256 _removeAmount = 0;
        uint256 removeAmount = _boundRemoveCollateralAmount(_removeAmount, _bb);
        _removeShare = _bb.convertToShares(removeAmount);
        (Module[] memory _modules, bytes[] memory _calls) = _getRemoveCollateralData(_removeShare, _from, _to);

        vm.expectEmit(true, true, true, false);
        // it should emit 'LogRemoveCollateral'
        emit LogRemoveCollateral(_from, _to, _removeShare);

        _resetPrank(_executor);

        _bb.execute(_modules, _calls, true);

        return (_removeShare, _removeAmount);
    }

    function _removeCollateral(
        uint256 addAmount,
        uint256 removeShare,
        uint256 borrowAmount,
        BigBang bb,
        address executor,
        address from,
        address to
    ) internal {
        // **** Add collateral ****
        _addCollateral(addAmount, bb, executor, from, to);

        // **** Borrow ****
        borrowAmount = _boundBorrowAmount(borrowAmount, addAmount);
        if (borrowAmount > 0) {
            _borrow(borrowAmount, bb, executor, from, to);
        }

        // **** Remove collateral ****
        _RemoveCollateralInternal memory _data = _createRemoveCollateralInternal(bb, to);

        (uint256 boundedRemoveShares, uint256 removeAmount) =
            _executeRemoveCollateral(removeShare, bb, executor, from, to);

        _data.bbYieldBoxBalanceAfter = bb.totalAssets();
        _data.userYieldBoxBalanceAfter = IERC20(bb.collateral()).balanceOf(address(to));
        _data.userCollateralAfter = bb.balanceOf(to);
        _data.totalCollateralShareAfter = bb._totalCollateralShare();

        // it should decrease 'userCollateralShare'
        assertEq(_data.userCollateralBefore - boundedRemoveShares, _data.userCollateralAfter, "userCollateral check");

        // it should decrease 'totalCollateralShare'
        assertEq(
            _data.totalCollateralShareBefore - boundedRemoveShares,
            _data.totalCollateralShareAfter,
            "totalCollateral check"
        );

        // it should decrease market's YieldBox balance
        assertApproxEqAbs(
            _data.bbYieldBoxBalanceBefore - removeAmount, _data.bbYieldBoxBalanceAfter, 1, "bb internal balance check"
        );

        console.log(_data.userYieldBoxBalanceBefore, removeAmount, _data.userYieldBoxBalanceAfter);
        // it should increase user's YieldBox balance
        assertApproxEqAbs(
            _data.userYieldBoxBalanceBefore + removeAmount, _data.userYieldBoxBalanceAfter, 1, "user balance check"
        );
    }

    function _addCollateralAndBorrow(
        uint256 collateralAmount,
        uint256 borrowAmount,
        BigBang bb,
        address from,
        address to
    ) internal returns (uint256 borrowedAmount) {
        // **** Add collateral ****
        _addCollateral(collateralAmount, bb, address(this), from, to);

        // **** Borrow ****
        borrowedAmount = _boundBorrowAmount(borrowAmount, collateralAmount);
        _borrow(borrowedAmount, bb, address(this), from, to);

        skip(86400 * 10);

        bb.accrue();
    }

    function _createBorrowInternal(BigBang _bb, address _to) internal returns (_BorrowInternal memory) {
        _BorrowInternal memory _data;
        // get `before` state
        _data.totalBorrowBefore = _bb._totalBorrow();
        _data.userBorrowPartBefore = _bb._userBorrowPart(_to);
        _data.userYieldBoxBalanceBefore = IERC20(_bb.borrowableToken()).balanceOf(address(_to));
        _data.usdoSupplyBefore = usdo.totalSupply();
        return _data;
    }

    function _createRepayData(uint256 _repayPart, BigBang _bb, address _from, address _to)
        internal
        returns (Module[] memory modules, bytes[] memory calls, uint256 repayAmount)
    {
        _repayPart = _boundRepayAmount(_repayPart, _bb);
        Rebase memory _totalBorrow = _bb._totalBorrow();
        repayAmount = _totalBorrow.toElastic(_repayPart, false);
        (modules, calls) = _getRepayData(_repayPart, _from, _to);
    }

    function _repay(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 repayPart,
        BigBang bb,
        address executor,
        address from,
        address to
    ) internal {
        vm.startPrank(executor);
        uint256 borrowedAmount = _addCollateralAndBorrow(collateralAmount, borrowAmount, bb, from, to);

        _BorrowInternal memory _data = _createBorrowInternal(bb, to);

        (Module[] memory modules, bytes[] memory calls, uint256 repayAmount) = _createRepayData(repayPart, bb, from, to);

        // it should emit 'LogAccrue'
        // it should emit 'ReaccruedMarkets'
        //        │   │   │   ├─ emit LogAccrue(accruedAmount: 0, rate: 158440439 [1.584e8])
        // │   │   │   │   │   │   └─ ← [Stop]
        // │   │   │   │   │   └─ ← [Return]
        // │   │   │   │   ├─ emit ReaccruedMarkets(mainMarketIncluded: false)
        // it should emit 'LogRepay'
        usdo.approve(address(bb), type(uint256).max);
        vm.expectEmit(true, true, false, false);
        emit LogRepay(from, to, repayAmount, repayPart);
        bb.execute(modules, calls, true);

        vm.stopPrank();

        // get `after` state
        _data.totalBorrowAfter = bb._totalBorrow();
        _data.userBorrowPartAfter = bb._userBorrowPart(to);
        _data.userYieldBoxBalanceAfter = IERC20(bb.borrowableToken()).balanceOf(address(to));
        _data.usdoSupplyAfter = usdo.totalSupply();

        // it should decrease 'userBorrowPart'
        assertGt(_data.userBorrowPartBefore, _data.userBorrowPartAfter, "A");

        // it should burn asset's supply
        assertGt(_data.usdoSupplyBefore, _data.usdoSupplyAfter, "b");

        // it should decrease 'totalBorrow.base'
        assertGt(_data.totalBorrowBefore.base, _data.totalBorrowAfter.base, "c");

        // it should decrease 'totalBorrow.elastic'
        assertGt(_data.totalBorrowBefore.elastic, _data.totalBorrowAfter.elastic, "D");
    }

    struct _LiquidateInternal {
        // TODO Rename properties
        uint256 bbYieldBoxAssetBalanceBefore;
        uint256 bbYieldBoxAssetBalanceAfter;
        uint256 bbYieldBoxCollateralBalanceBefore;
        uint256 bbYieldBoxCollateralBalanceAfter;
        uint256 userAssetYieldBoxBalanceBefore;
        uint256 userAssetYieldBoxBalanceAfter;
        uint256 userCollateralYieldBoxBalanceBefore;
        uint256 userCollateralYieldBoxBalanceAfter;
        uint256 userCollateralBefore;
        uint256 userCollateralAfter;
        uint256 totalCollateralShareBefore;
        uint256 totalCollateralShareAfter;
        uint256 userBorrowPartBefore;
        uint256 userBorrowPartAfter;
        Rebase totalBorrowBefore;
        Rebase totalBorrowAfter;
        uint256 supplyFromBefore;
        uint256 supplyFromAfter;
        uint256 assetBalanceReceiverBefore;
        uint256 assetBalanceReceiverAfter;
        uint256 collateralBalanceReceiverBefore;
        uint256 collateralBalanceReceiverAfter;
    }

    function _liquidate(
        uint256 collateralAmount,
        uint256 oracleRate,
        uint256 swapAmount,
        BigBang bb,
        uint256 liquidationBonus
    ) internal whenOracleRateIsEth {
        // **** Add collateral ****
        _resetPrank(address(this));
        _addCollateral(collateralAmount, bb, address(this), address(this), address(this));

        // **** Borrow ****
        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(bb)));
        maxBorrowAmount = maxBorrowAmount - (maxBorrowAmount * 2e4 / 1e5);
        _resetPrank(address(this));
        _borrow(maxBorrowAmount, bb, address(this), address(this), address(this));

        _LiquidateInternal memory _data;
        // get `before` state
        _data.bbYieldBoxAssetBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(bb));
        _data.bbYieldBoxCollateralBalanceBefore = bb.totalAssets();
        _data.userAssetYieldBoxBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(this));
        _data.userCollateralYieldBoxBalanceBefore = IERC20(bb.collateral()).balanceOf(address(this));
        _data.userCollateralBefore = bb.balanceOf(address(this));
        _data.totalCollateralShareBefore = bb._totalCollateralShare();
        _data.userBorrowPartBefore = bb._userBorrowPart(address(this));
        _data.totalBorrowBefore = bb._totalBorrow();
        _data.supplyFromBefore = usdo.totalSupply();

        // set liquidation rate
        oracle.set(oracleRate);

        // compute asset amount
        SZeroXSwapData memory szeroXSwapData = SZeroXSwapData({
            sellToken: TOFTMock_test(payable(IMarket(address(bb)).collateral())).erc20(),
            buyToken: address(IMarket(address(bb))._asset()),
            swapTarget: payable(swapperTarget),
            swapCallData: abi.encodeWithSelector(
                ZeroXSwapperMockTarget_test.transferTokens.selector, address(IMarket(address(bb))._asset()), swapAmount
            )
        });
        SSwapData memory sswapData = SSwapData({minAmountOut: 0, data: szeroXSwapData});
        bytes memory swapData = abi.encode(sswapData);

        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidationData(address(this), swapData, maxBorrowAmount, liquidationBonus);
        // it should emit 'Liquidated'
        vm.expectEmit(true, false, false, false);
        emit Liquidated(address(this), new address[](0), 0, 0, 0, 0);
        bb.execute(modules, calls, true);

        _data.bbYieldBoxAssetBalanceAfter = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(bb));
        _data.bbYieldBoxCollateralBalanceAfter = bb.totalAssets();
        _data.userAssetYieldBoxBalanceAfter = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(this));
        _data.userCollateralYieldBoxBalanceAfter = IERC20(bb.collateral()).balanceOf(address(this));
        _data.userCollateralAfter = bb.balanceOf(address(this));
        _data.totalCollateralShareAfter = bb._totalCollateralShare();
        _data.userBorrowPartAfter = bb._userBorrowPart(address(this));
        _data.totalBorrowAfter = bb._totalBorrow();
        _data.supplyFromAfter = usdo.totalSupply();

        // it should decrease 'userCollateralShare'
        assertGt(_data.userCollateralBefore, _data.userCollateralAfter);

        // it should decrease 'totalCollateralShare'
        assertGt(_data.totalCollateralShareBefore, _data.totalCollateralShareAfter);
        assertEq(
            _data.totalCollateralShareBefore - _data.totalCollateralShareAfter,
            _data.userCollateralBefore - _data.userCollateralAfter
        );

        // it should burn asset's supply
        assertGt(_data.supplyFromBefore, _data.supplyFromAfter);

        // it should decrease 'totalBorrow.base'
        assertGt(_data.totalBorrowBefore.base, _data.totalBorrowAfter.base);

        // it should decrease 'totalBorrow.elastic'
        assertGt(_data.totalBorrowBefore.elastic, _data.totalBorrowAfter.elastic);

        // it should decrease 'totalBorrow.elastic'
        assertGt(_data.userBorrowPartBefore, _data.userBorrowPartAfter);
    }

    function _liquidateFailsCollateral(
        uint256 collateralAmount,
        uint256 oracleRate,
        uint256 swapAmount,
        BigBang bb,
        uint256 liquidationBonus
    ) internal whenOracleRateIsEth {
        // **** Add collateral ****
        _resetPrank(address(this));
        _addCollateral(collateralAmount, bb, address(this), address(this), address(this));

        // **** Borrow ****
        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(bb)));
        maxBorrowAmount = maxBorrowAmount - (maxBorrowAmount * 2e4 / 1e5);
        _resetPrank(address(this));
        _borrow(maxBorrowAmount, bb, address(this), address(this), address(this));

        _LiquidateInternal memory _data;
        // get `before` state
        _data.bbYieldBoxAssetBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(bb));
        _data.bbYieldBoxCollateralBalanceBefore = bb.totalAssets();
        _data.userAssetYieldBoxBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(this));
        _data.userCollateralYieldBoxBalanceBefore = IERC20(bb.collateral()).balanceOf(address(this));
        _data.userCollateralBefore = bb.balanceOf(address(this));
        _data.totalCollateralShareBefore = bb._totalCollateralShare();
        _data.userBorrowPartBefore = bb._userBorrowPart(address(this));
        _data.totalBorrowBefore = bb._totalBorrow();
        _data.supplyFromBefore = usdo.totalSupply();

        // set liquidation rate
        oracle.set(oracleRate);

        // compute asset amount
        SZeroXSwapData memory szeroXSwapData = SZeroXSwapData({
            sellToken: TOFTMock_test(payable(IMarket(address(bb)).collateral())).erc20(),
            buyToken: address(IMarket(address(bb))._asset()),
            swapTarget: payable(swapperTarget),
            swapCallData: abi.encodeWithSelector(
                ZeroXSwapperMockTarget_test.transferTokens.selector, address(IMarket(address(bb))._asset()), swapAmount
            )
        });
        SSwapData memory sswapData = SSwapData({minAmountOut: 0, data: szeroXSwapData});
        bytes memory swapData = abi.encode(sswapData);

        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidationData(address(this), swapData, maxBorrowAmount, liquidationBonus);
        // it should revert 'OnCollateralReceiverFailed'
        vm.expectRevert();
        bb.execute(modules, calls, true);
    }

    function _liquidateBadDebt(
        uint256 collateralAmount,
        uint256 borrowAmount,
        BigBang bb,
        address from,
        address to,
        bool swapCollateral
    ) internal whenOracleRateIsEth {
        // **** Add collateral ****
        _resetPrank(address(this));
        _addCollateral(collateralAmount, bb, address(this), address(this), address(this));

        // **** Borrow ****
        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(bb)));
        // assure a 20% threshold for insolvency
        maxBorrowAmount = maxBorrowAmount - (maxBorrowAmount * 2e4 / 1e5);
        borrowAmount = maxBorrowAmount;
        _resetPrank(address(this));
        _borrow(borrowAmount, bb, address(this), address(this), address(this));

        _LiquidateInternal memory _data;
        // get `before` state
        _data.bbYieldBoxAssetBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(bb));
        _data.bbYieldBoxCollateralBalanceBefore = bb.totalAssets();
        _data.userAssetYieldBoxBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(this));
        _data.userCollateralYieldBoxBalanceBefore = IERC20(bb.collateral()).balanceOf(address(this));
        _data.userCollateralBefore = bb.balanceOf(address(this));
        _data.totalCollateralShareBefore = bb._totalCollateralShare();
        _data.userBorrowPartBefore = bb._userBorrowPart(address(this));
        _data.totalBorrowBefore = bb._totalBorrow();
        _data.assetBalanceReceiverBefore = usdo.balanceOf(to);
        _data.collateralBalanceReceiverBefore = IERC20(bb.collateral()).balanceOf(to);

        // **** Liquidate bad debt ****

        uint256 existingAmount = _data.totalBorrowBefore.toElastic(_data.userBorrowPartBefore, false);

        _spawnAsset(existingAmount * 2, from);

        _data.supplyFromBefore = usdo.balanceOf(address(this));

        oracle.set(SMALL_AMOUNT);

        bytes memory swapData;
        uint256 inAssetAmount;
        if (swapCollateral) {
            // compute asset amount
            (, uint256 rate) = oracle.peek("");
            uint256 _collateralAmount = bb.convertToAssets(_data.userCollateralBefore);
            inAssetAmount = (_collateralAmount * (bb._exchangeRatePrecision() / FEE_PRECISION)) / rate;

            SZeroXSwapData memory szeroXSwapData = SZeroXSwapData({
                sellToken: TOFTMock_test(payable(IMarket(address(bb)).collateral())).erc20(),
                buyToken: address(IMarket(address(bb))._asset()),
                swapTarget: payable(swapperTarget),
                swapCallData: abi.encodeWithSelector(
                    ZeroXSwapperMockTarget_test.transferTokens.selector,
                    address(IMarket(address(bb))._asset()),
                    inAssetAmount
                )
            });
            SSwapData memory sswapData = SSwapData({minAmountOut: 0, data: szeroXSwapData});
            swapData = abi.encode(sswapData);
        }

        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidateBadDebtData(address(this), from, to, swapData, swapCollateral);
        bb.execute(modules, calls, true);

        _data.bbYieldBoxAssetBalanceAfter = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(bb));
        _data.bbYieldBoxCollateralBalanceAfter = bb.totalAssets();
        _data.userAssetYieldBoxBalanceAfter = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(this));
        _data.userCollateralYieldBoxBalanceAfter = IERC20(bb.collateral()).balanceOf(address(this));
        _data.userCollateralAfter = bb.balanceOf(address(this));
        _data.totalCollateralShareAfter = bb._totalCollateralShare();
        _data.userBorrowPartAfter = bb._userBorrowPart(address(this));
        _data.totalBorrowAfter = bb._totalBorrow();
        _data.supplyFromAfter = usdo.balanceOf(address(this));
        _data.assetBalanceReceiverAfter = usdo.balanceOf(to);
        _data.collateralBalanceReceiverAfter = IERC20(bb.collateral()).balanceOf(to);

        // it should set 'userCollateralShare' to 0
        assertGt(_data.userCollateralBefore, _data.userCollateralAfter);
        assertEq(_data.userCollateralAfter, 0);

        // it should decrease 'totalCollateralShare'
        assertGt(_data.totalCollateralShareBefore, _data.totalCollateralShareAfter);
        assertEq(_data.totalCollateralShareAfter, _data.totalCollateralShareBefore - _data.userCollateralBefore);

        // it should set 'userBorrowPart' to 0
        assertGt(_data.userBorrowPartBefore, _data.userBorrowPartAfter);
        assertEq(_data.userBorrowPartAfter, 0);

        // it should decrease 'totalBorrow.base'
        assertGt(_data.totalBorrowBefore.base, _data.totalBorrowAfter.base);

        // it should decrease 'totalBorrow.elastic'
        assertGt(_data.totalBorrowBefore.elastic, _data.totalBorrowAfter.elastic);

        // it should burn asset from 'from'
        assertGt(_data.supplyFromBefore, _data.supplyFromAfter);

        if (swapCollateral) {
            assertGt(_data.assetBalanceReceiverAfter, _data.assetBalanceReceiverBefore);
            assertEq(_data.assetBalanceReceiverAfter, _data.assetBalanceReceiverBefore + inAssetAmount);
        } else {
            assertGt(_data.collateralBalanceReceiverAfter, _data.collateralBalanceReceiverBefore);
        }
    }

    // to avoid stack too deep
    struct _LeverageInternal {
        Rebase totalBorrowAfter;
        Rebase totalBorrowBefore;
        uint256 userBorrowPartBefore;
        uint256 userBorrowPartAfter;
        uint256 userYieldBoxBalanceBefore;
        uint256 userYieldBoxBalanceAfter;
        uint256 usdoSupplyBefore;
        uint256 usdoSupplyAfter;
        uint256 feeAmount;
        uint256 bbYieldBoxBalanceBefore;
        uint256 bbYieldBoxBalanceAfter;
        uint256 userCollateralBefore;
        uint256 userCollateralAfter;
        uint256 totalCollateralShareBefore;
        uint256 totalCollateralShareAfter;
    }

    function _leverageDown(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 leverageAmount,
        BigBang bb,
        address executor,
        address from,
        address to,
        bool full
    ) internal {
        // add collateral
        _addCollateral(collateralAmount, bb, from, from, to);

        // borrow
        _borrow(borrowAmount, bb, from, from, to);

        leverageAmount = full ? collateralAmount : _boundLeverageDownAmount(leverageAmount, bb);

        _LeverageInternal memory _data;
        _data.userCollateralBefore = bb.balanceOf(to);
        _data.totalCollateralShareBefore = bb._totalCollateralShare();
        _data.bbYieldBoxBalanceBefore = bb.totalAssets();

        _data.totalBorrowBefore = bb._totalBorrow();
        _data.userBorrowPartBefore = bb._userBorrowPart(to);
        _data.userYieldBoxBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(to));
        _data.usdoSupplyBefore = usdo.totalSupply();

        // leverage
        uint256 share = bb.convertToShares(leverageAmount);
        (Module[] memory modules, bytes[] memory calls) = _getLeverageDownData(leverageAmount, address(this));

        _resetPrank(executor);
        bb.execute(modules, calls, true);

        _data.userCollateralAfter = bb.balanceOf(to);
        _data.totalCollateralShareAfter = bb._totalCollateralShare();
        _data.bbYieldBoxBalanceAfter = bb.totalAssets();
        _data.totalBorrowAfter = bb._totalBorrow();
        _data.userBorrowPartAfter = bb._userBorrowPart(to);
        _data.userYieldBoxBalanceAfter = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(to));
        _data.usdoSupplyAfter = usdo.totalSupply();

        // it should decrease 'userCollateralShare'
        assertEq(_data.userCollateralBefore - share, _data.userCollateralAfter);

        // it should decrease 'totalCollateralShare'
        assertEq(_data.totalCollateralShareBefore - share, _data.totalCollateralShareAfter);

        // it should decrease asset's supply
        assertGt(_data.usdoSupplyBefore, _data.usdoSupplyAfter);

        if (full) {
            // it should empty 'userBorrowPart'
            assertEq(_data.userBorrowPartAfter, 0);
            assertGt(_data.userYieldBoxBalanceAfter, _data.userYieldBoxBalanceBefore);
        }

        // it should decrease 'userBorrowPart'
        assertGt(_data.userBorrowPartBefore, _data.userBorrowPartAfter);

        // it should decrease 'totalBorrow.base'
        // it should decrease 'totalBorrow.elastic'
        assertGt(_data.totalBorrowBefore.base, _data.totalBorrowAfter.base);
        assertGt(_data.totalBorrowBefore.elastic, _data.totalBorrowAfter.elastic);

        uint256 amount = _data.usdoSupplyBefore - _data.usdoSupplyAfter;
        assertEq(_data.totalBorrowBefore.base - _data.totalBorrowAfter.base, amount);
        assertEq(_data.userBorrowPartBefore - _data.userBorrowPartAfter, amount);
    }

    function _leverageUp(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 leverageAmount,
        uint256 supplyAmount,
        BigBang bb,
        address executor,
        address from,
        address to
    ) internal {
        // add collateral
        _addCollateral(collateralAmount, bb, from, from, to);

        // borrow
        _borrow(borrowAmount, bb, from, from, to);

        leverageAmount = _boundLeverageUpAmount(leverageAmount, bb);

        _LeverageInternal memory _data;
        _data.userCollateralBefore = bb.balanceOf(to);
        _data.totalCollateralShareBefore = bb._totalCollateralShare();
        _data.bbYieldBoxBalanceBefore = bb.totalAssets();

        _data.totalBorrowBefore = bb._totalBorrow();
        _data.userBorrowPartBefore = bb._userBorrowPart(to);
        _data.userYieldBoxBalanceBefore = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(to));
        _data.usdoSupplyBefore = usdo.totalSupply();

        // leverage
        (Module[] memory modules, bytes[] memory calls) =
            _getLeverageUpData(leverageAmount, supplyAmount, address(this));

        _resetPrank(executor);
        bb.execute(modules, calls, true);

        _data.userCollateralAfter = bb.balanceOf(to);
        _data.totalCollateralShareAfter = bb._totalCollateralShare();
        _data.bbYieldBoxBalanceAfter = bb.totalAssets();
        _data.totalBorrowAfter = bb._totalBorrow();
        _data.userBorrowPartAfter = bb._userBorrowPart(to);
        _data.userYieldBoxBalanceAfter = IERC20(IMarket(address(bb)).borrowableToken()).balanceOf(address(to));
        _data.usdoSupplyAfter = usdo.totalSupply();

        // it should increase asset supply
        assertGt(_data.usdoSupplyAfter, _data.usdoSupplyBefore);
        assertEq(_data.usdoSupplyAfter, _data.usdoSupplyBefore + leverageAmount);

        // it should increase 'userBorrowPart'
        assertGt(_data.userBorrowPartAfter, _data.userBorrowPartBefore);
        assertApproxEqRel(_data.userBorrowPartAfter, _data.userBorrowPartBefore + leverageAmount, 0.01e18);

        // it should increase 'totalBorrow.base'
        assertGt(_data.totalBorrowAfter.base, _data.totalBorrowBefore.base);
        assertApproxEqRel(_data.totalBorrowAfter.base, _data.totalBorrowBefore.base + leverageAmount, 0.01e18);

        // it should increase 'totalBorrow.elastic'
        assertGt(_data.totalBorrowAfter.elastic, _data.totalBorrowBefore.elastic);
        assertApproxEqRel(_data.totalBorrowAfter.elastic, _data.totalBorrowBefore.elastic + leverageAmount, 0.01e18);

        // it should increase market's YieldBox balance
        assertGt(_data.bbYieldBoxBalanceAfter, _data.bbYieldBoxBalanceBefore);

        // it should increase 'userCollateralShare'
        assertGt(_data.userCollateralAfter, _data.userCollateralBefore);

        // it should increase 'totalCollateralShare'
        assertGt(_data.totalCollateralShareAfter, _data.totalCollateralShareBefore);
    }

    function _getBigBangInitData(BigBangInitData memory _bb)
        internal
        returns (
            BigBang._InitMemoryModulesData memory modulesData,
            BigBang._InitMemoryDebtData memory debtData,
            BigBang._InitMemoryData memory data
        )
    {
        BBCollateral bbCollateral = new BBCollateral();
        BBLiquidation bbLiq = new BBLiquidation();
        BBLeverage bbLev = new BBLeverage();
        BBBorrow bbBorrow = new BBBorrow();

        modulesData =
            BigBang._InitMemoryModulesData(address(bbLiq), address(bbBorrow), address(bbCollateral), address(bbLev));

        debtData = BigBang._InitMemoryDebtData(_bb.debtRateAgainstEth, _bb.debtRateMin, _bb.debtRateMax);

        data = BigBang._InitMemoryData(
            IPenrose(_bb.penrose),
            IERC20(_bb.collateral),
            ITapiocaOracle(address(_bb.oracle)),
            DEFAULT_EXCHANGE_RATE,
            COLLATERALIZATION_RATE,
            LIQUIDATION_COLLATERALIZATION_RATE,
            _bb.leverageExecutor
        );
    }

    function _registerBBMarket(address _collateral, bool _isMain) internal returns (address) {
        // *** DEPLOYMENT *** //
        deal(address(usdo), address(leverageExecutor), type(uint256).max);
        deal(address(mainToken), address(leverageExecutor), type(uint256).max);
        deal(address(randomCollateral), address(leverageExecutor), type(uint256).max);

        (
            BigBang._InitMemoryModulesData memory initModulesData,
            BigBang._InitMemoryDebtData memory initDebtData,
            BigBang._InitMemoryData memory initMemoryData
        ) = _getBigBangInitData(
            BigBangInitData(
                address(penrose),
                _collateral,
                ITapiocaOracle(address(oracle)),
                ILeverageExecutor(address(leverageExecutor)),
                _isMain ? VALUE_ZERO : BB_DEBT_RATE_AGAINST_MAIN_MARKET,
                _isMain ? VALUE_ZERO : BB_MIN_DEBT_RATE,
                _isMain ? VALUE_ZERO : BB_MAX_DEBT_RATE
            )
        );

        address _contract =
            penrose.registerBigBang(address(bbMc), abi.encode(initModulesData, initDebtData, initMemoryData), true);

        // *** AFTER DEPLOYMENT *** //
        address[] memory mc = new address[](1);
        bytes[] memory data = new bytes[](1);

        mc[0] = _contract;
        data[0] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, address(debtHelper));
        penrose.executeMarketFn(mc, data, true);

        data[0] = abi.encodeWithSelector(BigBang.setAssetOracle.selector, address(assetOracle), "0x");
        penrose.executeMarketFn(mc, data, true);

        usdo.setMinterStatus(_contract, true);
        usdo.setBurnerStatus(_contract, true);

        if (_isMain) {
            penrose.setBigBangEthMarket(_contract);
        }

        vm.label(_contract, "BigBang market");
        return _contract;
    }

    // ************************** //
    // *** INTERNAL - SETTERS *** //
    // ************************** //
    function _setBorrowCap(uint256 borrowAmount, BigBang bb) internal {
        address[] memory mc = new address[](1);
        bytes[] memory data = new bytes[](1);

        mc[0] = address(bb);
        data[0] = abi.encodeWithSelector(
            Market.setMarketConfig.selector,
            ITapiocaOracle(address(0)),
            "0x",
            0, //protocol fee
            0, //_liquidationBonusAmount
            0, //_minLiquidatorReward
            0, //_maxLiquidatorReward
            borrowAmount - 1, //_totalBorrowCap
            0, //_collateralizationRate
            0, //_liquidationCollateralizationRate
            0, //_minBorrowAmount
            0 //_minCollateralAmount
        );
        (bool[] memory success,) = penrose.executeMarketFn(mc, data, true);
        assertTrue(success[0]);
    }

    function _setLiquidationBonuAmount(uint256 amount, BigBang bb) internal {
        address[] memory mc = new address[](1);
        bytes[] memory data = new bytes[](1);

        mc[0] = address(bb);
        data[0] = abi.encodeWithSelector(
            Market.setMarketConfig.selector,
            ITapiocaOracle(address(0)),
            "0x",
            0, //protocol fee
            amount, //_liquidationBonusAmount
            0, //_minLiquidatorReward
            0, //_maxLiquidatorReward
            0, //_totalBorrowCap
            0, //_collateralizationRate
            0, //_liquidationCollateralizationRate
            0, //_minBorrowAmount
            0 //_minCollateralAmount
        );
        (bool[] memory success,) = penrose.executeMarketFn(mc, data, true);
        assertTrue(success[0]);
    }

    function _setLeverageExecutor(address _le, BigBang bb) internal {
        address[] memory mc = new address[](1);
        bytes[] memory data = new bytes[](1);

        mc[0] = address(bb);
        data[0] = abi.encodeWithSelector(Market.setLeverageExecutor.selector, ILeverageExecutor(_le));
        (bool[] memory success,) = penrose.executeMarketFn(mc, data, true);
        assertTrue(success[0]);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MagnetarTestUtils} from "../MagnetarTestUtils.t.sol";
import {MagnetarCallFactoryUtil} from "../utils/MagnetarCallFactoryUtil.sol";
import {MagnetarTest} from "../Magnetar.t.sol";
import {
    MagnetarAction,
    MagnetarModule,
    MagnetarCall,
    MagnetarWithdrawData,
    DepositRepayAndRemoveCollateralFromMarketData,
    DepositAddCollateralAndBorrowFromMarketData
} from "tap-utils/interfaces/periph/IMagnetar.sol";

import {ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarCollateralModule} from "tapioca-periph/Magnetar/modules/MagnetarCollateralModule.sol";

import {IPermit} from "tap-utils/interfaces/common/IPermit.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

// @review-test: This test is failing in the setup (check MagnetarTestHelper.createUsdo).
//MagnetarTestUtils, MagnetarCallFactoryUtil
contract MagnetarCollateralModuleTest is MagnetarTest {
    function setUp() public virtual override {
        super.setUp();
    }
    /*
    function _createDepositRepayAndRemoveCollateralFromMarketData(
        address market,
        address marketHelper,
        address user,
        uint256 depositAmount,
        uint256 repayAmount,
        uint256 collateralAmount
    ) private returns (DepositRepayAndRemoveCollateralFromMarketData memory _params) {
        MagnetarWithdrawData memory _withdrawData = createEmptyWithdrawData();
        _params = DepositRepayAndRemoveCollateralFromMarketData({
            market: market,
            marketHelper: marketHelper,
            user: user,
            depositAmount: depositAmount,
            repayAmount: repayAmount,
            collateralAmount: collateralAmount,
            withdrawCollateralParams: _withdrawData
        });
    }

    function _createDepositAddCollateralAndBorrowFromMarketData(
        address market,
        address marketHelper,
        address user,
        uint256 collateralAmount,
        uint256 borrowAmount,
        bool deposit
    ) private returns (DepositAddCollateralAndBorrowFromMarketData memory _params) {
        MagnetarWithdrawData memory _withdrawData = createEmptyWithdrawData();
        _params = DepositAddCollateralAndBorrowFromMarketData({
            market: market,
            marketHelper: marketHelper,
            user: user,
            collateralAmount: collateralAmount,
            borrowAmount: borrowAmount,
            deposit: deposit,
            withdrawParams: _withdrawData
        });
    }
    */

    /*
    function test_depositRepayAndRemoveCollateralFromMarket_validation() public {
        address randomAddr = makeAddr("not_whitelisted");
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            randomAddr, address(marketHelper), address(this), 1 ether, 1 ether, 1 ether
        );
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        // test marketHelper
        _params.market = address(magnetarA);
        _params.marketHelper = randomAddr;
        depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_external_approvals() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(assetA), address(this), tokenAmount_);
        }

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, 0
        );
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        uint256 balanceBefore = assetA.balanceOf(address(this));

        //aprovals

        magnetarA.burst{value: 0}(calls);

        uint256 balanceAfter = assetA.balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_burst_approvals() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(assetA), userA, tokenAmount_);
        }

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), userA, tokenAmount_, 0, 0
        );
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](2);

        (ERC20PermitStruct memory permit, uint8 v_, bytes32 r_, bytes32 s_) =
            _createErc20Permit(userA, userAPKey, address(magnetarA), type(uint256).max, address(assetA));
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.Permit),
            target: address(assetA),
            value: 0,
            call: abi.encodeWithSelector(
                IPermit.permit.selector, permit.owner, permit.spender, permit.value, permit.deadline, v_, r_, s_
            )
        });

        calls[1] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        vm.startPrank(userA);
        magnetarA.burst{value: 0}(calls);
        vm.stopPrank();

        // check balances
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_and_repay() public {
        uint256 tokenAmount_ = 1 ether;

        // setup SGL funds
        // ---- add asset
        // ---- add collateral
        // ---- borrow
        deal(address(assetA), address(this), tokenAmount_ * 2);
        depositAsset(assetA, sgl, tokenAmount_ * 2);
        deal(address(aERC20), address(this), tokenAmount_ * 10);
        depositCollateral(aERC20, collateralAId, sgl, tokenAmount_ * 10);
        borrow(sgl, tokenAmount_, false);

        // use magnetar to `depositRepayAndRemoveCollateralFromMarket`
        deal(address(assetA), address(this), tokenAmount_);

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, tokenAmount_, 0
        );
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });
        uint256 borrowPartBefore = sgl._userBorrowPart(address(this));

        //aprovals for deposit
        assetA.approve(address(magnetarA), type(uint256).max);

        //approvals for repay
        sgl.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 borrowPartAfter = sgl._userBorrowPart(address(this));
        assertGt(borrowPartBefore, borrowPartAfter);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_repay_and_remove_collateral() public {
        uint256 tokenAmount_ = 1 ether;

        // setup SGL funds
        // ---- add asset
        // ---- add collateral
        // ---- borrow
        deal(address(assetA), address(this), tokenAmount_ * 2);
        depositAsset(assetA, sgl, tokenAmount_ * 2);
        deal(address(aERC20), address(this), tokenAmount_ * 10);
        depositCollateral(aERC20, collateralAId, sgl, tokenAmount_ * 10);
        borrow(sgl, tokenAmount_, false);

        // use magnetar to `depositRepayAndRemoveCollateralFromMarket`
        deal(address(assetA), address(this), tokenAmount_);

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, tokenAmount_, tokenAmount_
        );
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        uint256 collateralShareBefore = sgl.balanceOf(address(this));

        //aprovals for deposit
        assetA.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 collateralShareAfter = sgl.balanceOf(address(this));
        assertGt(collateralShareBefore, collateralShareAfter);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_and_remove_collateral() public {
        uint256 tokenAmount_ = 1 ether;

        // setup SGL funds
        // ---- add asset
        // ---- add collateral
        // ---- borrow
        deal(address(assetA), address(this), tokenAmount_ * 2);
        depositAsset(assetA, sgl, tokenAmount_ * 2);
        deal(address(aERC20), address(this), tokenAmount_ * 10);
        depositCollateral(aERC20, collateralAId, sgl, tokenAmount_ * 10);
        borrow(sgl, tokenAmount_, false);

        // use magnetar to `depositRepayAndRemoveCollateralFromMarket`
        deal(address(assetA), address(this), tokenAmount_);

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, tokenAmount_
        );
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        uint256 collateralShareBefore = sgl.balanceOf(address(this));

        //aprovals for deposit
        assetA.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 collateralShareAfter = sgl.balanceOf(address(this));
        assertGt(collateralShareBefore, collateralShareAfter);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_remove_collateral_and_withdraw() public {
        uint256 tokenAmount_ = 1 ether;

        // setup SGL funds
        // ---- add asset
        // ---- add collateral
        // ---- borrow
        deal(address(assetA), address(this), tokenAmount_ * 2);
        depositAsset(assetA, sgl, tokenAmount_ * 2);
        deal(address(aERC20), address(this), tokenAmount_ * 10);
        depositCollateral(aERC20, collateralAId, sgl, tokenAmount_ * 10);
        borrow(sgl, tokenAmount_, false);

        // use magnetar to `depositRepayAndRemoveCollateralFromMarket`
        deal(address(assetA), address(this), tokenAmount_);

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, tokenAmount_
        );
        _params.withdrawCollateralParams = MagnetarWithdrawData({
            asset: address(aERC20),
            receiver: userA,
            amount: tokenAmount_,
            withdraw: true,
            unwrap: false,
            extractFromSender: false
        });
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        uint256 collateralShareBefore = sgl.balanceOf(address(this));
        uint256 userABalanceBefore = aERC20.balanceOf(userA);

        //aprovals for deposit
        assetA.approve(address(magnetarA), type(uint256).max);

        //approvals for collateral

        magnetarA.burst{value: 0}(calls);

        uint256 collateralShareAfter = sgl.balanceOf(address(this));
        assertGt(collateralShareBefore, collateralShareAfter);

        uint256 userABalanceAfter = aERC20.balanceOf(userA);
        assertGt(userABalanceAfter, userABalanceBefore);
        assertEq(userABalanceAfter, tokenAmount_);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_remove_collateral_and_unwrap_withdraw() public {
        uint256 tokenAmount_ = 1 ether;

        // setup SGL funds
        // ---- add asset
        // ---- add collateral
        // ---- borrow
        deal(address(assetA), address(this), tokenAmount_ * 2);
        depositAsset(assetA, sgl, tokenAmount_ * 2);
        deal(address(aERC20), address(this), tokenAmount_ * 10);
        depositCollateral(aERC20, collateralAId, sgl, tokenAmount_ * 10);
        borrow(sgl, tokenAmount_, false);

        // use magnetar to `depositRepayAndRemoveCollateralFromMarket`
        deal(address(assetA), address(this), tokenAmount_);

        // deal collateralErc20 for unwrap operation
        deal(address(collateralErc20), address(aERC20.vault()), tokenAmount_);

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, tokenAmount_
        );
        _params.withdrawCollateralParams = MagnetarWithdrawData({
            asset: address(aERC20),
            receiver: userA,
            amount: tokenAmount_,
            withdraw: true,
            unwrap: true,
            extractFromSender: false
        });
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        uint256 collateralShareBefore = sgl.balanceOf(address(this));
        uint256 userABalanceBefore = collateralErc20.balanceOf(userA);

        //aprovals for deposit
        assetA.approve(address(magnetarA), type(uint256).max);

        //approvals for collateral

        magnetarA.burst{value: 0}(calls);

        uint256 collateralShareAfter = sgl.balanceOf(address(this));
        assertGt(collateralShareBefore, collateralShareAfter);

        uint256 userABalanceAfter = collateralErc20.balanceOf(userA);
        assertGt(userABalanceAfter, userABalanceBefore);
        assertEq(userABalanceAfter, tokenAmount_);
    }

    function test_depositRepayAndRemoveCollateralFromMarket_deposit_different_user() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(assetA), userA, tokenAmount_);
        }

        DepositRepayAndRemoveCollateralFromMarketData memory _params =
        _createDepositRepayAndRemoveCollateralFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, 0
        );
        _params.user = userA;
        bytes memory depositRepayAndRemoveCollateralFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketData
        });

        uint256 ybBalanceBefore = sgl.balanceOf(userA);

        //aprovals
        vm.startPrank(userA);
        assetA.approve(address(magnetarA), type(uint256).max);
        vm.stopPrank();

        //authorize user
        clusterA.updateContract(0, address(this), true);

        magnetarA.burst{value: 0}(calls);

        uint256 ybBalanceAfter = sgl.balanceOf(userA);
        assertGt(ybBalanceAfter, ybBalanceBefore);
    }

    function test_depositAddCollateralAndBorrowFromMarket_validation() public {
        address randomAddr = makeAddr("not_whitelisted");
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        DepositAddCollateralAndBorrowFromMarketData memory _params = _createDepositAddCollateralAndBorrowFromMarketData(
            randomAddr, address(marketHelper), address(this), 1 ether, 1 ether, true
        );
        bytes memory depositAddCollateralAndBorrowFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        // test marketHelper
        _params.market = address(magnetarA);
        _params.marketHelper = randomAddr;
        depositAddCollateralAndBorrowFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);
    }

    function test_depositAddCollateralAndBorrowFromMarket_add_collateral_without_deposit_external_approvals() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(aERC20), address(this), tokenAmount_);
        }

        DepositAddCollateralAndBorrowFromMarketData memory _params = _createDepositAddCollateralAndBorrowFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, false
        );
        bytes memory depositAddCollateralAndBorrowFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketData
        });

        uint256 colSharesBefore = sgl.balanceOf(address(this));

        // manually deposit asset to YB

        //approvals for add collateral

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = sgl.balanceOf(address(this));
        assertGt(colSharesAfter, colSharesBefore);
    }

    function test_depositAddCollateralAndBorrowFromMarket_deposit_and_add_collateral() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(aERC20), address(this), tokenAmount_);
        }

        DepositAddCollateralAndBorrowFromMarketData memory _params = _createDepositAddCollateralAndBorrowFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, 0, true
        );
        bytes memory depositAddCollateralAndBorrowFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketData
        });

        uint256 colSharesBefore = sgl.balanceOf(address(this));

        //approvals for deposit & collateral add
        aERC20.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = sgl.balanceOf(address(this));
        assertGt(colSharesAfter, colSharesBefore);
    }

    function test_depositAddCollateralAndBorrowFromMarket_deposit_add_collateral_and_borrow() public {
        uint256 tokenAmount_ = 1 ether;
        uint256 borrowAmount_ = 0.2 ether;

        {
            deal(address(aERC20), address(this), tokenAmount_);
            deal(address(assetA), address(this), tokenAmount_);

            depositAsset(assetA, sgl, tokenAmount_);
        }

        DepositAddCollateralAndBorrowFromMarketData memory _params = _createDepositAddCollateralAndBorrowFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, borrowAmount_, true
        );
        bytes memory depositAddCollateralAndBorrowFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketData
        });

        uint256 colSharesBefore = sgl.balanceOf(address(this));
        uint256 borrowPartBefore = sgl._userBorrowPart(address(this));

        //approvals for deposit & collateral add
        aERC20.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = sgl.balanceOf(address(this));
        uint256 borrowPartAfter = sgl._userBorrowPart(address(this));
        assertGt(colSharesAfter, colSharesBefore);
        assertGt(borrowPartAfter, borrowPartBefore);
    }

    function test_depositAddCollateralAndBorrowFromMarket_deposit_add_collateral_borrow_and_withdraw() public {
        uint256 tokenAmount_ = 1 ether;
        uint256 borrowAmount_ = 0.2 ether;

        {
            deal(address(aERC20), address(this), tokenAmount_);
            deal(address(assetA), address(this), tokenAmount_);

            depositAsset(assetA, sgl, tokenAmount_);
        }

        DepositAddCollateralAndBorrowFromMarketData memory _params = _createDepositAddCollateralAndBorrowFromMarketData(
            address(sgl), address(marketHelper), address(this), tokenAmount_, borrowAmount_, true
        );
        _params.withdrawParams = MagnetarWithdrawData({
            asset: address(assetA),
            receiver: userA,
            amount: borrowAmount_,
            withdraw: true,
            unwrap: false,
            extractFromSender: false
        });
        bytes memory depositAddCollateralAndBorrowFromMarketData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector, _params);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(magnetarA),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketData
        });

        uint256 colSharesBefore = sgl.balanceOf(address(this));
        uint256 borrowPartBefore = sgl._userBorrowPart(address(this));
        uint256 assetBalanceBefore = assetA.balanceOf(userA);

        //approvals for deposit & collateral add
        aERC20.approve(address(magnetarA), type(uint256).max);
        // Atomic approval

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = sgl.balanceOf(address(this));
        uint256 borrowPartAfter = sgl._userBorrowPart(address(this));
        uint256 assetBalanceAfter = assetA.balanceOf(userA);
        assertGt(colSharesAfter, colSharesBefore);
        assertGt(borrowPartAfter, borrowPartBefore);
        assertGt(assetBalanceAfter, assetBalanceBefore);
    }
    */

    function test_burst_addCollateral_valid_with_permits(
        uint160 _userPk,
        uint256 _tokenAmount,
        uint256 _collateralAmount
    ) external withValidAmount(_tokenAmount) withValidAmount128(_collateralAmount) {
        vm.assume(sgl.minCollateralAmount() < _collateralAmount);
        address _user = _assumeValidAddress(_userPk, "user");

        deal(address(collateral), _user, _collateralAmount);

        _withMarketAddAsset(address(sgl), _userPk, _tokenAmount);
        uint256 _nonce = sgl.nonces(_user);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] =
            _getERC20PermitMagnetarCall(payable(address(collateral)), _userPk, address(sgl), _collateralAmount, 1 days);
        calls[1] = _getMarketAddCollateralMagnetarCall(address(sgl), address(marketHelper), _user, _collateralAmount);

        vm.startPrank(_user);
        magnetar.burst(calls);
        vm.stopPrank();

        assertGt(sgl.balanceOf(_user), 0, "user should have collateral shares");
        assertEq(sgl.balanceOf(address(magnetar)), 0, "magnetar should not have collateral shares");
        assertEq(collateral.balanceOf(address(sgl)), _collateralAmount, "Market should have collateral");
        assertEq(sgl.totalSupply(), sgl.balanceOf(_user), "total supply should be equal to user balance");
    }

    function test_burst_addCollateral_valid_with_permit(
        uint160 _userPk,
        uint256 _tokenAmount,
        uint256 _collateralAmount
    ) external withValidAmount(_tokenAmount) withValidAmount128(_collateralAmount) {
        vm.assume(sgl.minCollateralAmount() < _collateralAmount);
        address _user = _assumeValidAddress(_userPk, "user");

        deal(address(collateral), _user, _collateralAmount);

        _withMarketAddAsset(address(sgl), _userPk, _tokenAmount);
        uint256 _nonce = sgl.nonces(_user);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] =
            _getERC20PermitMagnetarCall(payable(address(collateral)), _userPk, address(sgl), _collateralAmount, 1 days);
        calls[1] = _getMarketAddCollateralMagnetarCall(address(sgl), address(marketHelper), _user, _collateralAmount);

        vm.startPrank(_user);
        magnetar.burst(calls);
        vm.stopPrank();

        assertGt(sgl.balanceOf(_user), 0, "user should have collateral shares");
        assertEq(sgl.balanceOf(address(magnetar)), 0, "magnetar should not have collateral shares");
        assertEq(collateral.balanceOf(address(sgl)), _collateralAmount, "Market should have collateral");
        assertEq(sgl.totalSupply(), sgl.balanceOf(_user), "total supply should be equal to user balance");
    }

    function test_burst_addAsset_addCollateral_borrow_valid_with_permit(
        uint160 _userPk,
        uint256 _tokenAmount,
        uint256 _collateralAmount
    ) external withValidAmount(_tokenAmount) withValidAmount128(_collateralAmount) {
        uint256 _borrowAmount = sgl.minBorrowAmount() * 3;
        vm.assume(sgl.minCollateralAmount() * 4 < _collateralAmount);
        vm.assume(sgl.minBorrowAmount() < _borrowAmount);
        vm.assume(_borrowAmount < _tokenAmount);
        vm.assume(_borrowAmount * 3 < _collateralAmount);
        address _user = _assumeValidAddress(_userPk, "user");

        deal(address(collateral), _user, _collateralAmount);

        _withMarketAddAsset(address(sgl), _userPk, _tokenAmount);
        uint256 _nonce = sgl.nonces(_user);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] =
            _getERC20PermitMagnetarCall(payable(address(collateral)), _userPk, address(sgl), _collateralAmount, 1 days);
        calls[1] = _getMarketAddCollateral_BorrowMagnetarCall(
            address(sgl), address(marketHelper), _user, _collateralAmount, _borrowAmount
        );

        vm.startPrank(_user);
        magnetar.burst(calls);
        vm.stopPrank();

        assertGt(sgl.balanceOf(_user), 0, "user should have collateral shares");
        assertEq(sgl.balanceOf(address(magnetar)), 0, "magnetar should not have collateral shares");
        assertEq(collateral.balanceOf(address(sgl)), _collateralAmount, "Market should have collateral");
        assertEq(sgl.totalSupply(), sgl.balanceOf(_user), "total supply should be equal to user balance");
        assertEq(sgl._userBorrowPart(_user), _borrowAmount, "user borrow part should be equal to borrow amount");
    }

    function test_burst_addAsset_addCollateral_borrow_repay_valid_with_permit(
        uint160 _userPk,
        uint256 _tokenAmount,
        uint256 _collateralAmount
    ) external withValidAmount(_tokenAmount) withValidAmount128(_collateralAmount) {
        uint256 _borrowAmount = sgl.minBorrowAmount() * 3;
        vm.assume(sgl.minCollateralAmount() * 4 < _collateralAmount);
        vm.assume(sgl.minBorrowAmount() < _borrowAmount);
        vm.assume(_borrowAmount < _tokenAmount);
        vm.assume(_borrowAmount * 3 < _collateralAmount);
        address _user = _assumeValidAddress(_userPk, "user");

        deal(address(collateral), _user, _collateralAmount);
        address _borrowableToken = sgl._asset();
        deal(_borrowableToken, _user, _borrowAmount);
        _withMarketAddAsset(address(sgl), _userPk, _tokenAmount);
        uint256 _nonce = sgl.nonces(_user);

        MagnetarCall[] memory calls = new MagnetarCall[](4);
        calls[0] =
            _getERC20PermitMagnetarCall(payable(address(collateral)), _userPk, address(sgl), _collateralAmount, 1 days);
        calls[1] = _getMarketAddCollateral_BorrowMagnetarCall(
            address(sgl), address(marketHelper), _user, _collateralAmount, _borrowAmount
        );
        calls[2] = _getERC20PermitMagnetarCall(
            payable(address(_borrowableToken)), _userPk, address(sgl), _borrowAmount, 1 days
        );
        calls[3] = _getMarketRepayMagnetarCall(address(sgl), address(marketHelper), _user, _borrowAmount);

        vm.startPrank(_user);
        magnetar.burst(calls);
        vm.stopPrank();

        assertGt(sgl.balanceOf(_user), 0, "user should have collateral shares");
        assertEq(sgl.balanceOf(address(magnetar)), 0, "magnetar should not have collateral shares");
        assertEq(collateral.balanceOf(address(sgl)), _collateralAmount, "Market should have collateral");
        assertEq(sgl.totalSupply(), sgl.balanceOf(_user), "total supply should be equal to user balance");
        assertEq(sgl._userBorrowPart(_user), 0, "user borrow part should be equal to borrow amount");
    }
}

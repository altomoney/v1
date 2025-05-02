// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {LZSendParam} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarTestHelper, MagnetarSetupData, TestBigBangData, TestSingularityData} from "./MagnetarTestHelper.t.sol";
import {
    MagnetarAction,
    MagnetarModule,
    MagnetarCall,
    MagnetarWithdrawData,
    LockData,
    MintFromBBAndLendOnSGLData,
    ExitPositionAndRemoveCollateralData,
    IExerciseOptionsData,
    IOptionsLockData,
    IOptionsUnlockData,
    IMintData,
    IRemoveAndRepay
} from "tap-utils/interfaces/periph/IMagnetar.sol";

import {ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarOptionModule} from "tapioca-periph/Magnetar/modules/MagnetarOptionModule.sol";
import {MagnetarMintModule} from "tapioca-periph/Magnetar/modules/MagnetarMintModule.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {ICommonExternalContracts, IDepositData} from "tap-utils/interfaces/common/ICommonData.sol";
import {IPermit} from "tap-utils/interfaces/common/IPermit.sol";

import {TapOftMock} from "../../mocks/TapOftMock.sol";
import {ERC721Mock} from "../../mocks/ERC721Mock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

// @review-test Fix the tests in this contract. Failing in the setUp.
abstract contract MagnetarOptionModuleTest is MagnetarTestHelper, IERC721Receiver {
    TapiocaOptionBroker public tOB;

    // -----------------------
    //
    // Setup
    //
    // -----------------------
    function setUp() public override {
        createCommonSetup();

        TapOftMock tapOft = new TapOftMock();
        ERC721Mock oTAP = new ERC721Mock();
        // TODO Review it tOB = new TapiocaOptionBroker(address(oTAP), address(tapOft));

        clusterA.updateContract(0, address(tOB), true);
    }

    function createLockAndParticipateData(address user, address singularity, address magnetar)
        private
        returns (LockData memory data)
    {
        return LockData({
            user: user,
            magnetar: magnetar,
            lockData: IOptionsLockData({
                lock: false,
                bucketId: 0,
                target: address(0),
                to: address(this),
                sglMarket: address(0),
                usdoAmount: 0
            })
        });
    }

    function _createMintFromBBAndLendOnSGLData(
        address user,
        uint256 lendAmount,
        uint256 mintAmount,
        uint256 depositAmount,
        address _magnetar,
        address _singularity,
        address _bigBang,
        address _marketHelper
    ) private returns (MintFromBBAndLendOnSGLData memory _params) {
        MagnetarWithdrawData memory _withdrawData = createEmptyWithdrawData();
        _params = MintFromBBAndLendOnSGLData({
            user: user,
            lendAmount: lendAmount,
            mintData: IMintData({
                mint: false,
                mintAmount: mintAmount,
                collateralDepositData: IDepositData({deposit: false, amount: depositAmount})
            }),
            depositData: IDepositData({deposit: false, amount: depositAmount}),
            lockData: IOptionsLockData({
                lock: false,
                target: address(0),
                bucketId: 0,
                to: address(this),
                sglMarket: address(0),
                usdoAmount: 0
            }),
            externalContracts: ICommonExternalContracts({
                magnetar: _magnetar,
                singularity: _singularity,
                bigBang: _bigBang,
                marketHelper: _marketHelper
            })
        });
    }

    function _runLockPrerequisites() public {
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // get SGL tokens
        uint256 tokenAmount_ = 1 ether;
        uint256 mintAmount_ = 0.5 ether;
        {
            deal(address(aERC20), address(this), tokenAmount_);
            deal(address(assetA), address(this), tokenAmount_);
        }

        // test market
        MintFromBBAndLendOnSGLData memory _params = _createMintFromBBAndLendOnSGLData(
            address(this),
            tokenAmount_ + mintAmount_,
            0,
            tokenAmount_,
            address(magnetarA),
            address(sgl),
            address(bb),
            address(marketHelper)
        );
        _params.mintData.mint = true;
        _params.mintData.mintAmount = mintAmount_;
        _params.mintData.collateralDepositData.deposit = true;
        _params.mintData.collateralDepositData.amount = tokenAmount_;
        _params.depositData.deposit = true;
        _params.depositData.amount = tokenAmount_;

        bytes memory mintFromBBAndLendOnSGLData =
            abi.encodeWithSelector(MagnetarMintModule.mintBBAndLock.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });

        //approvals for deposit & collateral add
        aERC20.approve(address(magnetarA), type(uint256).max);

        // Atomic approval

        assetA.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function createExitPositionAndRemoveCollateralData(
        address user,
        address _magnetar,
        address _singularity,
        address _bigBang,
        address _marketHelper
    ) private returns (ExitPositionAndRemoveCollateralData memory _params) {
        return ExitPositionAndRemoveCollateralData({
            user: user,
            externalData: ICommonExternalContracts({
                magnetar: _magnetar,
                singularity: _singularity,
                bigBang: _bigBang,
                marketHelper: _marketHelper
            }),
            removeAndRepayData: IRemoveAndRepay({
                removeAssetFromSGL: false,
                removeAmount: 0,
                repayAssetOnBB: false,
                repayAmount: 0,
                removeCollateralFromBB: false,
                collateralAmount: 0,
                unlockData: IOptionsUnlockData({unlock: false, target: address(0), bucketId: 0, to: address(this), amount: 0}),
                assetWithdrawData: createEmptyWithdrawData(),
                collateralWithdrawData: createEmptyWithdrawData()
            })
        });
    }

    function _lockAndParticipatePrerequisites() private {
        // mint and lend
        _runLockPrerequisites();
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // lock and participate
        LockData memory _paramsLock = createLockAndParticipateData(address(this), address(sgl), address(magnetarA));
        _paramsLock.lockData.lock = true;
        _paramsLock.lockData.target = address(tOB);
        _paramsLock.lockData.usdoAmount = assetA.balanceOf(address(this));
        bytes memory lockAndParticipateData = abi.encodeWithSelector(MagnetarOptionModule.lock.selector, _paramsLock);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: lockAndParticipateData
        });

        {}

        magnetarA.burst{value: 0}(calls);
    }

    // -----------------------0
    //
    // Tests
    //
    // -----------------------
    function test_exitPositionAndRemoveCollateral_validation() public {
        address randomAddr = makeAddr("not_whitelisted");
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        ExitPositionAndRemoveCollateralData memory _params = createExitPositionAndRemoveCollateralData(
            address(this), randomAddr, address(sgl), address(bb), address(marketHelper)
        );
        bytes memory exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalData.magnetar = address(magnetarA);
        _params.externalData.singularity = randomAddr;
        exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalData.singularity = address(sgl);
        _params.externalData.bigBang = randomAddr;
        exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalData.bigBang = address(bb);
        _params.externalData.marketHelper = randomAddr;
        exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);
    }

    function test_exitPositionAndRemoveCollateral_remove() public {
        _runLockPrerequisites();

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        ExitPositionAndRemoveCollateralData memory _params = createExitPositionAndRemoveCollateralData(
            address(this), address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.removeAndRepayData.removeAssetFromSGL = true;
        _params.removeAndRepayData.removeAmount = 1 ether;

        bytes memory exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });

        uint256 sglBalanceBefore = sgl.balanceOf(address(this));
        magnetarA.burst{value: 0}(calls);
        uint256 sglBalanceAfter = sgl.balanceOf(address(this));

        assertGt(sglBalanceBefore, sglBalanceAfter);
    }

    function test_exitPositionAndRemoveCollateral_remove_repay() public {
        vm.skip(true);
        _runLockPrerequisites();

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        ExitPositionAndRemoveCollateralData memory _params = createExitPositionAndRemoveCollateralData(
            address(this), address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.removeAndRepayData.removeAssetFromSGL = true;
        _params.removeAndRepayData.removeAmount = 1 ether;
        _params.removeAndRepayData.repayAssetOnBB = true;
        _params.removeAndRepayData.repayAmount = 1 ether - 1;

        bytes memory exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });

        uint256 sglBalanceBefore = sgl.balanceOf(address(this));
        uint256 borrowPartBefore = bb._userBorrowPart(address(this));
        magnetarA.burst{value: 0}(calls);
        uint256 sglBalanceAfter = sgl.balanceOf(address(this));
        uint256 borrowPartAfter = bb._userBorrowPart(address(this));

        assertGt(sglBalanceBefore, sglBalanceAfter);
        assertGt(borrowPartBefore, borrowPartAfter);
    }

    function test_exitPositionAndRemoveCollateral_remove_repay_removeCollateral() public {
        vm.skip(true);
        _runLockPrerequisites();

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        ExitPositionAndRemoveCollateralData memory _params = createExitPositionAndRemoveCollateralData(
            address(this), address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.removeAndRepayData.removeAssetFromSGL = true;
        _params.removeAndRepayData.removeAmount = 1 ether;
        _params.removeAndRepayData.repayAssetOnBB = true;
        _params.removeAndRepayData.repayAmount = 1 ether - 1;
        _params.removeAndRepayData.removeCollateralFromBB = true;
        _params.removeAndRepayData.collateralAmount = 0.5 ether;

        bytes memory exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });

        uint256 collateralShareBefore = bb.balanceOf(address(this));
        magnetarA.burst{value: 0}(calls);
        uint256 collateralShareAfter = bb.balanceOf(address(this));

        assertGt(collateralShareBefore, collateralShareAfter);
    }

    function test_exitPositionAndRemoveCollateral_remove_repay_removeCollateral_withdrawCollateral() public {
        vm.skip(true);
        _runLockPrerequisites();

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        ExitPositionAndRemoveCollateralData memory _params = createExitPositionAndRemoveCollateralData(
            address(this), address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.removeAndRepayData.removeAssetFromSGL = true;
        _params.removeAndRepayData.removeAmount = 1 ether;
        _params.removeAndRepayData.repayAssetOnBB = true;
        _params.removeAndRepayData.repayAmount = 1 ether - 1;
        _params.removeAndRepayData.removeCollateralFromBB = true;
        _params.removeAndRepayData.collateralAmount = 0.5 ether;

        _params.removeAndRepayData.collateralWithdrawData.withdraw = true;
        _params.removeAndRepayData.collateralWithdrawData.amount = 0.5 ether;

        bytes memory exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });

        address _collateral = bb.collateral();
        uint256 balanceBefore = ERC20Mock(_collateral).balanceOf(address(this));
        uint256 collateralShareBefore = bb.balanceOf(address(this));
        magnetarA.burst{value: 0}(calls);
        uint256 collateralShareAfter = bb.balanceOf(address(this));
        uint256 balanceAfter = ERC20Mock(_collateral).balanceOf(address(this));

        assertGt(collateralShareBefore, collateralShareAfter);
        assertGt(balanceAfter, balanceBefore);
    }

    function test_exitPositionAndRemoveCollateral_remove_repay_removeCollateral_withdrawCollateral_withdrawAsset()
        public
    {
        _runLockPrerequisites();

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        ExitPositionAndRemoveCollateralData memory _params = createExitPositionAndRemoveCollateralData(
            address(this), address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.removeAndRepayData.removeAssetFromSGL = true;
        _params.removeAndRepayData.removeAmount = 1 ether;
        _params.removeAndRepayData.repayAssetOnBB = false;
        _params.removeAndRepayData.removeCollateralFromBB = true;
        _params.removeAndRepayData.collateralAmount = 0.05 ether;

        _params.removeAndRepayData.collateralWithdrawData.withdraw = true;
        _params.removeAndRepayData.collateralWithdrawData.amount = 0.05 ether;

        _params.removeAndRepayData.assetWithdrawData.withdraw = true;
        _params.removeAndRepayData.assetWithdrawData.amount = 0.5 ether;

        bytes memory exitPositionAndRemoveCollateraleData =
            abi.encodeWithSelector(MagnetarOptionModule.exitPositionAndRemoveCollateral.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: exitPositionAndRemoveCollateraleData
        });

        address _collateral = bb.collateral();
        uint256 balanceBefore = ERC20Mock(_collateral).balanceOf(address(this));
        uint256 collateralShareBefore = bb.balanceOf(address(this));
        magnetarA.burst{value: 0}(calls);
        uint256 collateralShareAfter = bb.balanceOf(address(this));
        uint256 balanceAfter = ERC20Mock(_collateral).balanceOf(address(this));

        assertGt(collateralShareBefore, collateralShareAfter);
        assertGt(balanceAfter, balanceBefore);
    }

    function test_lockAndParticipate_validation() public {
        address randomAddr = makeAddr("not_whitelisted");
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        LockData memory _params = createLockAndParticipateData(address(this), randomAddr, address(magnetarA));
        bytes memory lockAndParticipateData = abi.encodeWithSelector(MagnetarOptionModule.lock.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: lockAndParticipateData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.magnetar = randomAddr;
        lockAndParticipateData = abi.encodeWithSelector(MagnetarOptionModule.lock.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: lockAndParticipateData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);
    }

    function test_lockAndParticipate_lock_validation() public {
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        LockData memory _params = createLockAndParticipateData(address(this), address(sgl), address(magnetarA));
        _params.lockData.lock = true;
        bytes memory lockAndParticipateData = abi.encodeWithSelector(MagnetarOptionModule.lock.selector, _params);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OptionModule),
            target: address(magnetarA),
            value: 0,
            call: lockAndParticipateData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);
    }

    function test_lockAndParticipate_lock_only() public {
        vm.skip(true);
    }

    function test_lockAndParticipate_lock_and_participate() public {
        vm.skip(true);
    }
}

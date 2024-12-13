// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {LZSendParam} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarTestHelper, MagnetarSetupData, TestBigBangData, TestSingularityData} from "./MagnetarTestHelper.t.sol";
import {
    MagnetarAction,
    MagnetarModule,
    MagnetarCall,
    MagnetarWithdrawData,
    DepositRepayAndRemoveCollateralFromMarketData,
    DepositAddCollateralAndBorrowFromMarketData,
    MintFromBBAndLendOnSGLData
} from "tap-utils/interfaces/periph/IMagnetar.sol";

import {ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarMintModule} from "tapioca-periph/Magnetar/modules/MagnetarMintModule.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IOptionsLockData} from "tap-utils/interfaces/tap-token/ITapiocaOptionLiquidityProvision.sol";
import {ICommonExternalContracts, IDepositData} from "tap-utils/interfaces/common/ICommonData.sol";
import {IOptionsParticipateData} from "tap-utils/interfaces/tap-token/ITapiocaOptionBroker.sol";

import {IPermit} from "tap-utils/interfaces/common/IPermit.sol";
import {IMintData} from "tap-utils/interfaces/oft/IUsdo.sol";

import {TapOftMock} from "../../mocks/TapOftMock.sol";
import {ERC721Mock} from "../../mocks/ERC721Mock.sol";
import {TOFTMock} from "../../mocks/TOFTMock.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

// @review-test Fix the tests in this contract. Failing in the setUp.
abstract contract MagnetarMintModuleTest is MagnetarTestHelper, IERC721Receiver {
    TapiocaOptionBroker public tOB;
    TapOftMock tapOft;
    TOFTMock tSgl;

    // -----------------------
    //
    // Setup
    //
    // -----------------------
    function setUp() public override {
        createCommonSetup();

        tapOft = new TapOftMock();
        ERC721Mock oTAP = new ERC721Mock();

        clusterA.updateContract(0, address(tOB), true);
        clusterA.updateContract(0, address(tapOft), true);
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
                tAsset: address(0),
                lockDuration: 0,
                amount: 0,
                fraction: 0,
                minDiscountOut: 0
            }),
            participateData: IOptionsParticipateData({participate: false, target: address(0), tOLPTokenId: 0}),
            externalContracts: ICommonExternalContracts({
                magnetar: _magnetar,
                singularity: _singularity,
                bigBang: _bigBang,
                marketHelper: _marketHelper
            })
        });
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // -----------------------0
    //
    // Tests
    //
    // -----------------------
    function test_mintFromBBAndLendOnSGL_validation() public {
        address randomAddr = makeAddr("not_whitelisted");
        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        MintFromBBAndLendOnSGLData memory _params = _createMintFromBBAndLendOnSGLData(
            address(this), 0, 0, 0, randomAddr, address(sgl), address(bb), address(marketHelper)
        );
        bytes memory mintFromBBAndLendOnSGLData =
            abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalContracts.magnetar = address(magnetarA);
        _params.externalContracts.singularity = randomAddr;
        mintFromBBAndLendOnSGLData = abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalContracts.singularity = address(magnetarA);
        _params.externalContracts.bigBang = randomAddr;
        mintFromBBAndLendOnSGLData = abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalContracts.bigBang = address(magnetarA);
        _params.externalContracts.marketHelper = randomAddr;
        mintFromBBAndLendOnSGLData = abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalContracts.bigBang = address(magnetarA);
        _params.externalContracts.marketHelper = randomAddr;
        mintFromBBAndLendOnSGLData = abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.externalContracts.marketHelper = address(magnetarA);
        _params.lockData.target = randomAddr;
        mintFromBBAndLendOnSGLData = abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);

        _params.lockData.target = address(magnetarA);
        _params.participateData.target = randomAddr;
        mintFromBBAndLendOnSGLData = abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });
        vm.expectRevert();
        magnetarA.burst{value: 0}(calls);
    }

    function test_mintFromBBAndLendOnSGL_addCollateral() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(collateralA), address(this), tokenAmount_);
        }

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        MintFromBBAndLendOnSGLData memory _params = _createMintFromBBAndLendOnSGLData(
            address(this), 0, 0, tokenAmount_, address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.mintData.mint = true;
        _params.mintData.collateralDepositData.deposit = true;
        _params.mintData.collateralDepositData.amount = tokenAmount_;

        bytes memory mintFromBBAndLendOnSGLData =
            abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });

        uint256 colSharesBefore = bb.balanceOf(address(this));

        //approvals for deposit & collateral add
        collateralA.approve(address(magnetarA), type(uint256).max);

        // Atomic approval

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = bb.balanceOf(address(this));
        assertGt(colSharesAfter, colSharesBefore);
    }

    function test_mintFromBBAndLendOnSGL_addCollateral_and_mint() public {
        uint256 tokenAmount_ = 1 ether;
        uint256 mintAmount_ = 0.5 ether;
        {
            deal(address(collateralA), address(this), tokenAmount_);
        }

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        MintFromBBAndLendOnSGLData memory _params = _createMintFromBBAndLendOnSGLData(
            address(this), 0, 0, tokenAmount_, address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.mintData.mint = true;
        _params.mintData.mintAmount = mintAmount_;
        _params.mintData.collateralDepositData.deposit = true;
        _params.mintData.collateralDepositData.amount = tokenAmount_;

        bytes memory mintFromBBAndLendOnSGLData =
            abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });

        uint256 colSharesBefore = bb.balanceOf(address(this));
        uint256 borrowPartBefore = bb._userBorrowPart(address(this));

        //approvals for deposit & collateral add
        collateralA.approve(address(magnetarA), type(uint256).max);

        // Atomic approval

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = bb.balanceOf(address(this));
        uint256 borrowPartAfter = bb._userBorrowPart(address(this));
        assertGt(colSharesAfter, colSharesBefore);
        assertGt(borrowPartAfter, borrowPartBefore);
    }

    function test_mintFromBBAndLendOnSGL_only_deposit() public {
        uint256 tokenAmount_ = 1 ether;
        {
            deal(address(assetA), address(this), tokenAmount_);
        }

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        MintFromBBAndLendOnSGLData memory _params = _createMintFromBBAndLendOnSGLData(
            address(this), 0, 0, tokenAmount_, address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.depositData.deposit = true;
        _params.depositData.amount = tokenAmount_;

        bytes memory mintFromBBAndLendOnSGLData =
            abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });

        uint256 assetABalanceBefore = sgl.balanceOf(address(this));

        // manually deposit asset to YB
        assetA.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 assetABalanceAfter = sgl.balanceOf(address(this));
        assertGt(assetABalanceAfter, assetABalanceBefore);
    }

    function test_mintFromBBAndLendOnSGL_addCollateral_and_mint_and_depositExtra() public {
        uint256 tokenAmount_ = 1 ether;
        uint256 mintAmount_ = 0.5 ether;
        {
            deal(address(collateralA), address(this), tokenAmount_);
            deal(address(assetA), address(this), tokenAmount_);
        }

        MagnetarCall[] memory calls = new MagnetarCall[](1);

        // test market
        MintFromBBAndLendOnSGLData memory _params = _createMintFromBBAndLendOnSGLData(
            address(this), 0, 0, tokenAmount_, address(magnetarA), address(sgl), address(bb), address(marketHelper)
        );
        _params.mintData.mint = true;
        _params.mintData.mintAmount = mintAmount_;
        _params.mintData.collateralDepositData.deposit = true;
        _params.mintData.collateralDepositData.amount = tokenAmount_;
        _params.depositData.deposit = true;
        _params.depositData.amount = tokenAmount_;

        bytes memory mintFromBBAndLendOnSGLData =
            abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });

        uint256 colSharesBefore = bb.balanceOf(address(this));
        uint256 borrowPartBefore = bb._userBorrowPart(address(this));
        uint256 assetABalanceBefore = sgl.balanceOf(address(this));

        //approvals for deposit & collateral add
        collateralA.approve(address(magnetarA), type(uint256).max);

        // Atomic approval

        assetA.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = bb.balanceOf(address(this));
        uint256 borrowPartAfter = bb._userBorrowPart(address(this));
        uint256 assetABalanceAfter = sgl.balanceOf(address(this));
        assertGt(assetABalanceAfter, assetABalanceBefore);
        assertGt(colSharesAfter, colSharesBefore);
        assertGt(borrowPartAfter, borrowPartBefore);
    }

    function test_mintFromBBAndLendOnSGL_addCollateral_mint_depositExtra_and_lend() public {
        uint256 tokenAmount_ = 1 ether;
        uint256 mintAmount_ = 0.5 ether;
        {
            deal(address(collateralA), address(this), tokenAmount_);
            deal(address(assetA), address(this), tokenAmount_);
        }

        MagnetarCall[] memory calls = new MagnetarCall[](1);

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
            abi.encodeWithSelector(MagnetarMintModule.mintBBLendSGLLockTOLP.selector, _params);

        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.MintModule),
            target: address(magnetarA),
            value: 0,
            call: mintFromBBAndLendOnSGLData
        });

        uint256 colSharesBefore = bb.balanceOf(address(this));
        uint256 borrowPartBefore = bb._userBorrowPart(address(this));
        uint256 sglBalanceBefore = sgl.balanceOf(address(this));

        //approvals for deposit & collateral add
        collateralA.approve(address(magnetarA), type(uint256).max);

        // Atomic approval

        assetA.approve(address(magnetarA), type(uint256).max);

        magnetarA.burst{value: 0}(calls);

        uint256 colSharesAfter = bb.balanceOf(address(this));
        uint256 borrowPartAfter = bb._userBorrowPart(address(this));
        uint256 sglBalanceAfter = sgl.balanceOf(address(this));
        assertGt(colSharesAfter, colSharesBefore);
        assertGt(borrowPartAfter, borrowPartBefore);
        assertGt(sglBalanceAfter, sglBalanceBefore);
    }

    function test_mintFromBBAndLendOnSGL_addCollateral_mint_depositExtra_lend_and_lock() public {
        vm.skip(true);
    }

    function test_mintFromBBAndLendOnSGL_addCollateral_mint_depositExtra_lend_lock_and_participate() public {
        vm.skip(true);
    }
}

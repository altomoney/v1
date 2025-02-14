// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import "forge-std/console2.sol";

// Lz
import {
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

// External
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {TapiocaOmnichainEngineHelper} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {TapiocaOmnichainEngineCodec} from "tap-utils/tapiocaOmnichainEngine/TapiocaOmnichainEngineCodec.sol";
import {MagnetarCollateralModule} from "tapioca-periph/Magnetar/modules/MagnetarCollateralModule.sol";
import {ITapiocaOmnichainEngine, ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarOptionModule} from "tapioca-periph/Magnetar/modules/MagnetarOptionModule.sol";
import {MagnetarMintModule} from "tapioca-periph/Magnetar/modules/MagnetarMintModule.sol";
import {MagnetarBaseModule} from "tapioca-periph/Magnetar/modules/MagnetarBaseModule.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {SendParamsMsg} from "tap-utils/interfaces/oft/ITOFT.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {Magnetar} from "tapioca-periph/Magnetar/Magnetar.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {TapToken} from "../../../contracts/tap-token/tokens/TapToken.sol";
import {TwTAP} from "../../../contracts/tap-token/governance/TwTAP.sol";
import {TapTokenMock} from "../../tap-token/TapTokenMock.sol";
import {ITapToken} from "../../../contracts/tap-token/tokens/ITapToken.sol";
import {Bucket} from "../../../contracts/tap-token/interfaces/ITWLBase.sol";
import {TapTokenSender} from "../../../contracts/tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "../../../contracts/tap-token/tokens/TapTokenReceiver.sol";

import {
    PrepareLzCallData,
    PrepareLzCallReturn,
    ComposeMsgData,
    LZSendParam,
    RemoteTransferMsg,
    TapiocaOmnichainEngineHelper
} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";
import {
    MagnetarAction,
    MagnetarModule,
    MagnetarCall,
    DepositAddCollateralAndBorrowFromMarketData,
    MagnetarWithdrawData,
    DepositRepayAndRemoveCollateralFromMarketData,
    IMintData,
    IDepositData,
    ICommonExternalContracts,
    MintFromBBAndLendOnSGLData,
    IRemoveAndRepay,
    ExitPositionAndRemoveCollateralData,
    IExerciseOptionsData,
    IOptionsLockData,
    IOptionsUnlockData
} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {MagnetarTestUtils, TestSingularityData, TestBigBangData} from "./MagnetarTestUtils.t.sol";
import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {ISingularity, IMarket} from "tap-utils/interfaces/bar/ISingularity.sol";
import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {MagnetarHelper} from "tapioca-periph/Magnetar/MagnetarHelper.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";

import {ZerroXSwapperMockTarget} from "../../utils/ZeroXSwapper/ZerroXSwapperMockTarget.sol";
import {ZeroXSwapper} from "tap-utils/Swapper/ZeroXSwapper.sol";

import {OracleMock} from "../mocks/OracleMock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

// Tests
import {ToeTokenReceiverMock} from "../mocks/ToeTokenMock/ToeTokenReceiverMock.sol";
import {ToeTokenSenderMock} from "../mocks/ToeTokenMock/ToeTokenSenderMock.sol";
import {ToeTokenMock} from "../mocks/ToeTokenMock/ToeTokenMock.sol";
import {ToeTestHelper} from "../../utils/LZSetup/ToeTestHelper.sol";
import {ERC1155Mock} from "../mocks/ERC1155Mock.sol";
import {TapOftMock} from "../mocks/TapOftMock.sol";
import {Weth9Mock} from "../mocks/Weth9Mock.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IBigBang} from "tap-utils/interfaces/bar/IBigBang.sol";

contract MagnetarTest is MagnetarTestUtils {
    Cluster cluster;
    Magnetar magnetar;
    MagnetarHelper magnetarHelper;
    Penrose penrose;
    OracleMock oracle;
    MarketHelper marketHelper;
    TapiocaOmnichainEngineHelper toeHelper;
    IBigBang bb;
    ERC20Mock aERC20;
    ERC20Mock bERC20;
    TapTokenMock tapToken;

    ERC20Mock asset;
    ERC20Mock collateral;

    /**
     * DEPLOY setup addresses
     */
    uint256 internal userAPKey = 0x1;
    uint256 internal userBPKey = 0x2;
    uint256 internal userCPKey = 0x3;
    address public userA = vm.addr(userAPKey);
    address public userB = vm.addr(userBPKey);
    address public userC = vm.addr(userCPKey);

    ISingularity sgl;

    error Magnetar_UserMismatch();

    modifier addRewardToken() {
        vm.startPrank(__admin);
        twTap.addRewardToken(IERC20(address(new ERC20Mock())));
        vm.stopPrank();
        _;
    }

    modifier withValidAmount(uint256 _amount) {
        vm.assume(_amount > 0);
        vm.assume(_amount < type(uint64).max);
        _;
    }

    function setUp() public override {
        super.setUp();
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.label(userA, "userA");
        vm.label(userB, "userB");

        cluster = Cluster(report.cluster);
        magnetar = Magnetar(payable(report.magnetar));
        penrose = Penrose(report.penrose);

        aERC20 = new ERC20Mock();
        bERC20 = new ERC20Mock();
        tapToken = TapTokenMock(payable(input.tapToken));
        asset = new ERC20Mock();
        collateral = ERC20Mock(input.wrappedNativeToken);

        magnetarHelper = MagnetarHelper(report.magnetarHelper);
        oracle = new OracleMock("Test", "TT", 1 ether);
        marketHelper = MarketHelper(report.marketHelper);

        sgl = ISingularity(address(launchSingularity(report, address(asset), address(collateral), address(oracle))));
        bb = IBigBang(address(launchBigBang(report, address(collateral))));

        vm.startPrank(report.tapiocaMulticall);
        cluster.updateContract(0, address(tapToken), true);
        cluster.updateContract(0, address(magnetar), true);
        cluster.updateContract(0, address(magnetarHelper), true);
        cluster.updateContract(0, address(oracle), true);
        cluster.updateContract(0, address(asset), true);
        cluster.updateContract(0, address(collateral), true);
        cluster.updateContract(0, address(marketHelper), true);
        cluster.updateContract(0, address(sgl), true);
        vm.stopPrank();

        vm.label(address(sgl), "Singularity");
        vm.label(address(magnetar), "Magnetar");
        vm.label(address(magnetarHelper), "MagnetarHelper");
        vm.label(address(oracle), "Oracle");
        vm.label(address(asset), "Asset");
        vm.label(address(collateral), "Collateral");
        vm.label(address(aERC20), "aERC20");
        vm.label(address(bERC20), "bERC20");
        vm.label(address(marketHelper), "MarketHelper");

        vm.startPrank(address(this));
        magnetar.setHelper(address(magnetarHelper));
        asset.approve(address(magnetar), type(uint256).max);
        collateral.approve(address(magnetar), type(uint256).max);

        vm.stopPrank();
    }

    function test_weth_wrap_through_burst() public {
        vm.skip(true);
        Weth9Mock weth9 = new Weth9Mock();
        cluster.updateContract(0, address(weth9), true);

        bytes memory wethDeposit = abi.encodeWithSelector(Weth9Mock.deposit.selector);
        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.WethWrap),
            target: address(weth9),
            value: 1 ether,
            call: wethDeposit
        });
        magnetar.burst{value: 1 ether}(calls);

        assertEq(weth9.balanceOf(address(this)), 1 ether);
    }

    function test_receive_erc1155() public {
        ERC1155Mock erc1155 = new ERC1155Mock();
        erc1155.mint(address(magnetar), 1, 1);
        assertEq(erc1155.balanceOf(address(magnetar), 1), 1);
    }

    function test_get_sgl_info() public view {
        ISingularity[] memory arr = new ISingularity[](1);
        arr[0] = ISingularity(address(sgl));

        MagnetarHelper.SingularityInfo[] memory response = magnetarHelper.singularityMarketInfo(address(this), arr);

        assertEq(response[0].market.totalCollateralShare, 0);
        assertEq(response[0].market.userCollateralShare, 0);
        assertEq(response[0].market.collateralizationRate, 75_000);
    }

    function test_lend() public {
        uint256 tokenAmount_ = 1 ether;

        deal(address(asset), userA, tokenAmount_);

        vm.startPrank(userA);

        asset.approve(address(magnetar), tokenAmount_);
        {
            bytes memory lendData =
                abi.encodeWithSelector(Singularity.addAsset.selector, address(userA), address(userA), tokenAmount_);

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({id: uint8(MagnetarAction.Market), target: address(sgl), value: 0, call: lendData});

            magnetar.burst(calls);
        }
        assertEq(asset.balanceOf(userA), 0, "asset balance of this");
        assertEq(asset.balanceOf(address(sgl)), tokenAmount_, "asset balance of sgl");
        assertEq(asset.balanceOf(address(magnetar)), 0, "asset balance of magnetar");
        assertEq(asset.allowance(address(sgl), address(magnetar)), 0, "asset allowance of sgl in magnetar");
        assertEq(sgl.liquidityBalance(userA), tokenAmount_, "sgl liquidity balance of user");
    }

    function test_repay() public {
        vm.skip(true);
        uint256 tokenAmount_ = 1 ether;
        uint256 borrowAmount_ = 1e17;
        uint256 repayDepositAmount_ = 1 ether;
        uint256 repayAmount_ = 1e17;

        {
            deal(address(asset), address(this), tokenAmount_);
            deal(address(collateral), address(this), tokenAmount_);
        }

        {
            // lend approvals
            asset.approve(address(magnetar), type(uint256).max);
            sgl.approve(address(magnetar), type(uint256).max);

            // collateral approvals
            collateral.approve(address(magnetar), type(uint256).max);

            // market operations approvals
            sgl.approve(address(magnetar), type(uint256).max);
            sgl.approveBorrow(address(magnetar), type(uint256).max);
        }
        {
            uint256 assetShare = sgl.convertToShares(tokenAmount_);
            bytes memory lendData =
                abi.encodeWithSelector(Singularity.addAsset.selector, address(this), address(this), false, assetShare);

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({id: uint8(MagnetarAction.Market), target: address(sgl), value: 0, call: lendData});

            magnetar.burst(calls);

            assertGt(sgl.balanceOf(address(this)), 0);
        }
        //add collateral
        {
            bytes memory depositAddCollateralAndBorrowFromMarketData = abi.encodeWithSelector(
                MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector,
                DepositAddCollateralAndBorrowFromMarketData({
                    market: address(sgl),
                    marketHelper: address(marketHelper),
                    user: address(this),
                    collateralAmount: tokenAmount_,
                    borrowAmount: borrowAmount_,
                    deposit: true,
                    withdrawParams: MagnetarWithdrawData({
                        asset: address(asset),
                        receiver: address(this),
                        amount: 0,
                        withdraw: false,
                        unwrap: false,
                        extractFromSender: false
                    })
                })
            );
            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.CollateralModule),
                target: address(sgl), // check
                value: 0,
                call: depositAddCollateralAndBorrowFromMarketData
            });

            magnetar.burst(calls);
        }

        // check collateral
        {
            uint256 colShare = sgl.balanceOf(address(this));
            uint256 colAmount = sgl.convertToAssets(colShare);
            assertEq(colAmount, tokenAmount_);
        }

        uint256 userBorrowPartBefore = sgl._userBorrowPart(address(this));
        deal(address(asset), address(this), repayDepositAmount_);
        // repay
        {
            bytes memory repayData = abi.encodeWithSelector(
                MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector,
                DepositRepayAndRemoveCollateralFromMarketData({
                    market: address(sgl),
                    marketHelper: address(marketHelper),
                    user: address(this),
                    depositAmount: repayDepositAmount_,
                    repayAmount: repayAmount_,
                    collateralAmount: 0,
                    withdrawCollateralParams: MagnetarWithdrawData({
                        asset: address(asset),
                        receiver: address(this),
                        amount: 0,
                        withdraw: false,
                        unwrap: false,
                        extractFromSender: false
                    })
                })
            );

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.CollateralModule),
                target: address(sgl),
                value: 0,
                call: repayData
            });

            sgl.approve(address(magnetar), type(uint256).max);

            magnetar.burst(calls);
        }

        // check repayment
        {
            uint256 userBorrowPart = sgl._userBorrowPart(address(this));
            assertLt(userBorrowPart, userBorrowPartBefore);
        }
    }

    function test_withdraw_sanitization() public {
        vm.skip(true);
        uint256 tokenAmount_ = 1 ether;
        uint256 borrowAmount_ = 1e17;

        //approvals
        {
            asset.approve(address(sgl), type(uint256).max);
            collateral.approve(address(sgl), type(uint256).max);
            sgl.approve(address(magnetar), type(uint256).max);
            sgl.approveBorrow(address(magnetar), type(uint256).max);
        }

        //deal
        {
            deal(address(asset), address(this), tokenAmount_);
            deal(address(collateral), address(this), tokenAmount_);
        }

        {
            uint256 assetShare = sgl.convertToShares(tokenAmount_);
            bytes memory lendData =
                abi.encodeWithSelector(Singularity.addAsset.selector, address(this), address(this), false, assetShare);

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({id: uint8(MagnetarAction.Market), target: address(sgl), value: 0, call: lendData});

            magnetar.burst(calls);

            assertGt(sgl.balanceOf(address(this)), 0);
        }

        //add collateral
        {
            bytes memory depositAddCollateralAndBorrowFromMarketData = abi.encodeWithSelector(
                MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector,
                DepositAddCollateralAndBorrowFromMarketData({
                    market: address(sgl),
                    marketHelper: address(marketHelper),
                    user: address(this),
                    collateralAmount: tokenAmount_,
                    borrowAmount: borrowAmount_,
                    deposit: true,
                    withdrawParams: MagnetarWithdrawData({
                        asset: address(asset),
                        receiver: address(this),
                        amount: 0,
                        withdraw: false,
                        unwrap: false,
                        extractFromSender: false
                    })
                })
            );
            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.CollateralModule),
                target: address(sgl),
                value: 0,
                call: depositAddCollateralAndBorrowFromMarketData
            });

            magnetar.burst(calls);
        }

        {
            uint256 colAmount = sgl.balanceOf(address(this));
            assertEq(colAmount, tokenAmount_);
        }

        {
            (Module[] memory borrowCallModules, bytes[] memory borrowCalls) =
                marketHelper.borrow(address(this), address(this), borrowAmount_);
            sgl.execute(borrowCallModules, borrowCalls, true);

            uint256 borrowPart = sgl._userBorrowPart(address(this));
            assertGt(borrowPart, 0);
        }

        {
            MagnetarWithdrawData memory withdrawData = MagnetarWithdrawData({
                asset: address(asset),
                receiver: address(this),
                amount: borrowAmount_,
                withdraw: true,
                unwrap: true,
                extractFromSender: false
            });
            MagnetarCall[] memory calls = new MagnetarCall[](0);

            vm.expectRevert(); //fails with Magnetar_UserMismatch
            magnetar.burst(calls);
        }
    }

    function test_withdraw() public {
        vm.skip(true);
        test_lend();

        uint256 tokenAmount_ = 1 ether;
        uint256 borrowAmount_ = 1e17;

        //approvals
        {
            asset.approve(address(sgl), type(uint256).max);
            collateral.approve(address(sgl), type(uint256).max);
            sgl.approve(address(magnetar), type(uint256).max);
            sgl.approveBorrow(address(magnetar), type(uint256).max);
        }

        //deal
        {
            deal(address(asset), address(this), tokenAmount_);
            deal(address(collateral), address(this), tokenAmount_);
        }

        {
            uint256 assetShare = sgl.convertToShares(tokenAmount_);
            bytes memory lendData =
                abi.encodeWithSelector(Singularity.addAsset.selector, address(this), address(this), false, assetShare);

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({id: uint8(MagnetarAction.Market), target: address(sgl), value: 0, call: lendData});

            magnetar.burst(calls);

            assertGt(sgl.balanceOf(address(this)), 0);
        }

        //add collateral
        {
            bytes memory depositAddCollateralAndBorrowFromMarketData = abi.encodeWithSelector(
                MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector,
                DepositAddCollateralAndBorrowFromMarketData({
                    market: address(sgl),
                    marketHelper: address(marketHelper),
                    user: address(this),
                    collateralAmount: tokenAmount_,
                    borrowAmount: borrowAmount_,
                    deposit: true,
                    withdrawParams: MagnetarWithdrawData({
                        asset: address(asset),
                        receiver: address(this),
                        amount: 0,
                        withdraw: false,
                        unwrap: false,
                        extractFromSender: false
                    })
                })
            );
            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.CollateralModule),
                target: address(sgl),
                value: 0,
                call: depositAddCollateralAndBorrowFromMarketData
            });

            magnetar.burst(calls);
        }

        {
            uint256 colAmount = sgl.balanceOf(address(this));
            assertEq(colAmount, tokenAmount_);
        }

        {
            (Module[] memory borrowCallModules, bytes[] memory borrowCalls) =
                marketHelper.borrow(address(this), address(this), borrowAmount_);
            sgl.execute(borrowCallModules, borrowCalls, true);

            uint256 borrowPart = sgl._userBorrowPart(address(this));
            assertGt(borrowPart, 0);
        }

        {
            MagnetarWithdrawData memory withdrawData = MagnetarWithdrawData({
                asset: address(asset),
                receiver: address(this),
                amount: borrowAmount_,
                withdraw: true,
                unwrap: false,
                extractFromSender: false
            });
            MagnetarCall[] memory calls = new MagnetarCall[](0);

            magnetar.burst(calls);

            uint256 balanceOf = asset.balanceOf(address(this));
            assertGt(balanceOf, 0);
            assertEq(balanceOf, borrowAmount_);
        }
    }

    function test_magnetar_execute_decode() public {
        vm.skip(true);
        uint256 tokenAmount_ = 1 ether;

        //deal
        {
            deal(address(collateral), address(this), tokenAmount_);
        }

        {
            MagnetarCall[] memory magnetarCalls = new MagnetarCall[](2);
            collateral.approve(address(magnetar), type(uint256).max);

            Module[] memory modules;
            bytes[] memory calls;
            (modules, calls) = marketHelper.addCollateral(address(this), address(this), tokenAmount_, 0);
            bytes memory data = abi.encodeWithSelector(IMarket.execute.selector, modules, calls, true);

            magnetarCalls[1] =
                MagnetarCall({id: uint8(MagnetarAction.Market), target: address(bb), value: 0, call: data});

            magnetar.burst(magnetarCalls);
        }
    }

    function test_mint() public {
        vm.skip(true);
        uint256 tokenAmount_ = 1 ether;
        uint256 mintAmount_ = 1e17;

        bb.approveBorrow(address(magnetar), type(uint256).max);

        {
            deal(address(collateral), address(this), tokenAmount_);
        }

        {
            bytes memory mintData = abi.encodeWithSelector(
                MagnetarMintModule.mintBBAndLock.selector,
                MintFromBBAndLendOnSGLData({
                    user: address(this),
                    lendAmount: 0,
                    mintData: IMintData({
                        mint: true,
                        mintAmount: mintAmount_,
                        collateralDepositData: IDepositData({deposit: true, amount: tokenAmount_})
                    }),
                    depositData: IDepositData({deposit: false, amount: 0}),
                    lockData: IOptionsLockData({
                        lock: false,
                        target: address(0),
                        bucketId: 0,
                        to: address(this),
                        sglMarket: address(0),
                        usdoAmount: 0
                    }),
                    externalContracts: ICommonExternalContracts({
                        singularity: address(0),
                        magnetar: address(magnetar),
                        bigBang: address(bb),
                        marketHelper: address(marketHelper)
                    })
                })
            );

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.MintModule),
                target: address(bb), //this is ignored
                value: 0,
                call: mintData
            });

            magnetar.burst(calls);
        }

        // checks
        {
            uint256 colShare = bb.balanceOf(address(this));
            assertGt(colShare, 0);
        }
    }

    function test_exit_and_remove_collateral() public {
        vm.skip(true);
        bb.approve(address(magnetar), type(uint256).max);

        uint256 tokenAmount_ = 1 ether;
        uint256 mintAmount_ = 1e17;

        collateral.approve(address(magnetar), type(uint256).max);
        asset.approve(address(magnetar), type(uint256).max);

        bb.approveBorrow(address(magnetar), type(uint256).max);

        //deal
        {
            deal(address(collateral), address(this), tokenAmount_);
        }

        //mint
        {
            bytes memory mintData = abi.encodeWithSelector(
                MagnetarMintModule.mintBBAndLock.selector,
                MintFromBBAndLendOnSGLData({
                    user: address(this),
                    lendAmount: 0,
                    mintData: IMintData({
                        mint: true,
                        mintAmount: mintAmount_,
                        collateralDepositData: IDepositData({deposit: true, amount: tokenAmount_})
                    }),
                    depositData: IDepositData({deposit: false, amount: 0}),
                    lockData: IOptionsLockData({
                        lock: false,
                        target: address(0),
                        bucketId: 0,
                        to: address(this),
                        sglMarket: address(0),
                        usdoAmount: 0
                    }),
                    externalContracts: ICommonExternalContracts({
                        singularity: address(0),
                        magnetar: address(magnetar),
                        bigBang: address(bb),
                        marketHelper: address(marketHelper)
                    })
                })
            );

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.MintModule),
                target: address(bb), //this is ignored
                value: 0,
                call: mintData
            });

            magnetar.burst(calls);
        }

        uint256 colShare = bb.balanceOf(address(this));
        assertGt(colShare, 0);

        uint256 repayAmount_ = bb._userBorrowPart(address(this));
        // exit and remove
        {
            IERC20(bb._asset()).approve(address(magnetar), type(uint256).max);

            deal(address(asset), address(this), repayAmount_); //deal more asset to be able to fully repay
            uint256 assetShare = bb.convertToShares(repayAmount_);

            bytes memory removeData = abi.encodeWithSelector(
                MagnetarOptionModule.exitPositionAndRemoveCollateral.selector,
                ExitPositionAndRemoveCollateralData({
                    user: address(this),
                    externalData: ICommonExternalContracts({
                        magnetar: address(magnetar),
                        singularity: address(0),
                        bigBang: address(bb),
                        marketHelper: address(marketHelper)
                    }),
                    removeAndRepayData: IRemoveAndRepay({
                        removeAssetFromSGL: false,
                        removeAmount: 0,
                        repayAssetOnBB: true,
                        repayAmount: repayAmount_,
                        removeCollateralFromBB: true,
                        collateralAmount: tokenAmount_ / 2,
                        unlockData: IOptionsUnlockData({
                            unlock: false,
                            target: address(0),
                            bucketId: 0,
                            to: address(this),
                            amount: 0
                        }),
                        assetWithdrawData: MagnetarWithdrawData({
                            asset: address(asset),
                            receiver: address(this),
                            amount: 0,
                            withdraw: false,
                            unwrap: false,
                            extractFromSender: false
                        }),
                        collateralWithdrawData: MagnetarWithdrawData({
                            asset: address(collateral),
                            receiver: address(this),
                            amount: 0,
                            withdraw: false,
                            unwrap: false,
                            extractFromSender: false
                        })
                    })
                })
            );

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.OptionModule),
                target: address(bb), //this is ignored
                value: 0,
                call: removeData
            });

            magnetar.burst(calls);
        }
    }

    function test_sgl_lend() public {
        vm.skip(true);
        uint256 tokenAmount_ = 1 ether;

        // lend approvals
        sgl.approve(address(magnetar), type(uint256).max);

        //deal
        {
            deal(address(asset), address(this), tokenAmount_);
        }

        {
            uint256 assetShare = sgl.convertToShares(tokenAmount_);
            bytes memory mintData = abi.encodeWithSelector(
                MagnetarMintModule.mintBBAndLock.selector,
                MintFromBBAndLendOnSGLData({
                    user: address(this),
                    lendAmount: tokenAmount_,
                    mintData: IMintData({
                        mint: false,
                        mintAmount: 0,
                        collateralDepositData: IDepositData({deposit: false, amount: 0})
                    }),
                    depositData: IDepositData({deposit: false, amount: 0}),
                    lockData: IOptionsLockData({
                        lock: false,
                        target: address(0),
                        bucketId: 0,
                        to: address(this),
                        sglMarket: address(0),
                        usdoAmount: 0
                    }),
                    externalContracts: ICommonExternalContracts({
                        singularity: address(sgl),
                        magnetar: address(magnetar),
                        bigBang: address(0),
                        marketHelper: address(marketHelper)
                    })
                })
            );

            MagnetarCall[] memory calls = new MagnetarCall[](1);
            calls[0] = MagnetarCall({
                id: uint8(MagnetarAction.MintModule),
                target: address(sgl), //this is ignored
                value: 0,
                call: mintData
            });

            magnetar.burst(calls);
        }

        // checks
        {
            uint256 lentAmount = sgl.balanceOf(address(this));
            assertGt(lentAmount, 0);
        }
    }

    function test_exercise_option() public {
        vm.skip(true);
        TapOftMock tapOft = new TapOftMock();
        TapOftMock oTAP = new TapOftMock();
        ERC20Mock paymentToken = new ERC20Mock();
        TapiocaOptionBroker tOb = TapiocaOptionBroker(address(0)); // replace mock with tob

        cluster.updateContract(0, address(tOb), true);
        cluster.updateContract(0, address(tapOft), true);
        cluster.updateContract(0, address(paymentToken), true);

        deal(address(paymentToken), address(this), 1 ether);

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.ExerciseOption),
            target: address(tOb),
            value: 0,
            call: abi.encodeWithSelector(TapiocaOptionBroker.exerciseOption.selector, 0, address(paymentToken), 1 ether)
        });
        magnetar.burst(calls);

        uint256 balanceOfTap = tapOft.balanceOf(address(this));
        assertEq(balanceOfTap, 1 ether);
    }

    function test_toe_sendPacketFrom() public {
        vm.skip(true);
        uint256 tokenAmount_ = 1 ether;

        (ToeTokenMock aToeOFT, ToeTokenMock bToeOFT) = _getToeMock();

        {
            deal(address(aToeOFT), address(this), tokenAmount_);
        }
        cluster.updateContract(0, address(aToeOFT), true);
        cluster.setRoleForContract(address(magnetar), keccak256("TOE"), true);

        PrepareLzCallReturn memory prepareLzCallReturn_ = toeHelper.prepareLzCall(
            ITapiocaOmnichainEngine(address(aToeOFT)),
            PrepareLzCallData({
                dstEid: bEid,
                recipient: OFTMsgCodec.addressToBytes32(address(this)),
                amountToSendLD: tokenAmount_,
                minAmountToCreditLD: tokenAmount_,
                msgType: 1,
                composeMsgData: ComposeMsgData({
                    index: 0,
                    gas: 1_000_000,
                    value: 0,
                    data: bytes(""),
                    prevData: bytes(""),
                    prevOptionsData: bytes("")
                }),
                lzReceiveGas: 1_000_000,
                lzReceiveValue: 0,
                refundAddress: address(this)
            })
        );

        bytes memory sendTokenFromCall = abi.encodeWithSelector(
            ITapiocaOmnichainEngine.sendPacketFrom.selector, address(this), prepareLzCallReturn_.lzSendParam, "0x"
        );
        uint256 feeValue = prepareLzCallReturn_.msgFee.nativeFee * 2;

        MagnetarCall[] memory calls = new MagnetarCall[](1);
        calls[0] = MagnetarCall({
            id: uint8(MagnetarAction.OFT),
            target: address(aToeOFT),
            value: feeValue,
            call: sendTokenFromCall
        });

        magnetar.burst{value: feeValue}(calls);

        assertEq(bToeOFT.balanceOf(address(this)), 0);
        verifyPackets(uint32(bEid), address(bToeOFT));

        assertEq(bToeOFT.balanceOf(address(this)), tokenAmount_);
    }

    function _getToeMock() private returns (ToeTokenMock aToeOFT, ToeTokenMock bToeOFT) {
        setUpEndpoints(3, LibraryType.UltraLightNode);
        address __extExec = address(new TapiocaOmnichainExtExec());

        aToeOFT = ToeTokenMock(
            payable(
                _deployOApp(
                    type(ToeTokenMock).creationCode,
                    abi.encode(
                        address(endpoints[aEid]),
                        __owner,
                        __extExec,
                        address(
                            new ToeTokenSenderMock("", "", address(endpoints[aEid]), address(this), address(0), cluster)
                        ),
                        address(
                            new ToeTokenReceiverMock(
                                "", "", address(endpoints[aEid]), address(this), address(0), cluster
                            )
                        ),
                        cluster
                    )
                )
            )
        );
        vm.label(address(aToeOFT), "aToeOFT");
        bToeOFT = ToeTokenMock(
            payable(
                _deployOApp(
                    type(ToeTokenMock).creationCode,
                    abi.encode(
                        address(endpoints[bEid]),
                        __owner,
                        address(__extExec),
                        address(
                            new ToeTokenSenderMock("", "", address(endpoints[bEid]), address(this), address(0), cluster)
                        ),
                        address(
                            new ToeTokenReceiverMock(
                                "", "", address(endpoints[bEid]), address(this), address(0), cluster
                            )
                        ),
                        cluster
                    )
                )
            )
        );
        vm.label(address(bToeOFT), "bToeOFT");

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aToeOFT);
        ofts[1] = address(bToeOFT);
        this.wireOApps(ofts);
    }

    function test_burst_tapLock_valid(uint160 _participantPk, uint256 _amount) external withValidAmount(_amount) {
        address _participant = _assumeValidAddress(_participantPk, "participant");
        _withTapTokenBalance(_participant, _amount);
        uint8 _bucketId = 0;

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] = _getTapTokenPermitMagnetarCall(_participantPk, address(twTap), _amount, 1 days);
        calls[1] = _getTwTapParticipateMagnetarCall(_participant, _amount, _bucketId);

        (,,,,,, uint24 bucketLockEpochDuration,,,) = twTap.buckets(_bucketId);

        vm.startPrank(_participant);
        twTap.setDelegatee(_bucketId, address(magnetar));
        uint56 expiry = uint56(block.timestamp + (bucketLockEpochDuration * EPOCH_DURATION));
        magnetar.burst(calls);
        vm.stopPrank();

        _assertTwTapParticipation(twTap, _participant, _bucketId, _amount, expiry, 0, address(magnetar));
    }

    function test_burst_tapUnlock_valid(uint160 _participantPk, uint256 _amount) external withValidAmount(_amount) {
        address _participant = _assumeValidAddress(_participantPk, "participant");
        _withTapTokenBalance(_participant, _amount);
        uint8 _bucketId = 0;

        _withTwTapParticipation(_participantPk, _amount, _bucketId);
        (,,,,,, uint24 bucketLockEpochDuration,,,) = twTap.buckets(_bucketId);

        vm.warp(block.timestamp + (bucketLockEpochDuration * EPOCH_DURATION));

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] = _getTapTokenPermitMagnetarCall(_participantPk, address(twTap), _amount, 1 days);
        calls[1] = _getTwTapExitPositionMagnetarCall(_participant, _bucketId);

        vm.startPrank(_participant);
        twTap.setDelegatee(_bucketId, address(magnetar));
        magnetar.burst(calls);
        vm.stopPrank();
    }

    function test_burst_tapReuseParticipation_valid(uint160 _participantPk, uint256 _amount) external withValidAmount(_amount) {
        address _participant = _assumeValidAddress(_participantPk, "participant");
        _withTapTokenBalance(_participant, _amount);
        uint8 _bucketId = 0;

        _withTwTapParticipation(_participantPk, _amount, _bucketId);
        (,,,,,, uint24 bucketLockEpochDuration,,,) = twTap.buckets(_bucketId);

        console.log("bucketLockEpochDuration:   ", bucketLockEpochDuration);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] = _getTapTokenPermitMagnetarCall(_participantPk, address(twTap), _amount, 1 days);
        calls[1] = _getTwTapReuseParticipationMagnetarCall(_participant, _bucketId);

        vm.startPrank(_participant);
        twTap.setDelegatee(_bucketId, address(magnetar));
        magnetar.burst(calls);
        uint56 expiry = uint56(block.timestamp + (bucketLockEpochDuration * EPOCH_DURATION));
        vm.stopPrank();

        _assertTwTapParticipation(twTap, _participant, _bucketId, _amount * 2, expiry, 0, address(magnetar));
    }

    function test_burst_skipEpochsAndparticipate_valid_nonReentrantShouldNotHappen(uint160 _participantPk, uint256 _amount)
        external
        withValidAmount(_amount)
    {
        address _participant = _assumeValidAddress(_participantPk, "participant");
        _withTapTokenBalance(_participant, _amount);
        uint8 _bucketId = 0;
        uint56 _skipEpochs = 2;
        skip(EPOCH_DURATION * _skipEpochs);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] = _getTapTokenPermitMagnetarCall(_participantPk, address(twTap), _amount, 1 days);
        calls[1] = _getTwTapParticipateMagnetarCall(_participant, _amount, _bucketId);

        (,,,,,, uint24 bucketLockEpochDuration,,,) = twTap.buckets(_bucketId);

        vm.startPrank(_participant);
        twTap.setDelegatee(_bucketId, address(magnetar));
        uint56 expiry = uint56(block.timestamp + EPOCH_DURATION);
        magnetar.burst(calls);
        vm.stopPrank();

        _assertTwTapParticipation(twTap, _participant, _bucketId, _amount, expiry, _skipEpochs, address(magnetar));
    }

    function test_burst_tapBatchClaimRewards_valid(uint160 _participantPk, uint256 _amount, uint256 _rewardAmount)
        external
        withValidAmount(_amount)
        withValidAmount(_rewardAmount)
        addRewardToken()
    {
        address _participant = _assumeValidAddress(_participantPk, "participant");
        _withTapTokenBalance(_participant, _amount);
        uint8 _bucketId = 0;

        _withTwTapParticipation(_participantPk, _amount, _bucketId);
        (,,,,,, uint24 bucketLockEpochDuration,,,) = twTap.buckets(_bucketId);
        uint256 weeksToSkip = 1;
        skip(EPOCH_DURATION * bucketLockEpochDuration * weeksToSkip);

        twTap.advanceWeek(2);
        _distributeRewards(_rewardAmount);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] = _getTapTokenPermitMagnetarCall(_participantPk, address(twTap), _amount, 1 days);
        calls[1] = _getTwTapBatchClaimRewardsMagnetarCall(_participant, _bucketId);

        vm.startPrank(_participant);
        twTap.setDelegatee(_bucketId, address(magnetar));
        magnetar.burst(calls);
        vm.stopPrank();

        // Index-0 is reserved for the zero address. Check twTap constructor.
        IERC20[] memory rewardTokens = twTap.getRewardTokens();
        assertGe(rewardTokens.length, 1, "No reward tokens");
        for (uint256 i = 1; i < rewardTokens.length; i++) {
            // TODO assertGt(rewardTokens[i].balanceOf(_participant), 0, "Invalid reward token balance");
        }
    }

    function _distributeRewards(uint256 _amount) internal {
        vm.startPrank(__admin);
        IERC20[] memory rewardTokens = twTap.getRewardTokens();
        for (uint256 i = 1; i < rewardTokens.length; i++) {
            ERC20Mock _rewardToken = ERC20Mock(address(rewardTokens[i]));
            _rewardToken.mint(__admin, _amount);
            _rewardToken.approve(address(twTap), _amount);
            twTap.distributeReward(i, _amount);
        }
        vm.stopPrank();
    }

    function _getTwTapBatchClaimRewardsMagnetarCall(address _participant, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        uint256[] memory _bucketIds = new uint256[](1);
        _bucketIds[0] = _bucketId;
        bytes memory twTapCallData = abi.encodeWithSelector(TwTAP.batchClaimRewards.selector, _participant, _bucketIds);
        return MagnetarCall({
            id: uint8(MagnetarAction.TapBatchClaimRewards),
            target: address(twTap),
            value: 0,
            call: twTapCallData
        });
    }

    function _getTwTapReuseParticipationMagnetarCall(address _participant, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory twTapCallData = abi.encodeWithSelector(TwTAP.reuseParticipation.selector, _participant, _bucketId);
        return MagnetarCall({id: uint8(MagnetarAction.TapExtendLock), target: address(twTap), value: 0, call: twTapCallData});
    }

    function _getTwTapExitPositionMagnetarCall(address _participant, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory twTapCallData =
            abi.encodeWithSelector(TwTAP.exitPosition.selector, _participant, _participant, _bucketId);
        return
            MagnetarCall({id: uint8(MagnetarAction.TapUnlock), target: address(twTap), value: 0, call: twTapCallData});
    }

    function _getTwTapParticipateMagnetarCall(address _participant, uint256 _amount, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory twTapCallData =
            abi.encodeWithSelector(TwTAP.participate.selector, _participant, _amount, _bucketId);
        return MagnetarCall({id: uint8(MagnetarAction.TapLock), target: address(twTap), value: 0, call: twTapCallData});
    }

    function _getTapTokenPermitMagnetarCall(
        uint256 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset
    ) internal view returns (MagnetarCall memory) {
        address _owner = vm.addr(_ownerPk);
        ERC20PermitStruct memory _permitStruct = ERC20PermitStruct({
            owner: _owner,
            spender: _spender,
            value: _amount,
            nonce: tapToken.nonces(_owner),
            deadline: block.timestamp + _deadlineOffset
        });
        bytes32 _digest = tapToken.getTypedDataHash(_permitStruct);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_ownerPk, _digest);
        bytes memory tapTokenPermitCallData = abi.encodeWithSelector(
            IERC20Permit.permit.selector,
            _permitStruct.owner,
            _permitStruct.spender,
            _permitStruct.value,
            _permitStruct.deadline,
            v,
            r,
            s
        );
        return MagnetarCall({
            id: uint8(MagnetarAction.Permit),
            target: address(tapToken),
            value: 0,
            call: tapTokenPermitCallData
        });
    }

    function _withTwTapParticipation(uint160 _participantPk, uint256 _amount, uint8 _bucketId) internal {
        address _participant = vm.addr(_participantPk);

        MagnetarCall[] memory calls = new MagnetarCall[](2);
        calls[0] = _getTapTokenPermitMagnetarCall(_participantPk, address(twTap), _amount, 1 days);
        calls[1] = _getTwTapParticipateMagnetarCall(_participant, _amount, _bucketId);

        (,,,,,, uint24 bucketLockEpochDuration,,,) = twTap.buckets(_bucketId);

        vm.startPrank(_participant);
        twTap.setDelegatee(_bucketId, address(magnetar));
        uint56 expiry = uint56(block.timestamp + (bucketLockEpochDuration * EPOCH_DURATION));
        magnetar.burst(calls);
        twTap.setDelegatee(_bucketId, address(0x0));
        vm.stopPrank();
        _assertTwTapParticipation(twTap, _participant, _bucketId, _amount, expiry, 0, address(0x0));
    }

    function _assumeValidAddress(uint160 _addressPk, string memory _label) internal returns (address _address) {
        vm.assume(_addressPk > 0);
        _address = vm.addr(_addressPk);
        vm.assume(_address != address(0));
        vm.assume(_address != address(this));
        vm.assume(_address != address(magnetar));
        vm.assume(_address != address(__admin));
        vm.assume(_address != address(__owner));
        vm.label(_address, _label);
        return _address;
    }

    function _withTapTokenBalance(address _participant, uint256 _amount) internal {
        TapTokenMock _tapToken = TapTokenMock(payable(IPenrose(report.penrose).tapToken()));
        assertNotEq(address(_tapToken), address(0), "tapToken is not set");
        assertNotEq(address(twTap), address(0), "twTap is not set");
        _tapToken.freeMint(_participant, _amount);
    }

    function _assertTwTapParticipation(
        TwTAP _twTap,
        address _participant,
        uint8 _bucketId,
        uint256 _amount,
        uint56 _expiry,
        uint56 _lastInactive,
        address _delegatee
    ) internal view {
        (
            uint8 bucketId,
            bool tapReleased,
            /*uint240 lockedAt*/,
            uint56 expiry,
            uint88 tapAmount,
            /*uint24 multiplier*/,
            uint40 lastInactive,
            uint40 lastActive,
            address delegatee
        ) = _twTap.participations(_participant, _bucketId);
        assertEq(bucketId, _bucketId, "Invalid bucket id");
        assertEq(tapReleased, false, "Invalid tap released");
        assertEq(expiry, _expiry, "Invalid expiry");
        assertEq(tapAmount, _amount, "Invalid tap amount");
        assertEq(lastInactive, _lastInactive, "Invalid last inactive");
        assertNotEq(lastActive, 0, "Invalid last active");
        assertEq(delegatee, _delegatee, "Invalid delegatee");
    }
}

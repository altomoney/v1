// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {Market, PauseType} from "tapioca-bar/markets/Market.sol";
import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";
import {MagnetarHelper} from "tapioca-periph/Magnetar/MagnetarHelper.sol";

import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IOracle} from "tap-utils/oracle/interfaces/IOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";
import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {MarketLiquidatorReceiverMock} from "../mocks/MarketLiquidatorReceiverMock.sol";
import {MarketLiquidatorReceiverAddAssetReentrancy} from
    "../mocks/liquidatorReceivers/MarketLiquidatorReceiverAddAssetReentrancy.sol";
import {MagnetarMock} from "../mocks/MagnetarMock.sol";
import {SwapperMock} from "../mocks/SwapperMock.sol";
import {OracleMock} from "../mocks/OracleMock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {TwTapMock} from "../mocks/TwTapMock.sol";
import {UsdoMock} from "../mocks/UsdoMock.sol";
import {TOFTMock} from "../mocks/TOFTMock.sol";

import {UsdoHelper} from "tapioca-bar/usdo/extensions/UsdoHelper.sol";
import {UsdoSender} from "tapioca-bar/usdo/modules/UsdoSender.sol";

import {UsdoTestHelper, TestPenroseData, TestSingularityData} from "../helpers/UsdoTestHelper.t.sol";

import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {SingularityLauncher} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {RiskParams} from "deployments/interfaces/ISingularityLauncher.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";

import "forge-std/Test.sol";

contract SingularityTest is UsdoTestHelper {
    uint32 aEid = 1;
    uint32 bEid = 2;

    Cluster cluster;

    ERC20Mock tapOFT;
    ERC20Mock weth;

    ERC20Mock assetErc20;
    ERC20Mock collateralErc20;
    TOFTMock asset;
    TOFTMock collateral;

    MagnetarMock magnetar;

    UsdoHelper usdoHelper;

    SwapperMock swapper;
    Penrose penrose;
    SimpleLeverageExecutor leverageExecutor;
    Singularity masterContract;
    Singularity singularity;
    SingularityLauncher singularityLauncher;
    SGLInit sglInit;
    MarketHelper marketHelper;
    OracleMock oracle;
    MarketLiquidatorReceiverMock liquidatorMock;
    MagnetarHelper magnetarHelper;

    uint256 internal userAPKey = 0x1;
    uint256 internal userBPKey = 0x2;
    address public userA = vm.addr(userAPKey);
    address public userB = vm.addr(userBPKey);
    uint256 public initialBalance = 100 ether;
    address owner;
    TapiocaInput input;
    TapiocaReport report;

    function setUp() public override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.label(userA, "userA");
        vm.label(userB, "userB");

        owner = address(this);
        TapiocaReport memory emptyReport;

        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));

        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXSwapper = address(1);
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);
        singularityLauncher = new SingularityLauncher(
            report.sglLiquidationModule,
            report.sglBorrowModule,
            report.sglCollateralModule,
            report.sglLeverageModule,
            report.sglInit,
            report.penrose,
            report.simpleLeverageExecutor,
            report.sglInterestHelper,
            report.singularity
        );

        {
            tapOFT = new ERC20Mock("Tapioca OFT", "TAP");
            vm.label(address(tapOFT), "tapOFT");

            weth = new ERC20Mock("Wrapped Ethereum", "WETH");
            vm.label(address(weth), "WETH");

            assetErc20 = new ERC20Mock("AERC", "AERC");
            vm.label(address(assetErc20), "assetErc20");

            collateralErc20 = new ERC20Mock("CERC", "CERC");
            vm.label(address(collateralErc20), "collateralErc20");

            asset = new TOFTMock(address(assetErc20));
            vm.label(address(asset), "asset");

            collateral = new TOFTMock(address(collateralErc20));
            vm.label(address(collateral), "collateral");
        }

        marketHelper = MarketHelper(report.marketHelper);
        magnetarHelper = MagnetarHelper(report.magnetarHelper);

        setUpEndpoints(3, LibraryType.UltraLightNode);

        {
            cluster = Cluster(report.cluster);
            magnetar = MagnetarMock(report.magnetar);
            sglInit = SGLInit(report.sglInit);
            penrose = Penrose(report.penrose);
            liquidatorMock = new MarketLiquidatorReceiverMock(IERC20(address(asset)));

            vm.label(address(endpoints[aEid]), "aEndpoint");
            vm.label(address(endpoints[bEid]), "bEndpoint");
            vm.label(address(cluster), "Cluster");
            vm.label(address(magnetar), "Magnetar");
        }

        oracle = new OracleMock("Oracle Test", "ORCT", 1 ether);
        singularity = launchSingularity(address(asset), address(collateral), address(oracle));
        vm.label(address(singularity), "Singularity");
    }

    function depositAsset(uint256 amount) public returns (uint256 fraction) {
        deal(address(asset), address(this), amount);
        IERC20(singularity.borrowableToken()).approve(address(singularity), amount);
        fraction = singularity.addAsset(address(this), address(this), amount);
    }

    function depositCollateral(uint256 amount) public {
        deal(address(collateral), address(this), amount);
        collateral.approve(address(singularity), type(uint256).max);

        uint256 share = singularity.convertToShares(amount);
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.addCollateral(address(this), address(this), amount, 0);
        singularity.execute(modules, calls, true);
    }

    function borrow(uint256 amount, bool expectRevert) public {
        (Module[] memory modules, bytes[] memory calls) = marketHelper.borrow(address(this), address(this), amount);

        if (expectRevert) vm.expectRevert();
        singularity.execute(modules, calls, true);
    }

    function repay(uint256 part) public {
        asset.approve(address(singularity), type(uint256).max);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.repay(address(this), address(this), part);
        singularity.execute(modules, calls, true);
    }

    function test_setSingularityConfig() public {
        uint256 borrowingOpeningFee = singularity.borrowOpeningFee();
        uint256 liquidationMultiplier = singularity._liquidationMultiplier();
        uint256 minimumTargetUtilization = singularity.minimumTargetUtilization();
        uint256 maximumTargetUtilization = singularity.maximumTargetUtilization();
        uint256 minimumInterestPerSecond = singularity.minimumInterestPerSecond();
        uint256 maximumInterestPerSecond = singularity.maximumInterestPerSecond();
        uint256 interestElasticity = singularity.interestElasticity();

        bytes memory payload = abi.encodeWithSelector(
            Singularity.setSingularityConfig.selector, singularity.borrowOpeningFee(), 0, 0, 0, 0, 0, 0, address(0), 0
        );
        address[] memory mc = new address[](1);
        mc[0] = address(singularity);

        bytes[] memory data = new bytes[](1);
        data[0] = payload;
        vm.prank(penrose.owner());
        penrose.executeMarketFn(mc, data, false);

        {
            assertEq(singularity.borrowOpeningFee(), borrowingOpeningFee);
            assertEq(singularity._liquidationMultiplier(), liquidationMultiplier);
            assertEq(singularity.minimumTargetUtilization(), minimumTargetUtilization);
            assertEq(singularity.maximumTargetUtilization(), maximumTargetUtilization);
            assertEq(singularity.minimumInterestPerSecond(), minimumInterestPerSecond);
            assertEq(singularity.maximumInterestPerSecond(), maximumInterestPerSecond);
            assertEq(singularity.interestElasticity(), interestElasticity);
        }

        uint256 toSetValue = 101;
        {
            payload = abi.encodeWithSelector(
                Singularity.setSingularityConfig.selector, toSetValue, 0, 0, 0, 0, 0, 0, address(0), 0
            );
            data = new bytes[](1);
            data[0] = payload;
            vm.prank(penrose.owner());
            penrose.executeMarketFn(mc, data, false);
        }
        assertEq(singularity.borrowOpeningFee(), toSetValue);
    }

    function test_setMarketConfig() public {
        address toSetAddress = address(userA);
        uint256 toSetValue = 101;
        uint256 toSetMaxValue = 102;
        {
            bytes memory payload = abi.encodeWithSelector(
                Market.setMarketConfig.selector,
                toSetAddress,
                "",
                toSetValue,
                toSetValue,
                toSetValue,
                toSetMaxValue,
                toSetValue,
                toSetValue,
                toSetMaxValue,
                toSetValue,
                toSetValue
            );
            address[] memory mc = new address[](1);
            mc[0] = address(singularity);

            bytes[] memory data = new bytes[](1);
            data[0] = payload;
            vm.prank(penrose.owner());
            penrose.executeMarketFn(mc, data, false);
        }

        {
            assertEq(address(singularity._oracle()), address(toSetAddress));
            assertEq(singularity._protocolFee(), toSetValue);
            assertEq(singularity._minLiquidatorReward(), toSetValue);
            assertEq(singularity._maxLiquidatorReward(), toSetMaxValue);
            assertEq(singularity._totalBorrowCap(), toSetValue);
            assertEq(singularity._collateralizationRate(), toSetValue);
            assertEq(singularity._liquidationCollateralizationRate(), toSetMaxValue);
            assertEq(singularity._minBorrowAmount(), toSetValue);
        }
    }

    function test_initialize_twice() public {
        vm.expectRevert();
        singularity.init(address(sglInit), "");
        singularity.accrue();
    }

    function test_remove_everything() public {
        uint256 tokenAmount_ = 1 ether;
        depositAsset(tokenAmount_);
        assertGt(singularity.liquidityBalance(address(this)), 0);

        uint256 share = singularity.convertToShares(tokenAmount_);
        vm.expectRevert();
        singularity.removeAsset(address(this), address(this), share);
    }

    function test_should_not_work_when_paused() public {
        {
            ICluster _cl = penrose.cluster();
            vm.prank(Cluster(address(_cl)).owner());
            _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);
            bytes memory payload =
                abi.encodeWithSelector(Market.setMarketConfig.selector, address(0), "", 0, 0, 0, 0, 0, 0, 0, 0, 0);
            address[] memory mc = new address[](1);
            mc[0] = address(singularity);

            bytes[] memory data = new bytes[](1);
            data[0] = payload;
            vm.prank(penrose.owner());
            penrose.executeMarketFn(mc, data, false);
        }

        //add collateral
        singularity.updatePause(PauseType.AddCollateral, true);

        Module[] memory modules;
        bytes[] memory calls;
        (modules, calls) = marketHelper.addCollateral(address(this), address(this), 1, 0);
        vm.expectRevert("Market: paused");
        singularity.execute(modules, calls, true);

        //add collateral
        singularity.updatePause(PauseType.RemoveCollateral, true);
        (modules, calls) = marketHelper.removeCollateral(address(this), address(this), 1);
        vm.expectRevert("Market: paused");
        singularity.execute(modules, calls, true);

        singularity.updatePause(PauseType.Borrow, true);
        (modules, calls) = marketHelper.borrow(address(this), address(this), 1);
        vm.expectRevert("Market: paused");
        singularity.execute(modules, calls, true);
    }

    function test_should_not_borrow_without_lenders() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        deal(address(collateral), address(this), collateralAmount);

        depositCollateral(collateralAmount);

        borrow(borrowAmount, true);
    }

    function test_addAsset_valid(address _from, address _to, uint256 _amount) public {
        vm.assume(_from != address(0));
        vm.assume(_to != address(0));
        vm.assume(_from != _to);
        vm.assume(_amount > singularity.minLendAmount());
        vm.assume(_amount < type(uint64).max);

        deal(address(singularity._asset()), _from, _amount);

        vm.startPrank(_from);
        IERC20(singularity._asset()).approve(address(singularity), _amount);
        uint256 fraction = singularity.addAsset(_from, _to, _amount);
        vm.stopPrank();

        assertEq(fraction, singularity.liquidityBalance(_to), "Liquidity balance of _to should be fraction");
        assertEq(0, singularity.liquidityBalance(_from), "Liquidity balance of _from should be 0");
    }

    function test_borrow_and_liquidate() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        {
            deal(address(collateral), address(this), collateralAmount);
            deal(address(asset), address(this), borrowAmount * 2);
        }

        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            borrow(borrowAmount, false);
        }

        bytes memory setLiquidationMaxSlippageCall =
            abi.encodeWithSelector(Market.setLiquidationMaxSlippage.selector, 1e4); //10%

        address[] memory mc = new address[](1);
        mc[0] = address(singularity);

        bytes[] memory data = new bytes[](1);
        data[0] = setLiquidationMaxSlippageCall;
        vm.prank(penrose.owner());
        penrose.executeMarketFn(mc, data, false);

        uint256 oracleRate = oracle.rate();
        oracle.set((oracleRate * 10) / 6);

        liquidatorMock = new MarketLiquidatorReceiverMock(IERC20(address(asset)));
        deal(address(asset), address(liquidatorMock), borrowAmount * 2);

        address[] memory users = new address[](1);
        users[0] = address(this);

        uint256[] memory borrowParts = new uint256[](1);
        borrowParts[0] = borrowAmount / 2;

        uint256[] memory minLiquidationBonuses = new uint256[](1);
        minLiquidationBonuses[0] = 1e4;

        IMarketLiquidatorReceiver[] memory receivers = new IMarketLiquidatorReceiver[](1);
        receivers[0] = IMarketLiquidatorReceiver(address(liquidatorMock));

        bytes[] memory receiverData = new bytes[](1);
        receiverData[0] = abi.encode(borrowAmount);

        uint256 borrowPartBefore = singularity._userBorrowPart(address(this));
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.liquidate(users, borrowParts, minLiquidationBonuses, receivers, receiverData);
        singularity.execute(modules, calls, true);
        uint256 borrowPartAfter = singularity._userBorrowPart(address(this));

        assertGt(borrowPartBefore, borrowPartAfter);
    }

    function _liquidateUser(address user, uint256 borrowAmount, address liquidator) internal {
        address[] memory users = new address[](1);
        users[0] = user;

        uint256[] memory borrowParts = new uint256[](1);
        borrowParts[0] = borrowAmount / 2;

        uint256[] memory minLiquidationBonuses = new uint256[](1);
        minLiquidationBonuses[0] = 1e4;

        IMarketLiquidatorReceiver[] memory receivers = new IMarketLiquidatorReceiver[](1);
        receivers[0] = IMarketLiquidatorReceiver(liquidator);

        bytes[] memory receiverData = new bytes[](1);
        receiverData[0] = abi.encode(borrowAmount / 2);

        uint256 borrowPartBefore = singularity._userBorrowPart(user);
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.liquidate(users, borrowParts, minLiquidationBonuses, receivers, receiverData);
        vm.expectRevert();
        singularity.execute(modules, calls, true);
        uint256 borrowPartAfter = singularity._userBorrowPart(user);
        assertEq(borrowPartBefore, borrowPartAfter, "Liquidate: borrowPartBefore should be equal to borrowPartAfter");
    }

    function test_borrow_and_liquidate_bad_debt() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        {
            deal(address(collateral), address(this), collateralAmount);
            deal(address(asset), address(this), borrowAmount * 2);
        }

        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            borrow(borrowAmount, false);
        }

        uint256 oracleRate = oracle.rate();
        oracle.set(oracleRate * 100);

        liquidatorMock = new MarketLiquidatorReceiverMock(IERC20(address(asset)));

        //cannot liquidate
        _liquidateUser(address(this), borrowAmount, address(liquidatorMock));

        //use liquidateBadDebt
        _liquidateUserBadDebt(address(this), address(liquidatorMock), borrowAmount);
    }

    function _getBadDebtCall(uint256 borrowAmount, Module[] memory modules, bytes[] memory calls)
        internal
        returns (bytes memory)
    {
        vm.prank(cluster.owner());
        cluster.updateContract(0, address(this), true);
        deal(address(asset), address(this), borrowAmount * 2);
        asset.approve(address(singularity), type(uint256).max);
        bytes memory badDebtCall = abi.encodeWithSelector(IMarket.execute.selector, modules, calls, true);
        return badDebtCall;
    }

    function _getMarkets(address _market) internal returns (address[] memory) {
        address[] memory markets = new address[](1);
        markets[0] = _market;
        return markets;
    }

    function _getDataCalls(bytes memory dataCall) internal returns (bytes[] memory) {
        bytes[] memory data = new bytes[](1);
        data[0] = dataCall;
        return data;
    }

    function _liquidateUserBadDebt(address user, address liquidator, uint256 borrowAmount) internal {
        uint256 borrowPartBefore = singularity._userBorrowPart(user);
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.liquidateBadDebt(user, user, user, IMarketLiquidatorReceiver(liquidator), "", false);

        bytes memory badDebtCall = _getBadDebtCall(borrowAmount, modules, calls);

        vm.startPrank(penrose.owner());
        penrose.executeMarketFn(_getMarkets(address(singularity)), _getDataCalls(badDebtCall), true);
        vm.stopPrank();
        uint256 borrowPartAfter = singularity._userBorrowPart(user);
        assertGt(
            borrowPartBefore,
            borrowPartAfter,
            "LiquidateBadDebt: borrowPartBefore should be greater than borrowPartAfter"
        );
    }

    function test_magnetar_helper_info() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        {
            deal(address(collateral), address(this), collateralAmount);
            deal(address(asset), address(this), borrowAmount * 2);
        }

        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            borrow(borrowAmount, false);
        }

        ISingularity[] memory markets = new ISingularity[](1);
        markets[0] = ISingularity(address(singularity));
        MagnetarHelper.SingularityInfo[] memory info = magnetarHelper.singularityMarketInfo(address(this), markets);

        assertEq(info[0].market.collateral, address(collateral));
        assertEq(info[0].market.asset, address(asset));
        assertEq(info[0].market.userCollateralShare, singularity.balanceOf(address(this)));
        assertEq(info[0].market.userBorrowPart, singularity._userBorrowPart(address(this)));

        uint256 share = marketHelper.computeAllowedLendShare(address(singularity), 1);
        assertGe(share, 1);

        uint256 borrowAmountFromHelper = magnetarHelper.getAmountForBorrowPart(
            IMarket(address(singularity)), singularity._userBorrowPart(address(this)), false
        );
        assertGe(borrowAmountFromHelper, borrowAmount);
    }

    function test_fees() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        {
            deal(address(collateral), address(this), collateralAmount);
            deal(address(asset), address(this), borrowAmount * 2);
        }

        uint256 userBorrowPart;
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            borrow(borrowAmount, false);

            vm.roll(10000);
            skip(86400 * 10);
            // prepare for repay
            deal(address(asset), address(this), borrowAmount * 2);

            userBorrowPart = singularity._userBorrowPart(address(this));

            repay(singularity._userBorrowPart(address(this)));
        }
        (,, uint128 feesEarnedFraction) = singularity.accrueInfo();
        assertGe(userBorrowPart, borrowAmount);
        assertGe(feesEarnedFraction, 0);

        IMarket[] memory markets = new IMarket[](1);
        markets[0] = IMarket(address(singularity));

        TwTapMock twTapMock = new TwTapMock(address(asset));

        uint256 twTapBalanceBefore = asset.balanceOf(address(twTapMock));
        vm.prank(penrose.owner());
        penrose.withdrawAllMarketFees(markets, ITWTAPv2(address(twTapMock)));
        uint256 twTapBalanceAfter = asset.balanceOf(address(twTapMock));
        assertGe(twTapBalanceAfter, twTapBalanceBefore, "TwTap balance should be greater than before");
        assertGe(twTapBalanceAfter, feesEarnedFraction, "TwTap balance should be greater than feesEarnedFraction");
    }

    function test_borrow_repay_different_users() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        {
            deal(address(collateral), address(this), collateralAmount);
            deal(address(asset), address(this), borrowAmount * 2);
        }

        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            borrow(borrowAmount, false);
        }

        uint256 borrowPart = singularity._userBorrowPart(address(this));
        assertGt(borrowPart, 0);

        singularity.approveBorrow(address(userA), type(uint256).max);
        singularity.approve(address(userA), type(uint256).max);

        deal(address(asset), address(userA), borrowAmount * 2);

        vm.startPrank(userA);
        uint256 share = singularity.convertToShares(borrowAmount * 2);

        IERC20(singularity.borrowableToken()).approve(address(singularity), share);

        (Module[] memory modules, bytes[] memory calls) = marketHelper.repay(address(userA), address(this), borrowPart);
        singularity.execute(modules, calls, true);

        uint256 borrowPartAfter = singularity._userBorrowPart(address(this));
        assertEq(borrowPartAfter, 0);
    }

    function test_addCollateral_valid(address _user, uint256 _amount) public {
        vm.assume(_user != address(0));
        vm.assume(_amount >= singularity._minCollateralAmount());
        vm.assume(_amount <= type(uint128).max);

        deal(address(collateral), _user, _amount);
        uint256 previewDepositAmount = singularity.previewDeposit(_amount);

        vm.startPrank(_user);
        collateral.approve(address(singularity), _amount);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(_user, _user, _amount, 0);
        singularity.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = singularity.balanceOf(_user);

        assertGt(userCollateralShare, 0, "User collateral share should be greater than 0");
        assertEq(
            collateral.balanceOf(address(singularity)),
            _amount,
            "Collateral balance of singularity should be equal to _amount"
        );
        assertEq(collateral.balanceOf(_user), 0, "Collateral balance of user should be 0");
        assertEq(
            userCollateralShare, previewDepositAmount, "User collateral share should be equal to previewDepositAmount"
        );
    }

    function test_addCollateral_valid_provide_both_values(address _user, uint256 _amount, uint256 _shares) public {
        vm.assume(_user != address(0));
        vm.assume(_amount >= singularity._minCollateralAmount());
        vm.assume(_amount <= type(uint128).max);
        vm.assume(_shares <= type(uint128).max);
        vm.assume(_shares > 1e18);

        uint256 previewMintAmount = singularity.previewMint(_shares);
        deal(address(collateral), _user, previewMintAmount);

        vm.startPrank(_user);
        collateral.approve(address(singularity), previewMintAmount);
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.addCollateral(_user, _user, previewMintAmount, _shares);
        singularity.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = singularity.balanceOf(_user);
        assertGt(userCollateralShare, 0, "User collateral share should be greater than 0");
        assertEq(
            collateral.balanceOf(address(singularity)),
            previewMintAmount,
            "Collateral balance of singularity should be equal to _amount"
        );
        assertEq(collateral.balanceOf(_user), 0, "Collateral balance of user should be 0");
        assertEq(userCollateralShare, previewMintAmount, "User collateral share should be equal to previewMintAmount");
    }

    function test_addCollateral_valid_provide_both_amount_and_shares(address _user, uint256 _amount) public {
        vm.assume(_user != address(0));
        vm.assume(_amount >= singularity._minCollateralAmount());
        vm.assume(_amount <= type(uint128).max);
        uint256 _shares = 1e18;

        uint256 previewMintAmount = singularity.previewMint(_shares);
        deal(address(collateral), _user, _shares + _amount); // To ensure enough collateral when it is lt shares (1e18)

        vm.startPrank(_user);
        collateral.approve(address(singularity), type(uint256).max);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(_user, _user, _amount, _shares);
        singularity.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = singularity.balanceOf(_user);
        assertEq(userCollateralShare, _shares, "User collateral share should be equal to _shares");
        assertEq(
            collateral.balanceOf(address(singularity)),
            previewMintAmount,
            "Collateral balance of singularity should be equal to _amount"
        );
    }

    function test_addCollateral_invalid_both_zero(address _user) public {
        vm.assume(_user != address(0));
        uint256 _amount = 0;
        uint256 _shares = 0;

        vm.startPrank(_user);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(_user, _user, _amount, _shares);
        vm.expectRevert();
        singularity.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = singularity.balanceOf(_user);

        assertEq(userCollateralShare, 0, "User collateral share should be 0");
        assertEq(collateral.balanceOf(address(singularity)), 0, "Collateral balance of singularity should be 0");
        assertEq(collateral.balanceOf(_user), 0, "Collateral balance of user should be 0");
        assertEq(userCollateralShare, _shares, "User collateral share should be equal to _shares");
    }

    function test_borrow_and_liquidate_add_asset_reentrancy_invalid() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        deal(address(collateral), address(this), collateralAmount);
        deal(address(asset), address(this), borrowAmount * 2);
        depositAsset(borrowAmount * 2);

        depositCollateral(collateralAmount);

        borrow(borrowAmount, false);

        bytes memory setLiquidationMaxSlippageCall =
            abi.encodeWithSelector(Market.setLiquidationMaxSlippage.selector, 1e4); //10%

        address[] memory mc = new address[](1);
        mc[0] = address(singularity);

        bytes[] memory data = new bytes[](1);
        data[0] = setLiquidationMaxSlippageCall;
        vm.startPrank(penrose.owner());
        penrose.executeMarketFn(mc, data, false);

        uint256 oracleRate = oracle.rate();
        oracle.set((oracleRate * 10) / 6);

        address attacker = address(0x1337);
        MarketLiquidatorReceiverAddAssetReentrancy liquidatorReentrancy =
            new MarketLiquidatorReceiverAddAssetReentrancy(IERC20(address(asset)), attacker);
        deal(address(asset), address(liquidatorReentrancy), borrowAmount * 2);

        address[] memory users = new address[](1);
        users[0] = address(this);
        uint256[] memory borrowParts = new uint256[](1);
        borrowParts[0] = borrowAmount / 2;
        uint256[] memory minLiquidationBonuses = new uint256[](1);
        minLiquidationBonuses[0] = 1e4;

        IMarketLiquidatorReceiver[] memory receivers = new IMarketLiquidatorReceiver[](1);
        receivers[0] = IMarketLiquidatorReceiver(address(liquidatorReentrancy));

        bytes[] memory receiverData = new bytes[](1);
        receiverData[0] = abi.encode(borrowAmount);

        uint256 borrowPartBefore = singularity._userBorrowPart(address(this));
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.liquidate(users, borrowParts, minLiquidationBonuses, receivers, receiverData);

        vm.expectRevert("ReentrancyGuard: reentrant call");
        singularity.execute(modules, calls, true);

        vm.startPrank(attacker);
        (uint256 liquidityBalance, uint256 liquidityShares) =
            liquidatorReentrancy.removeAsset(address(singularity), 51e16);
        vm.stopPrank();

        assertEq(liquidityBalance, 0, "Liquidity balance should be 0");
        assertEq(liquidityShares, 0, "Liquidity shares should be 0");
    }

    //TODO: complete after audit fixes
    // function test_buyCollateral() public {
    //     uint256 collateralAmount = 1 ether;
    //     uint256 borrowAmount = 4e17;
    //     uint256 leverageAmount = 2e17;
    //     Module[] memory modules;
    //     bytes[] memory calls;

    //     {
    //         deal(address(collateral), address(this), collateralAmount);
    //         deal(address(asset), address(this), borrowAmount * 2);
    //     }

    //     {
    //         depositAsset(borrowAmount * 2);

    //         depositCollateral(collateralAmount);

    //         borrow(borrowAmount, false);
    //     }

    //     uint256 borrowPartBefore = singularity._userBorrowPart(address(this));
    //     assertGe(borrowPartBefore, borrowAmount);

    //     bytes memory leverageData = abi.encode(1000, "");
    //     (modules, calls) = marketHelper.buyCollateral(address(this), leverageAmount, 0, leverageData);
    //     singularity.execute(modules, calls, true);

    //     uint256 share = 0;
    //     (modules, calls) = marketHelper.sellCollateral(address(this), share, leverageData);
    //     singularity.execute(modules, calls, true);
    // }

    function launchSingularity(address asset, address collateral, address oracle)
        public
        returns (Singularity singularity)
    {
        Singularity._InitMemoryTokensData memory tokensData;
        RiskParams memory riskParams;

        tokensData._asset = IERC20(asset);
        tokensData._collateral = IERC20(collateral);

        riskParams.oracle = oracle;
        riskParams.seedAmount = 1 ether;

        vm.startPrank(owner);
        deal(collateral, address(this), 1 ether);

        bytes memory payload =
            abi.encodeWithSelector(singularityLauncher.createSingularity.selector, tokensData, riskParams);

        bytes memory returnData =
            TapiocaMulticall(report.tapiocaMulticall).performDelegateCall(address(singularityLauncher), payload);

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "Singularity market address should not be zero");
        vm.stopPrank();
        return Singularity(payable(marketAddress));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {BBCollateral} from "tapioca-bar/markets/bigBang/BBCollateral.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {Market, PauseType} from "tapioca-bar/markets/Market.sol";
import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";
import {MagnetarHelper} from "tapioca-periph/Magnetar/MagnetarHelper.sol";
import {IMagnetarHelper, BigBangInfo} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";

import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IBigBang} from "tap-utils/interfaces/bar/IBigBang.sol";
import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";
import {IOracle} from "tap-utils/oracle/interfaces/IOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";

import {MarketLiquidatorReceiverMock} from "../mocks/MarketLiquidatorReceiverMock.sol";
import {MagnetarMock} from "../mocks/MagnetarMock.sol";
import {SwapperMock} from "../mocks/SwapperMock.sol";
import {OracleMock} from "../mocks/OracleMock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {TwTapMock} from "../mocks/TwTapMock.sol";
import {UsdoMock} from "../mocks/UsdoMock.sol";
import {TOFTMock} from "../mocks/TOFTMock.sol";

import {UsdoHelper} from "tapioca-bar/usdo/extensions/UsdoHelper.sol";
import {UsdoSender} from "tapioca-bar/usdo/modules/UsdoSender.sol";

import {UsdoTestHelper, TestPenroseData, TestSingularityData, TestBigBangData} from "../helpers/UsdoTestHelper.t.sol";

import "forge-std/Test.sol";

contract BigBangTest is UsdoTestHelper {
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
    BigBang masterContract;
    BigBang bigBang;
    MarketHelper marketHelper;
    OracleMock oracle;
    MarketLiquidatorReceiverMock liquidatorMock;
    MagnetarHelper magnetarHelper;
    TwTapMock twTap;

    uint256 internal userAPKey = 0x1;
    uint256 internal userBPKey = 0x2;
    address public userA = vm.addr(userAPKey);
    address public userB = vm.addr(userBPKey);
    uint256 public initialBalance = 100 ether;

    function setUp() public override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.label(userA, "userA");
        vm.label(userB, "userB");

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

        marketHelper = new MarketHelper();
        magnetarHelper = new MagnetarHelper();

        setUpEndpoints(3, LibraryType.UltraLightNode);

        {
            cluster = createCluster(aEid, address(this));
            magnetar = createMagnetar(address(cluster));
            twTap = new TwTapMock(address(asset));

            vm.label(address(endpoints[aEid]), "aEndpoint");
            vm.label(address(endpoints[bEid]), "bEndpoint");
            vm.label(address(cluster), "Cluster");
            vm.label(address(magnetar), "Magnetar");
            vm.label(address(twTap), "TwTapMock");
        }

        leverageExecutor = createLeverageExecutor(address(swapper), address(cluster));
        (penrose,) =
            createPenrose(TestPenroseData(address(cluster), address(tapOFT), address(collateral), address(this)));

        masterContract = new BigBang();
        penrose.registerBigBangMasterContract(address(masterContract), IPenrose.ContractType.mediumRisk);

        penrose.setUsdoToken(address(asset));

        oracle = createOracle();
        bigBang = createBigBang(
            TestBigBangData(
                address(penrose),
                address(collateral), //collateral
                ITapiocaOracle(address(oracle)),
                ILeverageExecutor(address(leverageExecutor)),
                0,
                0,
                0
            ),
            address(masterContract)
        );
        vm.label(address(bigBang), "BigBang");
        swapper = createSwapper(address(bigBang));

        // set asset oracle
        address[] memory markets = new address[](1);
        markets[0] = address(bigBang);
        bytes[] memory marketsData = new bytes[](1);
        marketsData[0] = abi.encodeWithSelector(BigBang.setAssetOracle.selector, oracle, "0x");

        penrose.executeMarketFn(markets, marketsData, true);
        penrose.setBigBangEthMarket(address(bigBang));

        BBDebtRateHelper bbRateHelper = new BBDebtRateHelper();
        marketsData[0] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, address(bbRateHelper));
        penrose.executeMarketFn(markets, marketsData, true);
    }

    function depositAsset(uint256 amount) public {
        deal(address(bigBang.borrowableToken()), address(this), amount);
        IERC20(bigBang.borrowableToken()).approve(address(bigBang), amount);
    }

    function depositCollateral(uint256 amount) public {
        deal(address(collateral), address(this), amount);
        collateral.approve(address(bigBang), type(uint256).max);

        uint256 share = bigBang.convertToShares(amount);

        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.addCollateral(address(this), address(this), share, 0);
        bigBang.execute(modules, calls, true);
    }

    function borrow(uint256 amount, bool expectRevert) public {
        (Module[] memory modules, bytes[] memory calls) = marketHelper.borrow(address(this), address(this), amount);

        if (expectRevert) vm.expectRevert();
        bigBang.execute(modules, calls, true);
    }

    function repay(uint256 part) public {
        (Module[] memory modules, bytes[] memory calls) = marketHelper.repay(address(this), address(this), part);
        IERC20(bigBang.borrowableToken()).approve(address(bigBang), type(uint256).max);
        bigBang.execute(modules, calls, true);
    }

    function test_open_interest_borrow_repay_borrow_repay() public {
        // console.log ("");
        // console.log ("");
        // console.log ("");
        // console.log ("=======SCENARIO 1:====== ");
        // console.log ("      borrow - repay all - borrow - repay all - borrow - repay all ");
        // console.log ("======================== ");

        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 1 ether;

        {
            deal(address(collateral), address(this), collateralAmount);
            asset.mint(address(this), borrowAmount * 100);
        }
        uint256 userBorrowPart;

        penrose.setBigBangEthMarket(address(bigBang));
        penrose.setBigBangEthMarketDebtRate(5e15);

        // 1
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            // console.log ("=======BEFORE BORROW ");
            borrow(borrowAmount, false);
            // console.log ("=======AFTER BORROW ");

            vm.roll(10000);
            skip(86400 * 10);
            penrose.mintOpenInterestDebt(address(twTap));
            // prepare for repay
            // TODO review it yieldBox.depositAsset(assetYieldBoxId, address(this), address(this), borrowAmount * 2, 0);
            userBorrowPart = bigBang._userBorrowPart(address(this));

            deal(address(bigBang.borrowableToken()), address(this), borrowAmount * 2);
            // console.log ("=======BEFORE REPAY ");
            repay(bigBang._userBorrowPart(address(this)));
            // console.log ("=======AFTER REPAY ");
            penrose.mintOpenInterestDebt(address(twTap));
        }

        // 2
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            // console.log ("=======BEFORE BORROW ");
            borrow(borrowAmount, false);
            // console.log ("=======AFTER BORROW ");
            penrose.mintOpenInterestDebt(address(twTap));

            vm.roll(10000);
            skip(86400 * 10);
            // prepare for repay
            penrose.mintOpenInterestDebt(address(twTap));
            userBorrowPart = bigBang._userBorrowPart(address(this));

            // console.log ("=======BEFORE REPAY ");
            repay(userBorrowPart);
            // console.log ("=======AFTER REPAY ");
            penrose.mintOpenInterestDebt(address(twTap));
        }

        // 3
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            // console.log ("=======BEFORE BORROW ");
            borrow(borrowAmount, false);
            // console.log ("=======AFTER BORROW ");

            vm.roll(10000);
            skip(86400 * 10);
            // prepare for repay
            // TODO review it yieldBox.depositAsset(assetYieldBoxId, address(this), address(this), borrowAmount * 2, 0);
            userBorrowPart = bigBang._userBorrowPart(address(this));

            penrose.mintOpenInterestDebt(address(twTap));
            repay(bigBang._userBorrowPart(address(this)));
        }

        uint256 totalMinted = asset.balanceOf(address(twTap));
        assertGt(totalMinted, 0);
        // console.log("-------------- totalMinted %s", totalMinted);
    }

    function test_open_interest_borrow_borrow_repay() public {
        // console.log ("");
        // console.log ("");
        // console.log ("");
        // console.log ("=======SCENARIO 2:====== ");
        // console.log ("      borrow - borrow - borrow - repay 1 - repay 2 ");
        // console.log ("======================== ");

        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 1 ether;

        {
            deal(address(collateral), address(this), collateralAmount);
            asset.mint(address(this), borrowAmount * 100);
        }
        uint256 userBorrowPart;

        penrose.setBigBangEthMarket(address(bigBang));
        penrose.setBigBangEthMarketDebtRate(5e15);

        // borrow
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            // console.log ("=======BEFORE BORROW ");
            penrose.mintOpenInterestDebt(address(twTap));
            borrow(borrowAmount, false);
            // console.log ("=======AFTER BORROW ");

            vm.roll(10000);
            skip(86400 * 10);
            penrose.mintOpenInterestDebt(address(twTap));
        }

        // borrow
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            // console.log ("=======BEFORE BORROW ");
            penrose.mintOpenInterestDebt(address(twTap));
            borrow(borrowAmount, false);
            // console.log ("=======AFTER BORROW ");
            penrose.mintOpenInterestDebt(address(twTap));

            vm.roll(10000);
            skip(86400 * 10);
            penrose.mintOpenInterestDebt(address(twTap));
        }

        // borrow
        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            // console.log ("=======BEFORE BORROW ");
            penrose.mintOpenInterestDebt(address(twTap));
            borrow(borrowAmount, false);
            // console.log ("=======AFTER BORROW ");

            vm.roll(10000);
            skip(86400 * 10);
            penrose.mintOpenInterestDebt(address(twTap));
        }

        // repay 1
        {
            // TODO review it yieldBox.depositAsset(assetYieldBoxId, address(this), address(this), borrowAmount * 2, 0);
            userBorrowPart = bigBang._userBorrowPart(address(this));

            // console.log ("=======BEFORE REPAY ");
            penrose.mintOpenInterestDebt(address(twTap));
            repay(bigBang._userBorrowPart(address(this)) / 10);
            // console.log ("=======AFTER REPAY ");
            penrose.mintOpenInterestDebt(address(twTap));
        }

        // repay 2
        {
            asset.mint(address(this), borrowAmount * 100);
            // uint256 balance = asset.balanceOf(address(this));
            // console.log("-------------- balance %s", balance);
            // TODO review it yieldBox.depositAsset(assetYieldBoxId, address(this), address(this), borrowAmount * 2, 0);
            userBorrowPart = bigBang._userBorrowPart(address(this));

            penrose.mintOpenInterestDebt(address(twTap));
            repay(bigBang._userBorrowPart(address(this)));
            penrose.mintOpenInterestDebt(address(twTap));
        }

        uint256 totalMinted = asset.balanceOf(address(twTap));
        assertGt(totalMinted, 0);
        // console.log("-------------- totalMinted %s", totalMinted);
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
            mc[0] = address(bigBang);

            bytes[] memory data = new bytes[](1);
            data[0] = payload;
            penrose.executeMarketFn(mc, data, false);
        }

        {
            assertEq(address(bigBang._oracle()), address(toSetAddress));
            assertEq(bigBang._protocolFee(), toSetValue);
            assertEq(bigBang._minLiquidatorReward(), toSetValue);
            assertEq(bigBang._maxLiquidatorReward(), toSetMaxValue);
            assertEq(bigBang._totalBorrowCap(), toSetValue);
            assertEq(bigBang._collateralizationRate(), toSetValue);
            assertEq(bigBang._liquidationCollateralizationRate(), toSetMaxValue);
            assertEq(bigBang._minBorrowAmount(), toSetValue);
        }
    }

    function test_initialize_twice() public {
        vm.expectRevert();
        bigBang.init("");
        bigBang.accrue();
    }

    function test_should_not_work_when_paused() public {
        {
            ICluster _cl = penrose.cluster();
            _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);
            bytes memory payload =
                abi.encodeWithSelector(Market.setMarketConfig.selector, address(0), "", 0, 0, 0, 0, 0, 0, 0, 0, 0);
            address[] memory mc = new address[](1);
            mc[0] = address(bigBang);

            bytes[] memory data = new bytes[](1);
            data[0] = payload;
            penrose.executeMarketFn(mc, data, false);
        }

        //add collateral
        bigBang.updatePause(PauseType.AddCollateral, true);

        Module[] memory modules;
        bytes[] memory calls;
        (modules, calls) = marketHelper.addCollateral(address(this), address(this), 1, 0);
        vm.expectRevert("Market: paused");
        bigBang.execute(modules, calls, true);

        //add collateral
        bigBang.updatePause(PauseType.RemoveCollateral, true);
        (modules, calls) = marketHelper.removeCollateral(address(this), address(this), 1);
        vm.expectRevert("Market: paused");
        bigBang.execute(modules, calls, true);

        bigBang.updatePause(PauseType.Borrow, true);
        (modules, calls) = marketHelper.borrow(address(this), address(this), 1);
        vm.expectRevert("Market: paused");
        bigBang.execute(modules, calls, true);
    }

    function test_should_borrow_without_lenders() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        deal(address(collateral), address(this), collateralAmount);

        depositCollateral(collateralAmount);

        borrow(borrowAmount, false);
    }

    function test_borrow_and_liquidate() public {
        uint256 collateralAmount = 1.2 ether;
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
        mc[0] = address(bigBang);

        bytes[] memory data = new bytes[](1);
        data[0] = setLiquidationMaxSlippageCall;
        penrose.executeMarketFn(mc, data, false);

        uint256 oracleRate = oracle.rate();
        oracle.set(oracleRate * 2);

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
        receiverData[0] = abi.encode(266124401913875596);

        uint256 borrowPartBefore = bigBang._userBorrowPart(address(this));
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.liquidate(users, borrowParts, minLiquidationBonuses, receivers, receiverData);
        bigBang.execute(modules, calls, true);
        uint256 borrowPartAfter = bigBang._userBorrowPart(address(this));

        assertGt(borrowPartBefore, borrowPartAfter);
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
        deal(address(asset), address(liquidatorMock), borrowAmount * 2);

        //cannot liquidate
        {
            address[] memory users = new address[](1);
            users[0] = address(this);

            uint256[] memory borrowParts = new uint256[](1);
            borrowParts[0] = borrowAmount / 2;

            uint256[] memory minLiquidationBonuses = new uint256[](1);
            minLiquidationBonuses[0] = 1e4;

            IMarketLiquidatorReceiver[] memory receivers = new IMarketLiquidatorReceiver[](1);
            receivers[0] = IMarketLiquidatorReceiver(address(liquidatorMock));

            bytes[] memory receiverData = new bytes[](1);
            receiverData[0] = abi.encode(borrowAmount / 2);

            uint256 borrowPartBefore = bigBang._userBorrowPart(address(this));
            (Module[] memory modules, bytes[] memory calls) =
                marketHelper.liquidate(users, borrowParts, minLiquidationBonuses, receivers, receiverData);
            vm.expectRevert();
            bigBang.execute(modules, calls, true);
            uint256 borrowPartAfter = bigBang._userBorrowPart(address(this));
            assertEq(borrowPartBefore, borrowPartAfter, "borrowPartBefore != borrowPartAfter liquidate");
        }

        //use liquidateBadDebt
        {
            uint256 borrowPartBefore = bigBang._userBorrowPart(address(this));
            (Module[] memory modules, bytes[] memory calls) = marketHelper.liquidateBadDebt(
                address(this),
                address(this),
                address(this),
                IMarketLiquidatorReceiver(address(liquidatorMock)),
                "",
                false
            );

            cluster.updateContract(0, address(this), true);
            deal(address(bigBang.borrowableToken()), address(this), 1e36);
            IERC20(address(bigBang.borrowableToken())).approve(address(bigBang), type(uint256).max);
            bytes memory badDebtCall = abi.encodeWithSelector(IMarket.execute.selector, modules, calls, true);

            address[] memory mc = new address[](1);
            mc[0] = address(bigBang);

            bytes[] memory data = new bytes[](1);
            data[0] = badDebtCall;
            penrose.executeMarketFn(mc, data, false);
            uint256 borrowPartAfter = bigBang._userBorrowPart(address(this));
            assertGt(borrowPartBefore, borrowPartAfter, "borrowPartBefore <= borrowPartAfter liquidateBadDebt");
        }
    }

    function test_bb_magnetar_helper_info() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        penrose.setBigBangEthMarket(address(bigBang));

        {
            deal(address(collateral), address(this), collateralAmount);
            deal(address(bigBang.borrowableToken()), address(this), borrowAmount * 2);
        }

        {
            depositAsset(borrowAmount * 2);

            depositCollateral(collateralAmount);

            borrow(borrowAmount, false);
        }

        IBigBang[] memory markets = new IBigBang[](1);
        markets[0] = IBigBang(address(bigBang));
        BigBangInfo[] memory info = magnetarHelper.bigBangMarketInfo(address(this), markets);

        assertEq(info[0].market.collateral, address(collateral));
        assertEq(info[0].market.asset, address(asset));
        assertEq(info[0].market.userCollateralShare, bigBang.balanceOf(address(this)));
        assertEq(info[0].market.userBorrowPart, bigBang._userBorrowPart(address(this)));

        uint256 borrowAmountFromHelper =
            magnetarHelper.getAmountForBorrowPart(address(bigBang), bigBang._userBorrowPart(address(this)), false);
        assertGe(borrowAmountFromHelper, borrowAmount);
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

        uint256 borrowPart = bigBang._userBorrowPart(address(this));
        assertGt(borrowPart, 0);

        bigBang.approveBorrow(address(userA), type(uint256).max);
        bigBang.approve(address(userA), type(uint256).max);

        deal(address(asset), address(userA), borrowAmount * 2);

        uint256 share = bigBang.convertToShares(borrowAmount * 2);
        vm.startPrank(userA);

        IERC20(bigBang.borrowableToken()).approve(address(bigBang), type(uint256).max);

        (Module[] memory modules, bytes[] memory calls) = marketHelper.repay(address(userA), address(this), borrowPart);
        bigBang.execute(modules, calls, true);

        uint256 borrowPartAfter = bigBang._userBorrowPart(address(this));
        assertEq(borrowPartAfter, 0);
    }

    function test_addCollateral_valid(address _user, uint256 _amount) public {
        vm.assume(_user != address(0));
        vm.assume(_amount > bigBang._minCollateralAmount());
        vm.assume(_amount <= type(uint128).max);

        deal(address(collateral), _user, _amount);
        uint256 previewDepositAmount = bigBang.previewDeposit(_amount);

        vm.startPrank(_user);
        collateral.approve(address(bigBang), _amount);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(_user, _user, _amount, 0);
        bigBang.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = bigBang.balanceOf(_user);

        assertGt(userCollateralShare, 0, "User collateral share should be greater than 0");
        assertEq(
            collateral.balanceOf(address(bigBang)), _amount, "Collateral balance of bigBang should be equal to _amount"
        );
        assertEq(collateral.balanceOf(_user), 0, "Collateral balance of user should be 0");
        assertEq(
            userCollateralShare, previewDepositAmount, "User collateral share should be equal to previewDepositAmount"
        );
    }

    function test_addCollateral_valid_provide_both_values(address _user, uint256 _amount, uint256 _shares) public {
        vm.assume(_user != address(0));
        vm.assume(_amount >= bigBang._minCollateralAmount());
        vm.assume(_amount <= type(uint128).max);
        vm.assume(_shares <= type(uint128).max);
        vm.assume(_shares > 1e18);

        uint256 previewMintAmount = bigBang.previewMint(_shares);
        deal(address(collateral), _user, previewMintAmount);

        vm.startPrank(_user);
        collateral.approve(address(bigBang), previewMintAmount);
        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.addCollateral(_user, _user, previewMintAmount, _shares);
        bigBang.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = bigBang.balanceOf(_user);
        assertGt(userCollateralShare, 0, "User collateral share should be greater than 0");
        assertEq(
            collateral.balanceOf(address(bigBang)),
            previewMintAmount,
            "Collateral balance of bigBang should be equal to _amount"
        );
        assertEq(collateral.balanceOf(_user), 0, "Collateral balance of user should be 0");
        assertEq(userCollateralShare, previewMintAmount, "User collateral share should be equal to previewMintAmount");
    }

    function test_addCollateral_valid_provide_both_amount_and_shares(address _user, uint256 _amount) public {
        vm.assume(_user != address(0));
        vm.assume(_amount >= bigBang._minCollateralAmount());
        vm.assume(_amount <= type(uint128).max);
        uint256 _shares = 1e18;

        uint256 previewMintAmount = bigBang.previewMint(_shares);
        deal(address(collateral), _user, _shares + _amount); // To ensure enough collateral when it is lt shares (1e18)

        vm.startPrank(_user);
        collateral.approve(address(bigBang), type(uint256).max);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(_user, _user, _amount, _shares);
        bigBang.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = bigBang.balanceOf(_user);
        assertEq(userCollateralShare, _shares, "User collateral share should be equal to _shares");
        assertEq(
            collateral.balanceOf(address(bigBang)),
            previewMintAmount,
            "Collateral balance of bigBang should be equal to _amount"
        );
    }

    function test_addCollateral_invalid_both_zero(address _user) public {
        vm.assume(_user != address(0));
        uint256 _amount = 0;
        uint256 _shares = 0;

        vm.startPrank(_user);
        (Module[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(_user, _user, _amount, _shares);
        vm.expectRevert();
        bigBang.execute(modules, calls, true);
        vm.stopPrank();

        uint256 userCollateralShare = bigBang.balanceOf(_user);

        assertEq(userCollateralShare, 0, "User collateral share should be 0");
        assertEq(collateral.balanceOf(address(bigBang)), 0, "Collateral balance of bigBang should be 0");
        assertEq(collateral.balanceOf(_user), 0, "Collateral balance of user should be 0");
        assertEq(userCollateralShare, _shares, "User collateral share should be equal to _shares");
    }

    function test_transferFrom_valid_with_approval_bypass(address _owner, address _spender, address _receiver, uint256 _amount) public {
        vm.assume(_owner != address(0));
        vm.assume(_spender != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_owner != _spender);
        vm.assume(_owner != _receiver);
        vm.assume(_spender != _receiver);
        vm.assume(_amount > 0);
        vm.assume(_amount <= type(uint128).max);
        deal(address(bigBang), _owner, _amount);

        Penrose(bigBang.penrose()).setMarketApprovalBypassContract(_spender, true);

        vm.startPrank(_spender);
        bigBang.transferFrom(_owner, _receiver, _amount);
        vm.stopPrank();

        assertEq(bigBang.balanceOf(_owner), 0, "BigBang balance of owner should be 0");
        assertEq(bigBang.balanceOf(_receiver), _amount, "BigBang balance of receiver should be equal to _amount");
        assertEq(bigBang.allowance(_owner, _spender), 0, "BigBang allowance of spender should be equal to zero");
    }

    function test_transferFrom_invalid_without_approval_bypass(address _owner, address _spender, address _receiver, uint256 _amount) public {
        vm.assume(_owner != address(0));
        vm.assume(_spender != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_owner != _spender);
        vm.assume(_owner != _receiver);
        vm.assume(_spender != _receiver);
        vm.assume(_amount > 0);
        vm.assume(_amount <= type(uint128).max);
        deal(address(bigBang), _owner, _amount);

        Penrose(bigBang.penrose()).setMarketApprovalBypassContract(_spender, false);

        vm.startPrank(_spender);
        vm.expectRevert();
        bigBang.transferFrom(_owner, _receiver, _amount);
        vm.stopPrank();

        assertEq(bigBang.balanceOf(_owner), _amount, "BigBang balance of owner should be 0");
        assertEq(bigBang.balanceOf(_receiver), 0, "BigBang balance of receiver should be equal to _amount");
        assertEq(bigBang.allowance(_owner, _spender), 0, "BigBang allowance of spender should be equal to zero");
    }

    function test_transferFrom_valid_without_approval_bypass_but_approve(address _owner, address _spender, address _receiver, uint256 _amount) public {
        vm.assume(_owner != address(0));
        vm.assume(_spender != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_owner != _spender);
        vm.assume(_owner != _receiver);
        vm.assume(_spender != _receiver);
        vm.assume(_amount > 0);
        vm.assume(_amount <= type(uint128).max);
        deal(address(bigBang), _owner, _amount);

        vm.startPrank(_owner);
        bigBang.approve(_spender, _amount);
        vm.stopPrank();

        vm.startPrank(_spender);
        bigBang.transferFrom(_owner, _receiver, _amount);
        vm.stopPrank();

        assertEq(bigBang.balanceOf(_owner), 0, "BigBang balance of owner should be 0");
        assertEq(bigBang.balanceOf(_receiver), _amount, "BigBang balance of receiver should be equal to _amount");
        assertEq(bigBang.allowance(_owner, _spender), 0, "BigBang allowance of spender should be equal to zero");
    }
}

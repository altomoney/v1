// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Origins} from "tapioca-bar/markets/origins/Origins.sol";
import {Market, PauseType} from "tapioca-bar/markets/Market.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IOracle} from "tap-utils/oracle/interfaces/IOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";

import {MagnetarMock} from "../mocks/MagnetarMock.sol";
import {OracleMock} from "../mocks/OracleMock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {TwTapMock} from "../mocks/TwTapMock.sol";
import {UsdoMock} from "../mocks/UsdoMock.sol";
import {TOFTMock} from "../mocks/TOFTMock.sol";

import {UsdoHelper} from "tapioca-bar/usdo/extensions/UsdoHelper.sol";
import {UsdoSender} from "tapioca-bar/usdo/modules/UsdoSender.sol";

import {UsdoTestHelper, TestPenroseData} from "../helpers/UsdoTestHelper.t.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import "deployments/interfaces/ITapiocaReport.sol";

import "forge-std/Test.sol";

contract OriginsTest is UsdoTestHelper {
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

    Penrose penrose;
    OracleMock oracle;

    Origins origins;

    uint256 assetYieldBoxId;
    uint256 collateralYieldBoxId;

    uint256 internal userAPKey = 0x1;
    uint256 internal userBPKey = 0x2;
    address public userA = vm.addr(userAPKey);
    address public userB = vm.addr(userBPKey);
    uint256 public initialBalance = 100 ether;

    TapiocaInput input;
    TapiocaReport report;

    function setUp() public override {
        TapiocaReport memory emptyReport;

        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.label(userA, "userA");
        vm.label(userB, "userB");

        input.owner = address(this);
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));
        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXProxy = address(1);
        input.bbMarketBorrowCap = 3_000_000e18;

        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

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

        setUpEndpoints(3, LibraryType.UltraLightNode);

        {
            cluster = Cluster(report.cluster);
            magnetar = MagnetarMock(report.magnetar);
            penrose = Penrose(report.penrose);

            vm.label(address(endpoints[aEid]), "aEndpoint");
            vm.label(address(endpoints[bEid]), "bEndpoint");
            vm.label(address(cluster), "Cluster");
            vm.label(address(magnetar), "Magnetar");
        }

        oracle = createOracle();
        origins = createOrigins(
            address(this),
            address(asset),
            address(collateral),
            ITapiocaOracle(address(oracle)),
            0,
            99999,
            address(penrose)
        );

        vm.label(address(origins), "Origins");

        vm.prank(penrose.owner());
        penrose.addOriginsMarket(address(origins));
    }

    function depositCollateral(address user, uint256 amount) public returns (uint256) {
        deal(address(collateral), user, amount);
        vm.startPrank(user);
        IERC20 _asset = IERC20(origins.collateral());
        _asset.approve(address(origins), amount);
        uint256 share = origins.deposit(amount, address(this));
        vm.stopPrank();
        return share;
    }

    function borrow(address user, uint256 amount, bool expectRevert) public returns (uint256 part, uint256 share) {
        vm.startPrank(user);
        if (expectRevert) vm.expectRevert();
        (part, share) = origins.borrow(amount);
        vm.stopPrank();
    }

    function repay(address user, uint256 part) public {
        IERC20 _asset = IERC20(origins._asset());
        vm.startPrank(user);
        _asset.approve(address(origins), part);
        origins.repay(part);
        vm.stopPrank();
    }

    function test_setMarketConfig() public {
        address toSetAddress = address(userA);
        uint256 toSetValue = 101;
        uint256 toSetMaxValue = 102;
        {
            origins.setMarketConfig(
                ITapiocaOracle(toSetAddress),
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
        }

        {
            assertEq(address(origins._oracle()), address(toSetAddress));
            assertEq(origins._protocolFee(), toSetValue);
            assertEq(origins._minLiquidatorReward(), toSetValue);
            assertEq(origins._maxLiquidatorReward(), toSetMaxValue);
            assertEq(origins._totalBorrowCap(), toSetValue);
            assertEq(origins._collateralizationRate(), toSetValue);
            assertEq(origins._liquidationCollateralizationRate(), toSetMaxValue);
            assertEq(origins._minBorrowAmount(), toSetValue);
        }
    }

    function test_should_not_work_when_paused_origins() public {
        {
            ICluster _cl = penrose.cluster();
            vm.prank(Ownable(address(_cl)).owner());
            _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);
            origins.setMarketConfig(ITapiocaOracle(address(0)), "", 0, 0, 0, 0, 0, 0, 0, 0, 0);
        }

        //add collateral
        origins.updatePause(PauseType.AddCollateral, true);

        vm.expectRevert("Market: paused");
        origins.addCollateral(1, 0);

        //add collateral
        origins.updatePause(PauseType.RemoveCollateral, true);
        vm.expectRevert("Market: paused");
        origins.removeCollateral(1);

        origins.updatePause(PauseType.Borrow, true);
        vm.expectRevert("Market: paused");
        origins.borrow(1);
    }

    function test_origin_should_borrow_max() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 9e17;

        deal(address(collateral), address(this), collateralAmount);

        depositCollateral(address(this), collateralAmount);

        borrow(address(this), borrowAmount, false);
    }

    function test_origin_should_borrow_max_2000_ether() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 1900e18;

        oracle.set(5e14);
        origins.updateExchangeRate();

        deal(address(collateral), address(this), collateralAmount);

        depositCollateral(address(this), collateralAmount);

        borrow(address(this), borrowAmount, false);

        borrow(address(this), 100e18, true);
    }

    function test_should_borrow_without_lenders() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        deal(address(collateral), address(this), collateralAmount);

        depositCollateral(address(this), collateralAmount);

        borrow(address(this), borrowAmount, false);
    }

    function test_should_borrow_and_repay() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;

        deal(address(asset), address(this), borrowAmount);
        deal(address(collateral), address(this), collateralAmount);

        uint256 collateralSharesBalanceBefore = depositCollateral(address(this), collateralAmount);

        borrow(address(this), borrowAmount, false);

        repay(address(this), borrowAmount);

        uint256 borrowPart = origins._userBorrowPart(address(this));
        assertEq(borrowPart, 0);

        uint256 collateralSharesBalanceAfter = origins.balanceOf(address(this));
        assertEq(collateralSharesBalanceBefore, collateralSharesBalanceAfter);
    }

    function test_only_allowed_users() public {
        uint256 collateralAmount = 1 ether;

        deal(address(collateral), address(this), collateralAmount);

        vm.startPrank(userA);
        vm.expectRevert(Origins.NotAuthorized.selector);
        origins.addCollateral(collateralAmount, 0);
        vm.stopPrank();
    }

    function test_time_updates() public {
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 5e17;
        address user = address(this);
        uint256 part;
        uint256 share;

        deal(address(collateral), user, collateralAmount);

        share = depositCollateral(user, collateralAmount);

        (part, share) = borrow(user, borrowAmount, false);

        skip(86400 * 1000);

        uint256 borrowPart = origins._userBorrowPart(user);
        assertEq(borrowPart, borrowAmount);

        repay(user, borrowAmount);
        borrowPart = origins._userBorrowPart(user);
        assertEq(borrowPart, 0);
    }
}

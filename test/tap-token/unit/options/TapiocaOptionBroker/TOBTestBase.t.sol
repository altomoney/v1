// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {TapiocaReport, TapiocaInput} from "deployments/interfaces/ITapiocaReport.sol";
import {ERC20Mock} from "tap-token/mocks/ERC20Mock.sol";
import {OracleMock} from "test/utils/mocks/OracleMock.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {SingularityLauncher, RiskParams} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {BigBangLauncher, BigBangRiskParams} from "deployments/releases/tapioca-v1/actions/BigBangLauncher.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TapTokenSender} from "tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "tap-token/tokens/TapTokenReceiver.sol";
import {TapiocaOptionBroker, ITapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {ITapToken} from "tap-token/tokens/ITapToken.sol";
import {Bucket} from "tap-token/governance/TWLBase.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {OwnerContract} from "tapioca-mocks/OwnerContract.sol";
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {Events} from "test/bar/btt/utils/Events.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {Utils} from "test/bar/btt/utils/Utils.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";

contract TOBTestBase is Test, Events, Utils {
    using RebaseLibrary for Rebase;

    address owner;
    OwnerContract ownerInstance;
    address user1;
    Cluster cluster;
    TapToken tapToken;
    TapiocaOptionBroker tob;
    SingularityLauncher singularityLauncher;
    BigBangLauncher bigBangLauncher;
    ERC20Mock paymentToken;
    MarketHelper marketHelper;
    address paymentTokenOracle;
    address tapOracle;

    TapiocaInput input;
    TapiocaReport report;

    uint256 EPOCH_DURATION = 1 weeks;

    address contributors;
    address earlySupporters;
    address supporters;
    address lbp;
    address dao;
    address airdrop;

    ERC20Mock sUSDX;
    ERC20Mock sWETH;
    uint256 sUSDXId;
    uint256 sWETHId;
    uint256 sWETH_bigBang_id;

    Usdo usdo;

    Bucket[] buckets;

    event ExitPosition(address indexed user, uint256 tapAmount);

    address public market;
    Singularity public marketInstance;
    address public bigBang;
    BigBang public bigBangInstance;

    struct _BorrowInternal {
        uint256 userBalanceBefore;
        uint256 userBalanceAfter;
        uint256 userBorrowPartBefore;
        uint256 userBorrowPartAfter;
        uint256 usdoSupplyBefore;
        uint256 usdoSupplyAfter;
        uint256 feeAmount;
        Rebase totalBorrowBefore;
        Rebase totalBorrowAfter;
    }

    function setUp() public virtual {
        deployDependencies();

        buckets.push(
            Bucket({
                enabled: true,
                epochGrowthRate: 1,
                epochDecayRate: 1,
                epochCeiling: 10,
                epochFloor: 1,
                rewardsMultiplier: 5000,
                lockEpochDuration: 5,
                currentEpochInflows: 0,
                lastEpochInflows: 0,
                growthGoal: 1000e18
            })
        );

        tob = new TapiocaOptionBroker(
            payable(tapToken), address(report.usdo), dao, EPOCH_DURATION, buckets, report.penrose, owner
        );

        vm.startPrank(owner);
        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        tob.setPaymentTokenBeneficiary(dao);
        tob.setTapOracle(tapOracle, "");
        tob.setCluster(report.cluster);
        tob.setPenrose(report.penrose);

        cluster = Cluster(report.cluster);

        vm.stopPrank();

        (marketInstance, sWETHId, sUSDXId) = createSingularityMarket(address(sWETH), address(usdo));
        market = address(marketInstance);

        (bigBangInstance, sWETH_bigBang_id) = createBigBangMarket(address(sWETH));
        bigBang = address(bigBangInstance);
        marketHelper = MarketHelper(report.marketHelper);

        vm.startPrank(tapToken.owner());
        tapToken.setMinter(address(tob));
        vm.stopPrank();

        vm.startPrank(tob.owner());
        tob.enableTapTokenRewards();
        vm.stopPrank();
    }

    function _mintTapToken(address to, uint256 amount) internal {
        deal(address(tapToken), to, amount);
    }

    function deployDependencies() internal {
        user1 = makeAddr("user1");
        tapOracle = makeAddr("tapOracle");
        paymentTokenOracle = makeAddr("paymentTokenOracle");
        paymentToken = new ERC20Mock("PaymentToken", "PT");
        contributors = makeAddr("contributors");
        earlySupporters = makeAddr("earlySupporters");
        supporters = makeAddr("supporters");
        lbp = makeAddr("lbp");
        dao = makeAddr("dao");
        airdrop = makeAddr("airdrop");
        owner = address(new OwnerContract());
        ownerInstance = OwnerContract(owner);
        sUSDX = new ERC20Mock("sUSDX", "sUSDX");
        sWETH = new ERC20Mock("sWETH", "sWETH");
        TapiocaReport memory emptyReport;

        tapOracle = address(new OracleMock("TapOracle", "TORC", 1 ether));
        paymentTokenOracle = address(new OracleMock("PaymentTokenOracle", "PORC", 1 ether));

        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.bbMarketBorrowCap = 3_000_000e18;

        input.lzEndpoint = address(new LZEndpointMock(uint16(block.chainid)));
        input.zeroXProxy = address(1);

        tapToken = new TapToken(
            ITapToken.TapTokenConstructorData(
                EPOCH_DURATION,
                input.lzEndpoint,
                contributors,
                earlySupporters,
                supporters,
                lbp,
                dao,
                airdrop,
                block.chainid,
                owner,
                address(new TapTokenSender("", "", input.lzEndpoint, owner, address(0))),
                address(new TapTokenReceiver("", "", input.lzEndpoint, owner, address(0))),
                address(address(0)),
                ICluster(address(0))
            )
        );
        vm.label(address(tapToken), "TapToken");

        input.tapToken = address(tapToken);

        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        vm.startPrank(owner);
        tapToken.setCluster(ICluster(report.cluster));
        vm.stopPrank();

        usdo = Usdo(payable(report.usdo));
        vm.label(address(usdo), "USDO");
    }

    function createSingularityMarket(address collateral, address asset)
        internal
        returns (Singularity, uint256 collateralId, uint256 assetId)
    {
        if (address(singularityLauncher) == address(0)) {
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
        }

        SGLInit._InitMemoryTokensData memory tokensData;
        RiskParams memory riskParams;

        tokensData._collateral = IERC20(collateral);
        tokensData._asset = IERC20(asset);

        riskParams.borrowOpeningFee = 0;
        riskParams.liquidationMultiplier = 0;
        riskParams.minimumTargetUtilization = 0;
        riskParams.maximumTargetUtilization = 0;
        riskParams.minimumInterestPerSecond = 0;
        riskParams.maximumInterestPerSecond = 0;
        riskParams.interestElasticity = 0;
        riskParams.minLendAmount = 1e6;
        riskParams.exchangeRatePrecision = 0;
        riskParams.collateralizationRate = 75000;
        riskParams.liquidationCollateralizationRate = 80000;
        riskParams.oracle = address(new OracleMock("Oracle Test", "ORCT", 1 ether));
        riskParams.seedAmount = 1 ether;
        riskParams.seedOwner = owner;

        bytes memory payload =
            abi.encodeWithSelector(singularityLauncher.createSingularity.selector, tokensData, riskParams);

        vm.startPrank(owner);
        deal(asset, owner, 1 ether);
        IERC20(asset).approve(address(report.tapiocaMulticall), 1 ether);
        bytes memory returnData = TapiocaMulticall(payable(report.tapiocaMulticall)).performDelegateCall(
            address(singularityLauncher), payload
        );
        vm.stopPrank();

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "Singularity market address should not be zero");

        vm.startPrank(owner);
        tob.setMarket(marketAddress, true);
        vm.stopPrank();

        // add liquidity to the market
        deal(address(usdo), owner, 10000 ether);
        vm.startPrank(owner);
        usdo.approve(marketAddress, 10000 ether);
        Singularity(payable(marketAddress)).addAsset(owner, owner, 10000 ether);
        vm.stopPrank();

        return (Singularity(payable(marketAddress)), collateralId, assetId);
    }

    function createBigBangMarket(address collateral) internal returns (BigBang, uint256 collateralId) {
        if (address(bigBangLauncher) == address(0)) {
            bigBangLauncher = new BigBangLauncher(
                report.bbLiquidation,
                report.bbBorrow,
                report.bbCollateral,
                report.bbLeverage,
                report.penrose,
                report.simpleLeverageExecutor,
                report.bigbang,
                report.bbDebtRateHelper,
                input.bbMarketBorrowCap
            );
        }

        BigBangRiskParams memory riskParams;
        riskParams.debtRateAgainstEth = 0;
        riskParams.debtRateMin = 0;
        riskParams.debtRateMax = 0;
        riskParams.exchangeRatePrecision = 1e18;
        riskParams.collateralizationRate = 75000;
        riskParams.liquidationCollateralizationRate = 80000;
        riskParams.collateral = collateral;
        riskParams.oracle = address(new OracleMock("Oracle Test", "ORCT", 1 ether));
        riskParams.isEthMarket = true;

        deal(collateral, address(this), 1 ether);
        bytes memory payload = abi.encodeWithSelector(bigBangLauncher.createBigBang.selector, riskParams);

        vm.startPrank(owner);

        bytes memory returnData =
            TapiocaMulticall(payable(report.tapiocaMulticall)).performDelegateCall(address(bigBangLauncher), payload);
        vm.stopPrank();

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "BigBang market address should not be zero");

        vm.startPrank(owner);
        usdo.setMinterStatus(marketAddress, true);
        usdo.setBurnerStatus(marketAddress, true);
        vm.stopPrank();

        return (BigBang(payable(marketAddress)), collateralId);
    }

    function _spawnCollateral(uint256 _collateralAmount, address _to) internal {
        deal(address(bigBangInstance.collateral()), _to, _collateralAmount);
    }

    function _addCollateralBigBang(
        uint256 collateralAmount,
        BigBang bb,
        address executor,
        address from,
        address depositTo,
        address onBehalfOf
    ) internal returns (uint256 share) {
        {
            // deal collateral
            _spawnCollateral(collateralAmount, from);

            // approvals
            vm.startPrank(from);
            IERC20(bb.collateral()).approve(address(bb), collateralAmount);
            vm.stopPrank();
        }

        // get `before` state
        uint256 bbBalanceBefore = IERC20(bb.collateral()).balanceOf(address(bb));
        uint256 userBalanceBefore = IERC20(bb.collateral()).balanceOf(address(onBehalfOf));
        uint256 userCollateralBefore = bb.balanceOf(depositTo);
        uint256 totalCollateralShareBefore = bb._totalCollateralShare();

        {
            vm.startPrank(from);
            // deposit to bigbang market
            share = bb.deposit(collateralAmount, depositTo);
            vm.stopPrank();
        }

        {
            uint256 resultedCollateral = bb.balanceOf(depositTo);
            assertEq(
                resultedCollateral, userCollateralBefore + share, "should increase user's collateral shares balance "
            );

            uint256 totalCollateralShare = bb._totalCollateralShare();
            assertEq(totalCollateralShare, totalCollateralShareBefore + share, "should increasetotalCollateralShare");

            assertEq(
                bbBalanceBefore + share,
                IERC20(bb.collateral()).balanceOf(address(bb)),
                "should increase market's erc20 balance"
            );
            assertEq(
                userBalanceBefore - share,
                IERC20(bb.collateral()).balanceOf(address(onBehalfOf)),
                "should decrease user's erc20 balance"
            );
        }
    }

    function _getBorrowData(uint256 _borrowAmount, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = marketHelper.borrow(_from, _to, _borrowAmount);
    }

    function _borrowBigBang(uint256 borrowAmount, BigBang bb, address executor, address from, address to)
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

            // it should increase 'userBorrowPart'
            assertGt(_data.userBorrowPartAfter, _data.userBorrowPartBefore);

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

    modifier resetPrank(address user) {
        _resetPrank(user);
        _;
    }

    function _getCollateralData(uint256 _collateralAmount, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = MarketHelper(report.marketHelper).addCollateral(_from, _to, _collateralAmount, 0);
    }

    function _createBorrowInternal(BigBang _bb, address _to) internal returns (_BorrowInternal memory) {
        _BorrowInternal memory _data;
        // get `before` state
        _data.totalBorrowBefore = _bb._totalBorrow();
        _data.userBorrowPartBefore = _bb._userBorrowPart(_to);
        _data.userBalanceBefore = IERC20(_bb.collateral()).balanceOf(_to);
        _data.usdoSupplyBefore = usdo.totalSupply();
        return _data;
    }

    function _setupValidPosition(address user, uint256 collateralAmount, uint256 borrowAmount, uint256 lockAmount)
        internal
    {
        _addCollateralBigBang(collateralAmount, bigBangInstance, user, user, user, user);
        _borrowBigBang(borrowAmount, bigBangInstance, user, user, user);

        vm.startPrank(user);
        tapToken.approve(address(tob), lockAmount);
        usdo.approve(address(tob), lockAmount);
        tob.lock(user, 0, lockAmount, market);
        vm.stopPrank();
    }

    function _repayBigBang(uint256 repayAmount, BigBang bb, address executor, address from, address to)
        internal
        resetPrank(executor)
    {
        deal(address(bb.borrowableToken()), from, repayAmount);
        IERC20(bb.borrowableToken()).approve(address(bb), repayAmount);
        (Module[] memory modules, bytes[] memory calls) = _getRepayData(repayAmount, from, to);
        bb.execute(modules, calls, true);
    }

    function _getRepayData(uint256 _repayPart, address _from, address _to)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = marketHelper.repay(_from, _to, _repayPart);
    }
}

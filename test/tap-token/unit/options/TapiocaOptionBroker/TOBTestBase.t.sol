// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {TapiocaReport, TapiocaInput} from "deployments/interfaces/ITapiocaReport.sol";
import {ERC20Mock} from "tap-token/mocks/ERC20Mock.sol";
import {OracleMock} from "tapioca-mocks/OracleMock.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {SingularityLauncher, RiskParams} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {BigBangLauncher, BigBangRiskParams} from "deployments/releases/tapioca-v1/actions/BigBangLauncher.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {IPearlmit} from "tap-utils/interfaces/periph/IPearlmit.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TapTokenSender} from "tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "tap-token/tokens/TapTokenReceiver.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {ITapToken} from "tap-token/tokens/ITapToken.sol";
import {Bucket} from "tap-token/governance/TWLBase.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {OwnerContract} from "tapioca-mocks/OwnerContract.sol";
import {YieldBox} from "contracts/yieldbox/YieldBox.sol";
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {Events} from "test/bar/btt/utils/Events.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {Utils} from "test/bar/btt/utils/Utils.sol";
import {ERC20WithoutStrategy} from "test/bar/helpers/UsdoTestHelper.t.sol";
import {IStrategy} from "contracts/yieldbox/interfaces/IStrategy.sol";
import {TokenType} from "yieldbox/enums/YieldBoxTokenType.sol";
import {IYieldBox} from "yieldbox/interfaces/IYieldBox.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";

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
    YieldBox yieldBox;
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
                lockEpochDuration: 1,
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

        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));

        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXSwapper = address(1);

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
                0,
                owner,
                address(new TapTokenSender("", "", input.lzEndpoint, owner, address(0))),
                address(new TapTokenReceiver("", "", input.lzEndpoint, owner, address(0))),
                address(address(0)),
                IPearlmit(address(0)),
                ICluster(address(0))
            )
        );
        vm.label(address(tapToken), "TapToken");
        vm.label(address(sUSDX), "sUSDX");
        input.tapToken = address(tapToken);

        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        vm.startPrank(owner);
        tapToken.setPearlmit(IPearlmit(report.pearlmit));
        tapToken.setCluster(ICluster(report.cluster));
        vm.stopPrank();

        yieldBox = YieldBox(report.yieldbox);
        usdo = Usdo(payable(report.usdo));
        vm.label(address(usdo), "USDO");
    }

    function createSingularityMarket(address collateral, address asset)
        internal
        returns (Singularity, uint256 collateralId, uint256 assetId)
    {
        IStrategy collateralStrategy =
            IStrategy(new ERC20WithoutStrategy(IYieldBox(report.yieldbox), IERC20(collateral)));
        IStrategy assetStrategy = IStrategy(new ERC20WithoutStrategy(IYieldBox(report.yieldbox), IERC20(asset)));

        collateralId = yieldBox.registerAsset(TokenType.ERC20, collateral, collateralStrategy, 0);
        assetId = yieldBox.registerAsset(TokenType.ERC20, asset, assetStrategy, 0);

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

        Singularity._InitMemoryTokensData memory tokensData;
        RiskParams memory riskParams;

        tokensData._collateral = IERC20(collateral);
        tokensData._collateralId = collateralId;
        tokensData._asset = IERC20(asset);
        tokensData._assetId = assetId;

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

        deal(collateral, address(this), 1 ether);
        bytes memory payload =
            abi.encodeWithSelector(singularityLauncher.createSingularity.selector, tokensData, riskParams);

        bytes memory returnData = ownerInstance.delegateCall(address(singularityLauncher), payload);

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "Singularity market address should not be zero");

        vm.startPrank(owner);
        tob.setMarket(marketAddress, true);
        vm.stopPrank();

        return (Singularity(payable(marketAddress)), collateralId, assetId);
    }

    function createBigBangMarket(address collateral) internal returns (BigBang, uint256 collateralId) {
        IStrategy collateralStrategy =
            IStrategy(new ERC20WithoutStrategy(IYieldBox(report.yieldbox), IERC20(collateral)));
        collateralId = yieldBox.registerAsset(TokenType.ERC20, collateral, collateralStrategy, 0);

        if (address(bigBangLauncher) == address(0)) {
            bigBangLauncher = new BigBangLauncher(
                report.bbLiquidation,
                report.bbBorrow,
                report.bbCollateral,
                report.bbLeverage,
                report.penrose,
                report.simpleLeverageExecutor,
                report.bigbang,
                report.bbDebtRateHelper
            );
        }

        BigBangRiskParams memory riskParams;
        riskParams.debtRateAgainstEth = 0;
        riskParams.debtRateMin = 0;
        riskParams.debtRateMax = 0;
        riskParams.exchangeRatePrecision = 1e18;
        riskParams.collateralizationRate = 75000;
        riskParams.liquidationCollateralizationRate = 80000;
        riskParams.collateralId = collateralId;
        riskParams.collateral = collateral;
        riskParams.oracle = address(new OracleMock("Oracle Test", "ORCT", 1 ether));
        riskParams.seedAmount = 1 ether;
        riskParams.isEthMarket = true;

        deal(collateral, address(this), 1 ether);
        bytes memory payload = abi.encodeWithSelector(bigBangLauncher.createBigBang.selector, riskParams);

        bytes memory returnData = ownerInstance.delegateCall(address(bigBangLauncher), payload);

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "BigBang market address should not be zero");

        vm.startPrank(owner);
        usdo.setMinterStatus(marketAddress, true);
        usdo.setBurnerStatus(marketAddress, true);
        vm.stopPrank();

        return (BigBang(payable(marketAddress)), collateralId);
    }

    function _spawnCollateral(uint256 _collateralAmount, address _to) internal {
        deal(address(bigBangInstance._collateral()), _to, _collateralAmount);
    }

    function _approveForCollateral(address txExecutor) internal virtual resetPrank(txExecutor) {
        _approveViaERC20(bigBangInstance._collateral(), txExecutor, address(yieldBox), type(uint256).max);
        _approveViaERC20(bigBangInstance._collateral(), txExecutor, report.pearlmit, type(uint256).max);
        _approveYieldBoxForAll(yieldBox, txExecutor, address(bigBangInstance));
        _approveYieldBoxForAll(yieldBox, txExecutor, address(report.pearlmit));
        _approveViaPearlmit(
            TOKEN_TYPE_ERC1155,
            address(report.yieldbox),
            IPearlmit(address(report.pearlmit)),
            txExecutor,
            address(bigBangInstance),
            type(uint200).max,
            uint48(block.timestamp),
            bigBangInstance._collateralId()
        );
    }

    function _createBorrowInternal(YieldBox _yieldBox, BigBang _bb, address _to)
        internal
        returns (_BorrowInternal memory)
    {
        _BorrowInternal memory _data;
        // get `before` state
        _data.totalBorrowBefore = _bb._totalBorrow();
        _data.userBorrowPartBefore = _bb._userBorrowPart(_to);
        _data.userYieldBoxBalanceBefore = _yieldBox.amountOf(address(_to), _bb._assetId());
        _data.usdoSupplyBefore = usdo.totalSupply();
        return _data;
    }

    function _addCollateralBigBang(
        uint256 collateralAmount,
        BigBang bb,
        address executor,
        address from,
        address depositTo,
        address onBehalfOf,
        bool skim
    ) internal returns (uint256 share) {
        {
            // deal collateral
            _spawnCollateral(collateralAmount, from);

            // approvals
            _approveForCollateral(from);
        }

        // deposit to YieldBox for market
        share = yieldBox.toShare(bb._collateralId(), collateralAmount, false);
        _depositToYieldBox(bb._collateral(), bb._collateralId(), share, from, depositTo);

        // get `before` state
        uint256 bbYieldBoxBalanceBefore = yieldBox.balanceOf(address(bb), bb._collateralId());
        uint256 userYieldBoxBalanceBefore = yieldBox.balanceOf(address(onBehalfOf), bb._collateralId());
        uint256 userCollateralBefore = bb._userCollateralShare(onBehalfOf);
        uint256 totalCollateralShareBefore = bb._totalCollateralShare();

        {
            (Module[] memory modules, bytes[] memory calls) =
                _getCollateralData(collateralAmount, from, onBehalfOf, skim);

            _resetPrank(executor);
            // it should emit 'LogAddCollateral'
            vm.expectEmit(true, true, true, false);
            emit LogAddCollateral(skim ? address(yieldBox) : from, onBehalfOf, share);
            bb.execute(modules, calls, true);
        }

        // checks
        {
            // get `after` state
            uint256 bbYieldBoxBalanceAfter = yieldBox.balanceOf(address(bb), bb._collateralId());
            uint256 userYieldBoxBalanceAfter = yieldBox.balanceOf(address(onBehalfOf), bb._collateralId());

            // it should increase 'userCollateralShare'
            uint256 resultedCollateral = bb._userCollateralShare(depositTo);
            assertEq(resultedCollateral, userCollateralBefore + share);

            // it should increase 'totalCollateralShare'
            uint256 totalCollateralShare = bb._totalCollateralShare();
            assertEq(totalCollateralShare, totalCollateralShareBefore + share);

            if (skim) {
                // it should NOT increase market's YieldBox balance
                assertEq(bbYieldBoxBalanceBefore, bbYieldBoxBalanceAfter);
                // it should NOT decrease user's YieldBox balance
                assertEq(userYieldBoxBalanceBefore, userYieldBoxBalanceAfter);
            } else {
                // it should increase market's YieldBox balance
                assertEq(bbYieldBoxBalanceBefore + share, bbYieldBoxBalanceAfter);
                // it should decrease user's YieldBox balance for collateral token
                assertEq(userYieldBoxBalanceBefore - share, userYieldBoxBalanceAfter);
            }
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
        _BorrowInternal memory _data = _createBorrowInternal(yieldBox, bb, to);

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
            _data.userYieldBoxBalanceAfter = yieldBox.amountOf(address(to), bb._assetId());

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

    modifier resetPrank(address user) {
        _resetPrank(user);
        _;
    }

    function _getCollateralData(uint256 _collateralAmount, address _from, address _to, bool _skim)
        internal
        view
        returns (Module[] memory modules, bytes[] memory calls)
    {
        (modules, calls) = MarketHelper(report.marketHelper).addCollateral(_from, _to, _skim, _collateralAmount, 0);
    }

    function _depositToYieldBox(address asset, uint256 id, uint256 share, address from, address to)
        internal
        resetPrank(from)
    {
        _approveViaERC20(asset, from, report.yieldbox, type(uint256).max);
        _approveViaERC20(asset, from, report.pearlmit, type(uint256).max);
        _approveYieldBoxForAll(yieldBox, from, report.pearlmit);

        yieldBox.depositAsset(id, from, to, 0, share);
    }
}

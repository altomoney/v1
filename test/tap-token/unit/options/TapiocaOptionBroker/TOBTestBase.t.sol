// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {AltoReport, TapiocaInput} from "deployments/interfaces/IAltoReport.sol";
import {ERC20Mock} from "tapioca-mocks/ERC20Mock.sol";
import {OracleMock} from "test/utils/mocks/OracleMock.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {AltoRelease} from "deployments/releases/tapioca-v1/AltoRelease.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
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
    ERC20Mock paymentToken;
    MarketHelper marketHelper;
    address paymentTokenOracle;
    address tapOracle;

    TapiocaInput input;
    AltoReport report;

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
        vm.skip(true);
        owner = makeAddr("owner");

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
            address(tapToken), address(report.usdo), dao, EPOCH_DURATION, buckets, address(1), owner
        );

        vm.startPrank(owner);
        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        tob.setPaymentTokenBeneficiary(dao);
        tob.setTapOracle(tapOracle, "");
        tob.setCluster(address(1));
        tob.setPenrose(address(1));

        vm.stopPrank();

        // TODO: replace with new markets
        market = address(1);
        bigBang = address(2);

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
        paymentToken = new ERC20Mock("PaymentToken", "PT", 0, 18, owner);
        contributors = makeAddr("contributors");
        earlySupporters = makeAddr("earlySupporters");
        supporters = makeAddr("supporters");
        lbp = makeAddr("lbp");
        dao = makeAddr("dao");
        airdrop = makeAddr("airdrop");
        owner = address(new OwnerContract());
        ownerInstance = OwnerContract(owner);
        sUSDX = new ERC20Mock("sUSDX", "sUSDX", 0, 18, owner);
        sWETH = new ERC20Mock("sWETH", "sWETH", 0, 18, owner);
        AltoReport memory emptyReport;

        tapOracle = address(new OracleMock("TapOracle", "TORC", 1 ether));
        paymentTokenOracle = address(new OracleMock("PaymentTokenOracle", "PORC", 1 ether));

        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A", 0, 18, owner));
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
                owner,
                address(1)
            )
        );
        vm.label(address(tapToken), "TapToken");

        input.tapToken = address(tapToken);

        report = AltoRelease.deployAltoV1(input, emptyReport);

        usdo = Usdo(payable(report.usdo));
        vm.label(address(usdo), "USDO");
    }

    function createSingularityMarket(address collateral, address asset)
        internal
        returns (Singularity, uint256 collateralId, uint256 assetId)
    {
        vm.skip(true);
    }

    function createBigBangMarket(address collateral) internal returns (BigBang, uint256 collateralId) {
        vm.skip(true);
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

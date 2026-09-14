// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import {ERC20Mock} from "morpho-blue/src/mocks/ERC20Mock.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {PegResponsiveExponentialIrmConfig} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";
import {
    CreditMarketInitParams,
    IAltoConvexCreditLineMarketEvents,
    ConvexCreditLineInitParams
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {Balance, BaseMarketInitParams, IMarketEvents, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";

import {ConvexBoosterMock} from "./mocks/ConvexBoosterMock.sol";
import {ConvexRewardPoolMock} from "./mocks/ConvexRewardPoolMock.sol";
import {CreditLineMarketCollateralTokenMock} from "./mocks/CreditLineMarketCollateralTokenMock.sol";

contract BorrowTokenReentrantCallMock {
    AltoConvexCreditLineMarket internal immutable MARKET;
    address internal immutable CREDIT_ACCOUNT;

    constructor(AltoConvexCreditLineMarket market, address creditAccount) {
        MARKET = market;
        CREDIT_ACCOUNT = creditAccount;
    }

    function mint(address, uint256) external {
        MARKET.borrow(1, 0, CREDIT_ACCOUNT, address(this), "");
    }
}

abstract contract ConvexCreditLineCommon is Test, IMarketEvents, IAltoConvexCreditLineMarketEvents {
    uint256 internal constant POOL_ID = 7;
    uint256 internal constant MAX_LTV = 0.75 ether;
    uint256 internal constant FORECLOSURE_LTV = 0.9 ether;
    uint256 internal constant CREDIT_LIMIT = 1_000_000 ether;
    uint256 internal constant BORROW_RATE = 0.04 ether / uint256(365 days);

    address internal OWNER = makeAddr("Owner");
    address internal CREDIT_ACCOUNT = makeAddr("CreditAccount");
    address internal DELEGATE = makeAddr("Delegate");
    address internal USER = makeAddr("User");
    address internal RECEIVER = makeAddr("Receiver");
    address internal FEE_RECIPIENT = makeAddr("FeeRecipient");
    address internal REWARD_RECIPIENT = makeAddr("RewardRecipient");
    address internal GAUGE = makeAddr("Gauge");

    AltoConvexCreditLineMarket internal market;
    DUSD internal borrowToken;
    CreditLineMarketCollateralTokenMock internal collateralToken;
    ERC20Mock internal depositToken;
    ERC20Mock internal primaryRewardToken;
    ERC20Mock internal extraRewardToken;
    FixedRateIrm internal irm;
    OracleMock internal oracle;
    ConvexRewardPoolMock internal rewardPool;
    ConvexBoosterMock internal booster;

    struct AccountingState {
        Balance totalSupply;
        Balance totalBorrowed;
        Position creditPosition;
        uint128 claimableFees;
        uint256 badDebt;
        uint256 creditBalance;
        uint256 receiverBorrowBalance;
        uint256 idleCollateral;
        uint256 stakedCollateral;
    }

    function setUp() public virtual {
        borrowToken = new DUSD(address(new EndpointV2Mock(1, address(this))), OWNER);
        collateralToken = new CreditLineMarketCollateralTokenMock("Curve LP", "LP");
        depositToken = new ERC20Mock();
        primaryRewardToken = new ERC20Mock();
        extraRewardToken = new ERC20Mock();
        irm = _newFixedRateIrm();
        oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        rewardPool = new ConvexRewardPoolMock(
            POOL_ID, address(0), address(depositToken), address(primaryRewardToken), address(collateralToken)
        );
        booster = new ConvexBoosterMock(address(collateralToken), address(depositToken), GAUGE, address(rewardPool));
        rewardPool.setPoolMetadata(POOL_ID, address(booster), address(depositToken), address(primaryRewardToken));

        market = _newUninitializedMarket();
        market.initialize(_validInitParams());

        vm.startPrank(OWNER);
        borrowToken.setMinterStatus(address(market), true);
        borrowToken.setMinterCeiling(address(market), type(uint256).max);
        borrowToken.setBurnerStatus(address(market), true);
        vm.stopPrank();

        vm.prank(CREDIT_ACCOUNT);
        market.setAuthorization(DELEGATE, true);
    }

    function _validInitParams() internal returns (ConvexCreditLineInitParams memory params) {
        FixedRateIrm paramsIrm = irm;
        if (paramsIrm.market() != address(0)) paramsIrm = _newFixedRateIrm();

        address[] memory rewards = new address[](2);
        rewards[0] = address(primaryRewardToken);
        rewards[1] = address(extraRewardToken);

        params = ConvexCreditLineInitParams({
            creditMarketInitParams: CreditMarketInitParams({
                baseMarketInitParams: BaseMarketInitParams({
                    borrowToken: address(borrowToken),
                    collateralToken: address(collateralToken),
                    irm: address(paramsIrm),
                    owner: OWNER,
                    emergencyAdmin: OWNER,
                    oracle: address(oracle),
                    maxLtv: MAX_LTV,
                    feeRecipient: FEE_RECIPIENT,
                    liquidationEngine: address(0)
                }),
                creditAccount: CREDIT_ACCOUNT,
                creditLimit: CREDIT_LIMIT,
                foreclosureLtv: FORECLOSURE_LTV,
                initialBorrowOpeningFee: 0
            }),
            convexBooster: address(booster),
            convexPoolId: POOL_ID,
            rewardRecipient: REWARD_RECIPIENT,
            rewardTokens: rewards
        });
    }

    function _newUninitializedMarket() internal returns (AltoConvexCreditLineMarket instance) {
        AltoConvexCreditLineMarket implementation = new AltoConvexCreditLineMarket();
        instance = AltoConvexCreditLineMarket(address(new ERC1967Proxy(address(implementation), "")));
    }

    function _initialize(ConvexCreditLineInitParams memory params)
        internal
        returns (AltoConvexCreditLineMarket instance)
    {
        instance = _newUninitializedMarket();
        instance.initialize(params);
    }

    function _newFixedRateIrm() internal returns (FixedRateIrm) {
        return new FixedRateIrm(BORROW_RATE, OWNER);
    }

    function _newAdaptiveCurveIrm() internal returns (AdaptiveCurveIrm) {
        return new AdaptiveCurveIrm(
            AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
                curveSteepness: 4 ether,
                adjustmentSpeed: int256(50 ether) / int256(365 days),
                targetUtilization: 0.9 ether,
                initialRateAtTarget: int256(BORROW_RATE),
                minRateAtTarget: int256(0.001 ether) / int256(365 days),
                maxRateAtTarget: int256(2 ether) / int256(365 days)
            }),
            OWNER
        );
    }

    function _newPegResponsiveIrm() internal returns (PegResponsiveExponentialIrm) {
        MockDusdPegOracle pegOracle = new MockDusdPegOracle();
        pegOracle.setPrice(1 ether, uint48(block.timestamp), true);
        return new PegResponsiveExponentialIrm(
            address(pegOracle),
            PegResponsiveExponentialIrmConfig({
                recoveryPrice: 1 ether,
                stressPrice: 0.995 ether,
                baseRate: BORROW_RATE,
                stressRate: 0.075 ether / uint256(365 days),
                maxRate: 8 ether / uint256(365 days),
                doublingDistance: 0.0025 ether,
                recoveryDelay: 6 hours,
                maxOracleAge: 30 minutes
            }),
            OWNER
        );
    }

    function _mockAccrual(uint256 interest, uint256 borrowRate) internal {
        _mockAccrual(irm, interest, borrowRate);
    }

    function _mockAccrual(FixedRateIrm targetIrm, uint256 interest, uint256 borrowRate) internal {
        vm.mockCall(
            address(targetIrm),
            abi.encodeWithSelector(IIrm.updateInterestRate.selector),
            abi.encode(interest, borrowRate)
        );
        vm.mockCall(
            address(targetIrm),
            abi.encodeWithSelector(IIrm.updateInterestRateView.selector),
            abi.encode(interest, borrowRate)
        );
    }

    function _mockIrmUpdateRevert() internal {
        vm.mockCallRevert(
            address(irm), abi.encodeWithSelector(IIrm.updateInterestRate.selector), bytes("UPDATE_REVERTED")
        );
    }

    function _mockBorrowTokenReentrancy() internal {
        BorrowTokenReentrantCallMock callback = new BorrowTokenReentrantCallMock(market, CREDIT_ACCOUNT);
        vm.mockFunction(address(borrowToken), address(callback), abi.encodeWithSelector(borrowToken.mint.selector));
    }

    function _addCollateral(uint256 assets) internal {
        _addCollateralFrom(CREDIT_ACCOUNT, assets);
    }

    function _addCollateralFrom(address caller, uint256 assets) internal {
        deal(address(collateralToken), caller, collateralToken.balanceOf(caller) + assets);
        vm.startPrank(caller);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(assets, CREDIT_ACCOUNT);
        vm.stopPrank();
    }

    function _borrow(uint256 assets) internal returns (uint256 addedAssets, uint256 shares, uint256 fee) {
        vm.prank(CREDIT_ACCOUNT);
        return market.borrow(assets, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
    }

    function _openPosition(uint256 collateralAssets, uint256 borrowAssets) internal {
        _addCollateral(collateralAssets);
        _borrow(borrowAssets);
    }

    function _repayAssets(address payer, uint256 assets) internal returns (uint256, uint256) {
        deal(address(borrowToken), payer, borrowToken.balanceOf(payer) + assets);
        vm.prank(payer);
        return market.repay(assets, 0, CREDIT_ACCOUNT);
    }

    function _repayAllShares(address payer) internal returns (uint256 assets, uint256 shares) {
        (, shares,) = market.position(CREDIT_ACCOUNT);
        (uint128 totalAssets, uint128 totalShares) = market.totalBorrowed();
        assets = uint256(shares) * (uint256(totalAssets) + 1) / (uint256(totalShares) + 1e6);
        if (uint256(shares) * (uint256(totalAssets) + 1) % (uint256(totalShares) + 1e6) != 0) ++assets;
        deal(address(borrowToken), payer, borrowToken.balanceOf(payer) + assets);
        vm.prank(payer);
        return market.repay(0, shares, CREDIT_ACCOUNT);
    }

    function _pause(bytes32 pauseType) internal {
        vm.prank(OWNER);
        market.pause(pauseType, true);
    }

    function _unpause(bytes32 pauseType) internal {
        vm.prank(OWNER);
        market.pause(pauseType, false);
    }

    function _exitConvex() internal returns (uint256) {
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        return market.emergencyExitConvex();
    }

    function _state() internal view returns (AccountingState memory state) {
        (state.totalSupply.assets, state.totalSupply.shares) = market.totalSupply();
        (state.totalBorrowed.assets, state.totalBorrowed.shares) = market.totalBorrowed();
        (state.creditPosition.supplyShares, state.creditPosition.borrowShares, state.creditPosition.collateralAssets) =
            market.position(CREDIT_ACCOUNT);
        state.claimableFees = market.claimableFeesAssets();
        state.badDebt = market.badDebtAssets();
        state.creditBalance = borrowToken.balanceOf(CREDIT_ACCOUNT);
        state.receiverBorrowBalance = borrowToken.balanceOf(RECEIVER);
        state.idleCollateral = collateralToken.balanceOf(address(market));
        state.stakedCollateral = rewardPool.balanceOf(address(market));
    }

    function _assertStateEq(AccountingState memory actual, AccountingState memory expected) internal pure {
        assertEq(actual.totalSupply.assets, expected.totalSupply.assets, "totalSupply.assets");
        assertEq(actual.totalSupply.shares, expected.totalSupply.shares, "totalSupply.shares");
        assertEq(actual.totalBorrowed.assets, expected.totalBorrowed.assets, "totalBorrowed.assets");
        assertEq(actual.totalBorrowed.shares, expected.totalBorrowed.shares, "totalBorrowed.shares");
        assertEq(actual.creditPosition.supplyShares, expected.creditPosition.supplyShares, "position.supplyShares");
        assertEq(actual.creditPosition.borrowShares, expected.creditPosition.borrowShares, "position.borrowShares");
        assertEq(
            actual.creditPosition.collateralAssets,
            expected.creditPosition.collateralAssets,
            "position.collateralAssets"
        );
        assertEq(actual.claimableFees, expected.claimableFees, "claimableFeesAssets");
        assertEq(actual.badDebt, expected.badDebt, "badDebtAssets");
        assertEq(actual.creditBalance, expected.creditBalance, "credit borrow-token balance");
        assertEq(actual.receiverBorrowBalance, expected.receiverBorrowBalance, "receiver borrow-token balance");
        assertEq(actual.idleCollateral, expected.idleCollateral, "idle collateral");
        assertEq(actual.stakedCollateral, expected.stakedCollateral, "staked collateral");
    }

    function _assertUnchanged(AccountingState memory beforeState) internal view {
        _assertStateEq(_state(), beforeState);
    }

    function _setOpeningFee(uint256 fee) internal {
        vm.prank(OWNER);
        market.setBorrowOpeningFee(fee);
    }

    function _configuredRewards(uint256 count) internal view returns (address[] memory tokens) {
        tokens = new address[](count);
        for (uint256 i; i < count; ++i) {
            tokens[i] = market.rewardToken(i);
        }
    }

    function _assertRewardList(address[] memory expected) internal {
        for (uint256 i; i < expected.length; ++i) {
            assertEq(market.rewardToken(i), expected[i]);
            assertTrue(market.isRewardToken(expected[i]));
        }
        _assertRewardTokenCount(expected.length);
    }

    function _assertRewardTokenCount(uint256 expectedCount) internal {
        if (expectedCount != 0) {
            assertTrue(market.rewardToken(expectedCount - 1) != address(0));
        }
        vm.expectRevert();
        market.rewardToken(expectedCount);
    }

    function _assertNoCollateralUnstakedEvent() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(market) && logs[i].topics.length != 0
                    && logs[i].topics[0] == IAltoConvexCreditLineMarketEvents.CollateralUnstaked.selector
            ) {
                fail("CollateralUnstaked emitted");
            }
        }
    }

    function _assertPausedRevert(bytes32 pauseType) internal {
        vm.expectRevert(abi.encodeWithSignature("IsPaused(bytes32)", pauseType));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {CreditMarketInitParams, IAltoCreditMarketEvents} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {
    ConvexCreditLineInitParams, IAltoConvexCreditLineEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {Balance, BaseMarketInitParams, IMarketEvents, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {ConvexBoosterMock} from "./mocks/ConvexBoosterMock.sol";
import {ConvexRewardPoolMock} from "./mocks/ConvexRewardPoolMock.sol";
import {CreditLineMarketCollateralTokenMock} from "./mocks/CreditLineMarketCollateralTokenMock.sol";

abstract contract ConvexCreditLineCommon is
    Test,
    IMarketEvents,
    IAltoCreditMarketEvents,
    IAltoConvexCreditLineEvents
{
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
    CreditLineMarketCollateralTokenMock internal borrowToken;
    CreditLineMarketCollateralTokenMock internal collateralToken;
    CreditLineMarketCollateralTokenMock internal depositToken;
    CreditLineMarketCollateralTokenMock internal primaryRewardToken;
    CreditLineMarketCollateralTokenMock internal extraRewardToken;
    FixedRateIrm internal irm;
    OracleMock internal oracle;
    ConvexRewardPoolMock internal rewardPool;
    ConvexBoosterMock internal booster;

    struct AccountingState {
        Balance totalSupply;
        Balance totalBorrowed;
        Position creditPosition;
        uint128 claimableFees;
        uint256 creditBalance;
        uint256 receiverBorrowBalance;
        uint256 idleCollateral;
        uint256 stakedCollateral;
    }

    function setUp() public virtual {
        borrowToken = new CreditLineMarketCollateralTokenMock("Borrow", "BORROW");
        collateralToken = new CreditLineMarketCollateralTokenMock("Curve LP", "LP");
        depositToken = new CreditLineMarketCollateralTokenMock("Convex Deposit", "cvxLP");
        primaryRewardToken = new CreditLineMarketCollateralTokenMock("Primary Reward", "PRM");
        extraRewardToken = new CreditLineMarketCollateralTokenMock("Extra Reward", "EXT");
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
        state.creditBalance = borrowToken.balanceOf(CREDIT_ACCOUNT);
        state.receiverBorrowBalance = borrowToken.balanceOf(RECEIVER);
        state.idleCollateral = market.idleCollateralAssets();
        state.stakedCollateral = market.stakedCollateralAssets();
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

    function _configuredRewards() internal view returns (address[] memory tokens) {
        uint256 count = market.rewardTokenCount();
        tokens = new address[](count);
        for (uint256 i; i < count; ++i) {
            tokens[i] = market.rewardToken(i);
        }
    }

    function _assertRewardList(address[] memory expected) internal view {
        assertEq(market.rewardTokenCount(), expected.length);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(market.rewardToken(i), expected[i]);
            assertTrue(market.isRewardToken(expected[i]));
        }
    }

    function _assertPausedRevert(bytes32 pauseType) internal {
        vm.expectRevert(abi.encodeWithSignature("IsPaused(bytes32)", pauseType));
    }
}

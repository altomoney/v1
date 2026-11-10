// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vm} from "forge-std/Vm.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents,
    ConvexCreditLineInitParams
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {IMarketErrors, IMarketEvents, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";
import {ConvexBoosterMock} from "./mocks/ConvexBoosterMock.sol";
import {ConvexRewardPoolMock} from "./mocks/ConvexRewardPoolMock.sol";
import {CreditLineMarketCollateralTokenMock} from "./mocks/CreditLineMarketCollateralTokenMock.sol";

contract AltoConvexCreditLineMarketInitializeTest is ConvexCreditLineCommon {
    function test_RevertWhenImplementationIsInitializedDirectly() external {
        AltoConvexCreditLineMarket implementation = new AltoConvexCreditLineMarket();
        ConvexCreditLineInitParams memory params = _validInitParams();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(params);
    }

    function test_RevertWhenProxyIsAlreadyInitialized() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        market.initialize(params);
    }

    function test_InitializesUupsAuthorizationAndPreservesStateAcrossUpgrade() external {
        AccountingState memory beforeState = _state();
        address creditAccountBefore = market.creditAccount();
        address boosterBefore = market.convexBooster();
        address rewardPoolBefore = market.convexRewardPool();
        AltoConvexCreditLineMarket newImplementation = new AltoConvexCreditLineMarket();

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        market.upgradeToAndCall(address(newImplementation), "");

        vm.prank(OWNER);
        market.upgradeToAndCall(address(newImplementation), "");

        assertEq(market.owner(), OWNER);
        assertEq(market.creditAccount(), creditAccountBefore);
        assertEq(market.convexBooster(), boosterBefore);
        assertEq(market.convexRewardPool(), rewardPoolBefore);
        assertEq(market.foreclosureLtv(), FORECLOSURE_LTV);
        (uint128 creditCapacity,) = market.totalSupply();
        assertEq(creditCapacity, CREDIT_LIMIT);
        assertEq(market.rewardToken(0), address(primaryRewardToken));
        assertEq(market.rewardToken(1), address(extraRewardToken));
        _assertUnchanged(beforeState);

        ConvexCreditLineInitParams memory params = _validInitParams();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        market.initialize(params);
    }

    function test_RevertForInvalidCreditAddresses() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        params.creditMarketInitParams.baseMarketInitParams.irm = address(0);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.creditAccount = address(0);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.feeRecipient = address(0);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        candidate.initialize(params);

        assertEq(candidate.owner(), address(0));
    }

    function test_RevertForInvalidBaseAddressesAndOwner() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(0);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.collateralToken = address(0);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.oracle = address(0);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.emergencyAdmin = address(0);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.owner = address(0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        candidate.initialize(params);
    }

    function test_RevertForInvalidCreditBoundsAndRelationships() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        params.creditMarketInitParams.creditLimit = 0;
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.creditMarketInitParams.creditLimit = uint256(type(uint128).max) + 1;
        vm.expectRevert(Uint128Converter.MathUtilsMaxUint128Overflow.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.creditMarketInitParams.initialBorrowOpeningFee = MATH_PRECISION + 1;
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.maxLtv = FORECLOSURE_LTV;
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.maxLtv = FORECLOSURE_LTV + 1;
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.creditMarketInitParams.foreclosureLtv = MATH_PRECISION + 1;
        _expectCreditInvalid(candidate, params);
    }

    function test_AllowsMatchingBorrowAndCollateralTokens() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(collateralToken);

        AltoConvexCreditLineMarket candidate = _initialize(params);

        assertEq(candidate.borrowToken(), address(collateralToken));
        assertEq(candidate.collateralToken(), address(collateralToken));
    }

    function test_AllowsAndRegistersNonzeroLiquidationEngine() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        DlbDcfPriorityLiquidationEngine liquidationEngine = new DlbDcfPriorityLiquidationEngine(address(this));
        params.creditMarketInitParams.baseMarketInitParams.liquidationEngine = address(liquidationEngine);

        AltoConvexCreditLineMarket candidate = _initialize(params);

        assertEq(candidate.liquidationEngine(), address(liquidationEngine));
        assertEq(liquidationEngine.market(), address(candidate));
    }

    function test_LiquidationEngineRegistrationFailureRollsBackInitialization() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        FixedRateIrm candidateIrm = FixedRateIrm(params.creditMarketInitParams.baseMarketInitParams.irm);
        DlbDcfPriorityLiquidationEngine liquidationEngine = new DlbDcfPriorityLiquidationEngine(address(this));
        params.creditMarketInitParams.baseMarketInitParams.liquidationEngine = address(liquidationEngine);
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        vm.mockCallRevert(
            address(liquidationEngine),
            abi.encodeCall(IAltoLiquidationEngine.setMarketOnce, (address(candidate))),
            bytes("ENGINE_REGISTRATION_REVERTED")
        );
        vm.expectRevert(bytes("ENGINE_REGISTRATION_REVERTED"));
        candidate.initialize(params);
        vm.clearMockedCalls();

        assertEq(candidate.owner(), address(0));
        assertEq(liquidationEngine.market(), address(0));
        assertEq(candidateIrm.market(), address(0));
    }

    function test_RevertWhen_IrmRegistrationFails() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();
        FixedRateIrm candidateIrm = FixedRateIrm(params.creditMarketInitParams.baseMarketInitParams.irm);
        vm.mockCallRevert(
            address(candidateIrm), abi.encodeWithSelector(IIrm.setMarket.selector), bytes("SET_MARKET_REVERTED")
        );
        vm.expectRevert(bytes("SET_MARKET_REVERTED"));
        candidate.initialize(params);
        assertEq(candidate.owner(), address(0));
        assertEq(candidateIrm.market(), address(0));
    }

    function test_InitializesWithAdaptiveCurveIrm() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AdaptiveCurveIrm candidateIrm = _newAdaptiveCurveIrm();
        params.creditMarketInitParams.baseMarketInitParams.irm = address(candidateIrm);

        AltoConvexCreditLineMarket candidate = _initialize(params);
        assertEq(candidate.irm(), address(candidateIrm));
        assertEq(candidateIrm.market(), address(candidate));
    }

    function test_InitializesWithPegResponsiveIrm() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        PegResponsiveExponentialIrm candidateIrm = _newPegResponsiveIrm();
        params.creditMarketInitParams.baseMarketInitParams.irm = address(candidateIrm);

        AltoConvexCreditLineMarket candidate = _initialize(params);
        assertEq(candidate.irm(), address(candidateIrm));
        assertEq(candidateIrm.market(), address(candidate));
    }

    function test_RevertWhen_IrmHasNoCode() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.irm = USER;
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();
        vm.expectRevert();
        candidate.initialize(params);
        assertEq(candidate.owner(), address(0));
    }

    function test_RevertForZeroConvexAddresses() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        params.convexBooster = address(0);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        candidate.initialize(params);

        params = _validInitParams();
        params.rewardRecipient = address(0);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        candidate.initialize(params);
    }

    function test_RevertForZeroPoolMetadata() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        booster.setPoolInfo(address(0), address(depositToken), GAUGE, address(rewardPool), address(0), false);
        _expectCreditZero(candidate, params);
        booster.setPoolInfo(address(collateralToken), address(0), GAUGE, address(rewardPool), address(0), false);
        _expectCreditZero(candidate, params);
        booster.setPoolInfo(
            address(collateralToken), address(depositToken), address(0), address(rewardPool), address(0), false
        );
        _expectCreditZero(candidate, params);
        booster.setPoolInfo(address(collateralToken), address(depositToken), GAUGE, address(0), address(0), false);
        _expectCreditZero(candidate, params);
    }

    function test_RevertForMismatchedOrShutdownPool() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        booster.setPoolInfo(
            address(collateralToken), address(depositToken), GAUGE, address(rewardPool), address(0), true
        );
        _expectCreditInvalid(candidate, params);

        booster.setPoolInfo(USER, address(depositToken), GAUGE, address(rewardPool), address(0), false);
        _expectCreditInvalid(candidate, params);

        booster.setPoolInfo(
            address(collateralToken), address(depositToken), GAUGE, address(rewardPool), address(0), false
        );
        rewardPool.setPoolMetadata(POOL_ID + 1, address(booster), address(depositToken), address(primaryRewardToken));
        _expectCreditInvalid(candidate, params);
        rewardPool.setPoolMetadata(POOL_ID, USER, address(depositToken), address(primaryRewardToken));
        _expectCreditInvalid(candidate, params);
        rewardPool.setPoolMetadata(POOL_ID, address(booster), USER, address(primaryRewardToken));
        _expectCreditInvalid(candidate, params);
    }

    function test_RevertAndRollbackWhenConvexMetadataCallsFail() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        vm.mockCallRevert(address(booster), abi.encodeCall(ConvexBoosterMock.poolInfo, (POOL_ID)), "POOL_REVERTED");
        vm.expectRevert(bytes("POOL_REVERTED"));
        candidate.initialize(params);
        vm.clearMockedCalls();

        vm.mockCall(address(booster), abi.encodeCall(ConvexBoosterMock.poolInfo, (POOL_ID)), hex"01");
        vm.expectRevert();
        candidate.initialize(params);
        vm.clearMockedCalls();

        _assertRewardPoolMetadataQueryFailure(candidate, params, IConvexRewardPool.pid.selector, "PID_REVERTED");
        _assertRewardPoolMetadataQueryFailure(
            candidate, params, IConvexRewardPool.operator.selector, "OPERATOR_REVERTED"
        );
        _assertRewardPoolMetadataQueryFailure(
            candidate, params, IConvexRewardPool.stakingToken.selector, "STAKING_TOKEN_REVERTED"
        );
    }

    function test_RevertAndRollbackWhenPrimaryRewardQueryFails() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();
        bytes memory rewardTokenCall = abi.encodeWithSelector(IConvexRewardPool.rewardToken.selector);

        vm.mockCallRevert(address(rewardPool), rewardTokenCall, "REWARD_TOKEN_REVERTED");
        vm.expectRevert(bytes("REWARD_TOKEN_REVERTED"));
        candidate.initialize(params);
        vm.clearMockedCalls();

        vm.mockCall(address(rewardPool), rewardTokenCall, hex"01");
        vm.expectRevert();
        candidate.initialize(params);
        vm.clearMockedCalls();
        assertEq(candidate.owner(), address(0));
    }

    function test_InitializationDoesNotApproveBooster() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        FixedRateIrm candidateIrm = FixedRateIrm(params.creditMarketInitParams.baseMarketInitParams.irm);
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();
        collateralToken.setApproveFailure(true);

        candidate.initialize(params);

        assertEq(candidate.owner(), OWNER);
        assertEq(candidateIrm.market(), address(candidate));
        assertEq(collateralToken.allowance(address(candidate), address(booster)), 0);
    }

    function test_InitializationEmitsBaseThenCreditThenConvexEvents() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();
        vm.recordLogs();
        candidate.initialize(params);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 liquidationEngineIndex = type(uint256).max;
        uint256 irmIndex = type(uint256).max;
        uint256 oracleIndex = type(uint256).max;
        uint256 maxLtvIndex = type(uint256).max;
        uint256 feeRecipientIndex = type(uint256).max;
        uint256 foreclosureIndex = type(uint256).max;
        uint256 creditLimitIndex = type(uint256).max;
        uint256 openingFeeIndex = type(uint256).max;
        uint256 convexIndex = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(candidate)) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == IMarketEvents.SetLiquidationEngine.selector) liquidationEngineIndex = i;
            if (topic == IMarketEvents.SetIrm.selector) irmIndex = i;
            if (topic == IMarketEvents.SetOracle.selector) oracleIndex = i;
            if (topic == IMarketEvents.SetMaxLtv.selector) maxLtvIndex = i;
            if (topic == IMarketEvents.SetFeeRecipient.selector) feeRecipientIndex = i;
            if (topic == IAltoConvexCreditLineMarketEvents.SetForeclosureLtv.selector) foreclosureIndex = i;
            if (topic == IAltoConvexCreditLineMarketEvents.SetCreditLimit.selector) creditLimitIndex = i;
            if (topic == IAltoConvexCreditLineMarketEvents.SetBorrowOpeningFee.selector) openingFeeIndex = i;
            if (topic == IAltoConvexCreditLineMarketEvents.ConvexConfigured.selector) convexIndex = i;
        }

        assertLt(liquidationEngineIndex, irmIndex);
        assertLt(irmIndex, foreclosureIndex);
        assertLt(irmIndex, oracleIndex);
        assertLt(oracleIndex, maxLtvIndex);
        assertLt(maxLtvIndex, feeRecipientIndex);
        assertLt(feeRecipientIndex, foreclosureIndex);
        assertLt(foreclosureIndex, creditLimitIndex);
        assertLt(creditLimitIndex, openingFeeIndex);
        assertLt(openingFeeIndex, convexIndex);
    }

    function test_InitializationEmitsCreditAccountAndEachInitialRewardTokenOnce() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        vm.expectEmit(address(candidate));
        emit SetCreditAccount(address(0), CREDIT_ACCOUNT);
        for (uint256 i = 0; i < params.rewardTokens.length; ++i) {
            vm.expectEmit(address(candidate));
            emit RewardTokenAdded(params.rewardTokens[i]);
        }
        vm.expectEmit(address(candidate));
        emit ConvexConfigured(address(booster), POOL_ID, address(rewardPool), address(depositToken), REWARD_RECIPIENT);

        vm.recordLogs();
        candidate.initialize(params);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 creditAccountEvents;
        uint256 rewardTokenEvents;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(candidate)) continue;
            if (logs[i].topics[0] == IAltoConvexCreditLineMarketEvents.SetCreditAccount.selector) {
                ++creditAccountEvents;
            }
            if (logs[i].topics[0] == IAltoConvexCreditLineMarketEvents.RewardTokenAdded.selector) {
                ++rewardTokenEvents;
            }
        }
        assertEq(creditAccountEvents, 1);
        assertEq(rewardTokenEvents, params.rewardTokens.length);
    }

    function test_RevertForInvalidInitialRewardList() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();

        params.rewardTokens = new address[](0);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[0] = address(0);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[0] = USER;
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[0] = address(collateralToken);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[0] = address(borrowToken);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[0] = address(depositToken);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[1] = address(primaryRewardToken);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens = new address[](17);
        for (uint256 i; i < 17; ++i) {
            params.rewardTokens[i] = address(new CreditLineMarketCollateralTokenMock("R", "R"));
        }
        params.rewardTokens[0] = address(primaryRewardToken);
        _expectCreditInvalid(candidate, params);

        params = _validInitParams();
        params.rewardTokens[0] = address(extraRewardToken);
        params.rewardTokens[1] = address(new CreditLineMarketCollateralTokenMock("Other", "OTH"));
        _expectCreditInvalid(candidate, params);
    }

    function test_InitializesAllBaseCreditAndConvexState() external {
        assertEq(uint256(market.MARKET_TYPE()), uint256(MarketType.CREDIT_MINT));
        assertEq(market.borrowToken(), address(borrowToken));
        assertEq(market.collateralToken(), address(collateralToken));
        assertEq(market.irm(), address(irm));
        assertEq(market.oracle(), address(oracle));
        assertEq(market.maxLtv(), MAX_LTV);
        assertEq(market.feeRecipient(), FEE_RECIPIENT);
        assertEq(market.owner(), OWNER);
        assertEq(market.liquidationEngine(), address(0));
        assertEq(irm.market(), address(market));
        assertTrue(market.pausers(OWNER, PAUSE_TYPE));
        assertTrue(market.pausers(OWNER, FROZEN_TYPE));

        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
        assertEq(market.foreclosureLtv(), FORECLOSURE_LTV);
        assertEq(market.borrowOpeningFee(), 0);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(market.badDebtAssets(), 0);
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyAssets, CREDIT_LIMIT);
        assertEq(supplyShares, 0);
        (uint128 borrowAssets, uint128 borrowShares) = market.totalBorrowed();
        assertEq(borrowAssets, 0);
        assertEq(borrowShares, 0);
        (uint128 supplyPositionShares, uint128 positionBorrowShares, uint128 positionCollateralAssets) =
            market.position(CREDIT_ACCOUNT);
        assertEq(supplyPositionShares, 0);
        assertEq(positionBorrowShares, 0);
        assertEq(positionCollateralAssets, 0);

        assertEq(market.convexBooster(), address(booster));
        assertEq(market.convexPoolId(), POOL_ID);
        assertEq(market.convexRewardPool(), address(rewardPool));
        assertEq(market.rewardRecipient(), REWARD_RECIPIENT);
        assertTrue(market.convexActive());
        _assertRewardTokenCount(2);
        assertEq(market.rewardToken(0), address(primaryRewardToken));
        assertEq(market.rewardToken(1), address(extraRewardToken));
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
        assertEq(collateralToken.balanceOf(address(market)), 0);
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(booster.depositCalls(), 0);
    }

    function test_GrantsPauseRolesOnlyToConfiguredEmergencyAdmin() external {
        address emergencyAdmin = makeAddr("EmergencyAdmin");
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.irm = address(_newFixedRateIrm());
        params.creditMarketInitParams.baseMarketInitParams.emergencyAdmin = emergencyAdmin;

        AltoConvexCreditLineMarket candidate = _initialize(params);

        assertEq(candidate.owner(), OWNER);
        assertTrue(candidate.pausers(emergencyAdmin, PAUSE_TYPE));
        assertTrue(candidate.pausers(emergencyAdmin, FROZEN_TYPE));
        assertFalse(candidate.pausers(OWNER, PAUSE_TYPE));
        assertFalse(candidate.pausers(OWNER, FROZEN_TYPE));
    }

    function test_AcceptsInclusiveBoundsPoolZeroAndZeroStashFromNonOwnerCaller() external {
        FixedRateIrm newIrm = _newFixedRateIrm();
        ConvexRewardPoolMock newPool = new ConvexRewardPoolMock(
            0, address(0), address(depositToken), address(primaryRewardToken), address(collateralToken)
        );
        ConvexBoosterMock newBooster =
            new ConvexBoosterMock(address(collateralToken), address(depositToken), GAUGE, address(newPool));
        newPool.setPoolMetadata(0, address(newBooster), address(depositToken), address(primaryRewardToken));

        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.irm = address(newIrm);
        params.creditMarketInitParams.baseMarketInitParams.maxLtv = 0;
        params.creditMarketInitParams.creditLimit = type(uint128).max;
        params.creditMarketInitParams.foreclosureLtv = MATH_PRECISION;
        params.creditMarketInitParams.initialBorrowOpeningFee = MATH_PRECISION;
        params.convexBooster = address(newBooster);
        params.convexPoolId = 0;
        params.rewardTokens = new address[](1);
        params.rewardTokens[0] = address(primaryRewardToken);

        AltoConvexCreditLineMarket candidate = _newUninitializedMarket();
        vm.prank(USER);
        candidate.initialize(params);

        assertEq(candidate.owner(), OWNER);
        assertEq(candidate.convexPoolId(), 0);
        (uint128 creditCapacity,) = candidate.totalSupply();
        assertEq(creditCapacity, type(uint128).max);
        assertEq(candidate.foreclosureLtv(), MATH_PRECISION);
        assertEq(candidate.borrowOpeningFee(), MATH_PRECISION);
    }

    function test_AllowsExactlyMaximumRewardTokensAndPreservesOrder() external {
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.irm = address(_newFixedRateIrm());
        params.rewardTokens = new address[](16);
        params.rewardTokens[0] = address(primaryRewardToken);
        for (uint256 i = 1; i < 16; ++i) {
            params.rewardTokens[i] = address(new CreditLineMarketCollateralTokenMock("R", "R"));
        }

        AltoConvexCreditLineMarket candidate = _initialize(params);
        for (uint256 i; i < 16; ++i) {
            assertEq(candidate.rewardToken(i), params.rewardTokens[i]);
            assertTrue(candidate.isRewardToken(params.rewardTokens[i]));
        }
        vm.expectRevert();
        candidate.rewardToken(16);
    }

    function _expectCreditInvalid(AltoConvexCreditLineMarket candidate, ConvexCreditLineInitParams memory params)
        private
    {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        candidate.initialize(params);
    }

    function _expectCreditZero(AltoConvexCreditLineMarket candidate, ConvexCreditLineInitParams memory params) private {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        candidate.initialize(params);
    }

    function _assertRewardPoolMetadataQueryFailure(
        AltoConvexCreditLineMarket candidate,
        ConvexCreditLineInitParams memory params,
        bytes4 selector,
        bytes memory revertData
    ) private {
        bytes memory callData = abi.encodeWithSelector(selector);

        vm.mockCallRevert(address(rewardPool), callData, revertData);
        vm.expectRevert(revertData);
        candidate.initialize(params);
        vm.clearMockedCalls();
        assertEq(candidate.owner(), address(0));

        vm.mockCall(address(rewardPool), callData, hex"01");
        vm.expectRevert();
        candidate.initialize(params);
        vm.clearMockedCalls();
        assertEq(candidate.owner(), address(0));
    }
}

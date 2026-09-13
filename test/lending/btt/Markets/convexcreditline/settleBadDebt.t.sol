// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {
    ConvexCreditLineInitParams,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSettleBadDebtTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwnerBeforeBurn() external {
        vm.mockCallRevert(address(borrowToken), borrowToken.burn.selector, bytes("BURN_MUST_NOT_BE_CALLED"));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.settleBadDebt(0);
    }

    function test_AvailableWhenActiveFrozenOrPaused() external {
        _createBadDebtAndFundOwner(100 ether);
        vm.prank(OWNER);
        market.settleBadDebt(100 ether);
        assertEq(market.badDebtAssets(), 0);

        setUp();
        _createBadDebtAndFundOwner(100 ether);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.settleBadDebt(100 ether);
        assertEq(market.badDebtAssets(), 0);

        setUp();
        _createBadDebtAndFundOwner(100 ether);
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.settleBadDebt(100 ether);
        assertEq(market.badDebtAssets(), 0);
    }

    function test_PartialAndFullSettlementBurnOwnerTokensEmitAndPreserveOtherState() external {
        _createBadDebtAndFundOwner(100 ether);
        AccountingState memory expected = _state();
        address[] memory rewardsBefore = _configuredRewards(2);
        address boosterBefore = market.convexBooster();
        uint256 poolIdBefore = market.convexPoolId();
        address rewardPoolBefore = market.convexRewardPool();
        address rewardRecipientBefore = market.rewardRecipient();
        bool convexActiveBefore = market.convexActive();
        uint256 supplyBefore = borrowToken.totalSupply();
        assertEq(borrowToken.allowance(OWNER, address(market)), 0);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.BadDebtSettled(40 ether);
        vm.prank(OWNER);
        market.settleBadDebt(40 ether);

        expected.badDebt = 60 ether;
        _assertStateEq(_state(), expected);
        assertEq(borrowToken.balanceOf(OWNER), 60 ether);
        assertEq(borrowToken.balanceOf(address(market)), 0);
        assertEq(borrowToken.allowance(OWNER, address(market)), 0);
        assertEq(borrowToken.totalSupply(), supplyBefore - 40 ether);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.BadDebtSettled(60 ether);
        vm.prank(OWNER);
        market.settleBadDebt(60 ether);

        expected.badDebt = 0;
        _assertStateEq(_state(), expected);
        assertEq(borrowToken.balanceOf(OWNER), 0);
        assertEq(borrowToken.balanceOf(address(market)), 0);
        assertEq(borrowToken.totalSupply(), supplyBefore - 100 ether);
        _assertRewardList(rewardsBefore);
        assertEq(market.convexBooster(), boosterBefore);
        assertEq(market.convexPoolId(), poolIdBefore);
        assertEq(market.convexRewardPool(), rewardPoolBefore);
        assertEq(market.rewardRecipient(), rewardRecipientBefore);
        assertEq(market.convexActive(), convexActiveBefore);
    }

    function test_SettlementRestoresExactlyTheSettledCreditCapacity() external {
        vm.prank(OWNER);
        market.setCreditLimit(100 ether);
        _createBadDebt(100 ether);
        _fundOwnerFromCreditAccount(40 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);

        AccountingState memory beforeRejectedBorrow = _state();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
        _assertUnchanged(beforeRejectedBorrow);

        vm.prank(OWNER);
        market.settleBadDebt(40 ether);
        _borrow(40 ether);

        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 40 ether);
        assertEq(market.badDebtAssets(), 60 ether);

        AccountingState memory capacityState = _state();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
        _assertUnchanged(capacityState);
    }

    function test_ActualDusdBurnsOwnerBalanceSupplyAndMarketMinterBucketWithoutAllowance() external {
        (DUSD dusd, AltoConvexCreditLineMarket dusdMarket) = _createDusdBadDebt(0);
        (uint256 mintedBefore,) = dusd.minterConfig(address(dusdMarket));
        uint256 supplyBefore = dusd.totalSupply();
        assertEq(dusd.balanceOf(OWNER), 100 ether);
        assertEq(dusd.allowance(OWNER, address(dusdMarket)), 0);
        assertEq(dusdMarket.badDebtAssets(), 100 ether);

        vm.expectEmit(address(dusdMarket));
        emit IAltoConvexCreditLineMarketEvents.BadDebtSettled(40 ether);
        vm.prank(OWNER);
        dusdMarket.settleBadDebt(40 ether);

        (uint256 mintedAfterPartial,) = dusd.minterConfig(address(dusdMarket));
        assertEq(dusd.balanceOf(OWNER), 60 ether);
        assertEq(dusd.balanceOf(address(dusdMarket)), 0);
        assertEq(dusd.allowance(OWNER, address(dusdMarket)), 0);
        assertEq(dusd.totalSupply(), supplyBefore - 40 ether);
        assertEq(mintedAfterPartial, mintedBefore - 40 ether);
        assertEq(dusdMarket.badDebtAssets(), 60 ether);

        vm.prank(OWNER);
        dusdMarket.settleBadDebt(60 ether);

        (uint256 mintedAfterFull,) = dusd.minterConfig(address(dusdMarket));
        assertEq(dusd.balanceOf(OWNER), 0);
        assertEq(dusd.balanceOf(address(dusdMarket)), 0);
        assertEq(dusd.totalSupply(), 0);
        assertEq(mintedAfterFull, 0);
        assertEq(dusdMarket.badDebtAssets(), 0);
    }

    function test_ActualDusdAuthorizationAndPauseFailuresRevertAtomically() external {
        (DUSD dusd, AltoConvexCreditLineMarket dusdMarket) = _createDusdBadDebt(0);
        uint256 ownerBalanceBefore = dusd.balanceOf(OWNER);
        uint256 supplyBefore = dusd.totalSupply();
        (uint256 mintedBefore,) = dusd.minterConfig(address(dusdMarket));

        vm.prank(OWNER);
        dusd.setBurnerStatus(address(dusdMarket), false);
        vm.prank(OWNER);
        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusdMarket.settleBadDebt(1 ether);
        _assertDusdFailureState(dusd, dusdMarket, ownerBalanceBefore, supplyBefore, mintedBefore, 100 ether);

        vm.startPrank(OWNER);
        dusd.setBurnerStatus(address(dusdMarket), true);
        dusd.pause(PAUSE_TYPE, true);
        vm.stopPrank();
        vm.prank(OWNER);
        _assertPausedRevert(PAUSE_TYPE);
        dusdMarket.settleBadDebt(1 ether);
        _assertDusdFailureState(dusd, dusdMarket, ownerBalanceBefore, supplyBefore, mintedBefore, 100 ether);
    }

    function test_ActualDusdCannotSettleUnmintedFeesUntilTheyAreClaimed() external {
        (DUSD dusd, AltoConvexCreditLineMarket dusdMarket) = _createDusdBadDebt(0.1 ether);
        assertEq(dusdMarket.badDebtAssets(), 110 ether);
        assertEq(dusdMarket.claimableFeesAssets(), 10 ether);
        assertEq(dusd.balanceOf(OWNER), 100 ether);
        (uint256 mintedBefore,) = dusd.minterConfig(address(dusdMarket));
        assertEq(mintedBefore, 100 ether);

        vm.prank(OWNER);
        vm.expectRevert(IDUSD.DUSDInvalidInput.selector);
        dusdMarket.settleBadDebt(100 ether + 1);
        _assertDusdFailureState(dusd, dusdMarket, 100 ether, 100 ether, 100 ether, 110 ether);
        assertEq(dusdMarket.claimableFeesAssets(), 10 ether);

        vm.prank(OWNER);
        dusdMarket.settleBadDebt(100 ether);
        assertEq(dusdMarket.badDebtAssets(), 10 ether);
        assertEq(dusdMarket.claimableFeesAssets(), 10 ether);
        (uint256 mintedAfterPrincipal,) = dusd.minterConfig(address(dusdMarket));
        assertEq(mintedAfterPrincipal, 0);

        vm.prank(FEE_RECIPIENT);
        dusdMarket.claimInterest(10 ether);
        vm.prank(FEE_RECIPIENT);
        dusd.transfer(OWNER, 10 ether);
        vm.prank(OWNER);
        dusdMarket.settleBadDebt(10 ether);

        (uint256 mintedAfterFees,) = dusd.minterConfig(address(dusdMarket));
        assertEq(mintedAfterFees, 0);
        assertEq(dusd.totalSupply(), 0);
        assertEq(dusd.balanceOf(OWNER), 0);
        assertEq(dusdMarket.badDebtAssets(), 0);
        assertEq(dusdMarket.claimableFeesAssets(), 0);
    }

    function _createBadDebt(uint256 assets) private {
        _openPosition(1_000 ether, assets);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
    }

    function _createBadDebtAndFundOwner(uint256 assets) private {
        _createBadDebt(assets);
        _fundOwnerFromCreditAccount(assets);
    }

    function _fundOwnerFromCreditAccount(uint256 assets) private {
        vm.prank(CREDIT_ACCOUNT);
        borrowToken.transfer(OWNER, assets);
    }

    function _createDusdBadDebt(uint256 openingFee) private returns (DUSD dusd, AltoConvexCreditLineMarket dusdMarket) {
        dusd = new DUSD(address(new EndpointV2Mock(1, address(this))), OWNER);
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(dusd);
        params.creditMarketInitParams.initialBorrowOpeningFee = openingFee;
        dusdMarket = _initialize(params);

        vm.startPrank(OWNER);
        dusd.setMinterStatus(address(dusdMarket), true);
        dusd.setMinterCeiling(address(dusdMarket), 1_000 ether);
        dusd.setBurnerStatus(address(dusdMarket), true);
        vm.stopPrank();

        deal(address(collateralToken), CREDIT_ACCOUNT, 1_000 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        collateralToken.approve(address(dusdMarket), type(uint256).max);
        dusdMarket.addCollateral(1_000 ether, CREDIT_ACCOUNT);
        dusdMarket.borrow(100 ether, 0, CREDIT_ACCOUNT, OWNER, "");
        vm.stopPrank();

        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        dusdMarket.governanceLiquidate(CREDIT_ACCOUNT, false);
    }

    function _assertDusdFailureState(
        DUSD dusd,
        AltoConvexCreditLineMarket dusdMarket,
        uint256 ownerBalance,
        uint256 supply,
        uint256 minted,
        uint256 badDebt
    ) private view {
        (uint256 actualMinted,) = dusd.minterConfig(address(dusdMarket));
        assertEq(dusd.balanceOf(OWNER), ownerBalance);
        assertEq(dusd.balanceOf(address(dusdMarket)), 0);
        assertEq(dusd.totalSupply(), supply);
        assertEq(actualMinted, minted);
        assertEq(dusdMarket.badDebtAssets(), badDebt);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {SwapTargetMock} from "./mocks/SwapTargetMock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

/// @title WrapperTokenRoundingTest
/// @notice Fuzz tests for wrap/unwrap rounding and solvency across underlying token migration rollovers.
/// @dev WrapperToken uses floor rounding (`divideWithRounding(..., false)`) on:
///      - wrap:   wrapped = floor(ptAmount * 10**DECIMALS / exchangeRate)
///      - unwrap: ptOut   = floor(wrapped * exchangeRate / 10**DECIMALS)
///      - rollover: newRate = floor(exchangeRate * buyAmountOut / amountIn)
///
///      These tests verify that:
///      1) rounding never over-allocates wrapped tokens or PT vs the exact rational amount
///      2) all wrapped holders can fully unwrap after one or two rollovers
///      3) leftover rounding dust stays in the wrapper (does not break solvency)
contract WrapperTokenRoundingTest is WrapperTokenCommon {
    using FixedPointMath for uint256;

    /// @notice Fuzz inputs for the two-swap integration scenario.
    struct TwoSwapScenario {
        /// @dev PT amount user1 wraps before the first swap.
        uint256 user1WrapAmount;
        /// @dev PT1 amount received when the wrapper swaps all of user1's underlying PT.
        uint256 firstSwapBuyAmount;
        /// @dev PT1 amount user2 wraps after the first swap.
        uint256 user2WrapAmount;
        /// @dev PT2 amount received when the wrapper swaps its full PT1 balance.
        uint256 secondSwapBuyAmount;
    }

    uint256 internal constant MIN_PT_AMOUNT = 1e4;
    uint256 internal constant MAX_PT_AMOUNT = 1e27;

    address internal user1;
    address internal user2;

    SwapTargetMock internal swapTarget;
    ERC20MockMintableDecimals internal pt1;
    ERC20MockMintableDecimals internal pt2;

    function setUp() public override {
        super.setUp();
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        swapTarget = new SwapTargetMock();
        pt1 = new ERC20MockMintableDecimals("PT1", "PT1", TOKEN_DECIMALS);
        pt2 = new ERC20MockMintableDecimals("PT2", "PT2", TOKEN_DECIMALS);
        _whitelistSwapTarget(swapTarget);
    }

    /*//////////////////////////////////////////////////////////////
                        ROUNDING ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Checks that a wrap result matches floor rounding and does not over-mint wrapped tokens.
    ///      `wrapped * exchangeRate <= ptAmount * scale` means minted shares never claim more backing
    ///      than the PT actually deposited.
    function _assertWrapRoundingFavorsUser(uint256 ptAmount, uint256 exchangeRate, uint256 wrappedMinted)
        internal
        pure
    {
        uint256 scale = 10 ** TOKEN_DECIMALS;

        assertEq(wrappedMinted, ptAmount.divideWithRounding(scale, exchangeRate, false));
        assertLe(wrappedMinted * exchangeRate, ptAmount * scale);
        assertGe(wrappedMinted * exchangeRate + exchangeRate - 1, ptAmount * scale);
    }

    /// @dev Checks that an unwrap result matches floor rounding and does not over-pay PT.
    ///      `ptOut * scale <= wrapped * exchangeRate` means the user cannot withdraw more PT
    ///      than their wrapped balance represents at the current rate.
    function _assertUnwrapRoundingFavorsUser(uint256 wrappedAmount, uint256 exchangeRate, uint256 ptOut) internal pure {
        uint256 scale = 10 ** TOKEN_DECIMALS;

        assertEq(ptOut, wrappedAmount.divideWithRounding(exchangeRate, scale, false));
        assertLe(ptOut * scale, wrappedAmount * exchangeRate);
        assertGe(ptOut * scale + scale - 1, wrappedAmount * exchangeRate);
    }

    /// @dev Mirrors `WrapperToken.rollover` exchange-rate update:
    ///      newRate = floor(currentRate * buyAmountOut / amountIn)
    function _expectedRateAfterSwap(uint256 currentRate, uint256 buyAmountOut, uint256 amountIn)
        internal
        pure
        returns (uint256)
    {
        return currentRate.divideWithRounding(buyAmountOut, amountIn, false);
    }

    /*//////////////////////////////////////////////////////////////
                          SCENARIO HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Executes a rollOverBot rollover through the whitelisted mock swap target.
    ///      The wrapper must be paused during rollover and is unpaused before returning.
    function _executeRollover(
        ERC20MockMintableDecimals sellToken,
        ERC20MockMintableDecimals buyToken,
        uint256 amountIn,
        uint256 buyAmountOut
    ) internal {
        buyToken.mint(address(swapTarget), buyAmountOut);
        _pauseWrapper();

        bytes memory swapData =
            abi.encodeCall(SwapTargetMock.executeSwap, (address(sellToken), address(buyToken), amountIn, buyAmountOut));

        vm.prank(rollOverBot);
        wrapper.rollover(address(buyToken), amountIn, buyAmountOut, address(swapTarget), swapData);

        _unpauseWrapper();
    }

    /// @dev Mints PT to `account`, approves the wrapper, wraps, and returns the minted wrapped balance.
    function _wrap(address account, ERC20MockMintableDecimals ptToken, uint256 ptAmount)
        internal
        returns (uint256 wrappedMinted)
    {
        ptToken.mint(account, ptAmount);
        vm.startPrank(account);
        ptToken.approve(address(wrapper), ptAmount);
        wrapper.wrap(ptAmount);
        wrappedMinted = wrapper.balanceOf(account);
        vm.stopPrank();

        _assertWrapRoundingFavorsUser(ptAmount, wrapper.exchangeRate(), wrappedMinted);
    }

    /// @dev Unwraps `wrappedAmount` for `account` and returns the PT received.
    function _unwrap(address account, uint256 wrappedAmount) internal returns (uint256 ptOut) {
        ERC20MockMintableDecimals currentPt = ERC20MockMintableDecimals(wrapper.underlyingToken());
        uint256 ptBefore = currentPt.balanceOf(account);

        vm.prank(account);
        wrapper.unwrap(wrappedAmount);

        ptOut = currentPt.balanceOf(account) - ptBefore;
        _assertUnwrapRoundingFavorsUser(wrappedAmount, wrapper.exchangeRate(), ptOut);
    }

    /// @dev Clamps raw fuzz inputs to a practical PT amount range.
    function _boundTwoSwapScenario(
        uint256 user1WrapAmount,
        uint256 firstSwapBuyAmount,
        uint256 user2WrapAmount,
        uint256 secondSwapBuyAmount
    ) internal returns (TwoSwapScenario memory scenario) {
        scenario.user1WrapAmount = _boundPtAmount(user1WrapAmount);
        scenario.firstSwapBuyAmount = _boundPtAmount(firstSwapBuyAmount);
        scenario.user2WrapAmount = _boundPtAmount(user2WrapAmount);
        scenario.secondSwapBuyAmount = _boundPtAmount(secondSwapBuyAmount);
    }

    function _boundPtAmount(uint256 amount) private returns (uint256) {
        return bound(amount, MIN_PT_AMOUNT, MAX_PT_AMOUNT);
    }

    /// @dev Returns true when the scenario can complete both swaps and full withdrawals.
    function _isValidTwoSwapScenario(TwoSwapScenario memory scenario) internal pure returns (bool) {
        uint256 scale = 10 ** TOKEN_DECIMALS;

        // Swap 1: PT0 -> PT1. Reject if the updated rate would be zero.
        uint256 rateAfterFirstSwap =
            _expectedRateAfterSwap(scale, scenario.firstSwapBuyAmount, scenario.user1WrapAmount);
        if (rateAfterFirstSwap == 0) {
            return false;
        }

        // User2 must mint a non-zero wrapped balance at the post-swap rate.
        if (_expectedWrappedAmount(scenario.user2WrapAmount, rateAfterFirstSwap) == 0) {
            return false;
        }

        // Swap 2: full PT1 balance -> PT2. Reject if the updated rate would be zero.
        uint256 pt1Balance = scenario.firstSwapBuyAmount + scenario.user2WrapAmount;
        uint256 rateAfterSecondSwap =
            _expectedRateAfterSwap(rateAfterFirstSwap, scenario.secondSwapBuyAmount, pt1Balance);
        if (rateAfterSecondSwap == 0) {
            return false;
        }

        // Both users must receive a non-zero PT amount when unwrapping at the final rate.
        uint256 user1Wrapped = _expectedWrappedAmount(scenario.user1WrapAmount, scale);
        uint256 user2Wrapped = _expectedWrappedAmount(scenario.user2WrapAmount, rateAfterFirstSwap);
        uint256 user1ExpectedPt = _expectedPtAmount(user1Wrapped, rateAfterSecondSwap);
        uint256 user2ExpectedPt = _expectedPtAmount(user2Wrapped, rateAfterSecondSwap);

        if (user1ExpectedPt == 0 || user2ExpectedPt == 0) {
            return false;
        }

        return true;
    }

    /// @dev Full integration path:
    ///      1. user1 wraps PT0 at rate = 10**DECIMALS
    ///      2. owner swaps all user1 PT0 -> PT1
    ///      3. user2 wraps PT1 at the new rate
    ///      4. owner swaps full PT1 balance -> PT2
    ///      5. user1 and user2 fully unwrap; wrapper must remain solvent
    function _runTwoSwapScenario(TwoSwapScenario memory scenario) internal {
        uint256 scale = _tenPowDecimals();
        uint256 pt1BalanceBeforeSecondSwap = scenario.firstSwapBuyAmount + scenario.user2WrapAmount;
        uint256 user1Wrapped;
        uint256 user2Wrapped;
        uint256 user1ExpectedPt;
        uint256 user2ExpectedPt;

        // Step 1: initial wrap at 1:1 rate.
        assertEq(wrapper.exchangeRate(), scale);
        user1Wrapped = _wrap(user1, underlyingPt, scenario.user1WrapAmount);
        assertEq(underlyingPt.balanceOf(address(wrapper)), scenario.user1WrapAmount);

        // Step 2: migrate underlying from PT0 to PT1.
        _executeRollover(underlyingPt, pt1, scenario.user1WrapAmount, scenario.firstSwapBuyAmount);
        assertEq(
            wrapper.exchangeRate(), _expectedRateAfterSwap(scale, scenario.firstSwapBuyAmount, scenario.user1WrapAmount)
        );
        assertEq(wrapper.underlyingToken(), address(pt1));
        assertEq(pt1.balanceOf(address(wrapper)), scenario.firstSwapBuyAmount);

        // Step 3: second depositor joins after the first swap.
        user2Wrapped = _wrap(user2, pt1, scenario.user2WrapAmount);
        assertEq(pt1.balanceOf(address(wrapper)), scenario.firstSwapBuyAmount + scenario.user2WrapAmount);

        // Step 4: migrate underlying from PT1 to PT2 using the full wrapper balance.
        _executeRollover(pt1, pt2, pt1BalanceBeforeSecondSwap, scenario.secondSwapBuyAmount);
        assertEq(wrapper.underlyingToken(), address(pt2));
        assertEq(pt2.balanceOf(address(wrapper)), scenario.secondSwapBuyAmount);

        // Step 5: both users must be able to withdraw their full wrapped balances.
        user1ExpectedPt = _expectedPtAmount(user1Wrapped, wrapper.exchangeRate());
        user2ExpectedPt = _expectedPtAmount(user2Wrapped, wrapper.exchangeRate());

        assertGe(scenario.secondSwapBuyAmount, user1ExpectedPt + user2ExpectedPt);

        assertEq(_unwrap(user1, user1Wrapped), user1ExpectedPt);
        assertEq(_unwrap(user2, user2Wrapped), user2ExpectedPt);
        assertEq(wrapper.totalSupply(), 0);

        // Any rounding dust remains in the wrapper instead of breaking solvency.
        assertGe(pt2.balanceOf(address(wrapper)), scenario.secondSwapBuyAmount - user1ExpectedPt - user2ExpectedPt);
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice End-to-end fuzz test across two PT migrations and two depositors.
    function testFuzz_RoundingAndWithdrawalsAfterTwoSwaps(
        uint256 user1WrapAmount,
        uint256 firstSwapBuyAmount,
        uint256 user2WrapAmount,
        uint256 secondSwapBuyAmount
    ) public {
        TwoSwapScenario memory scenario = _boundTwoSwapScenario(
            user1WrapAmount, firstSwapBuyAmount, user2WrapAmount, secondSwapBuyAmount
        );
        vm.assume(_isValidTwoSwapScenario(scenario));
        _runTwoSwapScenario(scenario);
    }

    /// @notice Pure-math fuzz test: floor-minted wrapped amount must never exceed the ceil fair share.
    function testFuzz_WrapNeverOverMintsRelativeToCeil(uint256 ptAmount, uint256 exchangeRate) public {
        exchangeRate = bound(exchangeRate, 1, 1e36);
        ptAmount = bound(ptAmount, 1, 1e36);

        uint256 scale = _tenPowDecimals();
        uint256 wrappedMinted = ptAmount.divideWithRounding(scale, exchangeRate, false);
        vm.assume(wrappedMinted > 0);

        _assertWrapRoundingFavorsUser(ptAmount, exchangeRate, wrappedMinted);
        assertLe(wrappedMinted, Math.ceilDiv(ptAmount * scale, exchangeRate));
    }

    /// @notice Pure-math fuzz test: floor-paid PT amount must never exceed the ceil fair share.
    function testFuzz_UnwrapNeverOverPaysRelativeToCeil(uint256 wrappedAmount, uint256 exchangeRate) public {
        exchangeRate = bound(exchangeRate, 1, 1e36);
        wrappedAmount = bound(wrappedAmount, 1, 1e36);

        uint256 scale = _tenPowDecimals();
        uint256 ptOut = wrappedAmount.divideWithRounding(exchangeRate, scale, false);
        vm.assume(ptOut > 0);

        _assertUnwrapRoundingFavorsUser(wrappedAmount, exchangeRate, ptOut);
        assertLe(ptOut, Math.ceilDiv(wrappedAmount * exchangeRate, scale));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {WrapperTokenHarness} from "./mocks/WrapperTokenHarness.sol";
import {
    IWrapperTokenErrors,
    IWrapperTokenEvents,
    SwapTargetMetadata
} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SwapTargetMock} from "./mocks/SwapTargetMock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

contract RolloverTest is WrapperTokenCommon {
    uint256 internal constant AMOUNT_IN = 100 ether;
    uint256 internal constant BUY_AMOUNT_OUT = 90 ether;
    uint256 internal constant MIN_AMOUNT_OUT = 80 ether;
    uint256 internal constant DONATED_UNDERLYING = 5 ether;

    SwapTargetMock internal swapTarget;
    ERC20MockMintableDecimals internal newUnderlyingToken;

    function setUp() public override {
        super.setUp();
        swapTarget = new SwapTargetMock();
        newUnderlyingToken = new ERC20MockMintableDecimals("newPT", "nPT", TOKEN_DECIMALS);
        _mintUnderlyingToWrapper(AMOUNT_IN);
        _whitelistSwapTarget(swapTarget);
        _pauseWrapper();
    }

    function _rolloverData(uint256 buyAmountOut) internal view returns (bytes memory) {
        return _buildSwapData(
            address(swapTarget), address(underlyingPt), address(newUnderlyingToken), AMOUNT_IN, buyAmountOut
        );
    }

    function _callRollover(uint256 minAmountOut, uint256 buyAmountOut) internal {
        vm.prank(rollOverBot);
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, minAmountOut, address(swapTarget), _rolloverData(buyAmountOut)
        );
    }

    function test_RevertWhen_CallerIsNotRollOverBot() public {
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(nonOwner);
        vm.expectRevert(IWrapperTokenErrors.NotRollOverBot.selector);
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_ContractIsNotPaused() public {
        _unpauseWrapper();
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(abi.encodeWithSelector(IWrapperTokenErrors.IsNotPaused.selector, PAUSE_TYPE));
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_NewUnderlyingTokenIsZeroAddress() public {
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(address(0), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT));
    }

    function test_RevertWhen_NewUnderlyingTokenEqualsCurrentUnderlyingToken() public {
        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(
            address(underlyingPt),
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            address(swapTarget),
            _buildSwapData(address(swapTarget), address(underlyingPt), address(underlyingPt), AMOUNT_IN, BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_NewUnderlyingTokenDecimalsDifferFromDecimals() public {
        ERC20MockMintableDecimals wrongNewToken = new ERC20MockMintableDecimals("new6", "n6", 6);
        wrongNewToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(
            address(wrongNewToken),
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            address(swapTarget),
            _buildSwapData(
                address(swapTarget), address(underlyingPt), address(wrongNewToken), AMOUNT_IN, BUY_AMOUNT_OUT
            )
        );
    }

    function test_RevertWhen_NewUnderlyingTokenDecimalsDifferFromDecimals_WhenWrapperDecimalsIsSix() public {
        ERC20MockMintableDecimals pt6 = new ERC20MockMintableDecimals("PT6", "PT6", 6);
        address localRollOverBot = makeAddr("localRollOverBot");
        WrapperTokenHarness wrapper6 =
            new WrapperTokenHarness(WRAPPER_NAME, WRAPPER_SYMBOL, address(pt6), owner, localRollOverBot);
        SwapTargetMock localSwapTarget = new SwapTargetMock();
        ERC20MockMintableDecimals wrongNewToken = new ERC20MockMintableDecimals("new18", "n18", 18);

        pt6.mint(address(wrapper6), 100e6);
        wrongNewToken.mint(address(localSwapTarget), 90e6);

        vm.startPrank(owner);
        wrapper6.setSwapTargetToApproveTarget(
            address(localSwapTarget), SwapTargetMetadata({approveTarget: address(localSwapTarget), isValid: true})
        );
        wrapper6.setPauser(pauser, PAUSE_TYPE, true);
        vm.stopPrank();

        vm.prank(pauser);
        wrapper6.pause(PAUSE_TYPE, true);

        bytes memory swapData =
            abi.encodeCall(SwapTargetMock.executeSwap, (address(pt6), address(wrongNewToken), 100e6, 90e6));

        vm.prank(localRollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper6.rollover(address(wrongNewToken), 100e6, 80e6, address(localSwapTarget), swapData);
    }

    function test_RevertWhen_SwapTargetIsZeroAddress() public {
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(0), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_SwapTargetIsNotWhitelisted() public {
        SwapTargetMock unlistedTarget = new SwapTargetMock();
        newUnderlyingToken.mint(address(unlistedTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(
            address(newUnderlyingToken),
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            address(unlistedTarget),
            _buildSwapData(
                address(unlistedTarget), address(underlyingPt), address(newUnderlyingToken), AMOUNT_IN, BUY_AMOUNT_OUT
            )
        );
    }

    function test_RevertWhen_WhitelistedApproveTargetIsZeroAddress() public {
        SwapTargetMock targetWithZeroApprove = new SwapTargetMock();
        newUnderlyingToken.mint(address(targetWithZeroApprove), BUY_AMOUNT_OUT);

        vm.prank(owner);
        wrapper.setSwapTargetToApproveTarget(
            address(targetWithZeroApprove), SwapTargetMetadata({approveTarget: address(0), isValid: true})
        );

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(
            address(newUnderlyingToken),
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            address(targetWithZeroApprove),
            _buildSwapData(
                address(targetWithZeroApprove),
                address(underlyingPt),
                address(newUnderlyingToken),
                AMOUNT_IN,
                BUY_AMOUNT_OUT
            )
        );
    }

    function test_RevertWhen_MinAmountOutIsZero() public {
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(address(newUnderlyingToken), AMOUNT_IN, 0, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT));
    }

    function test_RevertWhen_AmountInIsZero() public {
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.rollover(
            address(newUnderlyingToken), 0, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_ContractUnderlyingBalanceIsZero() public {
        WrapperTokenHarness emptyWrapper =
            new WrapperTokenHarness(WRAPPER_NAME, WRAPPER_SYMBOL, address(underlyingPt), owner, rollOverBot);
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(owner);
        emptyWrapper.setSwapTargetToApproveTarget(
            address(swapTarget), SwapTargetMetadata({approveTarget: address(swapTarget), isValid: true})
        );
        vm.prank(owner);
        emptyWrapper.setPauser(pauser, PAUSE_TYPE, true);
        vm.prank(pauser);
        emptyWrapper.pause(PAUSE_TYPE, true);

        vm.prank(rollOverBot);
        vm.expectRevert();
        emptyWrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_SwapCallFails() public {
        swapTarget.setShouldRevert(true);
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.SwapFailed.selector);
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_SwapLeavesSellTokenBalance() public {
        swapTarget.setLeaveSellLeftover(AMOUNT_IN - 1);
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(abi.encodeWithSelector(IWrapperTokenErrors.SellTokenBalanceLeftover.selector, 1));
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );
    }

    function test_RevertWhen_BuyTokenReceivedIsLessThanMinAmountOut() public {
        newUnderlyingToken.mint(address(swapTarget), MIN_AMOUNT_OUT - 1);

        vm.prank(rollOverBot);
        vm.expectRevert(
            abi.encodeWithSelector(IWrapperTokenErrors.MinAmountOutNotMet.selector, MIN_AMOUNT_OUT, MIN_AMOUNT_OUT - 1)
        );
        wrapper.rollover(
            address(newUnderlyingToken),
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            address(swapTarget),
            _rolloverData(MIN_AMOUNT_OUT - 1)
        );
    }

    function test_RevertWhen_UpdatedExchangeRateWouldBeZero() public {
        wrapper.setExchangeRateForTest(1);
        newUnderlyingToken.mint(address(swapTarget), 1);

        vm.prank(rollOverBot);
        vm.expectRevert(IWrapperTokenErrors.ExchangeRateZero.selector);
        wrapper.rollover(address(newUnderlyingToken), AMOUNT_IN, 1, address(swapTarget), _rolloverData(1));
    }

    function test_Rollover_WhenAllInputsAreValidAndSwapSucceeds() public {
        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        uint256 oldExchangeRate = wrapper.exchangeRate();
        uint256 expectedExchangeRate = oldExchangeRate * BUY_AMOUNT_OUT / AMOUNT_IN;

        assertEq(underlyingPt.allowance(address(wrapper), address(swapTarget)), 0);

        vm.prank(rollOverBot);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.UnderlyingTokenSet(address(underlyingPt), address(newUnderlyingToken));
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.ExchangeRateUpdated(expectedExchangeRate);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.Rollover(address(underlyingPt), address(newUnderlyingToken), AMOUNT_IN, BUY_AMOUNT_OUT);
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );

        assertEq(underlyingPt.balanceOf(address(wrapper)), 0);
        assertEq(newUnderlyingToken.balanceOf(address(wrapper)), BUY_AMOUNT_OUT);
        assertEq(underlyingPt.allowance(address(wrapper), address(swapTarget)), 0);
        assertEq(wrapper.exchangeRate(), expectedExchangeRate);
        assertEq(wrapper.underlyingToken(), address(newUnderlyingToken));
    }

    function test_Rollover_WhenAmountInMatchesSwapButDonatedUnderlyingRemainsAfterSwap() public {
        address donor = makeAddr("donor");

        underlyingPt.mint(donor, DONATED_UNDERLYING);
        vm.prank(donor);
        underlyingPt.transfer(address(wrapper), DONATED_UNDERLYING);

        assertEq(
            underlyingPt.balanceOf(address(wrapper)),
            AMOUNT_IN + DONATED_UNDERLYING,
            "wrapper should hold collateral underlying plus post-pause donation"
        );

        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        uint256 oldExchangeRate = wrapper.exchangeRate();
        uint256 expectedExchangeRate = oldExchangeRate * BUY_AMOUNT_OUT / AMOUNT_IN;

        assertEq(underlyingPt.allowance(address(wrapper), address(swapTarget)), 0);

        vm.prank(rollOverBot);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.UnderlyingTokenSet(address(underlyingPt), address(newUnderlyingToken));
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.ExchangeRateUpdated(expectedExchangeRate);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.Rollover(address(underlyingPt), address(newUnderlyingToken), AMOUNT_IN, BUY_AMOUNT_OUT);
        wrapper.rollover(
            address(newUnderlyingToken), AMOUNT_IN, MIN_AMOUNT_OUT, address(swapTarget), _rolloverData(BUY_AMOUNT_OUT)
        );

        assertEq(newUnderlyingToken.balanceOf(address(wrapper)), BUY_AMOUNT_OUT);
        assertEq(
            underlyingPt.balanceOf(address(wrapper)),
            DONATED_UNDERLYING,
            "donated underlying should remain as remnant sell-token balance"
        );
        assertEq(underlyingPt.allowance(address(wrapper), address(swapTarget)), 0);
        assertEq(wrapper.exchangeRate(), expectedExchangeRate);
        assertEq(wrapper.underlyingToken(), address(newUnderlyingToken));
    }

    function test_RevertWhen_AmountInIncludesDonatedUnderlyingButSwapDataDoesNot() public {
        address donor = makeAddr("donor");

        underlyingPt.mint(donor, DONATED_UNDERLYING);
        vm.prank(donor);
        underlyingPt.transfer(address(wrapper), DONATED_UNDERLYING);

        newUnderlyingToken.mint(address(swapTarget), BUY_AMOUNT_OUT);

        vm.prank(rollOverBot);
        vm.expectRevert(
            abi.encodeWithSelector(IWrapperTokenErrors.SellTokenBalanceLeftover.selector, DONATED_UNDERLYING)
        );
        wrapper.rollover(
            address(newUnderlyingToken),
            AMOUNT_IN + DONATED_UNDERLYING,
            MIN_AMOUNT_OUT,
            address(swapTarget),
            _rolloverData(BUY_AMOUNT_OUT)
        );

        assertEq(wrapper.underlyingToken(), address(underlyingPt));
        assertEq(underlyingPt.balanceOf(address(wrapper)), AMOUNT_IN + DONATED_UNDERLYING);
        assertEq(newUnderlyingToken.balanceOf(address(wrapper)), 0);
    }
}

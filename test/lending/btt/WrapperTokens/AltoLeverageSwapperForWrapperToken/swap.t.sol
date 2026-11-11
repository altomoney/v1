// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoLeverageSwapperForWrapperTokenCommon} from "./AltoLeverageSwapperForWrapperTokenCommon.t.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperMultiTargetErrors,
    IAltoLeverageSwapperMultiTargetEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwapTargetMock} from "../WrapperToken/mocks/SwapTargetMock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

contract SwapTest is AltoLeverageSwapperForWrapperTokenCommon {
    function _sellCollateralSwapParams(uint256 minAmountOut, uint256 buyAmountOut)
        internal
        view
        returns (bytes memory)
    {
        return _encodeSwapParams(
            minAmountOut,
            address(underlyingPt),
            address(swapTarget),
            _buildSwapData(address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, buyAmountOut)
        );
    }

    function _buyCollateralSwapParams(uint256 minAmountOut, uint256 ptBuyAmountOut)
        internal
        view
        returns (bytes memory)
    {
        return _encodeSwapParams(
            minAmountOut,
            address(underlyingPt),
            address(swapTarget),
            _buildSwapData(address(otherToken), address(underlyingPt), OTHER_TOKEN_AMOUNT_IN, ptBuyAmountOut)
        );
    }

    function test_RevertWhen_CallerIsNotWhitelisted() public {
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);

        vm.prank(nonWhitelisted);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperErrors.AltoLeverageSwapperSenderNotValid.selector, nonWhitelisted
            )
        );
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_RevertWhen_NeitherSellNorBuyTokenIsMarketCollateral() public {
        bytes memory swapParams = _encodeSwapParams(
            MIN_AMOUNT_OUT,
            address(underlyingPt),
            address(swapTarget),
            _buildSwapData(address(otherToken), address(unrelatedToken), OTHER_TOKEN_AMOUNT_IN, BUY_AMOUNT_OUT)
        );

        vm.prank(caller);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.swap(address(otherToken), address(unrelatedToken), OTHER_TOKEN_AMOUNT_IN, swapParams);
    }

    function test_RevertWhen_SwapTargetIsNotValid() public {
        SwapTargetMock invalidTarget = new SwapTargetMock();
        bytes memory swapParams = _encodeSwapParams(
            MIN_AMOUNT_OUT,
            address(underlyingPt),
            address(invalidTarget),
            _buildSwapData(address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, BUY_AMOUNT_OUT)
        );

        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperMultiTargetErrors.AltoLeverageSwapperInvalidSwapTarget.selector,
                address(invalidTarget)
            )
        );
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_RevertWhen_UnderlyingTokenDoesNotMatch() public {
        ERC20MockMintableDecimals wrongPt = new ERC20MockMintableDecimals("wrongPT", "wPT", TOKEN_DECIMALS);
        bytes memory swapParams = _encodeSwapParams(
            MIN_AMOUNT_OUT,
            address(wrongPt),
            address(swapTarget),
            _buildSwapData(address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, BUY_AMOUNT_OUT)
        );

        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        vm.prank(caller);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_RevertWhen_SellTokenTransferFromFails() public {
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        vm.prank(caller);
        collateralWrapper.approve(address(swapper), 0);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(swapper), 0, WRAPPED_COLLATERAL_IN
            )
        );
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_RevertWhen_UnwrapReverts() public {
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        vm.prank(owner);
        collateralWrapper.setPausedForTest(true);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_RevertWhen_SwapCallFails_WhenSellTokenIsCollateral() public {
        swapTarget.setShouldRevert(true);
        otherToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        vm.prank(caller);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperSwapFailed.selector);
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_RevertWhen_BuyTokenReceivedIsLessThanMinAmountOut_WhenSellTokenIsCollateral() public {
        otherToken.mint(address(swapTarget), MIN_AMOUNT_OUT - 1);
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, MIN_AMOUNT_OUT - 1);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperErrors.AltoLeverageSwapperMinAmountOutNotMet.selector,
                MIN_AMOUNT_OUT,
                MIN_AMOUNT_OUT - 1
            )
        );
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);
    }

    function test_Swap_WhenSellTokenIsCollateralAndSwapSucceeds() public {
        otherToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        uint256 callerOtherTokenBefore = otherToken.balanceOf(caller);
        uint256 callerWrappedBefore = collateralWrapper.balanceOf(caller);

        assertEq(underlyingPt.allowance(address(swapper), address(swapTarget)), 0);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, BUY_AMOUNT_OUT, 0
        );
        uint256 amountOut = swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);

        assertEq(amountOut, BUY_AMOUNT_OUT);
        assertEq(collateralWrapper.balanceOf(caller), callerWrappedBefore - WRAPPED_COLLATERAL_IN);
        assertEq(otherToken.balanceOf(caller), callerOtherTokenBefore + BUY_AMOUNT_OUT);
        assertEq(underlyingPt.allowance(address(swapper), address(swapTarget)), 0);
        _assertZeroResidualBalances();
    }

    function test_Swap_WhenSellTokenIsCollateralAndSwapLeavesSellTokenBalance() public {
        uint256 leftover = 1 ether;
        swapTarget.setLeaveSellLeftover(PT_COLLATERAL_IN - leftover);
        otherToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        uint256 callerPtBefore = underlyingPt.balanceOf(caller);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, BUY_AMOUNT_OUT, leftover
        );
        swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);

        assertEq(underlyingPt.balanceOf(caller), callerPtBefore + leftover);
        _assertZeroResidualBalances();
    }

    function test_RevertWhen_SwapCallFails_WhenBuyTokenIsCollateral() public {
        swapTarget.setShouldRevert(true);
        underlyingPt.mint(address(swapTarget), PT_COLLATERAL_IN);
        bytes memory swapParams = _buyCollateralSwapParams(MIN_AMOUNT_OUT, PT_COLLATERAL_IN);
        _fundCallerWithOtherToken(OTHER_TOKEN_AMOUNT_IN);

        vm.prank(caller);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperSwapFailed.selector);
        swapper.swap(address(otherToken), _collateralToken(), OTHER_TOKEN_AMOUNT_IN, swapParams);
    }

    function test_RevertWhen_BuyTokenReceivedIsLessThanMinAmountOut_WhenBuyTokenIsCollateral() public {
        underlyingPt.mint(address(swapTarget), MIN_AMOUNT_OUT - 1);
        bytes memory swapParams = _buyCollateralSwapParams(MIN_AMOUNT_OUT, MIN_AMOUNT_OUT - 1);
        _fundCallerWithOtherToken(OTHER_TOKEN_AMOUNT_IN);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperErrors.AltoLeverageSwapperMinAmountOutNotMet.selector,
                MIN_AMOUNT_OUT,
                MIN_AMOUNT_OUT - 1
            )
        );
        swapper.swap(address(otherToken), _collateralToken(), OTHER_TOKEN_AMOUNT_IN, swapParams);
    }

    function test_Swap_WhenBuyTokenIsCollateralAndSwapSucceeds() public {
        underlyingPt.mint(address(swapTarget), PT_COLLATERAL_IN);
        bytes memory swapParams = _buyCollateralSwapParams(MIN_AMOUNT_OUT, PT_COLLATERAL_IN);
        _fundCallerWithOtherToken(OTHER_TOKEN_AMOUNT_IN);

        uint256 callerCollateralBefore = collateralWrapper.balanceOf(caller);
        uint256 callerOtherTokenBefore = otherToken.balanceOf(caller);
        uint256 expectedWrappedOut = collateralWrapper.previewWrap(PT_COLLATERAL_IN);

        assertEq(expectedWrappedOut, WRAPPED_COLLATERAL_IN);
        assertEq(underlyingPt.allowance(address(swapper), _collateralToken()), 0);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(otherToken), address(underlyingPt), OTHER_TOKEN_AMOUNT_IN, PT_COLLATERAL_IN, 0
        );
        uint256 amountOut = swapper.swap(address(otherToken), _collateralToken(), OTHER_TOKEN_AMOUNT_IN, swapParams);

        assertEq(amountOut, expectedWrappedOut);
        assertEq(otherToken.balanceOf(caller), callerOtherTokenBefore - OTHER_TOKEN_AMOUNT_IN);
        assertEq(collateralWrapper.balanceOf(caller), callerCollateralBefore + expectedWrappedOut);
        assertEq(underlyingPt.allowance(address(swapper), _collateralToken()), 0);
        _assertZeroResidualBalances();
    }

    function test_Swap_WhenBuyTokenIsCollateralAndSwapLeavesSellTokenBalance() public {
        uint256 leftover = 1 ether;
        swapTarget.setLeaveSellLeftover(OTHER_TOKEN_AMOUNT_IN - leftover);
        underlyingPt.mint(address(swapTarget), PT_COLLATERAL_IN);
        bytes memory swapParams = _buyCollateralSwapParams(MIN_AMOUNT_OUT, PT_COLLATERAL_IN);
        _fundCallerWithOtherToken(OTHER_TOKEN_AMOUNT_IN);

        uint256 callerOtherTokenBefore = otherToken.balanceOf(caller);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget),
            address(otherToken),
            address(underlyingPt),
            OTHER_TOKEN_AMOUNT_IN,
            PT_COLLATERAL_IN,
            leftover
        );
        swapper.swap(address(otherToken), _collateralToken(), OTHER_TOKEN_AMOUNT_IN, swapParams);

        assertEq(otherToken.balanceOf(caller), callerOtherTokenBefore - OTHER_TOKEN_AMOUNT_IN + leftover);
        _assertZeroResidualBalances();
    }

    function test_Swap_WhenSellTokenIsCollateralAndCollateralWasDonatedBeforeSwap() public {
        uint256 donatedWrapped = _donateCollateralToSwapper(DONATED_UNDERLYING);

        otherToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        uint256 callerOtherTokenBefore = otherToken.balanceOf(caller);
        uint256 callerWrappedBefore = collateralWrapper.balanceOf(caller);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, BUY_AMOUNT_OUT, 0
        );
        uint256 amountOut = swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);

        assertEq(amountOut, BUY_AMOUNT_OUT);
        assertEq(collateralWrapper.balanceOf(caller), callerWrappedBefore - WRAPPED_COLLATERAL_IN);
        assertEq(otherToken.balanceOf(caller), callerOtherTokenBefore + BUY_AMOUNT_OUT);
        assertEq(underlyingPt.allowance(address(swapper), address(swapTarget)), 0);
        assertEq(collateralWrapper.balanceOf(address(swapper)), donatedWrapped, "donated collateral should remain");
        assertEq(underlyingPt.balanceOf(address(swapper)), 0);
        assertEq(otherToken.balanceOf(address(swapper)), 0);
    }

    function test_Swap_WhenSellTokenIsCollateralAndUnderlyingWasDonatedBeforeSwap() public {
        _donateUnderlyingToSwapper(DONATED_UNDERLYING);

        otherToken.mint(address(swapTarget), BUY_AMOUNT_OUT);
        bytes memory swapParams = _sellCollateralSwapParams(MIN_AMOUNT_OUT, BUY_AMOUNT_OUT);
        _fundCallerWithCollateral(WRAPPED_COLLATERAL_IN);

        uint256 callerOtherTokenBefore = otherToken.balanceOf(caller);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(underlyingPt), address(otherToken), PT_COLLATERAL_IN, BUY_AMOUNT_OUT, 0
        );
        uint256 amountOut = swapper.swap(_collateralToken(), address(otherToken), WRAPPED_COLLATERAL_IN, swapParams);

        assertEq(amountOut, BUY_AMOUNT_OUT);
        assertEq(otherToken.balanceOf(caller), callerOtherTokenBefore + BUY_AMOUNT_OUT);
        assertEq(underlyingPt.allowance(address(swapper), address(swapTarget)), 0);
        assertEq(underlyingPt.balanceOf(address(swapper)), DONATED_UNDERLYING, "donated underlying should remain");
        assertEq(collateralWrapper.balanceOf(address(swapper)), 0);
        assertEq(otherToken.balanceOf(address(swapper)), 0);
    }

    function test_Swap_WhenBuyTokenIsCollateralAndCollateralWasDonatedBeforeSwap() public {
        uint256 donatedWrapped = _donateCollateralToSwapper(DONATED_UNDERLYING);

        underlyingPt.mint(address(swapTarget), PT_COLLATERAL_IN);
        bytes memory swapParams = _buyCollateralSwapParams(MIN_AMOUNT_OUT, PT_COLLATERAL_IN);
        _fundCallerWithOtherToken(OTHER_TOKEN_AMOUNT_IN);

        uint256 callerCollateralBefore = collateralWrapper.balanceOf(caller);
        uint256 expectedWrappedOut = collateralWrapper.previewWrap(PT_COLLATERAL_IN);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(otherToken), address(underlyingPt), OTHER_TOKEN_AMOUNT_IN, PT_COLLATERAL_IN, 0
        );
        uint256 amountOut = swapper.swap(address(otherToken), _collateralToken(), OTHER_TOKEN_AMOUNT_IN, swapParams);

        assertEq(amountOut, expectedWrappedOut);
        assertEq(collateralWrapper.balanceOf(caller), callerCollateralBefore + expectedWrappedOut);
        assertEq(underlyingPt.allowance(address(swapper), _collateralToken()), 0);
        assertEq(collateralWrapper.balanceOf(address(swapper)), donatedWrapped, "donated collateral should remain");
        assertEq(underlyingPt.balanceOf(address(swapper)), 0);
        assertEq(otherToken.balanceOf(address(swapper)), 0);
    }

    function test_Swap_WhenBuyTokenIsCollateralAndUnderlyingWasDonatedBeforeSwap() public {
        _donateUnderlyingToSwapper(DONATED_UNDERLYING);

        underlyingPt.mint(address(swapTarget), PT_COLLATERAL_IN);
        bytes memory swapParams = _buyCollateralSwapParams(MIN_AMOUNT_OUT, PT_COLLATERAL_IN);
        _fundCallerWithOtherToken(OTHER_TOKEN_AMOUNT_IN);

        uint256 callerCollateralBefore = collateralWrapper.balanceOf(caller);
        uint256 expectedWrappedOut = collateralWrapper.previewWrap(PT_COLLATERAL_IN);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperMultiTargetEvents.Swap(
            address(swapTarget), address(otherToken), address(underlyingPt), OTHER_TOKEN_AMOUNT_IN, PT_COLLATERAL_IN, 0
        );
        uint256 amountOut = swapper.swap(address(otherToken), _collateralToken(), OTHER_TOKEN_AMOUNT_IN, swapParams);

        assertEq(amountOut, expectedWrappedOut);
        assertEq(collateralWrapper.balanceOf(caller), callerCollateralBefore + expectedWrappedOut);
        assertEq(underlyingPt.allowance(address(swapper), _collateralToken()), 0);
        assertEq(underlyingPt.balanceOf(address(swapper)), DONATED_UNDERLYING, "donated underlying should remain");
        assertEq(collateralWrapper.balanceOf(address(swapper)), 0);
        assertEq(otherToken.balanceOf(address(swapper)), 0);
    }
}

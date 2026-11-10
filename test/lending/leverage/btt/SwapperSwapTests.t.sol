// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {stdError} from "forge-std/StdError.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAltoLeverageSwapperErrors} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";
import {SwapperCommon} from "./SwapperCommon.t.sol";

abstract contract SwapperSwapTests is SwapperCommon {
    function test_RevertWhen_CallerIsNotWhitelisted_IncludingOwner_BeforeDecoding() public {
        address[2] memory callers = [CALLER, OWNER];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAltoLeverageSwapperErrors.AltoLeverageSwapperSenderNotValid.selector, callers[i]
                )
            );
            swapper.swap(address(sellToken), address(buyToken), 100 ether, hex"ff");
            _assertBalancesUnchanged();
        }
    }

    function test_RevertWhen_EncodedParametersAreMalformed() public {
        _allowCaller();
        vm.prank(CALLER);
        vm.expectRevert(bytes(""));
        swapper.swap(address(sellToken), address(buyToken), 100 ether, hex"ff");
        _assertBalancesUnchanged();
    }

    function test_RevertWhen_CallerAllowanceIsInsufficient() public {
        _allowCaller();
        vm.prank(CALLER);
        sellToken.approve(address(swapper), 0);
        bytes memory params = _params(100 ether, 200 ether, 200 ether);
        vm.prank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(swapper), 0, 100 ether)
        );
        swapper.swap(address(sellToken), address(buyToken), 100 ether, params);
        _assertBalancesUnchanged();
    }

    function test_RevertWhen_CallerBalanceIsInsufficient() public {
        _allowCaller();
        bytes memory params = _params(CALLER_SELL + 1, 1, 0);
        vm.prank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, CALLER, CALLER_SELL, CALLER_SELL + 1)
        );
        swapper.swap(address(sellToken), address(buyToken), CALLER_SELL + 1, params);
        _assertBalancesUnchanged();
    }

    function test_RevertWhen_PullingTokensReturnsFalse() public {
        _allowCaller();
        vm.mockCall(
            address(sellToken),
            abi.encodeCall(IERC20.transferFrom, (CALLER, address(swapper), 100 ether)),
            abi.encode(false)
        );
        _expectSwapFailure(
            _params(100 ether, 200 ether, 200 ether),
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(sellToken))
        );
    }

    function test_RevertWhen_TargetCallFails_WrapsItsErrorAndRollsBackTransfers() public {
        _allowCaller();
        // Spending above amountIn fails inside the target after the caller's tokens were pulled.
        _expectSwapFailure(
            _params(101 ether, 200 ether, 200 ether),
            abi.encodeWithSelector(IAltoLeverageSwapperErrors.AltoLeverageSwapperSwapFailed.selector)
        );
    }

    function test_RevertWhen_OutputIsOneWeiBelowMinimum_RollsBackSwapAndApprovals() public {
        _allowCaller();
        _expectSwapFailure(
            _params(60 ether, 200 ether, 200 ether + 1),
            abi.encodeWithSelector(
                IAltoLeverageSwapperErrors.AltoLeverageSwapperMinAmountOutNotMet.selector, 200 ether + 1, 200 ether
            )
        );
    }

    function test_RevertWhen_ClearingTargetApprovalFails_RollsBackSwap() public {
        _allowCaller();
        vm.mockCall(address(sellToken), abi.encodeCall(IERC20.approve, (address(target), 0)), abi.encode(false));
        _expectSwapFailure(
            _params(60 ether, 200 ether, 200 ether),
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(sellToken))
        );
    }

    function test_RevertWhen_RefundOrOutputTransferReturnsFalse_RollsBackSwap() public {
        _allowCaller();
        vm.mockCall(address(sellToken), abi.encodeCall(IERC20.transfer, (CALLER, 40 ether)), abi.encode(false));
        _expectSwapFailure(
            _params(60 ether, 200 ether, 200 ether),
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(sellToken))
        );
        vm.clearMockedCalls();
        vm.mockCall(address(buyToken), abi.encodeCall(IERC20.transfer, (CALLER, 200 ether)), abi.encode(false));
        _expectSwapFailure(
            _params(60 ether, 200 ether, 200 ether),
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(buyToken))
        );
    }

    function test_WhenAllInputIsSpentAndMinimumIsMet_TransfersOutputAndClearsApproval() public {
        _allowCaller();
        _assertSuccessfulSwap(100 ether, 100 ether, 200 ether, 200 ether, 0);
    }

    function test_WhenInputIsPartiallySpent_RefundsOnlyThisSwapLeftover() public {
        _allowCaller();
        _assertSuccessfulSwap(100 ether, 60 ether, 200 ether, 150 ether, 0);
    }

    function test_WhenOutputAndMinimumAreZero_RefundsAllUnspentInput() public {
        _allowCaller();
        _assertSuccessfulSwap(100 ether, 0, 0, 0, 0);
    }

    function test_WhenInputAmountIsZero_AcceptsTheSwap() public {
        _allowCaller();
        _assertSuccessfulSwap(0, 0, 0, 0, 0);
    }

    function test_WhenTargetReportsAnUnbackedOutput_UsesBalanceDeltaInstead() public {
        _allowCaller();
        vm.mockCall(address(target), _swapData(0, 0), abi.encode(type(uint256).max));
        _assertSuccessfulSwap(100 ether, 0, 0, 0, 0);
    }

    function test_WhenNativeValueIsAttached_RetainsItWithoutForwardingToTarget() public {
        _allowCaller();
        _assertSuccessfulSwap(100 ether, 100 ether, 200 ether, 200 ether, 1 ether);
    }

    function test_WhenTargetHasNoCodeAndMinimumIsZero_RefundsInput() public {
        target = MockSwapper(OTHER);
        swapper = _deploySwapper(OTHER);
        _fundAndApprove();
        _allowCaller();
        _assertSuccessfulSwap(100 ether, 0, 0, 0, 0);
    }

    function test_RevertWhen_SameTokenSwapReducesBalance() public {
        _allowCaller();
        bytes memory data =
            abi.encodeCall(MockSwapper.swap, (abi.encode(address(sellToken), 100 ether, address(sellToken), 0)));
        bytes memory params = _encodeParams(address(target), 0, data);
        vm.prank(CALLER);
        vm.expectRevert(stdError.arithmeticError);
        swapper.swap(address(sellToken), address(sellToken), 100 ether, params);
        _assertBalancesUnchanged();
    }

    function _expectSwapFailure(bytes memory params, bytes memory expectedError) internal {
        vm.prank(CALLER);
        vm.expectRevert(expectedError);
        swapper.swap(address(sellToken), address(buyToken), 100 ether, params);
        _assertBalancesUnchanged();
    }
}

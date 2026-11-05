// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {
    IAltoLeverageSwapper,
    SwapParams,
    SwapParamsMultiTarget
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";

abstract contract SwapperCommon is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant CALLER = address(0xB0B);
    address internal constant OTHER = address(0xCAFE);
    uint256 internal constant CALLER_SELL = 1000 ether;
    uint256 internal constant CALLER_BUY = 13 ether;
    uint256 internal constant SELL_DUST = 7 ether;
    uint256 internal constant BUY_DUST = 11 ether;
    uint256 internal constant TARGET_BUY = 10_000 ether;

    IAltoLeverageSwapper internal swapper;
    MockSwapper internal target;
    ERC20Mock internal sellToken;
    ERC20Mock internal buyToken;

    function setUp() public virtual {
        sellToken = new ERC20Mock("Sell", "SELL");
        buyToken = new ERC20Mock("Buy", "BUY");
        target = new MockSwapper();
        swapper = _deploySwapper(address(target));
        _fundAndApprove();
    }

    function _deploySwapper(address swapTarget) internal virtual returns (IAltoLeverageSwapper);
    function _encodeParams(address swapTarget, uint256 minAmountOut, bytes memory data)
        internal
        pure
        virtual
        returns (bytes memory);
    function _assertSwapLog(Vm.Log memory entry, uint256 amountIn, uint256 amountOut, uint256 leftover)
        internal
        view
        virtual;

    function _fundAndApprove() internal {
        deal(address(sellToken), CALLER, CALLER_SELL);
        deal(address(buyToken), CALLER, CALLER_BUY);
        deal(address(sellToken), address(swapper), SELL_DUST);
        deal(address(buyToken), address(swapper), BUY_DUST);
        deal(address(buyToken), address(target), TARGET_BUY);
        vm.deal(CALLER, 2 ether);
        vm.prank(CALLER);
        sellToken.approve(address(swapper), type(uint256).max);
    }

    function _allowCaller() internal {
        vm.prank(OWNER);
        swapper.setWhitelisted(CALLER, true);
    }

    function _swapData(uint256 spent, uint256 amountOut) internal view returns (bytes memory) {
        return abi.encodeCall(MockSwapper.swap, (abi.encode(address(sellToken), spent, address(buyToken), amountOut)));
    }

    function _params(uint256 spent, uint256 amountOut, uint256 minimum) internal view returns (bytes memory) {
        return _encodeParams(address(target), minimum, _swapData(spent, amountOut));
    }

    function _assertSuccessfulSwap(uint256 amountIn, uint256 spent, uint256 amountOut, uint256 minimum, uint256 value)
        internal
    {
        bytes memory params = _params(spent, amountOut, minimum);
        vm.recordLogs();
        vm.prank(CALLER);
        uint256 received = swapper.swap{value: value}(address(sellToken), address(buyToken), amountIn, params);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(received, amountOut, "returned balance delta");
        assertEq(sellToken.balanceOf(CALLER), CALLER_SELL - spent);
        assertEq(buyToken.balanceOf(CALLER), CALLER_BUY + amountOut);
        assertEq(sellToken.balanceOf(address(swapper)), SELL_DUST, "sell dust preserved");
        assertEq(buyToken.balanceOf(address(swapper)), BUY_DUST, "buy dust preserved");
        assertEq(sellToken.balanceOf(address(target)), spent);
        assertEq(buyToken.balanceOf(address(target)), TARGET_BUY - amountOut);
        assertEq(sellToken.allowance(address(swapper), address(target)), 0, "target allowance cleared");
        assertEq(address(swapper).balance, value, "native value retained");
        assertEq(address(target).balance, 0, "native value not forwarded");
        assertEq(CALLER.balance, 2 ether - value);
        _assertSwapLog(logs[logs.length - 1], amountIn, amountOut, amountIn - spent);
    }

    function _assertBalancesUnchanged() internal view {
        assertEq(sellToken.balanceOf(CALLER), CALLER_SELL);
        assertEq(buyToken.balanceOf(CALLER), CALLER_BUY);
        assertEq(sellToken.balanceOf(address(swapper)), SELL_DUST);
        assertEq(buyToken.balanceOf(address(swapper)), BUY_DUST);
        assertEq(sellToken.balanceOf(address(target)), 0);
        assertEq(buyToken.balanceOf(address(target)), TARGET_BUY);
        assertEq(sellToken.allowance(address(swapper), address(target)), 0);
    }
}

abstract contract AltoLeverageSwapperCommon is SwapperCommon {
    function _deploySwapper(address swapTarget) internal override returns (IAltoLeverageSwapper) {
        return new AltoLeverageSwapper(OWNER, swapTarget);
    }

    function _encodeParams(address, uint256 minAmountOut, bytes memory data)
        internal
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(SwapParams(minAmountOut, data));
    }

    function _assertSwapLog(Vm.Log memory entry, uint256 amountIn, uint256 amountOut, uint256 leftover)
        internal
        view
        override
    {
        assertEq(entry.emitter, address(swapper));
        assertEq(entry.topics.length, 3);
        assertEq(entry.topics[0], keccak256("Swap(address,address,uint256,uint256,uint256)"));
        assertEq(entry.topics[1], bytes32(uint256(uint160(address(sellToken)))));
        assertEq(entry.topics[2], bytes32(uint256(uint160(address(buyToken)))));
        assertEq(entry.data, abi.encode(amountIn, amountOut, leftover));
    }
}

abstract contract AltoLeverageSwapperMultiTargetCommon is SwapperCommon {
    function _deploySwapper(address swapTarget) internal override returns (IAltoLeverageSwapper) {
        address[] memory targets = new address[](1);
        targets[0] = swapTarget;
        return new AltoLeverageSwapperMultiTarget(OWNER, targets);
    }

    function _encodeParams(address swapTarget, uint256 minAmountOut, bytes memory data)
        internal
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(SwapParamsMultiTarget(minAmountOut, swapTarget, data));
    }

    function _assertSwapLog(Vm.Log memory entry, uint256 amountIn, uint256 amountOut, uint256 leftover)
        internal
        view
        override
    {
        assertEq(entry.emitter, address(swapper));
        assertEq(entry.topics.length, 4);
        assertEq(entry.topics[0], keccak256("Swap(address,address,address,uint256,uint256,uint256)"));
        assertEq(entry.topics[1], bytes32(uint256(uint160(address(target)))));
        assertEq(entry.topics[2], bytes32(uint256(uint160(address(sellToken)))));
        assertEq(entry.topics[3], bytes32(uint256(uint160(address(buyToken)))));
        assertEq(entry.data, abi.encode(amountIn, amountOut, leftover));
    }
}

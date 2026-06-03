// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {WrapperTokenHarness} from "./mocks/WrapperTokenHarness.sol";
import {IWrapperTokenErrors, IWrapperTokenEvents} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

contract ConstructorTest is WrapperTokenCommon {
    function test_RevertWhen_RollOverBotIsZeroAddress() public {
        vm.expectRevert(IWrapperTokenErrors.ZeroAddress.selector);
        new WrapperTokenHarness(WRAPPER_NAME, WRAPPER_SYMBOL, address(underlyingPt), owner, address(0));
    }

    function test_RevertWhen_UnderlyingTokenIsZeroAddress() public {
        vm.expectRevert(IWrapperTokenErrors.ZeroAddress.selector);
        new WrapperTokenHarness(WRAPPER_NAME, WRAPPER_SYMBOL, address(0), owner, rollOverBot);
    }

    function test_Constructor_WhenAllConstructorArgsAreValid() public {
        ERC20MockMintableDecimals ptToken = new ERC20MockMintableDecimals("PT-6", "PT6", 6);
        address localRollOverBot = makeAddr("localRollOverBot");
        uint256 expectedExchangeRate = 10 ** 6;

        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.RollOverBotSet(address(0), localRollOverBot);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.UnderlyingTokenSet(address(0), address(ptToken));
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.ExchangeRateUpdated(expectedExchangeRate);

        WrapperTokenHarness localWrapper =
            new WrapperTokenHarness(WRAPPER_NAME, WRAPPER_SYMBOL, address(ptToken), owner, localRollOverBot);

        assertEq(localWrapper.underlyingToken(), address(ptToken));
        assertEq(localWrapper.rollOverBot(), localRollOverBot);
        assertEq(localWrapper.DECIMALS(), 6);
        assertEq(localWrapper.exchangeRate(), expectedExchangeRate);
        assertEq(localWrapper.name(), WRAPPER_NAME);
        assertEq(localWrapper.symbol(), WRAPPER_SYMBOL);
        assertEq(localWrapper.owner(), owner);
        assertEq(localWrapper.decimals(), 6);
    }
}

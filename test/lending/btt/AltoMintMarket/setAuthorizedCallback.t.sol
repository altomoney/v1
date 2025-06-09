// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract SetAuthorizedCallbackTest is AltoMintMarketTest {
    address internal mockCallback = makeAddr("mockCallback");

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setAuthorizedCallback(mockCallback, true);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_SetAuthorizedCallbackWhen_CallbackIsZeroAddress() public givenCallerIsOwner {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setAuthorizedCallback(address(0), true);
        vm.stopPrank();
    }

    function test_UpdateAuthorizedCallbackStatusWhen_CallbackIsValidAddress() external givenCallerIsOwner {
        // Check initial state
        bool initialStatus = market.authorizedCallbacks(mockCallback);
        assertFalse(initialStatus);

        vm.startPrank(owner);

        // it should update authorized callback status
        market.setAuthorizedCallback(mockCallback, true);
        bool authorizedStatus = market.authorizedCallbacks(mockCallback);
        assertTrue(authorizedStatus);

        // Set to unauthorized
        market.setAuthorizedCallback(mockCallback, false);
        bool unauthorizedStatus = market.authorizedCallbacks(mockCallback);
        assertFalse(unauthorizedStatus);

        vm.stopPrank();
    }
}

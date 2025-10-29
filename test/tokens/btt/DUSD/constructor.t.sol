// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DUSDConstructor is DUSDCommon {
    function test_RevertWhen_EndpointIsZeroAddress() external {
        vm.expectRevert(); // OFT will revert with its own error for zero endpoint
        new DUSD(address(0), OWNER);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new DUSD(address(endpoints[1]), address(0));
    }

    function test_WhenValidParametersAreProvided() external {
        DUSD newDusd = new DUSD(address(endpoints[1]), OWNER);

        // it should set the name to "DUSD"
        assertEq(newDusd.name(), "DUSD");

        // it should set the symbol to "DUSD"
        assertEq(newDusd.symbol(), "DUSD");

        // it should set the endpoint correctly
        assertEq(address(newDusd.endpoint()), address(endpoints[1]));

        // it should set the owner correctly
        assertEq(newDusd.owner(), OWNER);

        // it should initialize flashFeeReceiver to zero address
        assertEq(newDusd.flashFeeReceiver(), address(0));

        // it should initialize flashFee to zero
        (uint128 minFlashFee, uint128 maxFlashFee) = newDusd.flashFee();
        assertEq(minFlashFee, 0);
        assertEq(maxFlashFee, 0);

        // it should set owner as pauser with PAUSED_ROLE
        assertTrue(newDusd.pausers(OWNER, PAUSE_TYPE));
    }
}

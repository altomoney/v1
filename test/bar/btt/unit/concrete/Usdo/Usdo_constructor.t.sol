// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// tests
import {Usdo_Unit_Shared} from "../../shared/Usdo_Unit_Shared.t.sol";

contract Usdo_constructor is Usdo_Unit_Shared {
    function test_WhenUsdoIsCreatedWithTheRightParameters() external {
        // it should set the delegate parameter as the owner
        assertEq(usdo.owner(), address(this));

        // it should set the name to 'USDO Stablecoin'
        assertEq(usdo.name(), "USDO Stablecoin");

        // it should set the symbol to 'USDO'
        assertEq(usdo.symbol(), "USDO");

        assertEq(usdo.owner(), address(this));
    }
}

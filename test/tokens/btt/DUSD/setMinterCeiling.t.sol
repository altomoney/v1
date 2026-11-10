// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DUSDSetMinterCeiling is DUSDCommon {
    modifier whenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotOwner() external whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setMinterCeiling(MINTER, 1000e18);
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 newCeiling = 2000e18;

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetMinterCeiling(MINTER, newCeiling);

        dusd.setMinterCeiling(MINTER, newCeiling);

        // it should update minterConfig.ceiling to new value
        (, uint256 ceiling) = dusd.minterConfig(MINTER);
        assertEq(ceiling, newCeiling);
    }
}

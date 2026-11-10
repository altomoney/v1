// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

contract MulticallTest is IntegrationTest {
    bytes[] internal data;

    function testMulticall() public {
        data.push(abi.encodeCall(AltoVault.setCurator, (address(1))));
        data.push(abi.encodeCall(AltoVault.setIsAllocator, (address(1), true)));
        data.push(abi.encodeCall(AltoVault.submitTimelock, (ConstantsLib.MAX_TIMELOCK)));

        vm.prank(OWNER);
        Multicall(address(vault)).multicall(data);

        assertEq(vault.curator(), address(1));
        assertTrue(vault.isAllocator(address(1)));
        assertEq(vault.timelock(), ConstantsLib.MAX_TIMELOCK);
    }
}

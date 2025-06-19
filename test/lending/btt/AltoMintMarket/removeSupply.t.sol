// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract RemoveSupplyTest is AltoMintMarketTest {
    function test_RevertWhen_CalledWithAnyParameters() external {
        // it should revert with AltoMintMarketNotImplemented
        vm.expectRevert(AltoMintMarket.AltoMintMarketNotImplemented.selector);
        market.removeSupply(100 ether, 0, alice, alice);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract TestUsmUpgrade is TestDusdBase {
    function testUpgrade() public {
        assertEq(DUSD_USM.USM_REVISION(), 1, "Unexpected pre-upgrade USM revision");
        bytes32[] memory beforeSnapshot = _getStorageSnapshot();
        // Sanity check on select storage variable
        assertEq(uint256(beforeSnapshot[1]), uint160(TREASURY), "DUSD Treasury address not set");
        // Perform the mock upgrade
        address usmV2 = address(new MockUsmV2(address(DUSD_TOKEN), address(USDC_TOKEN)));
        bytes memory data = abi.encodeWithSelector(MockUsmV2.initialize.selector, "");
        UUPSUpgradeable(payable(address(DUSD_USM))).upgradeToAndCall(usmV2, data);
        assertEq(DUSD_USM.USM_REVISION(), 2, "Unexpected post-upgrade USM revision");
        bytes32[] memory afterSnapshot = _getStorageSnapshot();
        for (uint8 i = 0; i < afterSnapshot.length; i++) {
            assertEq(afterSnapshot[i], beforeSnapshot[i], "Unexpected storage value updated");
        }
    }

    function _getStorageSnapshot() internal view returns (bytes32[] memory) {
        // Snapshot values for priceStrategy, stableTokenTreasury, (fee)Strategy, isFrozen, isSeized), (exposureCap, currentExposure), accruedFees
        bytes32[] memory data = new bytes32[](5);
        data[0] = vm.load(address(DUSD_USM), bytes32(uint256(0)));
        data[1] = vm.load(address(DUSD_USM), bytes32(uint256(2)));
        data[2] = vm.load(address(DUSD_USM), bytes32(uint256(3)));
        data[3] = vm.load(address(DUSD_USM), bytes32(uint256(4)));
        data[4] = vm.load(address(DUSD_USM), bytes32(uint256(5)));
        return data;
    }
}

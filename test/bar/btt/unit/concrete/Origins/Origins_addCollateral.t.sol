// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// dependencies
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {Origins} from "tapioca-bar/markets/origins/Origins.sol";
import {Market} from "tapioca-bar/markets/Market.sol";

import {Origins_Unit_Shared} from "../../shared/Origins_Unit_Shared.t.sol";

contract Origins_addCollateral is Origins_Unit_Shared {
    function test_RevertWhen_AddCollateralIsCalledAndContractIsPaused() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        org.updatePause(Market.PauseType.AddCollateral, true);
        assertTrue(org._pauseOptions(Market.PauseType.AddCollateral));

        vm.expectRevert("Market: paused");
        org.addCollateral(100, 0);
    }

    function test_WhenOriginsAddCollateralIsCalledForSender() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        uint256 amount = 1 ether;
        deal(address(org.collateral()), address(this), amount);
        mainToken.approve(address(org), type(uint256).max);

        uint256 share = org.convertToShares(amount);
        org.deposit(amount, address(this));
        org.addCollateral(0, share);

        uint256 resultedCollateral = org.balanceOf(address(this));
        assertEq(resultedCollateral, share);

        uint256 totalCollateralShare = org._totalCollateralShare();
        assertEq(totalCollateralShare, share);

        uint256 bbYieldBoxBalance = org.totalSupply();
        assertEq(bbYieldBoxBalance, share);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// dependencies
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {Origins} from "tapioca-bar/markets/origins/Origins.sol";
import {Market} from "tapioca-bar/markets/Market.sol";

import {Origins_Unit_Shared} from "../../shared/Origins_Unit_Shared.t.sol";

contract Origins_removeCollateral is Origins_Unit_Shared {
    function test_RevertWhen_RemoveCollateralIsCalledAndContractIsPaused() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        org.updatePause(Market.PauseType.RemoveCollateral, true);
        assertTrue(org._pauseOptions(Market.PauseType.RemoveCollateral));

        vm.expectRevert("Market: paused");
        org.removeCollateral(100);
    }

    function test_RevertWhen_RemoveCollateralIsCalledAndUserIsNotSolvent() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));
        org.updateAllowedParticipants(address(this), true);
        usdo.setMinterStatus(address(org), true);

        uint256 borrowAmount = 9e17;
        _addCollateral(org);
        org.borrow(borrowAmount);

        vm.expectRevert("Market: insolvent");
        org.removeCollateral(0.1 ether);
    }

    function test_WhenRemoveCollateralIsCalledForSender() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));
        org.updateAllowedParticipants(address(this), true);
        usdo.setMinterStatus(address(org), true);

        _addCollateral(org);
        org.borrow(5e17);

        uint256 collateralShareBefore = org.balanceOf(address(this));
        org.removeCollateral(0.1 ether);
        uint256 collateralShareAfter = org.balanceOf(address(this));

        assertEq(collateralShareBefore - collateralShareAfter, 0.1 ether);
    }

    function _addCollateral(Origins org) private {
        uint256 amount = 1 ether;
        IERC20 collateral = IERC20(address(org.collateral()));
        deal(address(collateral), address(this), amount);
        uint256 share = org.convertToShares(amount);

        collateral.approve(address(org), amount);
        org.deposit(amount, address(this));
    }
}

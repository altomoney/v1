// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// dependencies
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {Origins} from "tapioca-bar/markets/origins/Origins.sol";
import {Market, PauseType} from "tapioca-bar/markets/Market.sol";

import {Origins_Unit_Shared} from "../../shared/Origins_Unit_Shared.t.sol";

contract Origins_repay is Origins_Unit_Shared {
    function test_RevertWhen_RepayIsCalledAndContractIsPaused() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        org.updatePause(PauseType.Repay, true);
        assertTrue(org._pauseOptions(PauseType.Repay));

        vm.expectRevert("Market: paused");
        org.repay(100);
    }

    function test_RevertWhen_RepayIsCalledForNoPosition() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        vm.expectRevert(Origins.NothingToRepay.selector);
        org.repay(100);
    }

    function test_WhenRepayIsCalledForSender_origins() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));
        org.updateAllowedParticipants(address(this), true);
        usdo.setMinterStatus(address(org), true);
        usdo.setBurnerStatus(address(org), true);

        _addCollateral(org);
        org.borrow(5e17);

        uint256 amountToRepay = 5e17;
        usdo.approve(address(org), amountToRepay);
        uint256 borrowPartBefore = org._userBorrowPart(address(this));
        org.repay(amountToRepay);
        uint256 borrowPartAfter = org._userBorrowPart(address(this));

        assertGt(borrowPartBefore, borrowPartAfter);
    }

    function _addCollateral(Origins org) private {
        uint256 amount = 1 ether;
        IERC20 collateral = IERC20(address(org.collateral()));
        deal(address(collateral), address(this), amount);

        collateral.approve(address(org), amount);
        org.deposit(amount, address(this));
    }
}

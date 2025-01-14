// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// dependencies
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {Origins} from "tapioca-bar/markets/origins/Origins.sol";
import {Market, PauseType} from "tapioca-bar/markets/Market.sol";

import {Origins_Unit_Shared} from "../../shared/Origins_Unit_Shared.t.sol";

contract Origins_borrow is Origins_Unit_Shared {
    function test_RevertWhen_BorrowIsCalledAndContractIsPaused() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        org.updatePause(PauseType.Borrow, true);
        assertTrue(org._pauseOptions(PauseType.Borrow));

        vm.expectRevert("Market: paused");
        org.borrow(100);
    }

    function test_WhenBorrowIsCalledForSender() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));
        org.updateAllowedParticipants(address(this), true);

        uint256 borrowAmount = 9e17;

        usdo.setMinterStatus(address(org), true);

        _addCollateral(org);

        vm.expectRevert(Market.MinBorrowAmountNotMet.selector);
        org.borrow(1);

        org.borrow(borrowAmount);

        uint256 usdoSupply = usdo.totalSupply();
        assertEq(usdoSupply, borrowAmount);

        uint256 borrowPart = org._userBorrowPart(address(this));
        assertEq(borrowPart, borrowAmount);
    }

    function _addCollateral(Origins org) private {
        uint256 amount = 1 ether;
        IERC20 collateral = IERC20(address(org.collateral()));
        deal(address(collateral), address(this), amount);
        collateral.approve(address(org), amount);

        org.deposit(amount, address(this));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// dependencies
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {Origins} from "tapioca-bar/markets/origins/Origins.sol";
import {Market} from "tapioca-bar/markets/Market.sol";

import {Origins_Unit_Shared} from "../../shared/Origins_Unit_Shared.t.sol";

contract Origins_repay is Origins_Unit_Shared {
    function test_RevertWhen_RepayIsCalledAndContractIsPaused() external {
        Origins org = Origins(payable(_registerDefaultOrigins()));

        ICluster _cl = penrose.cluster();
        _cl.setRoleForContract(address(this), keccak256("PAUSABLE"), true);

        org.updatePause(Market.PauseType.Repay, true);
        assertTrue(org._pauseOptions(Market.PauseType.Repay));

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

        _addToYieldBox(address(org), address(usdo), 5e17);

        uint256 borrowPartBefore = org._userBorrowPart(address(this));
        org.repay(5e17);
        uint256 borrowPartAfter = org._userBorrowPart(address(this));

        assertGt(borrowPartBefore, borrowPartAfter);
    }

    function _addToYieldBox(address _org, address _asset, uint256 _amount) private {
        vm.skip(true);
        /*
        deal(_asset, address(this), _amount);

        usdo.approve( type(uint256).max);
        usdo.approve(address(pearl mit), type(uint256).max);
        
        yieldBox.depositAsset(_assetId, address(this), address(this), _amount, 0);

        usdo.setMinterStatus(address(this), true);
        usdo.mint(address(this), _amount);
        */
    }

    function _addCollateral(Origins org) private {
        uint256 amount = 1 ether;
        deal(address(org._collateral()), address(this), amount);
        mainToken.approve(type(uint256).max);

        uint256 share = org.convertToShares(amount);

        org.deposit(amount, address(this));
        org.addCollateral(0, share);
    }
}

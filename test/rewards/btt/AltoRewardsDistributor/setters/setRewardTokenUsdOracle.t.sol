// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "../RewardsDistributorCommon.t.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsDistributorSetRewardTokenUsdOracle is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        OracleMock newOracle = new OracleMock();

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.setRewardTokenUsdOracle(address(newOracle));
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_NewOracleIsZeroAddress() external whenCallerIsOwner {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.setRewardTokenUsdOracle(address(0));
    }

    function test_WhenNewOracleIsNotZeroAddress() external whenCallerIsOwner {
        OracleMock newOracle = new OracleMock();
        newOracle.setPrice(_getOraclePriceFromEther(200 ether)); // $200 per token

        address oldOracle = distributor.rewardTokenUsdOracle();

        // it should emit SetRewardTokenUsdOracle event
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetRewardTokenUsdOracle(address(newOracle));

        vm.prank(OWNER);
        distributor.setRewardTokenUsdOracle(address(newOracle));

        // it should update reward token USD oracle
        assertEq(distributor.rewardTokenUsdOracle(), address(newOracle));
        assertNotEq(distributor.rewardTokenUsdOracle(), oldOracle);
    }

    function test_WhenSettingValidOracleMultipleTimes() external whenCallerIsOwner {
        OracleMock oracle1 = new OracleMock();
        OracleMock oracle2 = new OracleMock();

        oracle1.setPrice(_getOraclePriceFromEther(150 ether));
        oracle2.setPrice(_getOraclePriceFromEther(250 ether));

        // Set first oracle
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetRewardTokenUsdOracle(address(oracle1));

        vm.prank(OWNER);
        distributor.setRewardTokenUsdOracle(address(oracle1));

        assertEq(distributor.rewardTokenUsdOracle(), address(oracle1));

        // Set second oracle
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetRewardTokenUsdOracle(address(oracle2));

        vm.prank(OWNER);
        distributor.setRewardTokenUsdOracle(address(oracle2));

        assertEq(distributor.rewardTokenUsdOracle(), address(oracle2));
        assertNotEq(distributor.rewardTokenUsdOracle(), address(oracle1));
    }
}

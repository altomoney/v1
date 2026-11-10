// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "../RewardsDistributorCommon.t.sol";
import {IRewardsEvents} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsDistributorSetPaymentToken is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        address newToken = address(new ERC20MockDecimals("New Token", "NEW", 18));
        address newOracle = address(new OracleMock());

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.setPaymentToken(newToken, newOracle);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_WhenOracleIsNotZeroAddress() external whenCallerIsOwner {
        ERC20MockDecimals newToken = new ERC20MockDecimals("New Token", "NEW", 18);
        OracleMock newOracle = new OracleMock();
        newOracle.setPrice(_getOraclePriceFromEther(100 ether));

        // it should emit SetPaymentToken event
        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.SetPaymentToken(address(newToken), address(newOracle));

        vm.prank(OWNER);
        distributor.setPaymentToken(address(newToken), address(newOracle));

        // it should set payment token configuration
        (address oracle, uint8 decimals) = distributor.paymentTokens(address(newToken));
        assertEq(oracle, address(newOracle));

        // it should cache token decimals
        assertEq(decimals, 18);
    }

    function test_WhenOracleIsZeroAddress() external whenCallerIsOwner {
        // First set a payment token
        ERC20MockDecimals newToken = new ERC20MockDecimals("New Token", "NEW", 18);
        OracleMock newOracle = new OracleMock();

        vm.prank(OWNER);
        distributor.setPaymentToken(address(newToken), address(newOracle));

        // Verify it's set
        (address oracle,) = distributor.paymentTokens(address(newToken));
        assertEq(oracle, address(newOracle));

        // it should emit SetPaymentToken event
        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.SetPaymentToken(address(newToken), address(0));

        vm.prank(OWNER);
        distributor.setPaymentToken(address(newToken), address(0));

        // it should delete payment token configuration
        (address oracleAfter, uint8 decimalsAfter) = distributor.paymentTokens(address(newToken));
        assertEq(oracleAfter, address(0));
        assertEq(decimalsAfter, 0);
    }

    function test_RevertWhen_TokenDecimalsCallFails() external whenCallerIsOwner {
        // Create a mock contract that doesn't implement decimals() properly
        address invalidToken = address(new InvalidDecimalsToken());
        address newOracle = address(new OracleMock());

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert();
        distributor.setPaymentToken(invalidToken, newOracle);
    }
}

// Mock contract that doesn't implement decimals() or implements it incorrectly
contract InvalidDecimalsToken {
    function name() external pure returns (string memory) {
        return "Invalid Token";
    }

    function symbol() external pure returns (string memory) {
        return "INVALID";
    }

    // Missing decimals() function or implement it to revert
    function decimals() external pure returns (uint8) {
        revert("Decimals call failed");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract SetIrmTest is AltoMintMarketTest {
    FixedRateIrm internal newIrm;

    function setUp() public override {
        super.setUp();
        // Use a valid borrow rate (much less than MAX_BORROW_RATE = 8e18 / 365 days)
        // MAX_BORROW_RATE ≈ 253,678,335,870 wei per second, so use 1e11 (much smaller)
        uint256 validBorrowRate = 1e11; // ~0.1% of max rate
        newIrm = new FixedRateIrm(validBorrowRate, owner);
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setIrm(address(newIrm));
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_UpdateIRMAddressWhen_NewIRMIsZeroAddress() external givenCallerIsOwner {
        vm.startPrank(owner);
        // The contract doesn't validate zero address, so this should succeed
        market.setIrm(address(0));
        address updatedIrm = market.irm();
        assertEq(updatedIrm, address(0));
        vm.stopPrank();
    }

    modifier whenNewIRMIsValidAddress() {
        _;
    }

    function test_RevertWhen_IRMFailsToSetMarket() external givenCallerIsOwner whenNewIRMIsValidAddress {
        // Create a mock IRM that will fail on setMarket
        address failingIrm = makeAddr("failingIrm");

        vm.startPrank(owner);
        vm.expectRevert();
        market.setIrm(failingIrm);
        vm.stopPrank();
    }

    function test_UpdateIRMAddressWhen_IRMSuccessfullySetsMarket()
        external
        givenCallerIsOwner
        whenNewIRMIsValidAddress
    {
        address currentIrm = market.irm();

        vm.startPrank(owner);
        market.setIrm(address(newIrm));
        vm.stopPrank();

        // it should update IRM address
        address updatedIrm = market.irm();
        assertEq(updatedIrm, address(newIrm));
        assertNotEq(updatedIrm, currentIrm);
    }
}

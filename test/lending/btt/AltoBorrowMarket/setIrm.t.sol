// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SetIrmTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address owner = address(this);
    address newIrm;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        newIrm = address(new FixedRateIrm(0.05 ether / uint256(365 days), owner));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new AltoBorrowMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            0,
            owner,
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            })
        );
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setIrm(newIrm);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_IrmIsInvalidContract() public givenCallerIsOwner {
        vm.startPrank(owner);
        vm.expectRevert();
        market.setIrm(address(0x123)); // Invalid contract
        vm.stopPrank();
    }

    function test_SetIrmWhen_IrmIsValidContract() public givenCallerIsOwner {
        vm.startPrank(owner);
        market.setIrm(newIrm);
        assertEq(market.irm(), newIrm);
        vm.stopPrank();
    }

    function test_SetIrmWhen_IrmIsZeroAddress() public givenCallerIsOwner {
        vm.startPrank(owner);
        market.setIrm(address(0));
        assertEq(market.irm(), address(0));
        vm.stopPrank();
    }
}

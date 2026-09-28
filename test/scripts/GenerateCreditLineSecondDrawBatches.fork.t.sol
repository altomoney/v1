// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAltoConvexCreditLineMarket} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {GenerateCreditLineSecondDrawBatches} from "../../script/GenerateCreditLineSecondDrawBatches.s.sol";

contract GenerateCreditLineSecondDrawBatchesForkTest is Test {
    address private constant SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address private constant CREDIT = 0x6b3458c87CD38aeFA6A5D059Eb19f609420DD852;
    address private constant LP = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address private constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address private constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 26_075_908);
    }

    function testSevenDayDelayAndAllLpDeposited() external {
        vm.warp(block.timestamp + 7 days);
        IAltoConvexCreditLineMarket market = IAltoConvexCreditLineMarket(CREDIT);
        uint256 oldCollateral = market.position(SAFE).collateralAssets;
        GenerateCreditLineSecondDrawBatches generator = new GenerateCreditLineSecondDrawBatches();

        generator.run();
        uint256 mintedLp = IERC20(LP).balanceOf(SAFE);
        assertGt(mintedLp, 496_500 ether);
        assertEq(IERC20(DUSD).balanceOf(SAFE), 0);
        assertEq(IERC20(FRXUSD).balanceOf(SAFE), 0);

        generator.run();
        assertEq(IERC20(LP).balanceOf(SAFE), 0);
        assertEq(market.position(SAFE).collateralAssets, oldCollateral + mintedLp);
    }

    function testDrawRejectedAfterBufferExpires() external {
        vm.warp(block.timestamp + 17 days);
        GenerateCreditLineSecondDrawBatches generator = new GenerateCreditLineSecondDrawBatches();
        vm.expectRevert("499k draw no longer fits credit limit");
        generator.run();
    }
}

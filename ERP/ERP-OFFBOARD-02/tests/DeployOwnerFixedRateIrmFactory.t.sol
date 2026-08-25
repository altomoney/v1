// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingParams, BorrowMarketOffboardingPhase} from "../IBorrowMarketOffboarding.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DeployOwnerFixedRateIrmFactoryPhaseTest is BorrowMarketOffboardingTestBase {
    address internal constant PRODUCTION_TIMELOCK_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    uint256 internal constant BORROW_RATE_SPY = 0.1 ether / uint256(365 days);

    address internal targetMarket;
    AltoTimelockController internal factoryTimelock;
    BorrowMarketOffboardingParams internal params;

    function setUp() public {
        _selectFork();

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        factoryTimelock = AltoTimelockController(payable(vm.parseJsonAddress(addresses, ".contracts.timelock")));
        targetMarket = vm.parseJsonAddress(addresses, ".contracts.wbtcBorrowMarket");

        params = BorrowMarketOffboardingParams({
            phase: BorrowMarketOffboardingPhase.DEPLOY_OWNER_FIXED_RATE_IRM_FACTORY,
            freezerSafe: address(0),
            timelockSafe: PRODUCTION_TIMELOCK_SAFE
        });
        input.contracts.timelock = address(factoryTimelock);
    }

    function testDeployOwnerFixedRateIrmFactoryPhaseDeploysFactory() public {
        OwnerFixedRateIrmFactory factory = _runDeploymentPhase();

        assertGt(address(factory).code.length, 0, "factory not deployed");
        assertEq(factory.owner(), address(factoryTimelock), "factory owner is not Timelock");
        assertEq(factory.nonce(), 0, "factory nonce is not zero");
    }

    function testOwnerFixedRateIrmFactoryCanOnlyBeCalledThroughTimelock() public {
        OwnerFixedRateIrmFactory factory = _runDeploymentPhase();

        vm.prank(PRODUCTION_TIMELOCK_SAFE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PRODUCTION_TIMELOCK_SAFE));
        factory.deploy(targetMarket, BORROW_RATE_SPY, address(factoryTimelock));
        assertEq(factory.nonce(), 0, "unauthorized call changed factory nonce");

        address expectedIrm = factory.predictIrmAddress(BORROW_RATE_SPY, address(factoryTimelock), 0);
        bytes memory payload =
            abi.encodeCall(OwnerFixedRateIrmFactory.deploy, (targetMarket, BORROW_RATE_SPY, address(factoryTimelock)));
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay = factoryTimelock.getMinDelay();

        vm.prank(PRODUCTION_TIMELOCK_SAFE);
        factoryTimelock.schedule(address(factory), 0, payload, predecessor, salt, delay);

        vm.warp(block.timestamp + delay);
        vm.prank(PRODUCTION_TIMELOCK_SAFE);
        factoryTimelock.execute(address(factory), 0, payload, predecessor, salt);

        assertEq(factory.nonce(), 1, "Timelock call did not consume factory nonce");
        assertGt(expectedIrm.code.length, 0, "Timelock call did not deploy fixed-rate IRM");
        assertEq(FixedRateIrm(expectedIrm).owner(), address(factoryTimelock), "fixed-rate IRM owner is not Timelock");
    }

    function _runDeploymentPhase() internal returns (OwnerFixedRateIrmFactory factory) {
        input = BorrowMarketOffboarding.runPhase(params, input);
        factory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    OwnerPegResponsiveExponentialIrmFactory
} from "@alto/deployments/ethereum-mainnet/OwnerPegResponsiveExponentialIrmFactory.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {
    IPegResponsiveExponentialIrm,
    PegResponsiveExponentialIrmConfig
} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";

contract OwnerPegResponsiveExponentialIrmFactoryTest is Test {
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant VERSION = 1;
    uint256 internal constant SECOND_VERSION = 2;

    address internal timelock = makeAddr("timelock");
    address internal market = makeAddr("market");
    address internal secondMarket = makeAddr("secondMarket");

    MockDusdPegOracle internal pegOracle;
    OwnerPegResponsiveExponentialIrmFactory internal factory;
    PegResponsiveExponentialIrmConfig internal config;

    function setUp() public {
        pegOracle = new MockDusdPegOracle();
        config = _validConfig();
        factory = new OwnerPegResponsiveExponentialIrmFactory(timelock, address(pegOracle));
    }

    function test_constructorSetsTimelockOwnerAndPegOracle() public view {
        assertEq(factory.owner(), timelock, "factory owner");
        assertEq(factory.pendingOwner(), address(0), "factory pending owner");
        assertEq(factory.pegOracle(), address(pegOracle), "factory peg oracle");
    }

    function test_constructorRejectsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new OwnerPegResponsiveExponentialIrmFactory(address(0), address(pegOracle));
    }

    function test_constructorRejectsZeroPegOracle() public {
        vm.expectRevert(bytes("Invalid peg oracle"));
        new OwnerPegResponsiveExponentialIrmFactory(timelock, address(0));
    }

    function test_deployIsOwnerOnly() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.deploy(market, VERSION, config);
    }

    function test_setPegOracleIsOwnerOnlyAndRejectsZeroAddress() public {
        MockDusdPegOracle newOracle = new MockDusdPegOracle();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.setPegOracle(address(newOracle));

        vm.expectRevert(bytes("Invalid peg oracle"));
        vm.prank(timelock);
        factory.setPegOracle(address(0));
    }

    function test_deployRejectsZeroMarket() public {
        vm.expectRevert(bytes("Invalid market"));
        vm.prank(timelock);
        factory.deploy(address(0), VERSION, config);

        vm.expectRevert(bytes("Invalid market"));
        factory.predictIrmAddress(address(0), VERSION, config);
    }

    function test_deploysPredictedIrmOwnedByTimelockAndRecordsDeployment() public {
        address predicted = factory.predictIrmAddress(market, VERSION, config);
        assertEq(predicted.code.length, 0, "predicted IRM must not exist");

        vm.prank(timelock);
        address deployed = factory.deploy(market, VERSION, config);

        assertEq(deployed, predicted, "predicted IRM");
        assertGt(deployed.code.length, 0, "IRM code");

        (address recordedIrm, address recordedOwner, address recordedOracle) = factory.deployments(market, VERSION);
        assertEq(recordedIrm, deployed, "recorded IRM");
        assertEq(recordedOwner, timelock, "recorded owner");
        assertEq(recordedOracle, address(pegOracle), "recorded oracle");

        PegResponsiveExponentialIrm irm = PegResponsiveExponentialIrm(deployed);
        assertEq(irm.owner(), timelock, "IRM owner");
        assertEq(irm.pendingOwner(), address(0), "IRM pending owner");
        assertEq(irm.pegOracle(), address(pegOracle), "IRM peg oracle");
        assertEq(irm.market(), address(0), "IRM market before binding");
        assertEq(uint256(irm.IRM_TYPE()), uint256(IRMType.PEG_RESPONSIVE_EXPONENTIAL), "IRM type");
        PegResponsiveExponentialIrmConfig memory deployedConfig = IPegResponsiveExponentialIrm(deployed).irmConfig();
        assertEq(keccak256(abi.encode(deployedConfig)), keccak256(abi.encode(config)), "IRM config");
    }

    function test_exactRetryReturnsExistingIrm() public {
        vm.prank(timelock);
        address deployed = factory.deploy(market, VERSION, config);

        assertEq(factory.predictIrmAddress(market, VERSION, config), deployed, "existing prediction");

        vm.prank(timelock);
        assertEq(factory.deploy(market, VERSION, config), deployed, "exact retry");
    }

    function test_existingMarketRejectsDifferentConfig() public {
        vm.prank(timelock);
        factory.deploy(market, VERSION, config);

        PegResponsiveExponentialIrmConfig memory differentConfig = config;
        differentConfig.recoveryDelay += 1;

        vm.expectRevert(bytes("Version already used"));
        factory.predictIrmAddress(market, VERSION, differentConfig);

        vm.expectRevert(bytes("Version already used"));
        vm.prank(timelock);
        factory.deploy(market, VERSION, differentConfig);
    }

    function test_existingMarketRejectsDifferentFactoryOwner() public {
        vm.prank(timelock);
        factory.deploy(market, VERSION, config);

        address newOwner = makeAddr("newOwner");
        vm.prank(timelock);
        factory.transferOwnershipSkip2Step(newOwner);

        vm.expectRevert(bytes("Version already used"));
        factory.predictIrmAddress(market, VERSION, config);

        vm.expectRevert(bytes("Version already used"));
        vm.prank(newOwner);
        factory.deploy(market, VERSION, config);
    }

    function test_newVersionDeploysFreshIrmForSameMarket() public {
        address firstPrediction = factory.predictIrmAddress(market, VERSION, config);
        address secondPrediction = factory.predictIrmAddress(market, SECOND_VERSION, config);
        assertNotEq(firstPrediction, secondPrediction, "versions must have distinct predictions");

        vm.startPrank(timelock);
        address firstIrm = factory.deploy(market, VERSION, config);
        address secondIrm = factory.deploy(market, SECOND_VERSION, config);
        vm.stopPrank();

        assertEq(firstIrm, firstPrediction, "first version prediction");
        assertEq(secondIrm, secondPrediction, "second version prediction");
        assertNotEq(firstIrm, secondIrm, "versions must deploy distinct IRMs");

        (address recordedFirstIrm, address firstOwner, address firstOracle) = factory.deployments(market, VERSION);
        (address recordedSecondIrm, address secondOwner, address secondOracle) =
            factory.deployments(market, SECOND_VERSION);
        assertEq(recordedFirstIrm, firstIrm, "first version record");
        assertEq(recordedSecondIrm, secondIrm, "second version record");
        assertEq(firstOwner, timelock, "first version owner");
        assertEq(secondOwner, timelock, "second version owner");
        assertEq(firstOracle, address(pegOracle), "first version oracle");
        assertEq(secondOracle, address(pegOracle), "second version oracle");
    }

    function test_setPegOracleOnlyAffectsFutureDeployments() public {
        address oldPredictionForSecondMarket = factory.predictIrmAddress(secondMarket, VERSION, config);

        vm.prank(timelock);
        address firstIrm = factory.deploy(market, VERSION, config);

        MockDusdPegOracle newOracle = new MockDusdPegOracle();
        vm.prank(timelock);
        factory.setPegOracle(address(newOracle));

        assertEq(factory.pegOracle(), address(newOracle), "updated factory oracle");
        assertEq(factory.predictIrmAddress(market, VERSION, config), firstIrm, "existing IRM prediction");

        vm.prank(timelock);
        assertEq(factory.deploy(market, VERSION, config), firstIrm, "existing IRM retry");

        address newPredictionForSecondMarket = factory.predictIrmAddress(secondMarket, VERSION, config);
        assertNotEq(newPredictionForSecondMarket, oldPredictionForSecondMarket, "future prediction must change");

        vm.prank(timelock);
        address secondIrm = factory.deploy(secondMarket, VERSION, config);

        assertEq(secondIrm, newPredictionForSecondMarket, "new oracle prediction");
        assertEq(PegResponsiveExponentialIrm(secondIrm).owner(), timelock, "new IRM owner");
        assertEq(PegResponsiveExponentialIrm(secondIrm).pegOracle(), address(newOracle), "new IRM oracle");

        (,, address firstRecordedOracle) = factory.deployments(market, VERSION);
        (,, address secondRecordedOracle) = factory.deployments(secondMarket, VERSION);
        assertEq(firstRecordedOracle, address(pegOracle), "existing recorded oracle");
        assertEq(secondRecordedOracle, address(newOracle), "new recorded oracle");
    }

    function _validConfig() internal pure returns (PegResponsiveExponentialIrmConfig memory) {
        return PegResponsiveExponentialIrmConfig({
            recoveryPrice: 1.001e18,
            stressPrice: 1e18,
            baseRate: 0.05e18 / YEAR,
            stressRate: 0.075e18 / YEAR,
            maxRate: 8e18 / YEAR,
            doublingDistance: 0.0025e18,
            recoveryDelay: 6 hours,
            maxOracleAge: 30 minutes
        });
    }
}

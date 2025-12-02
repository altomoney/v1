// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

contract MockOwnableContract is AltoOwnable2Step {
    uint256 public value;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }
}

contract MockAccessControlContract is AccessControl {
    uint256 public value;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setValue(uint256 _value) external onlyRole(ADMIN_ROLE) {
        value = _value;
    }
}

contract AltoTimelockControllerTest is Test {
    AltoTimelockController public timelock;
    MockOwnableContract public mockOwnable;
    MockAccessControlContract public mockAccessControl;

    address public admin;
    address public proposer;
    address public executor;
    address public unauthorized;
    address public newAdmin;
    address public newProposer;
    address public newExecutor;

    uint256 public constant DELAY = 2 days;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function setUp() public {
        admin = address(0x1);
        proposer = address(0x2);
        executor = address(0x3);
        unauthorized = address(0x4);
        newAdmin = address(0x5);
        newProposer = address(0x6);
        newExecutor = address(0x7);

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;
        timelock = new AltoTimelockController(DELAY, proposers, executors, admin);

        mockOwnable = new MockOwnableContract(address(timelock));
        mockAccessControl = new MockAccessControlContract();
        mockAccessControl.grantRole(mockAccessControl.ADMIN_ROLE(), address(timelock));
    }

    function test_DirectGrantRole_Reverts_EvenWithAdmin() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.grantRole(adminRole, newAdmin);
    }

    function test_DirectGrantRole_Reverts_Unauthorized() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.grantRole(adminRole, newAdmin);
    }

    function test_DirectRevokeRole_Reverts_EvenWithAdmin() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.revokeRole(proposerRole, proposer);
    }

    function test_DirectRenounceRole_NonAdminRole_Succeeds() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        assertTrue(timelock.hasRole(proposerRole, proposer), "Proposer should have PROPOSER_ROLE initially");
        vm.prank(proposer);
        timelock.renounceRole(proposerRole, proposer);
        assertFalse(timelock.hasRole(proposerRole, proposer), "Role should be renounced");
    }

    function test_DirectRenounceRole_AdminRole_Reverts() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_AdminRoleCannotBeRenounced.selector)
        );
        timelock.renounceRole(adminRole, admin);
        assertTrue(timelock.hasRole(adminRole, admin), "Admin should still have DEFAULT_ADMIN_ROLE");
    }

    function test_DirectRenounceRole_WrongCallerConfirmation_Reverts() public {
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlBadConfirmation.selector));
        timelock.renounceRole(executorRole, proposer);
        assertTrue(timelock.hasRole(executorRole, executor), "Executor should still have EXECUTOR_ROLE");
    }

    function test_DirectRenounceRole_ExecutorRole_Succeeds() public {
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        assertTrue(timelock.hasRole(executorRole, executor), "Executor should have EXECUTOR_ROLE initially");
        vm.prank(executor);
        timelock.renounceRole(executorRole, executor);
        assertFalse(timelock.hasRole(executorRole, executor), "Role should be renounced");
    }

    function test_GrantRole_ThroughTimelock_Success() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, newAdmin);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);

        assertFalse(timelock.hasRole(adminRole, newAdmin), "Role should not be granted before execution");

        bytes32 operationId = timelock.hashOperation(address(timelock), 0, grantRoleData, predecessor, salt);
        bytes32 expectedStates = bytes32(uint256(1 << uint8(TimelockController.OperationState.Ready)));
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, operationId, expectedStates
            )
        );
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        vm.warp(block.timestamp + DELAY - 1);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, operationId, expectedStates
            )
        );
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        vm.warp(block.timestamp + 1);
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(adminRole, newAdmin, address(timelock));
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(adminRole, newAdmin), "Role should be granted after timelock execution");
        assertTrue(timelock.hasRole(adminRole, address(timelock)), "Timelock should have DEFAULT_ADMIN_ROLE");
        assertTrue(timelock.hasRole(adminRole, admin), "Admin should have DEFAULT_ADMIN_ROLE");
    }

    function test_RevokeRole_ThroughTimelock_Success() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        assertTrue(timelock.hasRole(proposerRole, proposer), "Proposer should have PROPOSER_ROLE initially");

        bytes memory revokeRoleData = abi.encodeWithSelector(AccessControl.revokeRole.selector, proposerRole, proposer);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, revokeRoleData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(proposerRole, proposer, address(timelock));
        vm.prank(executor);
        timelock.execute(address(timelock), 0, revokeRoleData, predecessor, salt);

        assertFalse(timelock.hasRole(proposerRole, proposer), "Role should be revoked after timelock execution");
    }

    function test_RenounceRole_AdminRole_CannotBeRenounced() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        assertTrue(timelock.hasRole(adminRole, admin), "Admin should have DEFAULT_ADMIN_ROLE initially");
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_AdminRoleCannotBeRenounced.selector)
        );
        timelock.renounceRole(adminRole, admin);
        assertTrue(timelock.hasRole(adminRole, admin), "Admin should still have DEFAULT_ADMIN_ROLE");
    }

    function test_RenounceRole_NonAdminRole_Directly_Succeeds() public {
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        address testCanceller = address(0x999);
        bytes memory grantRoleData =
            abi.encodeWithSelector(AccessControl.grantRole.selector, cancellerRole, testCanceller);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(cancellerRole, testCanceller), "Test canceller should have CANCELLER_ROLE");
        vm.prank(testCanceller);
        timelock.renounceRole(cancellerRole, testCanceller);
        assertFalse(timelock.hasRole(cancellerRole, testCanceller), "Role should be renounced");
    }

    function test_TimelockDelay_Enforced_ForGrantRole() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, newAdmin);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);

        bytes32 operationId = timelock.hashOperation(address(timelock), 0, grantRoleData, predecessor, salt);
        bytes32 expectedStates = bytes32(uint256(1 << uint8(TimelockController.OperationState.Ready)));
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, operationId, expectedStates
            )
        );
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        vm.warp(block.timestamp + DELAY - 1);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, operationId, expectedStates
            )
        );
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        vm.warp(block.timestamp + 1);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(adminRole, newAdmin), "Role should be granted after delay");
    }

    function test_AdminCannotBypassTimelock_GrantRole() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        assertTrue(timelock.hasRole(adminRole, admin), "Admin should have DEFAULT_ADMIN_ROLE");
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.grantRole(adminRole, newAdmin);
        assertFalse(timelock.hasRole(adminRole, newAdmin), "Role should not be granted");
    }

    function test_AdminCannotBypassTimelock_RevokeRole() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.revokeRole(proposerRole, proposer);
        assertTrue(timelock.hasRole(proposerRole, proposer), "Role should not be revoked");
    }

    function test_BatchRoleChanges_ThroughTimelock() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes32 proposerRole = timelock.PROPOSER_ROLE();

        address[] memory targets = new address[](2);
        targets[0] = address(timelock);
        targets[1] = address(timelock);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, newAdmin);
        payloads[1] = abi.encodeWithSelector(AccessControl.grantRole.selector, proposerRole, newProposer);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, predecessor, salt, DELAY);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.executeBatch(targets, values, payloads, predecessor, salt);

        assertTrue(timelock.hasRole(adminRole, newAdmin), "New admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(timelock.hasRole(proposerRole, newProposer), "New proposer should have PROPOSER_ROLE");
    }

    function test_MultipleRoleChanges_InSequence() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes32 proposerRole = timelock.PROPOSER_ROLE();

        bytes memory grantAdminData = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, newAdmin);
        bytes32 salt1 = bytes32(uint256(1));
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantAdminData, predecessor, salt1, DELAY);

        bytes memory grantProposerData =
            abi.encodeWithSelector(AccessControl.grantRole.selector, proposerRole, newProposer);
        bytes32 salt2 = bytes32(uint256(2));
        bytes32 predecessor2 = timelock.hashOperation(address(timelock), 0, grantAdminData, predecessor, salt1);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantProposerData, predecessor2, salt2, DELAY);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantAdminData, predecessor, salt1);

        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantProposerData, predecessor2, salt2);

        assertTrue(timelock.hasRole(adminRole, newAdmin), "New admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(timelock.hasRole(proposerRole, newProposer), "New proposer should have PROPOSER_ROLE");
    }

    function test_GrantRole_ToSelf_ThroughTimelock() public {
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, executorRole, admin);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(executorRole, admin), "Admin should have EXECUTOR_ROLE");
    }

    function test_RevokeRole_FromSelf_ThroughTimelock() public {
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes memory revokeRoleData = abi.encodeWithSelector(AccessControl.revokeRole.selector, executorRole, executor);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, revokeRoleData, predecessor, salt, DELAY);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(timelock), 0, revokeRoleData, predecessor, salt);

        assertFalse(timelock.hasRole(executorRole, executor), "Executor should not have EXECUTOR_ROLE");
    }

    function test_MsgSender_IsTimelock_WhenExecuting() public {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, newAdmin);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(adminRole, newAdmin), "Role should be granted when called from execute()");
    }

    function test_TimeDelayBetweenSubmissionAndExecution() public {
        uint256 newDelay = DELAY * 2;
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, newDelay);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, updateDelayData, predecessor, salt, DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, updateDelayData, predecessor, salt);

        vm.warp(block.timestamp + DELAY - 1);
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, updateDelayData, predecessor, salt);

        vm.warp(block.timestamp + 1);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, updateDelayData, predecessor, salt);

        assertEq(timelock.getMinDelay(), newDelay, "Delay should be updated after time delay");
    }

    function test_TimelockAsOwner_OwnableContract() public {
        uint256 newValue = 42;
        bytes memory setValueData = abi.encodeWithSelector(MockOwnableContract.setValue.selector, newValue);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(mockOwnable), 0, setValueData, predecessor, salt);

        assertEq(mockOwnable.value(), newValue, "Value should be set by timelock as owner");
        assertEq(mockOwnable.owner(), address(timelock), "Timelock should be the owner");
    }

    function test_TimelockAsOwner_AccessControlContract() public {
        uint256 newValue = 100;
        bytes memory setValueData = abi.encodeWithSelector(MockAccessControlContract.setValue.selector, newValue);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(mockAccessControl), 0, setValueData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(mockAccessControl), 0, setValueData, predecessor, salt);

        assertEq(mockAccessControl.value(), newValue, "Value should be set by timelock with role");
        assertTrue(
            mockAccessControl.hasRole(mockAccessControl.ADMIN_ROLE(), address(timelock)),
            "Timelock should have ADMIN_ROLE"
        );
    }

    function test_EnforcedTimeDelayOnChangingDelay() public {
        uint256 newDelay = DELAY * 2;
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, newDelay);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, updateDelayData, predecessor, salt, DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, updateDelayData, predecessor, salt);

        vm.warp(block.timestamp + DELAY - 1);
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, updateDelayData, predecessor, salt);

        vm.warp(block.timestamp + 1);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, updateDelayData, predecessor, salt);

        assertEq(timelock.getMinDelay(), newDelay, "Delay should be updated after time delay");
    }

    function test_EnforcedTimeDelayOnChangingAdmin() public {
        address testNewAdmin = address(0x8);
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, testNewAdmin);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        vm.warp(block.timestamp + DELAY - 1);
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        vm.warp(block.timestamp + 1);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(adminRole, testNewAdmin), "New admin should have DEFAULT_ADMIN_ROLE");
    }

    function test_OnlyProposerCanSchedule() public {
        bytes memory setValueData = abi.encodeWithSelector(MockOwnableContract.setValue.selector, 42);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(unauthorized);
        vm.expectRevert();
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);

        vm.prank(proposer);
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);
    }

    function test_OnlyExecutorCanExecute() public {
        bytes memory setValueData = abi.encodeWithSelector(MockOwnableContract.setValue.selector, 42);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.prank(unauthorized);
        vm.expectRevert();
        timelock.execute(address(mockOwnable), 0, setValueData, predecessor, salt);

        vm.prank(proposer);
        vm.expectRevert();
        timelock.execute(address(mockOwnable), 0, setValueData, predecessor, salt);

        vm.prank(executor);
        timelock.execute(address(mockOwnable), 0, setValueData, predecessor, salt);
    }

    function test_BatchOperationsRespectTimeDelay() public {
        address[] memory targets = new address[](2);
        targets[0] = address(mockOwnable);
        targets[1] = address(mockOwnable);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(MockOwnableContract.setValue.selector, 10);
        payloads[1] = abi.encodeWithSelector(MockOwnableContract.setValue.selector, 20);
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, predecessor, salt, DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.executeBatch(targets, values, payloads, predecessor, salt);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.executeBatch(targets, values, payloads, predecessor, salt);

        assertEq(mockOwnable.value(), 20, "Batch execution should work after delay");
    }

    function testFuzz_DirectGrantRole_Reverts_AnyCaller(address caller, bytes32 role, address account) public {
        vm.assume(caller != address(timelock));
        vm.assume(account != address(0));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.grantRole(role, account);
    }

    function testFuzz_DirectRevokeRole_Reverts_AnyCaller(address caller, bytes32 role, address account) public {
        vm.assume(caller != address(timelock));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_OnlyCallableFromTimelock.selector)
        );
        timelock.revokeRole(role, account);
    }

    function testFuzz_GrantRole_ThroughTimelock_AnyAddress(address newRoleHolder) public {
        vm.assume(newRoleHolder != address(0));
        vm.assume(newRoleHolder != proposer); // proposer already has this role

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        assertFalse(timelock.hasRole(proposerRole, newRoleHolder), "Should not have role initially");

        bytes memory grantRoleData =
            abi.encodeWithSelector(AccessControl.grantRole.selector, proposerRole, newRoleHolder);
        bytes32 salt = keccak256(abi.encodePacked(newRoleHolder));
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);

        vm.warp(block.timestamp + DELAY);

        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(proposerRole, newRoleHolder), "Role should be granted");
    }

    function testFuzz_RevokeRole_ThroughTimelock_AnyAddress(address roleHolder) public {
        vm.assume(roleHolder != address(0));
        vm.assume(roleHolder != proposer);

        // First grant the role
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, proposerRole, roleHolder);
        bytes32 grantSalt = keccak256(abi.encodePacked("grant", roleHolder));
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, grantSalt, DELAY);
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, grantSalt);

        assertTrue(timelock.hasRole(proposerRole, roleHolder), "Role should be granted");

        // Now revoke the role
        bytes memory revokeRoleData =
            abi.encodeWithSelector(AccessControl.revokeRole.selector, proposerRole, roleHolder);
        bytes32 revokeSalt = keccak256(abi.encodePacked("revoke", roleHolder));

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, revokeRoleData, predecessor, revokeSalt, DELAY);
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, revokeRoleData, predecessor, revokeSalt);

        assertFalse(timelock.hasRole(proposerRole, roleHolder), "Role should be revoked");
    }

    function testFuzz_RenounceRole_AdminRole_AlwaysReverts(address adminHolder) public {
        vm.assume(adminHolder != address(0));
        vm.assume(adminHolder != admin);
        vm.assume(adminHolder != address(timelock));

        // Grant admin role to fuzzed address
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, adminRole, adminHolder);
        bytes32 salt = keccak256(abi.encodePacked(adminHolder));
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(adminRole, adminHolder), "Admin role should be granted");

        // Try to renounce - should always revert
        vm.prank(adminHolder);
        vm.expectRevert(
            abi.encodeWithSelector(AltoTimelockController.AltoTimelockController_AdminRoleCannotBeRenounced.selector)
        );
        timelock.renounceRole(adminRole, adminHolder);

        assertTrue(timelock.hasRole(adminRole, adminHolder), "Admin role should still exist");
    }

    function testFuzz_RenounceRole_NonAdminRole_Succeeds(address roleHolder) public {
        vm.assume(roleHolder != address(0));
        vm.assume(roleHolder != executor);

        // Grant executor role to fuzzed address
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes memory grantRoleData = abi.encodeWithSelector(AccessControl.grantRole.selector, executorRole, roleHolder);
        bytes32 salt = keccak256(abi.encodePacked(roleHolder));
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, grantRoleData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(timelock), 0, grantRoleData, predecessor, salt);

        assertTrue(timelock.hasRole(executorRole, roleHolder), "Executor role should be granted");

        // Renounce should succeed for non-admin roles
        vm.prank(roleHolder);
        timelock.renounceRole(executorRole, roleHolder);

        assertFalse(timelock.hasRole(executorRole, roleHolder), "Role should be renounced");
    }

    function testFuzz_OnlyProposerCanSchedule_AnyAddress(address caller) public {
        vm.assume(caller != proposer);
        vm.assume(caller != address(0));

        bytes memory setValueData = abi.encodeWithSelector(MockOwnableContract.setValue.selector, 42);
        bytes32 salt = keccak256(abi.encodePacked(caller));
        bytes32 predecessor = bytes32(0);

        vm.prank(caller);
        vm.expectRevert();
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);
    }

    function testFuzz_OnlyExecutorCanExecute_AnyAddress(address caller) public {
        vm.assume(caller != executor);
        vm.assume(caller != address(0));

        bytes memory setValueData = abi.encodeWithSelector(MockOwnableContract.setValue.selector, 42);
        bytes32 salt = keccak256(abi.encodePacked(caller));
        bytes32 predecessor = bytes32(0);

        vm.prank(proposer);
        timelock.schedule(address(mockOwnable), 0, setValueData, predecessor, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.prank(caller);
        vm.expectRevert();
        timelock.execute(address(mockOwnable), 0, setValueData, predecessor, salt);
    }
}


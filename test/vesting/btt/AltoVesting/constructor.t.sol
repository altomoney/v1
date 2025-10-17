// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoVesting} from "@alto/vesting/AltoVesting.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoVestingConstructor is Test {
    ERC20MockMintable public vestingToken;

    address public OWNER = makeAddr("owner");
    uint256 public constant INITIAL_TIMELOCK = 3 days;
    bytes32 public constant TEST_MERKLE_ROOT = bytes32(uint256(123));
    bytes32 public constant TEST_IPFS_HASH = bytes32(uint256(456));

    // Modifiers for BTT structure
    modifier givenVestingTokenIsZeroAddress() {
        _;
    }

    modifier givenVestingTokenIsValidAddress() {
        vestingToken = new ERC20MockMintable("Alto Token", "ALTO");
        _;
    }

    modifier givenVestingIsUpdatable() {
        _;
    }

    modifier givenVestingIsNotUpdatable() {
        _;
    }

    function test_RevertWhen_VestingTokenIsZeroAddress() external givenVestingTokenIsZeroAddress {
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(0), TEST_MERKLE_ROOT, TEST_IPFS_HASH);
    }

    function test_WhenVestingTokenIsValidAddress_GivenVestingIsUpdatable()
        external
        givenVestingTokenIsValidAddress
        givenVestingIsUpdatable
    {
        AltoVesting vesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), TEST_MERKLE_ROOT, TEST_IPFS_HASH);

        // it should set VESTING_TOKEN correctly
        assertEq(vesting.VESTING_TOKEN(), address(vestingToken));

        // it should set IS_VESTING_UPDATABLE to true
        assertTrue(vesting.IS_VESTING_UPDATABLE());

        // it should set merkle root timelock to initialTimelock
        assertEq(vesting.merkleRootTimelock(), INITIAL_TIMELOCK);

        // it should submit pending root with provided merkle root and ipfs hash
        (bytes32 pendingRoot,, bytes32 pendingIpfsHash) = vesting.pendingMerkleRoot();
        assertEq(pendingRoot, TEST_MERKLE_ROOT);
        assertEq(pendingIpfsHash, TEST_IPFS_HASH);

        // it should set owner correctly
        assertEq(vesting.owner(), OWNER);

        // it should initialize all parent contracts correctly
        assertTrue(address(vesting).code.length > 0);
    }

    function test_WhenVestingTokenIsValidAddress_GivenVestingIsUpdatable_WhenNewMerkleRootIsSubmitted()
        external
        givenVestingTokenIsValidAddress
        givenVestingIsUpdatable
    {
        AltoVesting vesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), TEST_MERKLE_ROOT, TEST_IPFS_HASH);

        // it should allow submitting new pending root and update pending root
        vm.startPrank(OWNER);
        vesting.acceptPendingRoot(TEST_MERKLE_ROOT);
        bytes32 newMerkleRoot = bytes32(uint256(789));
        vesting.submitNewPendingRoot(newMerkleRoot, TEST_IPFS_HASH);
        vm.stopPrank();

        // it should update pending root
        (bytes32 pendingRoot,, bytes32 pendingIpfsHash) = vesting.pendingMerkleRoot();
        assertEq(pendingRoot, newMerkleRoot);
        assertEq(pendingIpfsHash, TEST_IPFS_HASH);
    }

    function test_WhenVestingTokenIsValidAddress_GivenVestingIsNotUpdatable()
        external
        givenVestingTokenIsValidAddress
        givenVestingIsNotUpdatable
    {
        AltoVesting vesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, false, address(vestingToken), TEST_MERKLE_ROOT, TEST_IPFS_HASH);

        // it should set VESTING_TOKEN correctly
        assertEq(vesting.VESTING_TOKEN(), address(vestingToken));

        // it should set IS_VESTING_UPDATABLE to false
        assertFalse(vesting.IS_VESTING_UPDATABLE());

        // timelock is not set for non-updatable vesting
        assertEq(vesting.merkleRootTimelock(), 0);

        assertEq(vesting.merkleRoot(), TEST_MERKLE_ROOT);
        assertEq(vesting.ipfsHash(), TEST_IPFS_HASH);

        // it should set owner correctly
        assertEq(vesting.owner(), OWNER);

        // it should initialize all parent contracts correctly
        assertTrue(address(vesting).code.length > 0);
    }

    function test_WhenVestingTokenIsValidAddress_GivenVestingIsNotUpdatable_WhenNewMerkleRootIsSubmitted()
        external
        givenVestingTokenIsValidAddress
        givenVestingIsNotUpdatable
    {
        AltoVesting vesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, false, address(vestingToken), TEST_MERKLE_ROOT, TEST_IPFS_HASH);

        // it should revert with AltoVestingNotUpdatable
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoVesting.AltoVestingNotUpdatable.selector);
        vesting.submitNewPendingRoot(TEST_MERKLE_ROOT, TEST_IPFS_HASH);
        vm.stopPrank();
    }
}

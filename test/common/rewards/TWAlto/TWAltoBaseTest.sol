// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {TWAlto} from "@alto/rewards/TWAlto.sol";
import {Bucket} from "@alto/rewards/TWLBase.sol";

contract TWAltoBaseTest is Test {
    ERC20MockMintable public alto;
    TWAlto public twAlto;

    // Constants
    uint256 public EPOCH_DURATION = 1 weeks;
    uint256 public MIN_LOCK_DURATION = 4;
    uint256 public MAX_LOCK_DURATION = 6;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public virtual {
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 1,
            lockEpochDuration: 1,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1000
        });

        alto = new ERC20MockMintable("Alto", "ALTO");
        twAlto = new TWAlto(address(alto), admin, EPOCH_DURATION, buckets);
    }

    modifier advanceWeeks(uint256 _num) {
        for (uint256 x; x < _num; x++) {
            vm.warp(block.timestamp + EPOCH_DURATION);
            vm.prank(admin);
            twAlto.advanceWeek(_num);
        }
        _;
    }

    modifier skipWeeks(uint256 _amount) {
        skip(EPOCH_DURATION * _amount);
        _;
    }

    modifier participate(uint256 _amount, uint8 _bucketId) {
        _participate(_amount, _bucketId);
        _;
    }

    function _participate(uint256 _amount, uint8 _bucketId) internal {
        vm.startPrank(alice);
        alto.mint(alice, _amount);
        IERC20(address(alto)).approve(address(twAlto), _amount);
        twAlto.participate(alice, _amount, _bucketId);
        vm.stopPrank();
    }

    function _participate(address _to, uint256 _amount, uint8 _bucketId) internal {
        vm.startPrank(_to);
        alto.mint(_to, _amount);
        IERC20(address(alto)).approve(address(twAlto), _amount);
        twAlto.participate(_to, _amount, _bucketId);
        vm.stopPrank();
    }

    function _boundValues(uint256 _lockAmount, uint8 _bucketId) internal pure returns (uint256, uint8) {
        _lockAmount = bound(_lockAmount, 1, type(uint88).max);
        _bucketId = uint8(bound(_bucketId, 0, 0)); // update with bucket length
        return (_lockAmount, _bucketId);
    }

    function _toWeek(uint256 _timestamp) internal view returns (uint256) {
        return (_timestamp - twAlto.INIT_TIMESTAMP()) / twAlto.EPOCH_DURATION();
    }
}

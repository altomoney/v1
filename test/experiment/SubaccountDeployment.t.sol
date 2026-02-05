pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum PositionType {
    SUPPLY,
    BORROW
}

contract Position {
    address public owner;
    PositionType public positionType;

    using SafeERC20 for IERC20;

    function initialize(address _owner, PositionType _positionType) public {
        owner = _owner;
        positionType = _positionType;
    }

    function supply(address market, uint256 amount) public {
        if (positionType != PositionType.SUPPLY) {
            revert("Invalid position type");
        }

        address borrowToken = IMarket(market).borrowToken();

        IERC20(borrowToken).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(borrowToken).forceApprove(market, type(uint256).max);
        // note: for supplying with shares as argument, this contract would need to calculate the amount corresponding to the share
        // todo: think how to manage this because to calculate amount, we would be mimicking the logic of the market
        IMarket(market).addSupply(amount, 0, address(this));

        IERC20(borrowToken).forceApprove(market, 0);
    }
}

contract BeaconContract {
    address public implementation;

    function initialize(address _implementation) public {
        implementation = _implementation;
    }
}

contract TestProxyDeployer is Test {
    address beacon;
    address position;
    address user;
    address market = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address borrowToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"), 24389955);
        BeaconContract beaconContract = new BeaconContract();
        beaconContract.initialize(address(new Position()));
        beacon = address(beaconContract);

        position = address(new Position());

        user = makeAddr("user");

        borrowToken = IMarket(market).borrowToken();

        deal(address(IMarket(market).borrowToken()), user, 100_000 ether);
    }

    function testdeployBeaconProxy() public {
        address positionProxy =
            address(new BeaconProxy(beacon, abi.encodeCall(Position.initialize, (user, PositionType.SUPPLY))));
        vm.startPrank(user);
        IERC20(borrowToken).approve(positionProxy, 10 ether);
        Position(positionProxy).supply(market, 10 ether);
        vm.stopPrank();
    }

    function testdeployMinimalProxy() public {
        address proxy = Clones.clone(position);
        Position(proxy).initialize(user, PositionType.SUPPLY);

        vm.startPrank(user);
        IERC20(borrowToken).approve(proxy, 10 ether);
        Position(proxy).supply(market, 10 ether);
        vm.stopPrank();
    }
}

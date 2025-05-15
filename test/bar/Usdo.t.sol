// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Signature} from "@alto-monorepo/utils/interfaces/common/IAuth.sol";
import {Cluster} from "@alto-monorepo/utils/Cluster/Cluster.sol";
import {Usdo} from "@alto-monorepo/bar/usdo/Usdo.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TestHelpers} from "@alto-monorepo-test/helpers/TestHelpers.sol";

contract UsdoTest is TestHelpers, TestHelperOz5 {
    Usdo usdo;
    Cluster cluster = new Cluster(1, address(this));

    address internal immutable USER = makeAddr("User");

    function setUp() public override {
        setUpEndpoints(1, LibraryType.UltraLightNode);

        usdo = new Usdo(endpoints[1], address(this), address(cluster));
        vm.label(address(usdo), "aUsdo");
    }

    function test_constructor() public {
        assertEq(address(usdo.getCluster()), address(cluster));
    }

    function test_erc20_permit(uint256 privateKey, uint32 deadline, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        Signature memory signature = _erc20PermitSignature(usdo, privateKey, USER, amount, 0, deadline);

        usdo.permit(user, USER, amount, deadline, signature.v, signature.r, signature.s);
        assertEq(usdo.allowance(user, USER), amount);
        assertEq(usdo.nonces(user), 1);
    }
}

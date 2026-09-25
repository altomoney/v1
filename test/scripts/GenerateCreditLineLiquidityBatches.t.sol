// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GenerateCreditLineLiquidityBatches} from "../../script/GenerateCreditLineLiquidityBatches.s.sol";

contract GenerateCreditLineLiquidityBatchesForkTest is Test {
    address constant SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant LP = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    string constant FIRST =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-credit-line-liquidity-01-create-lp.json";
    string constant SECOND =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-credit-line-liquidity-02-allocate-lp.json";

    function testFork_generatesSecondBatchFromMinedFirstBatch() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 26_053_047);
        GenerateCreditLineLiquidityBatches generator = new GenerateCreditLineLiquidityBatches();

        uint256 beforeFirst = vm.snapshotState();
        generator.run();
        assertTrue(vm.revertToState(beforeFirst));
        _execute(FIRST, 9);

        uint256 mintedLp = IERC20(LP).balanceOf(SAFE);
        assertGt(mintedLp, 0);
        uint256 beforeSecond = vm.snapshotState();
        generator.run();
        assertTrue(vm.revertToState(beforeSecond));
        _execute(SECOND, 6);
        assertEq(IERC20(LP).balanceOf(SAFE), 0);
    }

    function _execute(string memory path, uint256 count) internal {
        string memory json = vm.readFile(path);
        for (uint256 i; i < count; ++i) {
            string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
            vm.prank(SAFE);
            (bool ok, bytes memory result) = target.call(data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
        }
    }
}

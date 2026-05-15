// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Stake LP Tokens
/// @notice Generates raw calldata for the treasury multisig to approve and stake
///         all LP tokens into the Curve gauge.
/// @dev Run with: forge script script/StakeLpTokens.s.sol --fork-url ethereum -vvv
contract StakeLpTokensScript is Script {
    address constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant LP_TOKEN = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address constant CURVE_GAUGE = 0xA41eb3062FD68B6Fa9f11439C86503913806761D;
    string constant SAFE_TX_PATH = "contracts/deployments/ethereum-mainnet/output/safe-tx-stake-lp-tokens.json";

    function run() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));

        uint256 lpBalance = IERC20(LP_TOKEN).balanceOf(TREASURY);
        require(lpBalance > 0, "No LP tokens to stake");

        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, CURVE_GAUGE, lpBalance);

        // Transaction 2: Deposit LP tokens into gauge on behalf of treasury
        // Curve gauge deposit(uint256 _value, address _addr)
        bytes memory depositData = abi.encodeWithSignature("deposit(uint256,address)", lpBalance, TREASURY);

        vm.writeFile(SAFE_TX_PATH, _buildSafeJson(approveData, depositData));

        console.log("LP balance to stake:", lpBalance);
        console.log("Safe tx JSON:", SAFE_TX_PATH);
    }

    function _buildSafeJson(bytes memory approveData, bytes memory depositData) internal pure returns (string memory) {
        return string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"stake-lp-tokens"},',
            '"transactions":[',
            '{"to":"',
            vm.toString(LP_TOKEN),
            '","value":"0","data":"',
            vm.toString(approveData),
            '"},',
            '{"to":"',
            vm.toString(CURVE_GAUGE),
            '","value":"0","data":"',
            vm.toString(depositData),
            '"}',
            "]}"
        );
    }
}

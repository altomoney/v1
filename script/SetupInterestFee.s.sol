// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

string constant ADDRESSES_FILE =
    "./contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

uint256 constant COLLATERAL_BUFFER = 2;
uint256 constant TENDERLY_GAS_FUNDING_WEI = 100 ether;

/// @title SetupInterestFeeScript
/// @notice Tests interestFee behavior for borrow markets on Tenderly Virtual TestNet (same-block and different-block txs).
/// @dev All txs are sent via eth_sendTransaction (vm.rpc) so they execute immediately and in order on Tenderly.
///      Run: MARKET=susde NUM_USERS=10 forge script script/SetupInterestFee.s.sol --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC --slow -vvv
///      Env: MARKET (required), NUM_USERS (default 10). Phase 1 uses first half of users, Phase 2 the rest.
///      See https://docs.tenderly.co/virtual-testnets/admin-rpc
contract SetupInterestFeeScript is Script {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    uint256 constant INTEREST_FEE = 0.05 ether; // 5%
    uint256 constant BLOCKS_TO_FORWARD = 1;
    uint256 constant TIME_TO_FORWARD = 12; // 12 seconds

    address market;
    address dusd;
    address timelock;

    address collateralToken;
    uint256 collateralDecimals;

    uint256 numUsers;
    uint256 phase1UserCount;
    address[] users;

    function run() public {
        string memory marketName = vm.envString("MARKET");
        numUsers = vm.envOr("NUM_USERS", uint256(6));
        phase1UserCount = numUsers / 2;

        console.log("=========================================");
        console.log("  Interest Fee Test Script (Tenderly)");
        console.log("=========================================");
        console.log("Market:", marketName);
        console.log("Num users:", numUsers);

        _loadDeployment(marketName);

        collateralToken = IMarket(market).collateralToken();
        collateralDecimals = IERC20Metadata(collateralToken).decimals();

        console.log("Market address:", market);
        console.log("Collateral token:", collateralToken);
        console.log("Collateral decimals:", collateralDecimals);
        console.log("DUSD:", dusd);
        console.log("Timelock:", timelock);

        _generateUsers();
        _fundTimelockAndUsers();
        _runBorrowMarketTest();

        console.log("\n=========================================");
        console.log("  Test Script Completed Successfully");
        console.log("=========================================");
    }

    function _collateralForBorrow(uint256 borrowAmount) internal view returns (uint256) {
        uint256 oraclePrice = IOracle(IMarket(market).oracle()).getPrice();
        uint256 maxLtv = IMarket(market).maxLtv();
        uint256 collateralValueDusd = (borrowAmount * MATH_PRECISION) / maxLtv;
        return (collateralValueDusd * LENDING_ORACLE_PRICE_PRECISION * COLLATERAL_BUFFER) / oraclePrice;
    }

    function _loadDeployment(string memory marketName) internal {
        string memory json = vm.readFile(ADDRESSES_FILE);
        dusd = vm.parseJsonAddress(json, ".contracts.dusd");
        timelock = vm.parseJsonAddress(json, ".contracts.timelock");

        string memory borrowKey = string.concat(".contracts.", marketName, "BorrowMarket");
        market = vm.parseJsonAddress(json, borrowKey);
        require(market != address(0), "Borrow market not found in addresses.json");
    }

    function _generateUsers() internal {
        console.log("\n=== Generated user addresses ===");
        for (uint256 i = 0; i < numUsers; i++) {
            address user = vm.addr(uint256(keccak256(abi.encodePacked("interestFeeTestUser", i))));
            users.push(user);
            console.log(string.concat("  User ", vm.toString(i + 1), ":"), user);
        }
    }

    function _tenderlySendTransaction(address from, address to, bytes memory data) internal {
        string memory params = string.concat(
            '[{"from":"',
            vm.toString(from),
            '","to":"',
            vm.toString(to),
            '","value":"0x0","data":"',
            vm.toString(data),
            '"}]'
        );
        vm.rpc("eth_sendTransaction", params);
    }

    function _tenderlyIncreaseBlocksAndTime(uint256 blocks, uint256 time) internal {
        try vm.rpc("evm_increaseBlocks", string.concat('["', _toCompactHex(blocks), '"]')) returns (bytes memory) {}
            catch {}
        try vm.rpc("evm_increaseTime", string.concat('["', _toCompactHex(time), '"]')) returns (bytes memory) {}
            catch {}
    }

    function _tenderlySetBalance(address wallet, uint256 amountWei) internal {
        vm.rpc("tenderly_setBalance", string.concat('["', vm.toString(wallet), '","', _toCompactHex(amountWei), '"]'));
    }

    function _tenderlySetErc20Balance(address token, address wallet, uint256 amount) internal {
        vm.rpc(
            "tenderly_setErc20Balance",
            string.concat('["', vm.toString(token), '","', vm.toString(wallet), '","', _toCompactHex(amount), '"]')
        );
    }

    function _fundTimelockAndUsers() internal {
        console.log("Funding timelock + users on Tenderly...");

        _tenderlySetBalance(timelock, TENDERLY_GAS_FUNDING_WEI);

        for (uint256 i = 0; i < numUsers; i++) {
            _tenderlySetBalance(users[i], TENDERLY_GAS_FUNDING_WEI);
        }

        console.log(string.concat("  Timelock + ", vm.toString(numUsers), " users funded (ETH)"));
    }

    function _runBorrowMarketTest() internal {
        _enableInterestFee();

        _borrowMarketPhase1_Supply();

        _forwardBlocksAndTime();

        _borrowMarketPhase2_Borrow();

        _forwardBlocksAndTime();

        _borrowMarketPhase3();
    }

    function _enableInterestFee() internal {
        console.log("\n=== Enabling interestFee (5%) on borrow market ===");

        _tenderlySendTransaction(
            timelock, market, abi.encodeWithSelector(AltoBorrowMarket.setInterestFee.selector, INTEREST_FEE, false)
        );
    }

    function _borrowMarketPhase1_Supply() internal {
        console.log(
            string.concat("\n=== Phase 1: Supply DUSD (same block) - Users 1-", vm.toString(phase1UserCount), " ===")
        );

        uint256 baseSupply = 5000 * 1e18;

        for (uint256 i = 0; i < phase1UserCount; i++) {
            uint256 supplyAmount = baseSupply + (i * 1000 * 1e18);

            _tenderlySetErc20Balance(dusd, users[i], supplyAmount);
            _tenderlySendTransaction(
                users[i], dusd, abi.encodeWithSelector(IERC20.approve.selector, market, supplyAmount)
            );
            _tenderlySendTransaction(
                users[i], market, abi.encodeWithSelector(IMarketBase.addSupply.selector, supplyAmount, 0, users[i])
            );

            console.log(string.concat("  User ", vm.toString(i + 1), " supplied:"), supplyAmount / 1e18, "DUSD");
        }
    }

    function _borrowMarketPhase2_Borrow() internal {
        console.log(
            string.concat(
                "\n=== Phase 2: Collateral + Borrow (same block) - Users ",
                vm.toString(phase1UserCount + 1),
                "-",
                vm.toString(numUsers),
                " ==="
            )
        );

        uint256 baseBorrow = 1000 * 1e18;

        for (uint256 i = phase1UserCount; i < numUsers; i++) {
            uint256 borrowAmount = baseBorrow + ((i - phase1UserCount) * 1000 * 1e18);
            uint256 collateralAmount = _collateralForBorrow(borrowAmount);

            _tenderlySetErc20Balance(collateralToken, users[i], collateralAmount);
            _tenderlySendTransaction(
                users[i], collateralToken, abi.encodeWithSelector(IERC20.approve.selector, market, collateralAmount)
            );
            _tenderlySendTransaction(
                users[i], market, abi.encodeWithSelector(IMarketBase.addCollateral.selector, collateralAmount, users[i])
            );
            _tenderlySendTransaction(
                users[i],
                market,
                abi.encodeWithSelector(IMarketBase.borrow.selector, borrowAmount, 0, users[i], users[i], "")
            );

            console.log(
                string.concat("  User ", vm.toString(i + 1), " added collateral:"),
                collateralAmount / (10 ** collateralDecimals),
                "units"
            );
            console.log("    borrowed:", borrowAmount / 1e18, "DUSD");
        }
    }

    function _borrowMarketPhase3() internal {
        console.log(
            string.concat(
                "\n=== Phase 3: Supply + Collateral + Borrow (different blocks) - Users 1-",
                vm.toString(numUsers),
                " ==="
            )
        );

        for (uint256 i = 0; i < numUsers; i++) {
            uint256 supplyAmount = 1000 * 1e18 + (i * 1000 * 1e18);

            _tenderlySetErc20Balance(dusd, users[i], supplyAmount);
            _tenderlySendTransaction(
                users[i], dusd, abi.encodeWithSelector(IERC20.approve.selector, market, supplyAmount)
            );
            _tenderlySendTransaction(
                users[i], market, abi.encodeWithSelector(IMarketBase.addSupply.selector, supplyAmount, 0, users[i])
            );

            console.log(string.concat("  User ", vm.toString(i + 1), " supplied:"), supplyAmount / 1e18, "DUSD");

            _tenderlyIncreaseBlocksAndTime(1, 12);

            uint256 borrowAmount = (500 + i * 100) * 1e18;
            uint256 collateralAmount = _collateralForBorrow(borrowAmount);

            _tenderlySetErc20Balance(collateralToken, users[i], collateralAmount);
            _tenderlySendTransaction(
                users[i], collateralToken, abi.encodeWithSelector(IERC20.approve.selector, market, collateralAmount)
            );
            _tenderlySendTransaction(
                users[i], market, abi.encodeWithSelector(IMarketBase.addCollateral.selector, collateralAmount, users[i])
            );

            console.log(
                string.concat("  User ", vm.toString(i + 1), " added collateral:"),
                collateralAmount / (10 ** collateralDecimals),
                "units"
            );

            _tenderlyIncreaseBlocksAndTime(1, 12);

            _tenderlySendTransaction(
                users[i],
                market,
                abi.encodeWithSelector(IMarketBase.borrow.selector, borrowAmount, 0, users[i], users[i], "")
            );
            console.log("    borrowed:", borrowAmount / 1e18, "DUSD");

            _tenderlyIncreaseBlocksAndTime(1, 12);
        }
    }

    function _forwardBlocksAndTime() internal {
        console.log(
            string.concat(
                "\n>>> Forwarding ", vm.toString(BLOCKS_TO_FORWARD), " blocks + ", vm.toString(TIME_TO_FORWARD), "s"
            )
        );
        _tenderlyIncreaseBlocksAndTime(BLOCKS_TO_FORWARD, TIME_TO_FORWARD);

        _tenderlySendTransaction(users[0], market, abi.encodeWithSelector(IMarketBase.accrueInterest.selector));
    }

    function _toCompactHex(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0x0";
        uint256 temp = value;
        uint256 length;
        while (temp != 0) {
            length++;
            temp >>= 4;
        }
        bytes memory buf = new bytes(2 + length);
        buf[0] = "0";
        buf[1] = "x";
        temp = value;
        for (uint256 i = 2 + length; i > 2;) {
            unchecked {
                i--;
                uint8 nibble = uint8(temp & 0xf);
                buf[i] = nibble < 10 ? bytes1(uint8(0x30 + nibble)) : bytes1(uint8(0x57 + nibble));
                temp >>= 4;
            }
        }
        return string(buf);
    }
}

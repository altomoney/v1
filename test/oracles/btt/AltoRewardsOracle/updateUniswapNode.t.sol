// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleErrors,
    IAltoRewardsOracleEvents
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ModuleUniswap} from "@alto/oracles/modules/ModuleUniswap/ModuleUniswap.sol";
import {UniswapNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockUniswapPool} from "@alto-test/oracles/btt/mocks/MockUniswapPool.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";

contract AltoRewardsOracleUpdateUniswapNode is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;

    function setUp() public override {
        super.setUp();
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    modifier givenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function _createValidUniswapNode() internal view returns (UniswapNode memory) {
        return UniswapNode({
            pool: IUniswapV3Pool(address(mockPool)),
            twapPeriod: DEFAULT_TWAP_PERIOD,
            direction: ConversionDirection.IN_TO_OUT
        });
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        UniswapNode memory validNode = _createValidUniswapNode();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateUniswapNode(validNode);
    }

    function test_RevertWhen_PoolIsZeroAddress() external givenCallerIsOwner {
        UniswapNode memory invalidNode = _createValidUniswapNode();
        invalidNode.pool = IUniswapV3Pool(address(0));

        vm.expectRevert(ModuleUniswap.ModuleUniswapInvalidInput.selector);
        oracle.updateUniswapNode(invalidNode);
    }

    function test_RevertWhen_TwapPeriodIsZero() external givenCallerIsOwner {
        UniswapNode memory invalidNode = _createValidUniswapNode();
        invalidNode.twapPeriod = 0;

        vm.expectRevert(ModuleUniswap.ModuleUniswapInvalidInput.selector);
        oracle.updateUniswapNode(invalidNode);
    }

    function test_RevertWhen_InTokenIsNotAltoToken_WhenDirectionIsInToOut() external givenCallerIsOwner {
        UniswapNode memory invalidNode = _createValidUniswapNode();
        invalidNode.direction = ConversionDirection.IN_TO_OUT;

        // Create a non-ALTO token
        ERC20MockDecimals nonAltoToken = new ERC20MockDecimals("Wrapped Ether", "WETH", 18);
        address otherToken = MockUniswapPool(address(invalidNode.pool)).outToken();

        // Set non-ALTO token as token0 (which is the inToken for IN_TO_OUT direction)
        MockUniswapPool(address(invalidNode.pool)).setTokens(address(nonAltoToken), otherToken);

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        oracle.updateUniswapNode(invalidNode);
    }

    function test_RevertWhen_InTokenIsNotAltoToken_WhenDirectionIsOutToIn() external givenCallerIsOwner {
        UniswapNode memory invalidNode = _createValidUniswapNode();
        invalidNode.direction = ConversionDirection.OUT_TO_IN;

        // Create a non-ALTO token
        ERC20MockDecimals nonAltoToken = new ERC20MockDecimals("Wrapped Ether", "WETH", 18);
        address otherToken = MockUniswapPool(address(invalidNode.pool)).outToken();

        // Set non-ALTO token as token1 (which is the inToken for OUT_TO_IN direction)
        MockUniswapPool(address(invalidNode.pool)).setTokens(otherToken, address(nonAltoToken));

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        oracle.updateUniswapNode(invalidNode);
    }

    function test_ShouldEmitSetUniswapNodeEvent_WhenUniswapNodeIsValid() external givenCallerIsOwner {
        UniswapNode memory newUniswapNode = _createValidUniswapNode();
        newUniswapNode.twapPeriod = 2 hours; // Different value to ensure change
        newUniswapNode.direction = ConversionDirection.OUT_TO_IN; // Different value to ensure change
        address altoToken = MockUniswapPool(address(newUniswapNode.pool)).inToken();
        address otherToken = MockUniswapPool(address(newUniswapNode.pool)).outToken();
        MockUniswapPool(address(newUniswapNode.pool)).setTokens(otherToken, altoToken);

        // Get current uniswap node
        (IUniswapV3Pool pool, ConversionDirection direction, uint32 twapPeriod) = oracle.uniswapNode();
        UniswapNode memory oldUniswapNode = UniswapNode({pool: pool, twapPeriod: twapPeriod, direction: direction});

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.SetUniswapNode(oldUniswapNode, newUniswapNode);

        oracle.updateUniswapNode(newUniswapNode);

        // Verify the uniswap node was updated
        (pool, direction, twapPeriod) = oracle.uniswapNode();
        assertEq(address(pool), address(newUniswapNode.pool), "Pool should be updated");
        assertEq(uint8(direction), uint8(newUniswapNode.direction), "Direction should be updated");
        assertEq(twapPeriod, newUniswapNode.twapPeriod, "TWAP period should be updated");
        // Verify inTokenOneUnit updated to match in-currency decimals
        assertEq(oracle.inTokenOneUnit(), 10 ** 18, "inTokenOneUnit should be 1e18 for mock in-token");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    CowOrderAnalytics,
    CowOrderData,
    GenerateLiquidityIncentivesTransactionsScript,
    ICowSettlement,
    IMulticall3,
    IUniversalRewardsDistributor,
    IVotium,
    LiquidityIncentivesSafeTx,
    StakeDaoClaimData
} from "../../script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol";

contract GenerateLiquidityIncentivesTransactionsTest is Test {
    GenerateLiquidityIncentivesTransactionsScript internal generator;

    function setUp() public {
        generator = new GenerateLiquidityIncentivesTransactionsScript();
    }

    function test_GetClaimTransactions_encodesActionsCAndD() public view {
        StakeDaoClaimData memory claimData = _claimData();
        LiquidityIncentivesSafeTx[] memory txs = generator.getClaimTransactions(claimData);

        assertEq(txs.length, 2);
        assertEq(txs[0].to, generator.MULTICALL3());
        assertEq(_selector(txs[0].data), IMulticall3.aggregate3.selector);
        IMulticall3.Call3[] memory claimCalls = abi.decode(_arguments(txs[0].data), (IMulticall3.Call3[]));
        assertEq(claimCalls.length, 1);
        assertEq(claimCalls[0].target, generator.STAKEDAO_DELEGATOR_DISTRIBUTOR());
        assertFalse(claimCalls[0].allowFailure, "Action C must fail closed");
        assertEq(_selector(claimCalls[0].callData), IUniversalRewardsDistributor.claim.selector);
        (address account, address reward, uint256 cumulativeAmount, bytes32[] memory proof) =
            abi.decode(_arguments(claimCalls[0].callData), (address, address, uint256, bytes32[]));
        assertEq(account, generator.TREASURY_SAFE());
        assertEq(reward, generator.SCRVUSD());
        assertEq(cumulativeAmount, claimData.cumulativeAmount);
        assertEq(proof, claimData.proof);

        assertEq(txs[1].to, generator.CONVEX_CLAIM_ZAP());
        assertEq(
            keccak256(txs[1].data),
            0xdeaeb80670be5e770de72dd6f8db75a819e8020b36976cd76c9e10ca57f66708,
            "Action D must exactly match the supplied ClaimZap calldata"
        );
    }

    function test_GetConsolidationTransactions_encodesRedeemApprovalsAndPresignatures() public view {
        CowOrderData[] memory orders = new CowOrderData[](2);
        orders[0] = _cowOrder(generator.CRV(), 100 ether, 20 ether, 1);
        orders[1] = _cowOrder(generator.CVX(), 50 ether, 100 ether, 2);
        LiquidityIncentivesSafeTx[] memory txs = generator.getConsolidationTransactions(10 ether, orders);

        assertEq(txs.length, 5);
        assertEq(txs[0].to, generator.SCRVUSD());
        assertEq(_selector(txs[0].data), IERC4626.redeem.selector);
        (uint256 shares, address receiver, address owner) =
            abi.decode(_arguments(txs[0].data), (uint256, address, address));
        assertEq(shares, 10 ether);
        assertEq(receiver, generator.TREASURY_SAFE());
        assertEq(owner, generator.TREASURY_SAFE());

        _assertCowTransactions(txs[1], txs[2], orders[0]);
        _assertCowTransactions(txs[3], txs[4], orders[1]);
    }

    function test_GetConsolidationTransactions_rejectsWrongOrderOwner() public {
        CowOrderData[] memory orders = new CowOrderData[](1);
        orders[0] = _cowOrder(generator.CRV(), 100 ether, 20 ether, 1);
        orders[0].orderUid =
            abi.encodePacked(bytes32(uint256(1)), bytes20(makeAddr("wrong-owner")), bytes4(uint32(1_900_000_000)));

        vm.expectRevert(bytes("CoW order UID owner mismatch"));
        generator.getConsolidationTransactions(0, orders);
    }

    function test_GetVotiumTransactions_approvesExactCrvUsdAndDeposits() public view {
        uint256 amount = 100 ether;
        LiquidityIncentivesSafeTx[] memory txs = generator.getVotiumTransactions(amount);
        assertEq(txs.length, 2);
        assertEq(txs[0].to, generator.CRVUSD());
        (address spender, uint256 approvalAmount) = abi.decode(_arguments(txs[0].data), (address, uint256));
        assertEq(spender, generator.VOTIUM());
        assertEq(approvalAmount, amount);

        assertEq(txs[1].to, generator.VOTIUM());
        (address token, uint256 depositAmount, address gauge) =
            abi.decode(_arguments(txs[1].data), (address, uint256, address));
        assertEq(token, generator.CRVUSD());
        assertEq(depositAmount, amount);
        assertEq(gauge, generator.DUSD_FRXUSD_GAUGE());
    }

    function test_GetVotiumTransactions_rejectsZeroAmount() public {
        vm.expectRevert(bytes("zero Votium incentive amount"));
        generator.getVotiumTransactions(0);
    }

    function test_BuildJson_writesSafeBatchAndCowManifest() public view {
        LiquidityIncentivesSafeTx[] memory txs = generator.getVotiumTransactions(100 ether);
        string memory safeJson = generator.buildSafeBatchJson("test-votium", txs);
        assertEq(vm.parseJsonString(safeJson, ".meta.name"), "test-votium");
        assertEq(vm.parseJsonAddress(safeJson, ".transactions[0].to"), generator.CRVUSD());

        CowOrderData[] memory orders = new CowOrderData[](1);
        orders[0] = _cowOrder(generator.CRV(), 100 ether, 20 ether, 1);
        string memory orderJson = generator.buildCowOrdersJson(orders);
        assertEq(vm.parseJsonAddress(orderJson, ".orders[0].sellToken"), generator.CRV());
        assertEq(vm.parseJsonString(orderJson, ".orders[0].sellAmount"), vm.toString(uint256(100 ether)));
        assertEq(vm.parseJsonBytes(orderJson, ".orders[0].orderUid"), orders[0].orderUid);
        assertEq(vm.parseJsonString(orderJson, ".orders[0].analytics.expectedPriceImpactBps"), "0.00");
        assertEq(vm.parseJsonString(orderJson, ".orders[0].analytics.worstCasePriceImpactBps"), "0.00");
        assertEq(vm.parseJsonString(orderJson, ".orders[0].analytics.inputDisplay"), "100 CRV ($100.000000)");
    }

    function _assertCowTransactions(
        LiquidityIncentivesSafeTx memory approvalTx,
        LiquidityIncentivesSafeTx memory presignTx,
        CowOrderData memory order
    ) internal view {
        assertEq(approvalTx.to, order.sellToken);
        assertEq(_selector(approvalTx.data), IERC20.approve.selector);
        (address spender, uint256 amount) = abi.decode(_arguments(approvalTx.data), (address, uint256));
        assertEq(spender, generator.COW_VAULT_RELAYER());
        assertEq(amount, order.sellAmount);

        assertEq(presignTx.to, generator.COW_SETTLEMENT());
        assertEq(_selector(presignTx.data), ICowSettlement.setPreSignature.selector);
        (bytes memory orderUid, bool signed) = abi.decode(_arguments(presignTx.data), (bytes, bool));
        assertEq(orderUid, order.orderUid);
        assertTrue(signed);
    }

    function _cowOrder(address sellToken, uint256 sellAmount, uint256 buyAmount, uint256 salt)
        internal
        view
        returns (CowOrderData memory order)
    {
        uint256 validTo = 1_900_000_000;
        CowOrderAnalytics memory analytics;
        analytics.quotedBuyAmount = buyAmount;
        analytics.slippageBps = 0;
        analytics.methodology = "test";
        analytics.priceReferenceSource = "CoW Swap BFF USD prices";
        analytics.priceReferenceTimestamp = "2026-07-20T12:00:00.000Z";
        analytics.sellTokenSymbol = sellToken == generator.CRV() ? "CRV" : "CVX";
        analytics.buyTokenSymbol = "crvUSD";
        analytics.inputDisplay = sellToken == generator.CRV() ? "100 CRV ($100.000000)" : "50 CVX ($50.000000)";
        analytics.expectedOutputDisplay = "20 crvUSD ($20.000000)";
        analytics.minimumOutputDisplay = "20 crvUSD ($20.000000)";
        analytics.expectedPriceImpactBps = "0.00";
        analytics.expectedPriceImpactPercent = "0.0000%";
        analytics.worstCasePriceImpactBps = "0.00";
        analytics.worstCasePriceImpactPercent = "0.0000%";
        order = CowOrderData({
            sellToken: sellToken,
            buyToken: generator.CRVUSD(),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            orderUid: abi.encodePacked(bytes32(salt), bytes20(generator.TREASURY_SAFE()), bytes4(uint32(validTo))),
            analytics: analytics
        });
    }

    function _claimData() internal pure returns (StakeDaoClaimData memory claimData) {
        claimData.merkleRoot = 0xd156ef0150e702ec9c52e8ea4dacdea2d799130546e2778334cc2cc25ad289ce;
        claimData.cumulativeAmount = 414_776771874655079324;
        claimData.alreadyClaimed = 0;
        claimData.unclaimedAmount = claimData.cumulativeAmount;
        claimData.proof = _proof();
    }

    function _proof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](10);
        proof[0] = 0x4a8c5f2c7ec5ded7f39b8d43b2332d99352482859f6c0c2b0dd8fa3fd524a4d6;
        proof[1] = 0xf94f35ba572353b45afc64d26079e94d51886d212e4b529e032af24cb8782494;
        proof[2] = 0xca66a46677e64e8d23ade84301f2dc2c6b9e2695e9ec9b8d0c931ad14cb04f28;
        proof[3] = 0x48421984bd26a1f6bf035f749ad908e9fb5fa362c8b6c563785a7f4cdce74037;
        proof[4] = 0xe60f9fa6c1f992355def235671aa7540061c919796dc02d99c806ba74bb9f9bf;
        proof[5] = 0x6b3d29ccfa8678cfb64c892f6f0dff86b13050e2aae80a6d1accce4cf32316ff;
        proof[6] = 0xc35a1bb3e728704b70c056825b01d5d368efb7d2e197ccdc81591eec6ed35b89;
        proof[7] = 0x8533b5982213b2b04541ab017459b337fad9d7e793b33a0c9e26eade00f7539a;
        proof[8] = 0x8833bcacbb732fd3c866f73f77b7ca3c3e765224e0b01546bda6182d9e7ca8b5;
        proof[9] = 0xc8cbb2f134304fe5a8c8bedc7ed2d586bfb1b16efff06e259f90bcce3ec2ca6d;
    }

    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        require(data.length >= 4, "missing selector");
        assembly ("memory-safe") {
            selector := mload(add(data, 0x20))
        }
    }

    function _arguments(bytes memory data) internal pure returns (bytes memory arguments) {
        require(data.length >= 4, "missing selector");
        arguments = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; ++i) {
            arguments[i - 4] = data[i];
        }
    }
}

contract GenerateLiquidityIncentivesTransactionsForkTest is Test {
    uint256 internal constant FORK_BLOCK = 25_573_120;

    GenerateLiquidityIncentivesTransactionsScript internal generator;

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETHEREUM_RPC_URL", string("https://rpc.stakedao.org/main/evm/1"));
        vm.createSelectFork(rpcUrl, FORK_BLOCK);
        generator = new GenerateLiquidityIncentivesTransactionsScript();
    }

    function test_Fork_claimPhaseExecutesAsTreasurySafe() public {
        StakeDaoClaimData memory claimData = _claimData();
        LiquidityIncentivesSafeTx[] memory txs = generator.getClaimTransactions(claimData);
        generator.validateAndSimulateClaimTransactions(txs, claimData);
        assertEq(
            IUniversalRewardsDistributor(generator.STAKEDAO_DELEGATOR_DISTRIBUTOR())
                .claimed(generator.TREASURY_SAFE(), generator.SCRVUSD()),
            0,
            "claim simulation must revert state"
        );
    }

    function test_Fork_consolidationPhaseRedeemsAndPresigns() public {
        uint256 scrvUsdAmount = 10 ether;
        deal(generator.SCRVUSD(), generator.TREASURY_SAFE(), scrvUsdAmount);
        deal(generator.CRV(), generator.TREASURY_SAFE(), 100 ether);
        deal(generator.CVX(), generator.TREASURY_SAFE(), 50 ether);

        CowOrderData[] memory orders = new CowOrderData[](2);
        orders[0] = _cowOrder(generator.CRV(), 100 ether, 20 ether, 1);
        orders[1] = _cowOrder(generator.CVX(), 50 ether, 100 ether, 2);
        LiquidityIncentivesSafeTx[] memory txs = generator.getConsolidationTransactions(scrvUsdAmount, orders);
        generator.validateAndSimulateConsolidationTransactions(txs, scrvUsdAmount, orders);
    }

    function test_Fork_votiumPhaseUsesSettledCrvUsd() public {
        uint256 incentiveAmount = 100 ether;
        deal(generator.CRVUSD(), generator.TREASURY_SAFE(), incentiveAmount);
        LiquidityIncentivesSafeTx[] memory txs = generator.getVotiumTransactions(incentiveAmount);
        uint256 round = generator.validateAndSimulateVotiumTransactions(txs, incentiveAmount);
        assertEq(round, IVotium(generator.VOTIUM()).activeRound());
    }

    function test_Fork_votiumPhaseRejectsUnsettledAmount() public {
        uint256 currentBalance = IERC20(generator.CRVUSD()).balanceOf(generator.TREASURY_SAFE());
        LiquidityIncentivesSafeTx[] memory txs = generator.getVotiumTransactions(currentBalance + 1);
        vm.expectRevert(bytes("insufficient settled crvUSD balance"));
        generator.validateAndSimulateVotiumTransactions(txs, currentBalance + 1);
    }

    function _cowOrder(address sellToken, uint256 sellAmount, uint256 buyAmount, uint256 salt)
        internal
        view
        returns (CowOrderData memory order)
    {
        uint256 validTo = 1_900_000_000;
        CowOrderAnalytics memory analytics;
        analytics.quotedBuyAmount = buyAmount;
        analytics.priceReferenceSource = "CoW Swap BFF USD prices";
        analytics.expectedPriceImpactBps = "0.00";
        analytics.worstCasePriceImpactBps = "0.00";
        order = CowOrderData({
            sellToken: sellToken,
            buyToken: generator.CRVUSD(),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            orderUid: abi.encodePacked(bytes32(salt), bytes20(generator.TREASURY_SAFE()), bytes4(uint32(validTo))),
            analytics: analytics
        });
    }

    function _claimData() internal pure returns (StakeDaoClaimData memory claimData) {
        claimData.merkleRoot = 0xd156ef0150e702ec9c52e8ea4dacdea2d799130546e2778334cc2cc25ad289ce;
        claimData.cumulativeAmount = 414_776771874655079324;
        claimData.alreadyClaimed = 0;
        claimData.unclaimedAmount = claimData.cumulativeAmount;
        claimData.proof = new bytes32[](10);
        claimData.proof[0] = 0x4a8c5f2c7ec5ded7f39b8d43b2332d99352482859f6c0c2b0dd8fa3fd524a4d6;
        claimData.proof[1] = 0xf94f35ba572353b45afc64d26079e94d51886d212e4b529e032af24cb8782494;
        claimData.proof[2] = 0xca66a46677e64e8d23ade84301f2dc2c6b9e2695e9ec9b8d0c931ad14cb04f28;
        claimData.proof[3] = 0x48421984bd26a1f6bf035f749ad908e9fb5fa362c8b6c563785a7f4cdce74037;
        claimData.proof[4] = 0xe60f9fa6c1f992355def235671aa7540061c919796dc02d99c806ba74bb9f9bf;
        claimData.proof[5] = 0x6b3d29ccfa8678cfb64c892f6f0dff86b13050e2aae80a6d1accce4cf32316ff;
        claimData.proof[6] = 0xc35a1bb3e728704b70c056825b01d5d368efb7d2e197ccdc81591eec6ed35b89;
        claimData.proof[7] = 0x8533b5982213b2b04541ab017459b337fad9d7e793b33a0c9e26eade00f7539a;
        claimData.proof[8] = 0x8833bcacbb732fd3c866f73f77b7ca3c3e765224e0b01546bda6182d9e7ca8b5;
        claimData.proof[9] = 0xc8cbb2f134304fe5a8c8bedc7ed2d586bfb1b16efff06e259f90bcce3ec2ca6d;
    }
}

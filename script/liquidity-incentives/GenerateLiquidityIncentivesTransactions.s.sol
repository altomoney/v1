// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IUniversalRewardsDistributor {
    function root() external view returns (bytes32);
    function recipients(address account) external view returns (address);
    function claimed(address account, address reward) external view returns (uint256);
    function claim(address account, address reward, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount);
}

interface IConvexBaseRewardPool {
    function earned(address account) external view returns (uint256);
}

interface IConvexClaimZap {
    function claimRewards(
        address[] calldata rewardContracts,
        address[] calldata extraRewardContracts,
        address[] calldata tokenRewardContracts,
        address[] calldata tokenRewardTokens,
        uint256 depositCrvMaxAmount,
        uint256 minAmountOut,
        uint256 depositCvxMaxAmount,
        uint256 spendCvxAmount,
        uint256 options
    ) external;
}

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);
}

interface ICowSettlement {
    function vaultRelayer() external view returns (address);
    function preSignature(bytes calldata orderUid) external view returns (uint256);
    function setPreSignature(bytes calldata orderUid, bool signed) external;
}

interface IVotium {
    function DENOMINATOR() external view returns (uint256);
    function activeRound() external view returns (uint256);
    function incentivesLength(uint256 round, address gauge) external view returns (uint256);
    function platformFee() external view returns (uint256);
    function requireAllowlist() external view returns (bool);
    function tokenAllowed(address token) external view returns (bool);

    function incentives(uint256 round, address gauge, uint256 index)
        external
        view
        returns (
            address token,
            uint256 amount,
            uint256 maxPerVote,
            uint256 distributed,
            uint256 recycled,
            address depositor
        );

    function depositIncentiveSimple(address token, uint256 amount, address gauge) external;
}

struct LiquidityIncentivesSafeTx {
    address to;
    bytes data;
}

struct StakeDaoClaimData {
    bytes32 merkleRoot;
    uint256 cumulativeAmount;
    uint256 alreadyClaimed;
    uint256 unclaimedAmount;
    bytes32[] proof;
}

struct ClaimSimulationState {
    uint256 scrvUsdBefore;
    uint256 convexEarnedBefore;
    uint256 crvBefore;
    uint256 cvxBefore;
}

struct CowOrderAnalytics {
    uint256 quotedBuyAmount;
    uint256 networkFeeAmount;
    uint256 slippageBps;
    string methodology;
    string priceReferenceSource;
    string priceReferenceTimestamp;
    string sellTokenPriceUrl;
    string buyTokenPriceUrl;
    string sellTokenSymbol;
    string buyTokenSymbol;
    string sellAmountFormatted;
    string quotedBuyAmountFormatted;
    string minimumBuyAmountFormatted;
    string networkFeeAmountFormatted;
    string sellTokenUsdPrice;
    string buyTokenUsdPrice;
    string inputUsdValue;
    string expectedOutputUsdValue;
    string minimumOutputUsdValue;
    string inputDisplay;
    string expectedOutputDisplay;
    string minimumOutputDisplay;
    string expectedRate;
    string minimumRate;
    string networkFeeBps;
    string expectedPriceImpactBps;
    string expectedPriceImpactPercent;
    string worstCasePriceImpactBps;
    string worstCasePriceImpactPercent;
}

struct CowOrderData {
    address sellToken;
    address buyToken;
    uint256 sellAmount;
    uint256 buyAmount;
    uint256 validTo;
    bytes orderUid;
    CowOrderAnalytics analytics;
}

/// @title Generate staged Liquidity Incentive Management Safe transactions
/// @notice Generates claims, consolidation, or Votium Safe batches without crossing asynchronous settlement boundaries.
/// @dev Set LIQUIDITY_PHASE to `claims`, `consolidation`, or `votium`.
contract GenerateLiquidityIncentivesTransactionsScript is Script {
    address public constant TREASURY_SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    // Action C: Stake DAO's current vlCVX delegator UniversalRewardsDistributor.
    address public constant STAKEDAO_DELEGATOR_DISTRIBUTOR = 0x17F513CDE031C8B1E878Bde1Cb020cE29f77f380;
    address public constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    // Action D: current Convex ClaimZap payload for the DUSD/frxUSD POL reward pool.
    address public constant CONVEX_CLAIM_ZAP = 0x3f29cB4111CbdA8081642DA1f75B3c12DECf2516;
    address public constant CONVEX_REWARD_POOL = 0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // Consolidation: CoW Protocol contracts used by prior Safe nonce 66.
    address public constant COW_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant COW_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    // Action F2: Votium single-round crvUSD incentive for the DUSD/frxUSD Curve gauge.
    address public constant VOTIUM = 0x63942E31E98f1833A234077f47880A66136a2D1e;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant DUSD_FRXUSD_GAUGE = 0xA41eb3062FD68B6Fa9f11439C86503913806761D;

    string public constant STAKEDAO_MERKLE_URL = "https://raw.githubusercontent.com/stake-dao/bounties-report/refs/heads/main/"
        "bounties-reports/latest/vlCVX/vlcvx_merkle_delegators.json";
    string public constant COW_ORDER_HELPER = "script/liquidity-incentives/createCowPresignOrder.mjs";
    string public constant CLAIMS_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-01-claims.json";
    string public constant CONSOLIDATION_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-02-consolidation.json";
    string public constant COW_ORDERS_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-02-consolidation.json";
    string public constant VOTIUM_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-03-votium.json";

    string internal constant CLAIM_PATH = ".claims.0xA1148A1b94262540994Cf9Aa431A13ad39764228.tokens."
        "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367";

    function run() public {
        require(block.chainid == 1, "not Ethereum mainnet");
        string memory phase = vm.envString("LIQUIDITY_PHASE");

        if (_stringsEqual(phase, "claims")) _runClaims();
        else if (_stringsEqual(phase, "consolidation")) _runConsolidation();
        else if (_stringsEqual(phase, "votium")) _runVotium();
        else revert("LIQUIDITY_PHASE must be claims, consolidation, or votium");
    }

    function _runClaims() internal {
        StakeDaoClaimData memory claimData = fetchStakeDaoClaimData();
        LiquidityIncentivesSafeTx[] memory txs = getClaimTransactions(claimData);
        validateAndSimulateClaimTransactions(txs, claimData);
        vm.writeFile(CLAIMS_OUTPUT_PATH, buildSafeBatchJson("Liquidity 01 - Claims C and D", txs));

        console.log("Claims Safe JSON:", CLAIMS_OUTPUT_PATH);
        console.log("Stake DAO scrvUSD claim:", claimData.unclaimedAmount);
        console.log("Convex pending CRV before claim:", IConvexBaseRewardPool(CONVEX_REWARD_POOL).earned(TREASURY_SAFE));
    }

    function _runConsolidation() internal {
        uint256 scrvUsdAmount = vm.envOr("CONSOLIDATE_SCRVUSD_AMOUNT", uint256(0));
        uint256 crvAmount = vm.envOr("CONSOLIDATE_CRV_AMOUNT", uint256(0));
        uint256 cvxAmount = vm.envOr("CONSOLIDATE_CVX_AMOUNT", uint256(0));
        require(scrvUsdAmount > 0 || crvAmount > 0 || cvxAmount > 0, "no consolidation amount selected");
        _validateConsolidationBalances(scrvUsdAmount, crvAmount, cvxAmount);

        uint256 cowOrderCount = (crvAmount > 0 ? 1 : 0) + (cvxAmount > 0 ? 1 : 0);
        CowOrderData[] memory orders = new CowOrderData[](cowOrderCount);
        if (cowOrderCount > 0) {
            require(vm.envOr("COW_SUBMIT_ORDERS", false), "set COW_SUBMIT_ORDERS=true to post orders");
            uint256 slippageBps = vm.envUint("COW_SLIPPAGE_BPS");
            uint256 validFor = vm.envUint("COW_ORDER_VALIDITY_SECONDS");
            require(slippageBps <= 1_000, "CoW slippage exceeds 10%");
            require(validFor >= 1_800 && validFor <= 604_800, "CoW validity must be 1800-604800 seconds");

            uint256 orderIndex;
            if (crvAmount > 0) orders[orderIndex++] = _createCowOrder(CRV, crvAmount, slippageBps, validFor);
            if (cvxAmount > 0) orders[orderIndex] = _createCowOrder(CVX, cvxAmount, slippageBps, validFor);
        }

        LiquidityIncentivesSafeTx[] memory txs = getConsolidationTransactions(scrvUsdAmount, orders);
        validateAndSimulateConsolidationTransactions(txs, scrvUsdAmount, orders);
        vm.writeFile(CONSOLIDATION_OUTPUT_PATH, buildSafeBatchJson("Liquidity 02 - Consolidate rewards to crvUSD", txs));
        vm.writeFile(COW_ORDERS_OUTPUT_PATH, buildCowOrdersJson(orders));

        console.log("Consolidation Safe JSON:", CONSOLIDATION_OUTPUT_PATH);
        console.log("CoW order manifest:", COW_ORDERS_OUTPUT_PATH);
        console.log("scrvUSD shares selected:", scrvUsdAmount);
        console.log("CoW orders posted:", orders.length);
    }

    function _runVotium() internal {
        uint256 incentiveAmount = vm.envUint("VOTIUM_INCENTIVE_AMOUNT");
        LiquidityIncentivesSafeTx[] memory txs = getVotiumTransactions(incentiveAmount);
        uint256 votiumRound = validateAndSimulateVotiumTransactions(txs, incentiveAmount);
        vm.writeFile(VOTIUM_OUTPUT_PATH, buildSafeBatchJson("Liquidity 03 - Votium F2", txs));

        console.log("Votium Safe JSON:", VOTIUM_OUTPUT_PATH);
        console.log("crvUSD incentive amount:", incentiveAmount);
        console.log("Votium round:", votiumRound);
    }

    /// @notice Downloads the current Stake DAO delegator merkle and validates it against mainnet.
    function fetchStakeDaoClaimData() public returns (StakeDaoClaimData memory claimData) {
        string[] memory command = new string[](8);
        command[0] = "curl";
        command[1] = "--location";
        command[2] = "--fail";
        command[3] = "--silent";
        command[4] = "--show-error";
        command[5] = "--max-time";
        command[6] = "30";
        command[7] = STAKEDAO_MERKLE_URL;

        string memory merkleJson = string(vm.ffi(command));
        claimData.merkleRoot = vm.parseJsonBytes32(merkleJson, ".merkleRoot");
        claimData.cumulativeAmount = vm.parseUint(vm.parseJsonString(merkleJson, string.concat(CLAIM_PATH, ".amount")));
        claimData.proof = vm.parseJsonBytes32Array(merkleJson, string.concat(CLAIM_PATH, ".proof"));

        IUniversalRewardsDistributor distributor = IUniversalRewardsDistributor(STAKEDAO_DELEGATOR_DISTRIBUTOR);
        require(distributor.root() == claimData.merkleRoot, "Stake DAO merkle root mismatch");
        address recipient = distributor.recipients(TREASURY_SAFE);
        require(recipient == address(0) || recipient == TREASURY_SAFE, "Stake DAO recipient is not treasury");

        claimData.alreadyClaimed = distributor.claimed(TREASURY_SAFE, SCRVUSD);
        require(claimData.cumulativeAmount > claimData.alreadyClaimed, "no Stake DAO rewards to claim");
        claimData.unclaimedAmount = claimData.cumulativeAmount - claimData.alreadyClaimed;
    }

    function getClaimTransactions(StakeDaoClaimData memory claimData)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        _validateClaimData(claimData);
        txs = new LiquidityIncentivesSafeTx[](2);

        IMulticall3.Call3[] memory claimCalls = new IMulticall3.Call3[](1);
        claimCalls[0] = IMulticall3.Call3({
            target: STAKEDAO_DELEGATOR_DISTRIBUTOR,
            allowFailure: false,
            callData: abi.encodeCall(
                IUniversalRewardsDistributor.claim,
                (TREASURY_SAFE, SCRVUSD, claimData.cumulativeAmount, claimData.proof)
            )
        });
        txs[0] = LiquidityIncentivesSafeTx({to: MULTICALL3, data: abi.encodeCall(IMulticall3.aggregate3, (claimCalls))});
        txs[1] = LiquidityIncentivesSafeTx({to: CONVEX_CLAIM_ZAP, data: _buildConvexClaimZapData()});
    }

    function getConsolidationTransactions(uint256 scrvUsdAmount, CowOrderData[] memory orders)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        require(scrvUsdAmount > 0 || orders.length > 0, "empty consolidation batch");
        uint256 txCount = (scrvUsdAmount > 0 ? 1 : 0) + orders.length * 2;
        txs = new LiquidityIncentivesSafeTx[](txCount);
        uint256 txIndex;

        if (scrvUsdAmount > 0) {
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: SCRVUSD, data: abi.encodeCall(IERC4626.redeem, (scrvUsdAmount, TREASURY_SAFE, TREASURY_SAFE))
            });
        }

        for (uint256 i = 0; i < orders.length; ++i) {
            _validateCowOrder(orders[i]);
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: orders[i].sellToken, data: abi.encodeCall(IERC20.approve, (COW_VAULT_RELAYER, orders[i].sellAmount))
            });
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: COW_SETTLEMENT, data: abi.encodeCall(ICowSettlement.setPreSignature, (orders[i].orderUid, true))
            });
        }
    }

    function getVotiumTransactions(uint256 incentiveAmount)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        require(incentiveAmount > 0, "zero Votium incentive amount");
        txs = new LiquidityIncentivesSafeTx[](2);
        txs[0] =
            LiquidityIncentivesSafeTx({to: CRVUSD, data: abi.encodeCall(IERC20.approve, (VOTIUM, incentiveAmount))});
        txs[1] = LiquidityIncentivesSafeTx({
            to: VOTIUM,
            data: abi.encodeCall(IVotium.depositIncentiveSimple, (CRVUSD, incentiveAmount, DUSD_FRXUSD_GAUGE))
        });
    }

    function validateAndSimulateClaimTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        StakeDaoClaimData memory claimData
    ) public {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(txs.length == 2, "unexpected claim transaction count");
        _validateClaimData(claimData);
        require(STAKEDAO_DELEGATOR_DISTRIBUTOR.code.length > 0, "Stake DAO distributor has no code");
        require(CONVEX_CLAIM_ZAP.code.length > 0, "Convex claim zap has no code");
        require(CONVEX_REWARD_POOL.code.length > 0, "Convex reward pool has no code");

        IUniversalRewardsDistributor distributor = IUniversalRewardsDistributor(STAKEDAO_DELEGATOR_DISTRIBUTOR);
        require(distributor.root() == claimData.merkleRoot, "Stake DAO merkle root changed");
        require(distributor.claimed(TREASURY_SAFE, SCRVUSD) == claimData.alreadyClaimed, "Stake DAO claim changed");

        ClaimSimulationState memory state = ClaimSimulationState({
            scrvUsdBefore: IERC20(SCRVUSD).balanceOf(TREASURY_SAFE),
            convexEarnedBefore: IConvexBaseRewardPool(CONVEX_REWARD_POOL).earned(TREASURY_SAFE),
            crvBefore: IERC20(CRV).balanceOf(TREASURY_SAFE),
            cvxBefore: IERC20(CVX).balanceOf(TREASURY_SAFE)
        });

        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);
        require(distributor.claimed(TREASURY_SAFE, SCRVUSD) == claimData.cumulativeAmount, "Action C claim mismatch");
        require(
            IERC20(SCRVUSD).balanceOf(TREASURY_SAFE) == state.scrvUsdBefore + claimData.unclaimedAmount,
            "Action C scrvUSD mismatch"
        );
        require(IConvexBaseRewardPool(CONVEX_REWARD_POOL).earned(TREASURY_SAFE) == 0, "Action D rewards remain");
        require(IERC20(CRV).balanceOf(TREASURY_SAFE) >= state.crvBefore, "Action D CRV balance decreased");
        require(IERC20(CVX).balanceOf(TREASURY_SAFE) >= state.cvxBefore, "Action D CVX balance decreased");
        if (state.convexEarnedBefore > 0) {
            require(IERC20(CRV).balanceOf(TREASURY_SAFE) > state.crvBefore, "Action D did not receive CRV");
            require(IERC20(CVX).balanceOf(TREASURY_SAFE) > state.cvxBefore, "Action D did not receive CVX");
        }
        require(vm.revertToState(snapshot), "failed to revert claim simulation");
    }

    function validateAndSimulateConsolidationTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        uint256 scrvUsdAmount,
        CowOrderData[] memory orders
    ) public {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(ICowSettlement(COW_SETTLEMENT).vaultRelayer() == COW_VAULT_RELAYER, "CoW relayer mismatch");
        require(IERC4626(SCRVUSD).asset() == CRVUSD, "scrvUSD asset is not crvUSD");
        require(txs.length == (scrvUsdAmount > 0 ? 1 : 0) + orders.length * 2, "wrong consolidation tx count");
        require(IERC20(SCRVUSD).balanceOf(TREASURY_SAFE) >= scrvUsdAmount, "insufficient scrvUSD balance");

        for (uint256 i = 0; i < orders.length; ++i) {
            _validateCowOrder(orders[i]);
            require(orders[i].validTo > block.timestamp + 15 minutes, "CoW order expires too soon");
            require(
                IERC20(orders[i].sellToken).balanceOf(TREASURY_SAFE) >= orders[i].sellAmount,
                "insufficient CoW sell balance"
            );
            for (uint256 j = 0; j < i; ++j) {
                require(orders[j].sellToken != orders[i].sellToken, "duplicate CoW sell token");
            }
        }

        uint256 scrvUsdBefore = IERC20(SCRVUSD).balanceOf(TREASURY_SAFE);
        uint256 crvUsdBefore = IERC20(CRVUSD).balanceOf(TREASURY_SAFE);
        uint256 expectedRedeemAssets = IERC4626(SCRVUSD).previewRedeem(scrvUsdAmount);
        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);

        require(IERC20(SCRVUSD).balanceOf(TREASURY_SAFE) == scrvUsdBefore - scrvUsdAmount, "scrvUSD redeem mismatch");
        require(
            IERC20(CRVUSD).balanceOf(TREASURY_SAFE) == crvUsdBefore + expectedRedeemAssets, "crvUSD redeem mismatch"
        );
        for (uint256 i = 0; i < orders.length; ++i) {
            require(
                IERC20(orders[i].sellToken).allowance(TREASURY_SAFE, COW_VAULT_RELAYER) == orders[i].sellAmount,
                "CoW allowance mismatch"
            );
            require(ICowSettlement(COW_SETTLEMENT).preSignature(orders[i].orderUid) != 0, "CoW presignature missing");
        }
        require(vm.revertToState(snapshot), "failed to revert consolidation simulation");
    }

    function validateAndSimulateVotiumTransactions(LiquidityIncentivesSafeTx[] memory txs, uint256 incentiveAmount)
        public
        returns (uint256 votiumRound)
    {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(txs.length == 2, "unexpected Votium transaction count");
        require(incentiveAmount > 0, "zero Votium incentive amount");
        require(IERC20(CRVUSD).balanceOf(TREASURY_SAFE) >= incentiveAmount, "insufficient settled crvUSD balance");

        IVotium votium = IVotium(VOTIUM);
        require(!votium.requireAllowlist() || votium.tokenAllowed(CRVUSD), "crvUSD is not Votium-allowed");
        votiumRound = votium.activeRound();
        uint256 incentiveCountBefore = votium.incentivesLength(votiumRound, DUSD_FRXUSD_GAUGE);
        uint256 balanceBefore = IERC20(CRVUSD).balanceOf(TREASURY_SAFE);
        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);

        require(IERC20(CRVUSD).balanceOf(TREASURY_SAFE) == balanceBefore - incentiveAmount, "F2 balance mismatch");
        require(IERC20(CRVUSD).allowance(TREASURY_SAFE, VOTIUM) == 0, "F2 allowance not consumed");
        require(
            votium.incentivesLength(votiumRound, DUSD_FRXUSD_GAUGE) == incentiveCountBefore + 1,
            "F2 incentive not created"
        );
        (address storedToken, uint256 storedAmount, uint256 maxPerVote,,, address depositor) =
            votium.incentives(votiumRound, DUSD_FRXUSD_GAUGE, incentiveCountBefore);
        uint256 fee = incentiveAmount * votium.platformFee() / votium.DENOMINATOR();
        require(fee > 0, "F2 amount is below minimum fee precision");
        require(storedToken == CRVUSD, "F2 stored token mismatch");
        require(storedAmount == incentiveAmount - fee, "F2 stored amount mismatch");
        require(maxPerVote == 0, "F2 max per vote mismatch");
        require(depositor == TREASURY_SAFE, "F2 depositor mismatch");
        require(vm.revertToState(snapshot), "failed to revert Votium simulation");
    }

    function buildSafeBatchJson(string memory name, LiquidityIncentivesSafeTx[] memory txs)
        public
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"', name, '","txBuilderVersion":"1.16.5"},"transactions":['
        );
        for (uint256 i = 0; i < txs.length; ++i) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(txs[i].to),
                '","value":"0","data":"',
                vm.toString(txs[i].data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }
        return string.concat(json, "]}");
    }

    function buildCowOrdersJson(CowOrderData[] memory orders) public pure returns (string memory) {
        string memory json = '{"version":"1.0","chainId":"1","orders":[';
        for (uint256 i = 0; i < orders.length; ++i) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, _buildCowOrderJson(orders[i]));
        }
        return string.concat(json, "]}");
    }

    function _buildCowOrderJson(CowOrderData memory order) internal pure returns (string memory json) {
        CowOrderAnalytics memory analytics = order.analytics;
        json = string.concat('{"sellToken":"', vm.toString(order.sellToken));
        json = string.concat(json, '","buyToken":"', vm.toString(order.buyToken));
        json = string.concat(json, '","sellAmount":"', vm.toString(order.sellAmount));
        json = string.concat(json, '","quotedBuyAmount":"', vm.toString(analytics.quotedBuyAmount));
        json = string.concat(json, '","minimumBuyAmount":"', vm.toString(order.buyAmount));
        json = string.concat(json, '","networkFeeAmount":"', vm.toString(analytics.networkFeeAmount));
        json = string.concat(json, '","slippageBps":', vm.toString(analytics.slippageBps));
        json = string.concat(json, ',"validTo":', vm.toString(order.validTo));
        json = string.concat(json, ',"orderUid":"', vm.toString(order.orderUid), '","analytics":{');
        json = string.concat(json, '"methodology":"', analytics.methodology);
        json = string.concat(json, '","priceReferenceSource":"', analytics.priceReferenceSource);
        json = string.concat(json, '","priceReferenceTimestamp":"', analytics.priceReferenceTimestamp);
        json = string.concat(json, '","sellTokenPriceUrl":"', analytics.sellTokenPriceUrl);
        json = string.concat(json, '","buyTokenPriceUrl":"', analytics.buyTokenPriceUrl);
        json = string.concat(json, '","sellTokenSymbol":"', analytics.sellTokenSymbol);
        json = string.concat(json, '","buyTokenSymbol":"', analytics.buyTokenSymbol);
        json = string.concat(json, '","sellAmountFormatted":"', analytics.sellAmountFormatted);
        json = string.concat(json, '","quotedBuyAmountFormatted":"', analytics.quotedBuyAmountFormatted);
        json = string.concat(json, '","minimumBuyAmountFormatted":"', analytics.minimumBuyAmountFormatted);
        json = string.concat(json, '","networkFeeAmountFormatted":"', analytics.networkFeeAmountFormatted);
        json = string.concat(json, '","sellTokenUsdPrice":"', analytics.sellTokenUsdPrice);
        json = string.concat(json, '","buyTokenUsdPrice":"', analytics.buyTokenUsdPrice);
        json = string.concat(json, '","inputUsdValue":"', analytics.inputUsdValue);
        json = string.concat(json, '","expectedOutputUsdValue":"', analytics.expectedOutputUsdValue);
        json = string.concat(json, '","minimumOutputUsdValue":"', analytics.minimumOutputUsdValue);
        json = string.concat(json, '","inputDisplay":"', analytics.inputDisplay);
        json = string.concat(json, '","expectedOutputDisplay":"', analytics.expectedOutputDisplay);
        json = string.concat(json, '","minimumOutputDisplay":"', analytics.minimumOutputDisplay);
        json = string.concat(json, '","expectedRate":"', analytics.expectedRate);
        json = string.concat(json, '","minimumRate":"', analytics.minimumRate);
        json = string.concat(json, '","networkFeeBps":"', analytics.networkFeeBps);
        json = string.concat(json, '","expectedPriceImpactBps":"', analytics.expectedPriceImpactBps);
        json = string.concat(json, '","expectedPriceImpactPercent":"', analytics.expectedPriceImpactPercent);
        json = string.concat(json, '","worstCasePriceImpactBps":"', analytics.worstCasePriceImpactBps);
        return string.concat(json, '","worstCasePriceImpactPercent":"', analytics.worstCasePriceImpactPercent, '"}}');
    }

    function _createCowOrder(address sellToken, uint256 sellAmount, uint256 slippageBps, uint256 validFor)
        internal
        returns (CowOrderData memory order)
    {
        string[] memory command = new string[](11);
        command[0] = "node";
        command[1] = COW_ORDER_HELPER;
        command[2] = "--sell-token";
        command[3] = vm.toString(sellToken);
        command[4] = "--sell-amount";
        command[5] = vm.toString(sellAmount);
        command[6] = "--slippage-bps";
        command[7] = vm.toString(slippageBps);
        command[8] = "--valid-for";
        command[9] = vm.toString(validFor);
        command[10] = "--submit";

        string memory result = string(vm.ffi(command));
        require(_stringsEqual(vm.parseJsonString(result, ".mode"), "submitted"), "CoW order was not submitted");
        require(
            _stringsEqual(vm.parseJsonString(result, ".status"), "presignaturePending"), "unexpected CoW order status"
        );
        CowOrderAnalytics memory analytics;
        analytics.quotedBuyAmount = vm.parseUint(vm.parseJsonString(result, ".quotedBuyAmount"));
        analytics.networkFeeAmount = vm.parseUint(vm.parseJsonString(result, ".networkFeeAmount"));
        analytics.slippageBps = vm.parseJsonUint(result, ".slippageBps");
        analytics.methodology = vm.parseJsonString(result, ".analytics.methodology");
        analytics.priceReferenceSource = vm.parseJsonString(result, ".analytics.priceReferenceSource");
        analytics.priceReferenceTimestamp = vm.parseJsonString(result, ".analytics.priceReferenceTimestamp");
        analytics.sellTokenPriceUrl = vm.parseJsonString(result, ".analytics.sellTokenPriceUrl");
        analytics.buyTokenPriceUrl = vm.parseJsonString(result, ".analytics.buyTokenPriceUrl");
        analytics.sellTokenSymbol = vm.parseJsonString(result, ".analytics.sellTokenSymbol");
        analytics.buyTokenSymbol = vm.parseJsonString(result, ".analytics.buyTokenSymbol");
        analytics.sellAmountFormatted = vm.parseJsonString(result, ".analytics.sellAmountFormatted");
        analytics.quotedBuyAmountFormatted = vm.parseJsonString(result, ".analytics.quotedBuyAmountFormatted");
        analytics.minimumBuyAmountFormatted = vm.parseJsonString(result, ".analytics.minimumBuyAmountFormatted");
        analytics.networkFeeAmountFormatted = vm.parseJsonString(result, ".analytics.networkFeeAmountFormatted");
        analytics.sellTokenUsdPrice = vm.parseJsonString(result, ".analytics.sellTokenUsdPrice");
        analytics.buyTokenUsdPrice = vm.parseJsonString(result, ".analytics.buyTokenUsdPrice");
        analytics.inputUsdValue = vm.parseJsonString(result, ".analytics.inputUsdValue");
        analytics.expectedOutputUsdValue = vm.parseJsonString(result, ".analytics.expectedOutputUsdValue");
        analytics.minimumOutputUsdValue = vm.parseJsonString(result, ".analytics.minimumOutputUsdValue");
        analytics.inputDisplay = vm.parseJsonString(result, ".analytics.inputDisplay");
        analytics.expectedOutputDisplay = vm.parseJsonString(result, ".analytics.expectedOutputDisplay");
        analytics.minimumOutputDisplay = vm.parseJsonString(result, ".analytics.minimumOutputDisplay");
        analytics.expectedRate = vm.parseJsonString(result, ".analytics.expectedRate");
        analytics.minimumRate = vm.parseJsonString(result, ".analytics.minimumRate");
        analytics.networkFeeBps = vm.parseJsonString(result, ".analytics.networkFeeBps");
        analytics.expectedPriceImpactBps = vm.parseJsonString(result, ".analytics.expectedPriceImpactBps");
        analytics.expectedPriceImpactPercent = vm.parseJsonString(result, ".analytics.expectedPriceImpactPercent");
        analytics.worstCasePriceImpactBps = vm.parseJsonString(result, ".analytics.worstCasePriceImpactBps");
        analytics.worstCasePriceImpactPercent = vm.parseJsonString(result, ".analytics.worstCasePriceImpactPercent");
        order = CowOrderData({
            sellToken: vm.parseJsonAddress(result, ".sellToken"),
            buyToken: vm.parseJsonAddress(result, ".buyToken"),
            sellAmount: vm.parseUint(vm.parseJsonString(result, ".sellAmount")),
            buyAmount: vm.parseUint(vm.parseJsonString(result, ".buyAmount")),
            validTo: vm.parseJsonUint(result, ".validTo"),
            orderUid: vm.parseJsonBytes(result, ".orderUid"),
            analytics: analytics
        });
        require(order.sellToken == sellToken && order.sellAmount == sellAmount, "CoW helper changed sell input");
        require(order.analytics.slippageBps == slippageBps, "CoW helper changed slippage");
        _validateCowOrder(order);
    }

    function _validateClaimData(StakeDaoClaimData memory claimData) internal pure {
        require(claimData.merkleRoot != bytes32(0), "zero Stake DAO merkle root");
        require(claimData.proof.length > 0, "empty Stake DAO proof");
        require(claimData.cumulativeAmount > claimData.alreadyClaimed, "no Stake DAO rewards to claim");
        require(
            claimData.unclaimedAmount == claimData.cumulativeAmount - claimData.alreadyClaimed,
            "Stake DAO unclaimed amount mismatch"
        );
    }

    function _validateConsolidationBalances(uint256 scrvUsdAmount, uint256 crvAmount, uint256 cvxAmount) internal view {
        require(ICowSettlement(COW_SETTLEMENT).vaultRelayer() == COW_VAULT_RELAYER, "CoW relayer mismatch");
        require(IERC4626(SCRVUSD).asset() == CRVUSD, "scrvUSD asset is not crvUSD");
        require(IERC20(SCRVUSD).balanceOf(TREASURY_SAFE) >= scrvUsdAmount, "insufficient scrvUSD balance");
        require(IERC20(CRV).balanceOf(TREASURY_SAFE) >= crvAmount, "insufficient CRV balance");
        require(IERC20(CVX).balanceOf(TREASURY_SAFE) >= cvxAmount, "insufficient CVX balance");
    }

    function _validateCowOrder(CowOrderData memory order) internal pure {
        require(order.sellToken == CRV || order.sellToken == CVX, "unsupported CoW sell token");
        require(order.buyToken == CRVUSD, "CoW buy token is not crvUSD");
        require(order.sellAmount > 0 && order.buyAmount > 0, "zero CoW order amount");
        require(order.orderUid.length == 56, "invalid CoW order UID length");
        require(order.analytics.quotedBuyAmount >= order.buyAmount, "CoW quoted buy below minimum");
        require(order.analytics.networkFeeAmount <= order.sellAmount, "CoW network fee exceeds sell amount");
        require(order.analytics.slippageBps <= 1_000, "CoW analytics slippage exceeds 10%");
        require(
            _stringsEqual(order.analytics.priceReferenceSource, "CoW Swap BFF USD prices"),
            "unexpected CoW price reference"
        );
        require(bytes(order.analytics.expectedPriceImpactBps).length > 0, "missing expected CoW price impact");
        require(bytes(order.analytics.worstCasePriceImpactBps).length > 0, "missing worst-case CoW price impact");

        address uidOwner;
        uint32 uidValidTo;
        bytes memory orderUid = order.orderUid;
        assembly ("memory-safe") {
            uidOwner := shr(96, mload(add(orderUid, 0x40)))
            uidValidTo := shr(224, mload(add(orderUid, 0x54)))
        }
        require(uidOwner == TREASURY_SAFE, "CoW order UID owner mismatch");
        require(uint256(uidValidTo) == order.validTo, "CoW order UID validity mismatch");
    }

    function _buildConvexClaimZapData() internal pure returns (bytes memory) {
        address[] memory rewardContracts = new address[](1);
        rewardContracts[0] = CONVEX_REWARD_POOL;
        address[] memory empty = new address[](0);
        return abi.encodeCall(IConvexClaimZap.claimRewards, (rewardContracts, empty, empty, empty, 0, 0, 0, 0, 0));
    }

    function _simulateSafeTransactions(LiquidityIncentivesSafeTx[] memory txs) internal {
        vm.startPrank(TREASURY_SAFE);
        for (uint256 i = 0; i < txs.length; ++i) {
            _callOrRevert(txs[i].to, txs[i].data);
        }
        vm.stopPrank();
    }

    function _callOrRevert(address target, bytes memory data) internal returns (bytes memory returnData) {
        bool success;
        (success, returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

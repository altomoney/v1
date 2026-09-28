// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

interface IConvexCreditLineMarket {
    function claimRewards() external returns (uint256[] memory claimedAmounts);
    function convexRewardPool() external view returns (address);
    function rewardRecipient() external view returns (address);
    function rewardToken(uint256 index) external view returns (address);
}

interface IStakeDaoAccountant {
    function REWARD_TOKEN() external view returns (address);
    function getPendingRewards(address gauge, address account) external view returns (uint256);
    function claim(address[] calldata gauges, bytes[] calldata harvestData) external;
}

interface IYearnV2Vault {
    function apiVersion() external view returns (string memory);
    function token() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function withdraw(uint256 maxShares, address recipient, uint256 maxLoss) external returns (uint256 assets);
}

interface ICurveStableSwapNg {
    function N_COINS() external view returns (uint256);
    function coins(uint256 index) external view returns (address);
    function balances(uint256 index) external view returns (uint256);
    function totalSupply() external view returns (uint256);

    function remove_liquidity(
        uint256 burnAmount,
        uint256[] calldata minimumAmounts,
        address receiver,
        bool claimAdminFees
    ) external returns (uint256[] memory amounts);
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
    uint256 stakeDaoCrvPendingBefore;
    uint256 crvBefore;
    uint256 cvxBefore;
    uint256 wfraxBefore;
    uint256 marketCrvBefore;
    uint256 marketCvxBefore;
    uint256 marketWfraxBefore;
    uint256 yearnSharesBefore;
    uint256 curveLpBefore;
}

struct YearnWithdrawalData {
    uint256 retainedPrincipalAssets;
    uint256 safeShares;
    uint256 pricePerShare;
    uint256 safeAssets;
    uint256 rewardShares;
    uint256 expectedLpAssets;
    uint256 maxLossBps;
}

struct CurveWithdrawalData {
    uint256 lpAmount;
    uint256 expectedFrxUsd;
    uint256 expectedDusd;
    uint256 minimumFrxUsd;
    uint256 minimumDusd;
    uint256 slippageBps;
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

struct ExternalVotiumIncentive {
    address token;
    uint256 amount;
    uint8 decimals;
    address depositor;
}

struct VotiumAllocationData {
    uint256 round;
    uint256 crvUsdProceedsAmount;
    uint256 maximumStoredCrvUsdAmount;
    uint256 maximumGrossCrvUsdAmount;
    uint256 votiumGrossAmount;
    uint256 votiumFeeAmount;
    uint256 votiumStoredAmount;
    uint256 surplusCrvUsdAmount;
    bool externalCapExceeded;
}

/// @title Generate staged Liquidity Incentive Management Safe transactions
/// @notice Generates claims, Curve withdrawal, consolidation, or Votium Safe batches without crossing state boundaries.
/// @dev Set LIQUIDITY_PHASE to `claims`, `curve-withdrawal`, `consolidation`, `votium-plan`, or `votium`.
contract GenerateLiquidityIncentivesTransactionsScript is Script {
    address public constant TREASURY_SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_YEARN_LOSS_BPS = 100;
    uint256 public constant MAX_CURVE_SLIPPAGE_BPS = 100;
    uint256 public constant YEARN_RETAINED_PRINCIPAL_LP = 215_246 ether;
    uint256 public constant VOTIUM_INCENTIVE_CAP_USD = 16_000;

    // Action C: Stake DAO's current vlCVX delegator UniversalRewardsDistributor.
    address public constant STAKEDAO_DELEGATOR_DISTRIBUTOR = 0x17F513CDE031C8B1E878Bde1Cb020cE29f77f380;
    address public constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    // Action D: the credit line owns the DUSD/frxUSD Convex stake and forwards rewards to the Treasury Safe.
    address public constant CONVEX_CREDIT_LINE_MARKET = 0x6b3458c87CD38aeFA6A5D059Eb19f609420DD852;
    address public constant CONVEX_REWARD_POOL = 0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant WFRAX = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;

    // Optional Stake DAO gauge CRV claim. Disabled unless CLAIM_STAKEDAO_CRV=true.
    address public constant STAKEDAO_ACCOUNTANT = 0x93b4B9bd266fFA8AF68e39EDFa8cFe2A62011Ce0;

    // Yearn reward realization: yvCurve-frxUSDDUSD-f returns the underlying Curve LP token.
    address public constant YEARN_VAULT = 0xB53B70Cb960FeEAf2093Df3C733E368F6D254898;
    address public constant DUSD_FRXUSD_CURVE_POOL = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address public constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address public constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    // Consolidation: CoW Protocol contracts used by prior Safe nonce 66.
    address public constant COW_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant COW_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Action F2: Votium single-round crvUSD incentive for the DUSD/frxUSD Curve gauge.
    address public constant VOTIUM = 0x63942E31E98f1833A234077f47880A66136a2D1e;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant DUSD_FRXUSD_GAUGE = 0xA41eb3062FD68B6Fa9f11439C86503913806761D;

    string public constant STAKEDAO_MERKLE_URL = "https://raw.githubusercontent.com/stake-dao/bounties-report/refs/heads/main/"
        "bounties-reports/latest/vlCVX/vlcvx_merkle_delegators.json";
    string public constant COW_ORDER_HELPER = "script/liquidity-incentives/createCowPresignOrder.mjs";
    string public constant VOTIUM_ALLOCATION_HELPER = "script/liquidity-incentives/calculateVotiumAllocation.mjs";
    string public constant CLAIMS_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-01-claims.json";
    string public constant CURVE_WITHDRAWAL_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-02-curve-withdrawal.json";
    string public constant CONSOLIDATION_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-03-consolidation.json";
    string public constant COW_ORDERS_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-03-consolidation.json";
    string public constant VOTIUM_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-04-votium.json";
    string public constant VOTIUM_ALLOCATION_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/votium-allocation-liquidity-04.json";
    string public constant VOTIUM_COW_ORDERS_OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-04-surplus.json";

    string internal constant CLAIM_PATH = ".claims.0xA1148A1b94262540994Cf9Aa431A13ad39764228.tokens."
        "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367";

    function run() public {
        require(block.chainid == 1, "not Ethereum mainnet");
        string memory phase = vm.envString("LIQUIDITY_PHASE");

        if (_stringsEqual(phase, "claims")) _runClaims();
        else if (_stringsEqual(phase, "curve-withdrawal")) _runCurveWithdrawal();
        else if (_stringsEqual(phase, "consolidation")) _runConsolidation();
        else if (_stringsEqual(phase, "votium-plan")) _runVotiumPlan();
        else if (_stringsEqual(phase, "votium")) _runVotium();
        else revert("invalid LIQUIDITY_PHASE");
    }

    function _runClaims() internal {
        StakeDaoClaimData memory claimData = fetchStakeDaoClaimData();
        bool claimStakeDaoCrv = vm.envOr("CLAIM_STAKEDAO_CRV", false);
        bool claimYearnRewards = vm.envOr("CLAIM_YEARN_REWARDS", false);
        YearnWithdrawalData memory yearnData;
        if (claimYearnRewards) {
            uint256 retainedPrincipal = vm.envOr("YEARN_RETAINED_PRINCIPAL_LP", YEARN_RETAINED_PRINCIPAL_LP);
            uint256 maxLossBps = vm.envOr("YEARN_MAX_LOSS_BPS", uint256(1));
            yearnData = getYearnWithdrawalData(retainedPrincipal, maxLossBps);
        }
        LiquidityIncentivesSafeTx[] memory txs = getClaimTransactions(claimData, yearnData, claimStakeDaoCrv);
        validateAndSimulateClaimTransactions(txs, claimData, yearnData, claimStakeDaoCrv);
        vm.writeFile(
            CLAIMS_OUTPUT_PATH,
            buildSafeBatchJson("Liquidity 01 - Claims C and D plus explicitly enabled optional claims", txs)
        );

        console.log("Claims Safe JSON:", CLAIMS_OUTPUT_PATH);
        console.log("Stake DAO scrvUSD claim:", claimData.unclaimedAmount);
        console.log(
            "Credit line pending CRV before claim:",
            IConvexBaseRewardPool(CONVEX_REWARD_POOL).earned(CONVEX_CREDIT_LINE_MARKET)
        );
        console.log("Stake DAO CRV claim enabled:", claimStakeDaoCrv);
        if (claimStakeDaoCrv) {
            console.log(
                "Stake DAO pending CRV before claim:",
                IStakeDaoAccountant(STAKEDAO_ACCOUNTANT).getPendingRewards(DUSD_FRXUSD_GAUGE, TREASURY_SAFE)
            );
        }
        console.log("Yearn reward withdrawal enabled:", claimYearnRewards);
        console.log("Yearn Safe LP value:", yearnData.safeAssets);
        console.log("Yearn retained LP principal:", yearnData.retainedPrincipalAssets);
        console.log("Yearn reward shares selected:", yearnData.rewardShares);
        console.log("Yearn expected LP withdrawal:", yearnData.expectedLpAssets);
    }

    function _runCurveWithdrawal() internal {
        uint256 lpAmount = vm.envOr("CURVE_LP_AMOUNT", uint256(0));
        uint256 slippageBps;
        if (lpAmount > 0) slippageBps = vm.envUint("CURVE_WITHDRAWAL_SLIPPAGE_BPS");

        CurveWithdrawalData memory curveData = getCurveWithdrawalData(lpAmount, slippageBps);
        LiquidityIncentivesSafeTx[] memory txs = getCurveWithdrawalTransactions(curveData);
        validateAndSimulateCurveWithdrawalTransactions(txs, curveData);
        vm.writeFile(
            CURVE_WITHDRAWAL_OUTPUT_PATH, buildSafeBatchJson("Liquidity 02 - Withdraw Yearn reward LP from Curve", txs)
        );

        console.log("Curve withdrawal Safe JSON:", CURVE_WITHDRAWAL_OUTPUT_PATH);
        console.log("Curve LP selected:", curveData.lpAmount);
        console.log("Expected frxUSD:", curveData.expectedFrxUsd);
        console.log("Minimum frxUSD:", curveData.minimumFrxUsd);
        console.log("Expected DUSD:", curveData.expectedDusd);
        console.log("Minimum DUSD:", curveData.minimumDusd);
    }

    function _runConsolidation() internal {
        uint256 scrvUsdAmount = vm.envOr("CONSOLIDATE_SCRVUSD_AMOUNT", uint256(0));
        uint256 crvAmount = vm.envOr("CONSOLIDATE_CRV_AMOUNT", uint256(0));
        uint256 cvxAmount = vm.envOr("CONSOLIDATE_CVX_AMOUNT", uint256(0));
        uint256 wfraxAmount = vm.envOr("CONSOLIDATE_WFRAX_AMOUNT", uint256(0));
        uint256 frxUsdAmount = vm.envOr("CONSOLIDATE_FRXUSD_AMOUNT", uint256(0));
        uint256 dusdAmount = vm.envOr("CONSOLIDATE_DUSD_AMOUNT", uint256(0));
        require(
            scrvUsdAmount > 0 || crvAmount > 0 || cvxAmount > 0 || wfraxAmount > 0 || frxUsdAmount > 0
                || dusdAmount > 0,
            "no consolidation amount selected"
        );
        _validateConsolidationBalances(scrvUsdAmount, crvAmount, cvxAmount, wfraxAmount, frxUsdAmount, dusdAmount);

        uint256 cowOrderCount = (crvAmount > 0 ? 1 : 0) + (cvxAmount > 0 ? 1 : 0) + (wfraxAmount > 0 ? 1 : 0)
            + (frxUsdAmount > 0 ? 1 : 0) + (dusdAmount > 0 ? 1 : 0);
        CowOrderData[] memory orders = new CowOrderData[](cowOrderCount);
        if (cowOrderCount > 0) {
            require(vm.envOr("COW_SUBMIT_ORDERS", false), "set COW_SUBMIT_ORDERS=true to post orders");
            uint256 slippageBps = vm.envUint("COW_SLIPPAGE_BPS");
            uint256 validFor = vm.envUint("COW_ORDER_VALIDITY_SECONDS");
            require(slippageBps <= 1_000, "CoW slippage exceeds 10%");
            require(validFor >= 1_800 && validFor <= 604_800, "CoW validity must be 1800-604800 seconds");

            uint256 orderIndex;
            if (crvAmount > 0) orders[orderIndex++] = _createCowOrder(CRV, CRVUSD, crvAmount, slippageBps, validFor);
            if (cvxAmount > 0) orders[orderIndex++] = _createCowOrder(CVX, CRVUSD, cvxAmount, slippageBps, validFor);
            if (wfraxAmount > 0) {
                orders[orderIndex++] = _createCowOrder(WFRAX, CRVUSD, wfraxAmount, slippageBps, validFor);
            }
            if (frxUsdAmount > 0) {
                orders[orderIndex++] = _createCowOrder(FRXUSD, CRVUSD, frxUsdAmount, slippageBps, validFor);
            }
            if (dusdAmount > 0) orders[orderIndex] = _createCowOrder(DUSD, CRVUSD, dusdAmount, slippageBps, validFor);
        }

        LiquidityIncentivesSafeTx[] memory txs = getConsolidationTransactions(scrvUsdAmount, orders);
        validateAndSimulateConsolidationTransactions(txs, scrvUsdAmount, orders);
        vm.writeFile(CONSOLIDATION_OUTPUT_PATH, buildSafeBatchJson("Liquidity 03 - Consolidate rewards to crvUSD", txs));
        vm.writeFile(COW_ORDERS_OUTPUT_PATH, buildCowOrdersJson(orders));

        console.log("Consolidation Safe JSON:", CONSOLIDATION_OUTPUT_PATH);
        console.log("CoW order manifest:", COW_ORDERS_OUTPUT_PATH);
        console.log("scrvUSD shares selected:", scrvUsdAmount);
        console.log("CoW orders posted:", orders.length);
    }

    function _runVotiumPlan() internal {
        (VotiumAllocationData memory allocation, string memory allocationJson) = _createVotiumAllocation();
        vm.writeFile(VOTIUM_ALLOCATION_OUTPUT_PATH, allocationJson);
        _logVotiumAllocation(allocation);
    }

    function _runVotium() internal {
        (VotiumAllocationData memory allocation, string memory allocationJson) = _createVotiumAllocation();
        CowOrderData[] memory surplusOrders = new CowOrderData[](allocation.surplusCrvUsdAmount > 0 ? 1 : 0);
        if (surplusOrders.length > 0) {
            require(vm.envOr("COW_SUBMIT_ORDERS", false), "set COW_SUBMIT_ORDERS=true to post surplus order");
            uint256 slippageBps = vm.envUint("COW_SLIPPAGE_BPS");
            uint256 validFor = vm.envUint("COW_ORDER_VALIDITY_SECONDS");
            require(slippageBps <= 1_000, "CoW slippage exceeds 10%");
            require(validFor >= 1_800 && validFor <= 604_800, "CoW validity must be 1800-604800 seconds");
            surplusOrders[0] = _createCowOrder(CRVUSD, USDC, allocation.surplusCrvUsdAmount, slippageBps, validFor);
        }

        LiquidityIncentivesSafeTx[] memory txs =
            getVotiumAndSurplusTransactions(allocation.votiumGrossAmount, surplusOrders);
        uint256 votiumRound = validateAndSimulateVotiumTransactions(txs, allocation.votiumGrossAmount, surplusOrders);
        require(votiumRound == allocation.round, "Votium round changed during generation");
        vm.writeFile(VOTIUM_OUTPUT_PATH, buildSafeBatchJson("Liquidity 04 - Votium F2 and surplus crvUSD to USDC", txs));
        vm.writeFile(VOTIUM_ALLOCATION_OUTPUT_PATH, allocationJson);
        vm.writeFile(VOTIUM_COW_ORDERS_OUTPUT_PATH, buildCowOrdersJson(surplusOrders));

        console.log("Votium Safe JSON:", VOTIUM_OUTPUT_PATH);
        console.log("Votium allocation:", VOTIUM_ALLOCATION_OUTPUT_PATH);
        console.log("Surplus CoW order manifest:", VOTIUM_COW_ORDERS_OUTPUT_PATH);
        _logVotiumAllocation(allocation);
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

    function calculateYearnWithdrawalData(
        uint256 safeShares,
        uint256 pricePerShare,
        uint256 retainedPrincipalAssets,
        uint256 maxLossBps
    ) public pure returns (YearnWithdrawalData memory yearnData) {
        require(pricePerShare > 0, "zero Yearn price per share");
        require(retainedPrincipalAssets > 0, "zero Yearn retained principal");
        require(maxLossBps <= MAX_YEARN_LOSS_BPS, "Yearn max loss exceeds 1%");

        uint256 safeAssets = Math.mulDiv(safeShares, pricePerShare, 1 ether);
        yearnData = YearnWithdrawalData({
            retainedPrincipalAssets: retainedPrincipalAssets,
            safeShares: safeShares,
            pricePerShare: pricePerShare,
            safeAssets: safeAssets,
            rewardShares: 0,
            expectedLpAssets: 0,
            maxLossBps: maxLossBps
        });
        if (safeAssets <= retainedPrincipalAssets) return yearnData;

        uint256 sharesToKeep = Math.mulDiv(retainedPrincipalAssets, 1 ether, pricePerShare, Math.Rounding.Ceil);
        if (sharesToKeep >= safeShares) return yearnData;

        yearnData.rewardShares = safeShares - sharesToKeep;
        yearnData.expectedLpAssets = Math.mulDiv(yearnData.rewardShares, pricePerShare, 1 ether);
        if (yearnData.expectedLpAssets == 0) yearnData.rewardShares = 0;
    }

    function getYearnWithdrawalData(uint256 retainedPrincipalAssets, uint256 maxLossBps)
        public
        view
        returns (YearnWithdrawalData memory yearnData)
    {
        _validateYearnMainnetState();
        IYearnV2Vault vault = IYearnV2Vault(YEARN_VAULT);
        yearnData = calculateYearnWithdrawalData(
            vault.balanceOf(TREASURY_SAFE), vault.pricePerShare(), retainedPrincipalAssets, maxLossBps
        );
    }

    function getCurveWithdrawalData(uint256 lpAmount, uint256 slippageBps)
        public
        view
        returns (CurveWithdrawalData memory curveData)
    {
        _validateCurvePoolState();
        require(slippageBps <= MAX_CURVE_SLIPPAGE_BPS, "Curve slippage exceeds 1%");
        if (lpAmount == 0) return curveData;

        ICurveStableSwapNg pool = ICurveStableSwapNg(DUSD_FRXUSD_CURVE_POOL);
        uint256 totalSupply = pool.totalSupply();
        require(totalSupply > 0, "zero Curve LP supply");
        uint256 expectedFrxUsd = Math.mulDiv(pool.balances(0), lpAmount, totalSupply);
        uint256 expectedDusd = Math.mulDiv(pool.balances(1), lpAmount, totalSupply);
        require(expectedFrxUsd > 0 && expectedDusd > 0, "zero Curve withdrawal output");

        curveData = CurveWithdrawalData({
            lpAmount: lpAmount,
            expectedFrxUsd: expectedFrxUsd,
            expectedDusd: expectedDusd,
            minimumFrxUsd: Math.mulDiv(expectedFrxUsd, BPS_DENOMINATOR - slippageBps, BPS_DENOMINATOR),
            minimumDusd: Math.mulDiv(expectedDusd, BPS_DENOMINATOR - slippageBps, BPS_DENOMINATOR),
            slippageBps: slippageBps
        });
    }

    function getExternalVotiumIncentives()
        public
        view
        returns (uint256 round, ExternalVotiumIncentive[] memory externalIncentives)
    {
        IVotium votium = IVotium(VOTIUM);
        round = votium.activeRound();
        uint256 incentiveLength = votium.incentivesLength(round, DUSD_FRXUSD_GAUGE);
        ExternalVotiumIncentive[] memory candidates = new ExternalVotiumIncentive[](incentiveLength);
        uint256 externalCount;

        for (uint256 i = 0; i < incentiveLength; ++i) {
            (address token, uint256 amount,,,, address depositor) = votium.incentives(round, DUSD_FRXUSD_GAUGE, i);
            if (amount == 0) continue;
            require(depositor != TREASURY_SAFE, "Treasury already posted an incentive this round");
            require(token.code.length > 0, "external incentive token has no code");
            candidates[externalCount++] = ExternalVotiumIncentive({
                token: token, amount: amount, decimals: IERC20Metadata(token).decimals(), depositor: depositor
            });
        }

        externalIncentives = new ExternalVotiumIncentive[](externalCount);
        for (uint256 i = 0; i < externalCount; ++i) {
            externalIncentives[i] = candidates[i];
        }
    }

    function _createVotiumAllocation()
        internal
        returns (VotiumAllocationData memory allocation, string memory allocationJson)
    {
        uint256 proceedsAmount = vm.envUint("LIQUIDITY_CRVUSD_PROCEEDS_AMOUNT");
        require(proceedsAmount > 0, "zero selected crvUSD proceeds");
        require(
            IERC20(CRVUSD).balanceOf(TREASURY_SAFE) >= proceedsAmount,
            "selected crvUSD proceeds exceed Treasury balance"
        );

        (uint256 round, ExternalVotiumIncentive[] memory externalIncentives) = getExternalVotiumIncentives();
        IVotium votium = IVotium(VOTIUM);
        uint256 platformFee = votium.platformFee();
        uint256 feeDenominator = votium.DENOMINATOR();
        require(platformFee < feeDenominator, "invalid Votium platform fee");

        string[] memory command = new string[](12 + externalIncentives.length * 2);
        command[0] = "node";
        command[1] = VOTIUM_ALLOCATION_HELPER;
        command[2] = "--round";
        command[3] = vm.toString(round);
        command[4] = "--cap-usd";
        command[5] = vm.toString(VOTIUM_INCENTIVE_CAP_USD);
        command[6] = "--crvusd-proceeds";
        command[7] = vm.toString(proceedsAmount);
        command[8] = "--platform-fee";
        command[9] = vm.toString(platformFee);
        command[10] = "--fee-denominator";
        command[11] = vm.toString(feeDenominator);
        for (uint256 i = 0; i < externalIncentives.length; ++i) {
            command[12 + i * 2] = "--external-incentive";
            command[13 + i * 2] = string.concat(
                vm.toString(externalIncentives[i].token),
                ":",
                vm.toString(externalIncentives[i].amount),
                ":",
                vm.toString(uint256(externalIncentives[i].decimals)),
                ":",
                vm.toString(externalIncentives[i].depositor)
            );
        }

        allocationJson = string(vm.ffi(command));
        allocation = VotiumAllocationData({
            round: vm.parseJsonUint(allocationJson, ".round"),
            crvUsdProceedsAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".crvUsdProceedsAmount")),
            maximumStoredCrvUsdAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".maximumStoredCrvUsdAmount")),
            maximumGrossCrvUsdAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".maximumGrossCrvUsdAmount")),
            votiumGrossAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".votiumGrossAmount")),
            votiumFeeAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".votiumFeeAmount")),
            votiumStoredAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".votiumStoredAmount")),
            surplusCrvUsdAmount: vm.parseUint(vm.parseJsonString(allocationJson, ".surplusCrvUsdAmount")),
            externalCapExceeded: vm.parseJsonBool(allocationJson, ".externalCapExceeded")
        });

        require(allocation.round == round, "allocation round mismatch");
        require(allocation.crvUsdProceedsAmount == proceedsAmount, "allocation proceeds mismatch");
        require(
            allocation.votiumGrossAmount + allocation.surplusCrvUsdAmount == proceedsAmount,
            "allocation does not consume selected proceeds"
        );
        require(
            allocation.votiumGrossAmount <= allocation.maximumGrossCrvUsdAmount,
            "allocation gross amount exceeds maximum"
        );
        require(
            allocation.votiumFeeAmount == allocation.votiumGrossAmount * platformFee / feeDenominator,
            "allocation fee mismatch"
        );
        require(
            allocation.votiumStoredAmount == allocation.votiumGrossAmount - allocation.votiumFeeAmount,
            "allocation stored amount mismatch"
        );
        require(
            allocation.votiumStoredAmount <= allocation.maximumStoredCrvUsdAmount,
            "allocation stored amount exceeds cap"
        );
        if (allocation.externalCapExceeded) {
            require(allocation.votiumGrossAmount == 0, "external cap handling mismatch");
        }
    }

    function _logVotiumAllocation(VotiumAllocationData memory allocation) internal pure {
        console.log("Votium allocation:", VOTIUM_ALLOCATION_OUTPUT_PATH);
        console.log("Votium round:", allocation.round);
        console.log("Selected crvUSD proceeds:", allocation.crvUsdProceedsAmount);
        console.log("Maximum stored crvUSD incentive:", allocation.maximumStoredCrvUsdAmount);
        console.log("Maximum gross crvUSD deposit:", allocation.maximumGrossCrvUsdAmount);
        console.log("Gross crvUSD deposited to Votium:", allocation.votiumGrossAmount);
        console.log("Votium fee:", allocation.votiumFeeAmount);
        console.log("Stored crvUSD incentive:", allocation.votiumStoredAmount);
        console.log("Surplus crvUSD selected for USDC:", allocation.surplusCrvUsdAmount);
        console.log("External incentives already exceed cap:", allocation.externalCapExceeded);
    }

    function getClaimTransactions(StakeDaoClaimData memory claimData)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        YearnWithdrawalData memory yearnData;
        return getClaimTransactions(claimData, yearnData, false);
    }

    function getClaimTransactions(StakeDaoClaimData memory claimData, YearnWithdrawalData memory yearnData)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        return getClaimTransactions(claimData, yearnData, false);
    }

    function getClaimTransactions(
        StakeDaoClaimData memory claimData,
        YearnWithdrawalData memory yearnData,
        bool claimStakeDaoCrv
    ) public pure returns (LiquidityIncentivesSafeTx[] memory txs) {
        _validateClaimData(claimData);
        _validateYearnWithdrawalData(yearnData);
        txs = new LiquidityIncentivesSafeTx[](2 + (claimStakeDaoCrv ? 1 : 0) + (yearnData.rewardShares > 0 ? 1 : 0));

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
        txs[1] = LiquidityIncentivesSafeTx({
            to: CONVEX_CREDIT_LINE_MARKET, data: abi.encodeCall(IConvexCreditLineMarket.claimRewards, ())
        });

        uint256 txIndex = 2;
        if (claimStakeDaoCrv) {
            address[] memory gauges = new address[](1);
            gauges[0] = DUSD_FRXUSD_GAUGE;
            bytes[] memory harvestData = new bytes[](1);
            harvestData[0] = bytes("");
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: STAKEDAO_ACCOUNTANT, data: abi.encodeCall(IStakeDaoAccountant.claim, (gauges, harvestData))
            });
        }
        if (yearnData.rewardShares > 0) {
            txs[txIndex] = LiquidityIncentivesSafeTx({
                to: YEARN_VAULT,
                data: abi.encodeCall(
                    IYearnV2Vault.withdraw, (yearnData.rewardShares, TREASURY_SAFE, yearnData.maxLossBps)
                )
            });
        }
    }

    function getCurveWithdrawalTransactions(CurveWithdrawalData memory curveData)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        _validateCurveWithdrawalData(curveData);
        if (curveData.lpAmount == 0) return new LiquidityIncentivesSafeTx[](0);

        uint256[] memory minimumAmounts = new uint256[](2);
        minimumAmounts[0] = curveData.minimumFrxUsd;
        minimumAmounts[1] = curveData.minimumDusd;
        txs = new LiquidityIncentivesSafeTx[](1);
        txs[0] = LiquidityIncentivesSafeTx({
            to: DUSD_FRXUSD_CURVE_POOL,
            data: abi.encodeCall(
                ICurveStableSwapNg.remove_liquidity, (curveData.lpAmount, minimumAmounts, TREASURY_SAFE, true)
            )
        });
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
        CowOrderData[] memory noSurplusOrders = new CowOrderData[](0);
        return getVotiumAndSurplusTransactions(incentiveAmount, noSurplusOrders);
    }

    function getVotiumAndSurplusTransactions(uint256 incentiveAmount, CowOrderData[] memory surplusOrders)
        public
        pure
        returns (LiquidityIncentivesSafeTx[] memory txs)
    {
        require(incentiveAmount > 0 || surplusOrders.length > 0, "empty Votium allocation batch");
        require(surplusOrders.length <= 1, "multiple surplus orders");
        txs = new LiquidityIncentivesSafeTx[]((incentiveAmount > 0 ? 2 : 0) + surplusOrders.length * 2);
        uint256 txIndex;
        if (incentiveAmount > 0) {
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: CRVUSD, data: abi.encodeCall(IERC20.approve, (VOTIUM, incentiveAmount))
            });
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: VOTIUM,
                data: abi.encodeCall(IVotium.depositIncentiveSimple, (CRVUSD, incentiveAmount, DUSD_FRXUSD_GAUGE))
            });
        }
        if (surplusOrders.length > 0) {
            _validateCowOrder(surplusOrders[0]);
            require(
                surplusOrders[0].sellToken == CRVUSD && surplusOrders[0].buyToken == USDC,
                "surplus order is not crvUSD to USDC"
            );
            txs[txIndex++] = LiquidityIncentivesSafeTx({
                to: CRVUSD, data: abi.encodeCall(IERC20.approve, (COW_VAULT_RELAYER, surplusOrders[0].sellAmount))
            });
            txs[txIndex] = LiquidityIncentivesSafeTx({
                to: COW_SETTLEMENT,
                data: abi.encodeCall(ICowSettlement.setPreSignature, (surplusOrders[0].orderUid, true))
            });
        }
    }

    function validateAndSimulateClaimTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        StakeDaoClaimData memory claimData
    ) public {
        YearnWithdrawalData memory yearnData;
        validateAndSimulateClaimTransactions(txs, claimData, yearnData, false);
    }

    function validateAndSimulateClaimTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        StakeDaoClaimData memory claimData,
        YearnWithdrawalData memory yearnData
    ) public {
        validateAndSimulateClaimTransactions(txs, claimData, yearnData, false);
    }

    function validateAndSimulateClaimTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        StakeDaoClaimData memory claimData,
        YearnWithdrawalData memory yearnData,
        bool claimStakeDaoCrv
    ) public {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(
            txs.length == 2 + (claimStakeDaoCrv ? 1 : 0) + (yearnData.rewardShares > 0 ? 1 : 0),
            "unexpected claim transaction count"
        );
        _validateClaimData(claimData);
        _validateYearnWithdrawalData(yearnData);
        require(STAKEDAO_DELEGATOR_DISTRIBUTOR.code.length > 0, "Stake DAO distributor has no code");
        require(CONVEX_CREDIT_LINE_MARKET.code.length > 0, "Convex credit line has no code");
        require(CONVEX_REWARD_POOL.code.length > 0, "Convex reward pool has no code");
        _validateConvexCreditLineState();
        if (claimStakeDaoCrv) _validateStakeDaoAccountantState();

        if (yearnData.retainedPrincipalAssets > 0) {
            YearnWithdrawalData memory currentYearnData =
                getYearnWithdrawalData(yearnData.retainedPrincipalAssets, yearnData.maxLossBps);
            require(currentYearnData.safeShares == yearnData.safeShares, "Yearn Safe shares changed");
            require(currentYearnData.pricePerShare == yearnData.pricePerShare, "Yearn price per share changed");
            require(currentYearnData.rewardShares == yearnData.rewardShares, "Yearn reward shares changed");
        }

        IUniversalRewardsDistributor distributor = IUniversalRewardsDistributor(STAKEDAO_DELEGATOR_DISTRIBUTOR);
        require(distributor.root() == claimData.merkleRoot, "Stake DAO merkle root changed");
        require(distributor.claimed(TREASURY_SAFE, SCRVUSD) == claimData.alreadyClaimed, "Stake DAO claim changed");

        ClaimSimulationState memory state = ClaimSimulationState({
            scrvUsdBefore: IERC20(SCRVUSD).balanceOf(TREASURY_SAFE),
            convexEarnedBefore: IConvexBaseRewardPool(CONVEX_REWARD_POOL).earned(CONVEX_CREDIT_LINE_MARKET),
            stakeDaoCrvPendingBefore: claimStakeDaoCrv
                ? IStakeDaoAccountant(STAKEDAO_ACCOUNTANT).getPendingRewards(DUSD_FRXUSD_GAUGE, TREASURY_SAFE)
                : 0,
            crvBefore: IERC20(CRV).balanceOf(TREASURY_SAFE),
            cvxBefore: IERC20(CVX).balanceOf(TREASURY_SAFE),
            wfraxBefore: IERC20(WFRAX).balanceOf(TREASURY_SAFE),
            marketCrvBefore: IERC20(CRV).balanceOf(CONVEX_CREDIT_LINE_MARKET),
            marketCvxBefore: IERC20(CVX).balanceOf(CONVEX_CREDIT_LINE_MARKET),
            marketWfraxBefore: IERC20(WFRAX).balanceOf(CONVEX_CREDIT_LINE_MARKET),
            yearnSharesBefore: IYearnV2Vault(YEARN_VAULT).balanceOf(TREASURY_SAFE),
            curveLpBefore: IERC20(DUSD_FRXUSD_CURVE_POOL).balanceOf(TREASURY_SAFE)
        });

        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);
        require(distributor.claimed(TREASURY_SAFE, SCRVUSD) == claimData.cumulativeAmount, "Action C claim mismatch");
        require(
            IERC20(SCRVUSD).balanceOf(TREASURY_SAFE) == state.scrvUsdBefore + claimData.unclaimedAmount,
            "Action C scrvUSD mismatch"
        );
        require(
            IConvexBaseRewardPool(CONVEX_REWARD_POOL).earned(CONVEX_CREDIT_LINE_MARKET) == 0, "Action D rewards remain"
        );
        require(IERC20(CRV).balanceOf(CONVEX_CREDIT_LINE_MARKET) == 0, "Action D CRV not forwarded");
        require(IERC20(CVX).balanceOf(CONVEX_CREDIT_LINE_MARKET) == 0, "Action D CVX not forwarded");
        require(IERC20(WFRAX).balanceOf(CONVEX_CREDIT_LINE_MARKET) == 0, "Action D WFRAX not forwarded");
        require(
            IERC20(CRV).balanceOf(TREASURY_SAFE) >= state.crvBefore + state.marketCrvBefore,
            "Action D CRV balance decreased"
        );
        require(
            IERC20(CVX).balanceOf(TREASURY_SAFE) >= state.cvxBefore + state.marketCvxBefore,
            "Action D CVX balance decreased"
        );
        require(
            IERC20(WFRAX).balanceOf(TREASURY_SAFE) >= state.wfraxBefore + state.marketWfraxBefore,
            "Action D WFRAX balance decreased"
        );
        if (state.convexEarnedBefore > 0) {
            require(
                IERC20(CRV).balanceOf(TREASURY_SAFE)
                    >= state.crvBefore + state.marketCrvBefore + state.convexEarnedBefore,
                "Action D did not receive CRV"
            );
        }
        if (claimStakeDaoCrv) {
            require(
                IStakeDaoAccountant(STAKEDAO_ACCOUNTANT).getPendingRewards(DUSD_FRXUSD_GAUGE, TREASURY_SAFE) == 0,
                "Stake DAO CRV rewards remain"
            );
            require(
                IERC20(CRV).balanceOf(TREASURY_SAFE) >= state.crvBefore + state.stakeDaoCrvPendingBefore,
                "Stake DAO CRV claim mismatch"
            );
        }
        _validateSimulatedYearnWithdrawal(state, yearnData);
        require(vm.revertToState(snapshot), "failed to revert claim simulation");
    }

    function validateAndSimulateCurveWithdrawalTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        CurveWithdrawalData memory curveData
    ) public {
        require(block.chainid == 1, "not Ethereum mainnet");
        _validateCurvePoolState();
        _validateCurveWithdrawalData(curveData);
        require(txs.length == (curveData.lpAmount > 0 ? 1 : 0), "unexpected Curve withdrawal transaction count");
        if (curveData.lpAmount == 0) return;

        CurveWithdrawalData memory currentData = getCurveWithdrawalData(curveData.lpAmount, curveData.slippageBps);
        require(currentData.expectedFrxUsd == curveData.expectedFrxUsd, "Curve frxUSD output changed");
        require(currentData.expectedDusd == curveData.expectedDusd, "Curve DUSD output changed");
        require(
            IERC20(DUSD_FRXUSD_CURVE_POOL).balanceOf(TREASURY_SAFE) >= curveData.lpAmount,
            "insufficient Curve LP balance"
        );

        uint256 lpBefore = IERC20(DUSD_FRXUSD_CURVE_POOL).balanceOf(TREASURY_SAFE);
        uint256 frxUsdBefore = IERC20(FRXUSD).balanceOf(TREASURY_SAFE);
        uint256 dusdBefore = IERC20(DUSD).balanceOf(TREASURY_SAFE);
        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);

        require(
            IERC20(DUSD_FRXUSD_CURVE_POOL).balanceOf(TREASURY_SAFE) == lpBefore - curveData.lpAmount,
            "Curve LP burn mismatch"
        );
        require(
            IERC20(FRXUSD).balanceOf(TREASURY_SAFE) >= frxUsdBefore + curveData.minimumFrxUsd,
            "Curve frxUSD minimum not received"
        );
        require(
            IERC20(DUSD).balanceOf(TREASURY_SAFE) >= dusdBefore + curveData.minimumDusd,
            "Curve DUSD minimum not received"
        );
        require(vm.revertToState(snapshot), "failed to revert Curve withdrawal simulation");
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
        require(IERC20(CRVUSD).balanceOf(TREASURY_SAFE) >= incentiveAmount, "insufficient settled crvUSD balance");
        CowOrderData[] memory noSurplusOrders = new CowOrderData[](0);
        return validateAndSimulateVotiumTransactions(txs, incentiveAmount, noSurplusOrders);
    }

    function validateAndSimulateVotiumTransactions(
        LiquidityIncentivesSafeTx[] memory txs,
        uint256 incentiveAmount,
        CowOrderData[] memory surplusOrders
    ) public returns (uint256 votiumRound) {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(incentiveAmount > 0 || surplusOrders.length > 0, "empty Votium allocation batch");
        require(surplusOrders.length <= 1, "multiple surplus orders");
        require(
            txs.length == (incentiveAmount > 0 ? 2 : 0) + surplusOrders.length * 2,
            "unexpected Votium transaction count"
        );
        uint256 surplusAmount;
        if (surplusOrders.length > 0) {
            _validateCowOrder(surplusOrders[0]);
            require(
                surplusOrders[0].sellToken == CRVUSD && surplusOrders[0].buyToken == USDC,
                "surplus order is not crvUSD to USDC"
            );
            require(surplusOrders[0].validTo > block.timestamp + 15 minutes, "CoW order expires too soon");
            require(ICowSettlement(COW_SETTLEMENT).vaultRelayer() == COW_VAULT_RELAYER, "CoW relayer mismatch");
            surplusAmount = surplusOrders[0].sellAmount;
        }
        require(
            IERC20(CRVUSD).balanceOf(TREASURY_SAFE) >= incentiveAmount + surplusAmount,
            "insufficient selected crvUSD proceeds"
        );

        IVotium votium = IVotium(VOTIUM);
        require(!votium.requireAllowlist() || votium.tokenAllowed(CRVUSD), "crvUSD is not Votium-allowed");
        votiumRound = votium.activeRound();
        uint256 incentiveCountBefore = votium.incentivesLength(votiumRound, DUSD_FRXUSD_GAUGE);
        uint256 balanceBefore = IERC20(CRVUSD).balanceOf(TREASURY_SAFE);
        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);

        require(IERC20(CRVUSD).balanceOf(TREASURY_SAFE) == balanceBefore - incentiveAmount, "F2 balance mismatch");
        if (incentiveAmount > 0) {
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
        } else {
            require(
                votium.incentivesLength(votiumRound, DUSD_FRXUSD_GAUGE) == incentiveCountBefore,
                "unexpected F2 incentive"
            );
        }
        if (surplusOrders.length > 0) {
            require(
                IERC20(CRVUSD).allowance(TREASURY_SAFE, COW_VAULT_RELAYER) == surplusAmount,
                "surplus CoW allowance mismatch"
            );
            require(
                ICowSettlement(COW_SETTLEMENT).preSignature(surplusOrders[0].orderUid) != 0,
                "surplus CoW presignature missing"
            );
        }
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

    function _createCowOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 slippageBps,
        uint256 validFor
    ) internal returns (CowOrderData memory order) {
        string[] memory command = new string[](13);
        command[0] = "node";
        command[1] = COW_ORDER_HELPER;
        command[2] = "--sell-token";
        command[3] = vm.toString(sellToken);
        command[4] = "--buy-token";
        command[5] = vm.toString(buyToken);
        command[6] = "--sell-amount";
        command[7] = vm.toString(sellAmount);
        command[8] = "--slippage-bps";
        command[9] = vm.toString(slippageBps);
        command[10] = "--valid-for";
        command[11] = vm.toString(validFor);
        command[12] = "--submit";

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
        require(
            order.sellToken == sellToken && order.buyToken == buyToken && order.sellAmount == sellAmount,
            "CoW helper changed order input"
        );
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

    function _validateStakeDaoAccountantState() internal view {
        require(STAKEDAO_ACCOUNTANT.code.length > 0, "Stake DAO Accountant has no code");
        require(IStakeDaoAccountant(STAKEDAO_ACCOUNTANT).REWARD_TOKEN() == CRV, "Stake DAO reward token is not CRV");
    }

    function _validateYearnMainnetState() internal view {
        require(YEARN_VAULT.code.length > 0, "Yearn vault has no code");
        IYearnV2Vault vault = IYearnV2Vault(YEARN_VAULT);
        require(_stringsEqual(vault.apiVersion(), "0.4.6"), "unexpected Yearn vault version");
        require(vault.token() == DUSD_FRXUSD_CURVE_POOL, "Yearn vault token mismatch");
        require(vault.pricePerShare() > 0, "zero Yearn price per share");
    }

    function _validateCurvePoolState() internal view {
        require(DUSD_FRXUSD_CURVE_POOL.code.length > 0, "Curve pool has no code");
        ICurveStableSwapNg pool = ICurveStableSwapNg(DUSD_FRXUSD_CURVE_POOL);
        require(pool.N_COINS() == 2, "unexpected Curve coin count");
        require(pool.coins(0) == FRXUSD, "Curve coin 0 is not frxUSD");
        require(pool.coins(1) == DUSD, "Curve coin 1 is not DUSD");
    }

    function _validateYearnWithdrawalData(YearnWithdrawalData memory yearnData) internal pure {
        require(yearnData.maxLossBps <= MAX_YEARN_LOSS_BPS, "Yearn max loss exceeds 1%");
        if (yearnData.retainedPrincipalAssets == 0) {
            require(
                yearnData.safeShares == 0 && yearnData.pricePerShare == 0 && yearnData.safeAssets == 0
                    && yearnData.rewardShares == 0 && yearnData.expectedLpAssets == 0,
                "incomplete Yearn withdrawal data"
            );
            return;
        }

        require(yearnData.pricePerShare > 0, "zero Yearn price per share");
        require(
            yearnData.safeAssets == Math.mulDiv(yearnData.safeShares, yearnData.pricePerShare, 1 ether),
            "Yearn Safe asset value mismatch"
        );
        if (yearnData.rewardShares == 0) {
            require(yearnData.expectedLpAssets == 0, "unexpected zero-reward Yearn assets");
            return;
        }

        require(yearnData.rewardShares < yearnData.safeShares, "Yearn withdrawal consumes principal shares");
        require(
            yearnData.expectedLpAssets == Math.mulDiv(yearnData.rewardShares, yearnData.pricePerShare, 1 ether),
            "Yearn expected LP mismatch"
        );
        require(
            Math.mulDiv(yearnData.safeShares - yearnData.rewardShares, yearnData.pricePerShare, 1 ether)
                >= yearnData.retainedPrincipalAssets,
            "Yearn retained principal mismatch"
        );
    }

    function _validateCurveWithdrawalData(CurveWithdrawalData memory curveData) internal pure {
        require(curveData.slippageBps <= MAX_CURVE_SLIPPAGE_BPS, "Curve slippage exceeds 1%");
        if (curveData.lpAmount == 0) {
            require(
                curveData.expectedFrxUsd == 0 && curveData.expectedDusd == 0 && curveData.minimumFrxUsd == 0
                    && curveData.minimumDusd == 0,
                "unexpected zero-LP Curve output"
            );
            return;
        }

        require(curveData.expectedFrxUsd > 0 && curveData.expectedDusd > 0, "zero Curve withdrawal output");
        require(
            curveData.minimumFrxUsd
                == Math.mulDiv(curveData.expectedFrxUsd, BPS_DENOMINATOR - curveData.slippageBps, BPS_DENOMINATOR),
            "Curve frxUSD minimum mismatch"
        );
        require(
            curveData.minimumDusd
                == Math.mulDiv(curveData.expectedDusd, BPS_DENOMINATOR - curveData.slippageBps, BPS_DENOMINATOR),
            "Curve DUSD minimum mismatch"
        );
    }

    function _validateSimulatedYearnWithdrawal(ClaimSimulationState memory state, YearnWithdrawalData memory yearnData)
        internal
        view
    {
        IYearnV2Vault vault = IYearnV2Vault(YEARN_VAULT);
        uint256 sharesAfter = vault.balanceOf(TREASURY_SAFE);
        uint256 curveLpAfter = IERC20(DUSD_FRXUSD_CURVE_POOL).balanceOf(TREASURY_SAFE);
        if (yearnData.rewardShares == 0) {
            require(sharesAfter == state.yearnSharesBefore, "zero-reward Yearn shares changed");
            require(curveLpAfter == state.curveLpBefore, "zero-reward Curve LP changed");
            return;
        }

        require(sharesAfter == state.yearnSharesBefore - yearnData.rewardShares, "Yearn share burn mismatch");
        uint256 minimumLpAssets =
            Math.mulDiv(yearnData.expectedLpAssets, BPS_DENOMINATOR - yearnData.maxLossBps, BPS_DENOMINATOR);
        require(curveLpAfter >= state.curveLpBefore + minimumLpAssets, "Yearn LP withdrawal below maximum loss");
        require(
            Math.mulDiv(sharesAfter, vault.pricePerShare(), 1 ether) >= yearnData.retainedPrincipalAssets,
            "Yearn principal not retained"
        );
    }

    function _validateConsolidationBalances(
        uint256 scrvUsdAmount,
        uint256 crvAmount,
        uint256 cvxAmount,
        uint256 wfraxAmount,
        uint256 frxUsdAmount,
        uint256 dusdAmount
    ) internal view {
        require(ICowSettlement(COW_SETTLEMENT).vaultRelayer() == COW_VAULT_RELAYER, "CoW relayer mismatch");
        require(IERC4626(SCRVUSD).asset() == CRVUSD, "scrvUSD asset is not crvUSD");
        require(IERC20(SCRVUSD).balanceOf(TREASURY_SAFE) >= scrvUsdAmount, "insufficient scrvUSD balance");
        require(IERC20(CRV).balanceOf(TREASURY_SAFE) >= crvAmount, "insufficient CRV balance");
        require(IERC20(CVX).balanceOf(TREASURY_SAFE) >= cvxAmount, "insufficient CVX balance");
        require(IERC20(WFRAX).balanceOf(TREASURY_SAFE) >= wfraxAmount, "insufficient WFRAX balance");
        require(IERC20(FRXUSD).balanceOf(TREASURY_SAFE) >= frxUsdAmount, "insufficient frxUSD balance");
        require(IERC20(DUSD).balanceOf(TREASURY_SAFE) >= dusdAmount, "insufficient DUSD balance");
    }

    function _validateCowOrder(CowOrderData memory order) internal pure {
        bool consolidationPair = order.buyToken == CRVUSD
            && (order.sellToken == CRV
                || order.sellToken == CVX
                || order.sellToken == WFRAX
                || order.sellToken == FRXUSD
                || order.sellToken == DUSD);
        bool surplusPair = order.sellToken == CRVUSD && order.buyToken == USDC;
        require(consolidationPair || surplusPair, "unsupported CoW pair");
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

    function _validateConvexCreditLineState() internal view {
        IConvexCreditLineMarket market = IConvexCreditLineMarket(CONVEX_CREDIT_LINE_MARKET);
        require(market.convexRewardPool() == CONVEX_REWARD_POOL, "credit line reward pool changed");
        require(market.rewardRecipient() == TREASURY_SAFE, "credit line reward recipient changed");
        require(market.rewardToken(0) == CRV, "credit line CRV reward changed");
        require(market.rewardToken(1) == CVX, "credit line CVX reward changed");
        require(market.rewardToken(2) == WFRAX, "credit line WFRAX reward changed");
        (bool unexpectedRewardToken,) =
            CONVEX_CREDIT_LINE_MARKET.staticcall(abi.encodeCall(IConvexCreditLineMarket.rewardToken, (3)));
        require(!unexpectedRewardToken, "unexpected credit line reward token");
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

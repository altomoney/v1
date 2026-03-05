import {
  createPublicClient,
  http,
  parseAbiItem,
  formatEther,
  type Address,
  type PublicClient,
} from "viem";
import { mainnet } from "viem/chains";

const RPC_URL = process.env.RPC_URL ?? "https://eth-mainnet.g.alchemy.com/v2/77cV4gmcDi4c8scxsA1YH";

const client = createPublicClient({
  chain: mainnet,
  transport: http(RPC_URL),
});

const MINT_MARKETS: Record<string, Address> = {
  WETH: "0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff",
  wstETH: "0xfd8c25047f4397dC5461B919999585a2a3EaC2eF",
  rETH: "0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf",
  mETH: "0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b",
  tBTC: "0xE17F10f8535336143d4F2FE304f3Dcf7B23671e1",
};

const liquidationEvent = parseAbiItem(
  "event Liquidation(address indexed user, address liquidator, uint256 liquidatedCollateral, uint256 protocolFee, uint256 repaidBorrow, uint256 repaidBorrowShares, uint256 badDebtClearedAssets, uint256 badDebtClearedShares)"
);

const govLiquidationEvent = parseAbiItem(
  "event GovernanceLiquidation(address indexed user, address liquidator, uint256 liquidatedCollateral, uint256 badDebtClearedAssets, uint256 badDebtClearedShares)"
);

const setDebtCeilingEvent = parseAbiItem(
  "event SetDebtCeiling(uint256 oldDebtCeiling, uint256 newDebtCeiling)"
);

const marketAbi = [
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "assets", type: "uint128" },
      { name: "shares", type: "uint128" },
    ],
  },
  {
    name: "totalBorrowed",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "assets", type: "uint128" },
      { name: "shares", type: "uint128" },
    ],
  },
] as const;

async function getBadDebtFromEvents(
  client: PublicClient,
  market: Address
): Promise<{ fromLiquidations: bigint; fromGovLiquidations: bigint; events: number }> {
  const [liquidationLogs, govLiquidationLogs] = await Promise.all([
    client.getLogs({
      address: market,
      event: liquidationEvent,
      fromBlock: 0n,
      toBlock: "latest",
    }),
    client.getLogs({
      address: market,
      event: govLiquidationEvent,
      fromBlock: 0n,
      toBlock: "latest",
    }),
  ]);

  let fromLiquidations = 0n;
  for (const log of liquidationLogs) {
    const badDebt = log.args.badDebtClearedAssets ?? 0n;
    if (badDebt > 0n) {
      console.log(
        `    Liquidation bad debt: ${formatEther(badDebt)} | user: ${log.args.user} | tx: ${log.transactionHash}`
      );
    }
    fromLiquidations += badDebt;
  }

  let fromGovLiquidations = 0n;
  for (const log of govLiquidationLogs) {
    const badDebt = log.args.badDebtClearedAssets ?? 0n;
    if (badDebt > 0n) {
      console.log(
        `    GovLiquidation bad debt: ${formatEther(badDebt)} | user: ${log.args.user} | tx: ${log.transactionHash}`
      );
    }
    fromGovLiquidations += badDebt;
  }

  return {
    fromLiquidations,
    fromGovLiquidations,
    events: liquidationLogs.length + govLiquidationLogs.length,
  };
}

async function getDebtCeilingHistory(
  client: PublicClient,
  market: Address
): Promise<{ initial: bigint; current: bigint }> {
  const logs = await client.getLogs({
    address: market,
    event: setDebtCeilingEvent,
    fromBlock: 0n,
    toBlock: "latest",
  });

  if (logs.length === 0) {
    return { initial: 0n, current: 0n };
  }

  const initial = logs[0].args.newDebtCeiling ?? 0n;
  const current = logs[logs.length - 1].args.newDebtCeiling ?? 0n;

  return { initial, current };
}

async function sanityCheck(
  client: PublicClient,
  market: Address,
  totalBadDebt: bigint
) {
  const [totalSupply, totalBorrowed, debtCeiling] = await Promise.all([
    client.readContract({ address: market, abi: marketAbi, functionName: "totalSupply" }),
    client.readContract({ address: market, abi: marketAbi, functionName: "totalBorrowed" }),
    getDebtCeilingHistory(client, market),
  ]);

  const currentDebtCeiling = totalSupply[0]; // totalSupply.assets IS the debt ceiling for mint markets
  const currentBorrowed = totalBorrowed[0];

  // In the old implementation, bad debt reduced totalSupply.assets (debt ceiling).
  // So: originalDebtCeiling - cumulativeBadDebt = currentDebtCeiling (if no setDebtCeiling calls changed it)
  // If setDebtCeiling was called, the last SetDebtCeiling event's newDebtCeiling should match currentDebtCeiling.
  const lastSetCeiling = debtCeiling.current;
  const ceilingMatchesLastSet = lastSetCeiling === 0n || currentDebtCeiling === lastSetCeiling - totalBadDebt;

  console.log(`    --- Sanity Check ---`);
  console.log(`    Current debt ceiling (totalSupply.assets): ${formatEther(currentDebtCeiling)}`);
  console.log(`    Current borrowed (totalBorrowed.assets):   ${formatEther(currentBorrowed)}`);
  console.log(`    Last SetDebtCeiling value:                 ${formatEther(lastSetCeiling)}`);
  console.log(`    Expected ceiling (lastSet - badDebt):      ${formatEther(lastSetCeiling - totalBadDebt)}`);

  if (lastSetCeiling > 0n) {
    const expected = lastSetCeiling - totalBadDebt;
    if (expected === currentDebtCeiling) {
      console.log(`    ✓ Debt ceiling matches: lastSetCeiling - badDebt == currentDebtCeiling`);
    } else {
      const diff = currentDebtCeiling - expected;
      console.log(`    ✗ Mismatch! diff = ${formatEther(diff)} (could indicate intermediate setDebtCeiling calls)`);
    }
  }

  // After upgrade, the new debt ceiling check is: totalBorrowed + badDebtAssets <= totalSupply.assets
  // Make sure the upgrade won't brick borrowing by making this check fail
  const postUpgradeCeiling = currentDebtCeiling; // totalSupply.assets won't change on upgrade
  const postUpgradeEffectiveUsed = currentBorrowed + totalBadDebt;
  if (postUpgradeEffectiveUsed > postUpgradeCeiling) {
    console.log(
      `    ⚠ WARNING: After upgrade, borrowed + badDebt (${formatEther(postUpgradeEffectiveUsed)}) > ceiling (${formatEther(postUpgradeCeiling)}). New borrows will be blocked until debt ceiling is raised!`
    );
  } else {
    console.log(
      `    ✓ Post-upgrade headroom: ${formatEther(postUpgradeCeiling - postUpgradeEffectiveUsed)} available for new borrows`
    );
  }
}

const SUBGRAPH_URL =
  "https://api.goldsky.com/api/public/project_cll6foogb576z38zr00ybh2hw/subgraphs/alto-lending-mainnet/0.0.4/gn";

interface SubgraphBadDebt {
  badDebt: string;
  badDebtUSD: string;
  market: { id: string };
  liquidation: { hash: string };
}

async function getSubgraphBadDebt(): Promise<Map<string, { total: bigint; entries: SubgraphBadDebt[] }>> {
  const query = `{
    badDebtRealizations(first: 1000) {
      badDebtUSD
      badDebt
      market {
        id
      }
      liquidation {
        hash
      }
    }
  }`;

  const res = await fetch(SUBGRAPH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });

  const json = (await res.json()) as { data: { badDebtRealizations: SubgraphBadDebt[] } };
  const entries = json.data.badDebtRealizations;

  const byMarket = new Map<string, { total: bigint; entries: SubgraphBadDebt[] }>();

  for (const entry of entries) {
    const marketId = entry.market.id.toLowerCase();
    const existing = byMarket.get(marketId) ?? { total: 0n, entries: [] };
    existing.total += BigInt(entry.badDebt);
    existing.entries.push(entry);
    byMarket.set(marketId, existing);
  }

  return byMarket;
}

async function main() {
  console.log(`Using RPC: ${RPC_URL.replace(/\/v2\/.*/, "/v2/***")}`);
  console.log(`Block: ${await client.getBlockNumber()}\n`);

  const subgraphData = await getSubgraphBadDebt();

  const results: Record<string, bigint> = {};

  for (const [name, address] of Object.entries(MINT_MARKETS)) {
    console.log(`\n=== ${name} Market (${address}) ===\n`);

    const { fromLiquidations, fromGovLiquidations, events } = await getBadDebtFromEvents(
      client,
      address
    );

    const total = fromLiquidations + fromGovLiquidations;
    results[name] = total;

    console.log(`\n    Total liquidation events: ${events}`);
    console.log(`    Bad debt from liquidations:     ${formatEther(fromLiquidations)}`);
    console.log(`    Bad debt from gov liquidations:  ${formatEther(fromGovLiquidations)}`);
    console.log(`    Total bad debt:                  ${formatEther(total)}`);
    console.log(`    Total bad debt (raw):            ${total.toString()}`);

    // Subgraph cross-check
    const sgData = subgraphData.get(address.toLowerCase());
    const sgTotal = sgData?.total ?? 0n;
    console.log(`\n    --- Subgraph Cross-Check ---`);
    console.log(`    Subgraph bad debt total:         ${formatEther(sgTotal)}`);
    if (sgData) {
      for (const e of sgData.entries) {
        console.log(`      badDebt: ${formatEther(BigInt(e.badDebt))} | badDebtUSD: ${e.badDebtUSD} | tx: ${e.liquidation.hash}`);
      }
    }
    if (sgTotal === total) {
      console.log(`    ✓ Subgraph matches on-chain events`);
    } else {
      console.log(`    ✗ MISMATCH: on-chain=${formatEther(total)} vs subgraph=${formatEther(sgTotal)}`);
    }

    await sanityCheck(client, address, total);
  }

  // Log any subgraph bad debt for non-mint markets (shouldn't exist for mint markets, but good to know)
  const mintAddresses = new Set(Object.values(MINT_MARKETS).map((a) => a.toLowerCase()));
  for (const [marketId, data] of subgraphData) {
    if (!mintAddresses.has(marketId)) {
      console.log(`\n    [info] Subgraph bad debt on non-mint market ${marketId}: ${formatEther(data.total)}`);
    }
  }

  // Summary for copy-paste into the upgrade script
  console.log(`\n\n${"=".repeat(60)}`);
  console.log(`SUMMARY — Values for UpgradeMarkets.s.sol`);
  console.log(`${"=".repeat(60)}\n`);

  for (const [name, badDebt] of Object.entries(results)) {
    const constName = `${name.toUpperCase().replace(/[^A-Z]/g, "")}_BAD_DEBT`;
    console.log(`    uint128 constant ${constName} = ${badDebt.toString()};  // ${formatEther(badDebt)}`);
  }
}

main().catch(console.error);

#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

const DEFAULT_SUBGRAPH_URL =
  "https://api.goldsky.com/api/public/project_cll6foogb576z38zr00ybh2hw/subgraphs/alto-lending-mainnet/0.0.6/gn";
const PAGE_SIZE = 1000;
const SEVERITIES = ["medium", "high", "critical"] as const;

type Address = `0x${string}`;
type Manifest = {
  activationId: string;
  severity: number;
  sourceBlock: number;
  step: number;
  markets: { market: Address }[];
};
type Metadata = { block: { number: number | string }; hasIndexingErrors: boolean };
type QueryData = {
  positions: { account: { id: string }; id: string }[];
  sourceMeta: Pick<Metadata, "hasIndexingErrors">;
  headMeta: Metadata;
};
type QueryVariables = { cursor: string; first: number; market: Address; sourceBlock: number };
type MarketBorrowers = { borrowers: Address[]; market: Address };

const QUERY = `
  query BorrowerPositions($market: String!, $sourceBlock: Int!, $cursor: ID!, $first: Int!) {
    positions(
      first: $first
      orderBy: id
      orderDirection: asc
      block: { number: $sourceBlock }
      where: { market: $market, side: BORROWER, id_gt: $cursor }
    ) {
      id
      account { id }
    }
    sourceMeta: _meta(block: { number: $sourceBlock }) {
      hasIndexingErrors
    }
    headMeta: _meta {
      block { number }
      hasIndexingErrors
    }
  }
`;

async function fetchPage(subgraphUrl: string, variables: QueryVariables): Promise<QueryData> {
  const response = await fetch(subgraphUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query: QUERY, variables }),
  });
  if (!response.ok) {
    throw new Error(`Goldsky request failed: ${response.status} ${await response.text()}`);
  }
  const body = (await response.json()) as { data?: QueryData; errors?: unknown[] };
  if (body.errors?.length) throw new Error(`Goldsky query failed: ${JSON.stringify(body.errors)}`);
  if (!body.data) throw new Error("Goldsky response is missing data");
  return body.data;
}

function validateMetadata(data: QueryData, sourceBlock: number) {
  if (data.sourceMeta.hasIndexingErrors || data.headMeta.hasIndexingErrors) {
    throw new Error("Goldsky reports indexing errors");
  }
  const headBlock = Number(data.headMeta.block.number);
  if (!Number.isSafeInteger(headBlock) || headBlock < sourceBlock) {
    throw new Error(`Goldsky is behind source block ${sourceBlock}: ${headBlock}`);
  }
}

async function fetchBorrowers(
  market: Address,
  sourceBlock: number,
  subgraphUrl: string,
): Promise<Address[]> {
  const borrowers = new Set<Address>();
  let cursor = "";
  for (;;) {
    const data = await fetchPage(subgraphUrl, {
      market: market.toLowerCase() as Address,
      sourceBlock,
      cursor,
      first: PAGE_SIZE,
    });
    validateMetadata(data, sourceBlock);
    for (const { account } of data.positions) borrowers.add(account.id.toLowerCase() as Address);
    if (data.positions.length < PAGE_SIZE) break;
    const nextCursor = data.positions.at(-1)?.id;
    if (!nextCursor || nextCursor === cursor) throw new Error("Goldsky pagination did not advance");
    cursor = nextCursor;
  }
  return [...borrowers].sort();
}

async function main() {
  const [manifestPath, outputPath] = process.argv.slice(2);
  if (!manifestPath || !outputPath) {
    throw new Error("usage: node ERP/scripts/fetch-borrowers.ts <manifest.json> <borrowers.json>");
  }

  const manifest = JSON.parse(await readFile(manifestPath, "utf8")) as Manifest;
  if (!Number.isSafeInteger(manifest.sourceBlock) || manifest.sourceBlock <= 0) {
    throw new Error("manifest sourceBlock must be a positive safe integer");
  }
  if (!manifest.markets?.length) throw new Error("manifest must contain at least one market");
  if (!SEVERITIES[manifest.severity]) throw new Error(`invalid manifest severity: ${manifest.severity}`);

  const subgraphUrl = process.env.GOLDSKY_SUBGRAPH_URL || DEFAULT_SUBGRAPH_URL;
  const markets: MarketBorrowers[] = [];
  for (const { market } of manifest.markets) {
    const borrowers = await fetchBorrowers(market, manifest.sourceBlock, subgraphUrl);
    markets.push({ borrowers, market });
  }

  const output = { chainId: 1, markets, sourceBlock: manifest.sourceBlock, subgraphUrl };
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`);
  process.stdout.write(JSON.stringify(output));
}

await main();

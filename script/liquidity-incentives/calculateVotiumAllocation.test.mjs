import assert from "node:assert/strict";
import test from "node:test";
import { calculateVotiumAllocation, createVotiumAllocation } from "./calculateVotiumAllocation.mjs";

const frxUsd = "0xcacd6fd266af91b8aed52accc382b4e165586e29";
const crvUsd = "0xf939e0a03fb07f59a73314e73794be0e57ac1b4e";
const depositor = "0x6e74053a3798e0fc9a9775f7995316b27f21c4d2";
const oneEther = 10n ** 18n;
const fixedTimestamp = "2026-09-14T15:00:00.000Z";

function fraction(value) {
  const [whole, decimal = ""] = String(value).split(".");
  return {
    numerator: BigInt(`${whole}${decimal}`),
    denominator: 10n ** BigInt(decimal.length),
    display: String(value),
  };
}

function allocation(overrides = {}) {
  return calculateVotiumAllocation({
    round: 131,
    capUsd: "16000",
    crvUsdProceeds: (20_000n * oneEther).toString(),
    platformFee: "200",
    feeDenominator: "10000",
    externalIncentives: [{
      token: frxUsd,
      amount: (3_290_840_000_000_000_000_000n).toString(),
      decimals: 18,
      depositor,
    }],
    prices: new Map([
      [frxUsd, fraction("0.999642")],
      [crvUsd, fraction("0.9998")],
    ]),
    priceReferenceTimestamp: fixedTimestamp,
    ...overrides,
  });
}

test("caps combined stored incentives and sends the remaining proceeds to surplus", () => {
  const result = allocation();
  const gross = BigInt(result.votiumGrossAmount);
  const fee = gross * 200n / 10_000n;

  assert.equal(result.externalUsdValue, "3289.661879");
  assert.equal(BigInt(result.votiumFeeAmount), fee);
  assert.equal(BigInt(result.votiumStoredAmount), gross - fee);
  assert.equal(
    BigInt(result.votiumGrossAmount) + BigInt(result.surplusCrvUsdAmount),
    20_000n * oneEther,
  );
  assert.equal(result.retainedSurplusCrvUsdAmount, result.surplusCrvUsdAmount);
  assert.equal(result.cowSurplusCrvUsdAmount, undefined);
  assert.ok(Number(result.combinedUsdValue) <= 16_000);
  assert.ok(Number(result.combinedUsdValue) > 15_999.99);
});

test("deposits all proceeds when they are below the remaining cap", () => {
  const proceeds = 5_000n * oneEther;
  const result = allocation({ crvUsdProceeds: proceeds.toString() });

  assert.equal(result.votiumGrossAmount, proceeds.toString());
  assert.equal(result.surplusCrvUsdAmount, "0");
  assert.equal(result.retainedSurplusCrvUsdAmount, "0");
});

test("uses no Alto incentive when third-party incentives already consume the cap", () => {
  const result = allocation({
    externalIncentives: [{
      token: frxUsd,
      amount: (17_000n * oneEther).toString(),
      decimals: 18,
      depositor,
    }],
  });

  assert.equal(result.votiumGrossAmount, "0");
  assert.equal(result.surplusCrvUsdAmount, (20_000n * oneEther).toString());
  assert.equal(result.retainedSurplusCrvUsdAmount, result.surplusCrvUsdAmount);
  assert.equal(result.externalCapExceeded, true);
});

test("retains one wei of surplus while preserving the Votium deposit amount", () => {
  const maximumGross = 16_000n * oneEther * 10_000n / 9_800n;
  const result = allocation({
    crvUsdProceeds: (maximumGross + 1n).toString(),
    externalIncentives: [],
    prices: new Map([[crvUsd, fraction("1")]]),
  });

  assert.equal(result.votiumGrossAmount, maximumGross.toString());
  assert.equal(result.surplusCrvUsdAmount, "1");
  assert.equal(result.retainedSurplusCrvUsdAmount, "1");
});

test("retains a one crvUSD surplus in Treasury", () => {
  const maximumGross = 16_000n * oneEther * 10_000n / 9_800n;
  const result = allocation({
    crvUsdProceeds: (maximumGross + oneEther).toString(),
    externalIncentives: [],
    prices: new Map([[crvUsd, fraction("1")]]),
  });

  assert.equal(result.surplusCrvUsdAmount, oneEther.toString());
  assert.equal(result.retainedSurplusCrvUsdAmount, oneEther.toString());
});

test("retains all proceeds without a Votium deposit when external incentives exhaust the cap", () => {
  const result = allocation({
    crvUsdProceeds: "1",
    externalIncentives: [{
      token: frxUsd,
      amount: (17_000n * oneEther).toString(),
      decimals: 18,
      depositor,
    }],
  });

  assert.equal(result.votiumGrossAmount, "0");
  assert.equal(result.surplusCrvUsdAmount, "1");
  assert.equal(result.retainedSurplusCrvUsdAmount, "1");
});

test("fetches each unique token price once", async () => {
  const calls = [];
  const result = await createVotiumAllocation({
    round: 131,
    capUsd: "16000",
    crvUsdProceeds: (5_000n * oneEther).toString(),
    platformFee: "200",
    feeDenominator: "10000",
    externalIncentives: [
      { token: frxUsd, amount: oneEther.toString(), decimals: 18, depositor },
      { token: frxUsd, amount: oneEther.toString(), decimals: 18, depositor },
    ],
    fetchImpl: async (url) => {
      calls.push(url);
      return new Response(JSON.stringify({ price: url.includes(frxUsd) ? 0.999642 : 0.9998 }), { status: 200 });
    },
    now: () => new Date(fixedTimestamp),
  });

  assert.equal(calls.length, 2);
  assert.equal(result.priceReferenceTimestamp, fixedTimestamp);
});

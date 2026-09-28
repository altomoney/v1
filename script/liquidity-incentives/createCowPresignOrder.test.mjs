import assert from "node:assert/strict";
import test from "node:test";
import { buildPresignOrder, buildQuoteAnalytics, createCowPresignOrder } from "./createCowPresignOrder.mjs";

const safe = "0xa1148a1b94262540994cf9aa431a13ad39764228";
const crv = "0xd533a949740bb3306d119cc777fa900ba034cd52";
const wfrax = "0x04acaf8d2865c0714f79da09645c13fd2888977f";
const frxUsd = "0xcacd6fd266af91b8aed52accc382b4e165586e29";
const dusd = "0x63d74d22e689c715a04f2c13962b1f77f443d35b";
const crvUsd = "0xf939e0a03fb07f59a73314e73794be0e57ac1b4e";
const usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
const uid = `0x${"11".repeat(32)}${safe.slice(2)}${"70000000"}`;
const oneEther = 10n ** 18n;
const requestedSellAmount = (1_000n * oneEther).toString();
const fixedTimestamp = "2026-07-20T12:00:00.000Z";

function quoteResponse(sellToken = crv, buyToken = crvUsd) {
  return {
    id: 42,
    quote: {
      sellToken,
      buyToken,
      receiver: safe,
      sellAmount: (990n * oneEther).toString(),
      buyAmount: (buyToken === usdc ? 500n * 10n ** 6n : 500n * oneEther).toString(),
      validTo: 1_879_048_192,
      appData: `0x${"00".repeat(32)}`,
      feeAmount: (10n * oneEther).toString(),
      kind: "sell",
      partiallyFillable: false,
      sellTokenBalance: "erc20",
      buyTokenBalance: "erc20",
      signingScheme: "presign",
    },
  };
}

function priceResponse(url) {
  if (url.includes(crv)) return new Response(JSON.stringify({ price: 1 }), { status: 200 });
  if (url.includes(wfrax) || url.includes(frxUsd) || url.includes(dusd)) {
    return new Response(JSON.stringify({ price: 1 }), { status: 200 });
  }
  if (url.includes(crvUsd)) return new Response(JSON.stringify({ price: 2 }), { status: 200 });
  if (url.includes(usdc)) return new Response(JSON.stringify({ price: 1 }), { status: 200 });
  throw new Error(`unexpected price URL: ${url}`);
}

test("buildPresignOrder consumes the exact sell amount and applies slippage", () => {
  const order = buildPresignOrder(quoteResponse(), requestedSellAmount, 100);
  assert.equal(order.sellAmount, requestedSellAmount);
  assert.equal(order.buyAmount, (495n * oneEther).toString());
  assert.equal(order.feeAmount, "0");
  assert.equal(order.signature, safe);
});

test("buildPresignOrder rejects a quote that changes the requested sell amount", () => {
  assert.throws(() => buildPresignOrder(quoteResponse(), (1_001n * oneEther).toString(), 100), /exact requested sell amount/);
});

test("quote analytics reports price improvement as negative impact", () => {
  const order = buildPresignOrder(quoteResponse(), requestedSellAmount, 100);
  const analytics = buildQuoteAnalytics(
    order,
    { numerator: 1n, denominator: 1n, display: "1" },
    { numerator: 21n, denominator: 10n, display: "2.1" },
    fixedTimestamp,
    "https://price.test",
  );
  assert.equal(analytics.expectedPriceImpactBps, "-500.00");
  assert.equal(analytics.expectedPriceImpactPercent, "-5.0000%");
  assert.equal(analytics.worstCasePriceImpactBps, "-395.00");
});

test("quote-only mode reports expected and worst-case price impact without posting an order", async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (url.endsWith("/quote")) return new Response(JSON.stringify(quoteResponse()), { status: 200 });
    return priceResponse(url);
  };
  const result = await createCowPresignOrder({
    sellToken: crv,
    sellAmount: requestedSellAmount,
    slippageBps: 100,
    validFor: 86_400,
    fetchImpl,
    now: () => new Date(fixedTimestamp),
  });
  assert.equal(result.mode, "quote-only");
  assert.equal(calls.length, 3);
  assert.match(calls[0].url, /\/quote$/);
  assert.equal(calls.filter(({ url }) => url.includes("/orders")).length, 0);
  assert.equal(result.analytics.sellAmountFormatted, "1000");
  assert.equal(result.analytics.quotedBuyAmountFormatted, "500");
  assert.equal(result.analytics.minimumBuyAmountFormatted, "495");
  assert.equal(result.analytics.expectedRate, "0.50000000");
  assert.equal(result.analytics.minimumRate, "0.49500000");
  assert.equal(result.analytics.inputUsdValue, "1000.000000");
  assert.equal(result.analytics.expectedOutputUsdValue, "1000.000000");
  assert.equal(result.analytics.minimumOutputUsdValue, "990.000000");
  assert.equal(result.analytics.inputDisplay, "1000 CRV ($1000.000000)");
  assert.equal(result.analytics.expectedOutputDisplay, "500 crvUSD ($1000.000000)");
  assert.equal(result.analytics.minimumOutputDisplay, "495 crvUSD ($990.000000)");
  assert.equal(result.analytics.networkFeeBps, "100.00");
  assert.equal(result.analytics.expectedPriceImpactBps, "0.00");
  assert.equal(result.analytics.expectedPriceImpactPercent, "0.0000%");
  assert.equal(result.analytics.worstCasePriceImpactBps, "100.00");
  assert.equal(result.analytics.worstCasePriceImpactPercent, "1.0000%");
  assert.equal(result.analytics.priceReferenceTimestamp, fixedTimestamp);
});

test("quote-only mode supports Curve withdrawal coins", async () => {
  for (const [sellToken, symbol] of [[frxUsd, "frxUSD"], [dusd, "DUSD"]]) {
    const fetchImpl = async (url) => {
      if (url.endsWith("/quote")) {
        return new Response(JSON.stringify(quoteResponse(sellToken)), { status: 200 });
      }
      return priceResponse(url);
    };
    const result = await createCowPresignOrder({
      sellToken,
      sellAmount: requestedSellAmount,
      slippageBps: 100,
      validFor: 86_400,
      fetchImpl,
      now: () => new Date(fixedTimestamp),
    });

    assert.equal(result.sellToken, sellToken);
    assert.equal(result.analytics.sellTokenSymbol, symbol);
    assert.equal(result.analytics.inputDisplay, `1000 ${symbol} ($1000.000000)`);
  }
});

test("quote-only mode supports WFRAX rewards", async () => {
  const fetchImpl = async (url) => {
    if (url.endsWith("/quote")) {
      return new Response(JSON.stringify(quoteResponse(wfrax)), { status: 200 });
    }
    return priceResponse(url);
  };
  const result = await createCowPresignOrder({
    sellToken: wfrax,
    sellAmount: requestedSellAmount,
    slippageBps: 100,
    validFor: 86_400,
    fetchImpl,
    now: () => new Date(fixedTimestamp),
  });

  assert.equal(result.sellToken, wfrax);
  assert.equal(result.analytics.inputDisplay, "1000 WFRAX ($1000.000000)");
});

test("quote-only mode supports converting surplus crvUSD to USDC", async () => {
  const fetchImpl = async (url) => {
    if (url.endsWith("/quote")) {
      return new Response(JSON.stringify(quoteResponse(crvUsd, usdc)), { status: 200 });
    }
    return priceResponse(url);
  };
  const result = await createCowPresignOrder({
    sellToken: crvUsd,
    buyToken: usdc,
    sellAmount: requestedSellAmount,
    slippageBps: 100,
    validFor: 86_400,
    fetchImpl,
    now: () => new Date(fixedTimestamp),
  });

  assert.equal(result.sellToken, crvUsd);
  assert.equal(result.buyToken, usdc);
  assert.equal(result.analytics.sellTokenSymbol, "crvUSD");
  assert.equal(result.analytics.buyTokenSymbol, "USDC");
});

test("quote creation fails closed when reference prices are unavailable", async () => {
  const fetchImpl = async (url) => {
    if (url.endsWith("/quote")) return new Response(JSON.stringify(quoteResponse()), { status: 200 });
    return new Response("price service unavailable", { status: 503 });
  };
  await assert.rejects(
    createCowPresignOrder({
      sellToken: crv,
      sellAmount: requestedSellAmount,
      slippageBps: 100,
      validFor: 86_400,
      fetchImpl,
    }),
    /USD price failed \(503\)/,
  );
});

test("submit mode posts and verifies the presign order", async () => {
  const fetchImpl = async (url, init) => {
    if (url.endsWith("/quote")) return new Response(JSON.stringify(quoteResponse()), { status: 200 });
    if (url.includes("/usdPrice")) return priceResponse(url);
    if (url.endsWith("/orders") && init?.method === "POST") {
      return new Response(JSON.stringify(uid), { status: 201 });
    }
    if (url.endsWith(`/orders/${uid}`)) {
      return new Response(JSON.stringify({
        ...buildPresignOrder(quoteResponse(), requestedSellAmount, 100),
        owner: safe,
        status: "presignaturePending",
      }), { status: 200 });
    }
    throw new Error(`unexpected URL: ${url}`);
  };
  const result = await createCowPresignOrder({
    sellToken: crv,
    sellAmount: requestedSellAmount,
    slippageBps: 100,
    validFor: 86_400,
    submit: true,
    fetchImpl,
    now: () => new Date(fixedTimestamp),
  });
  assert.equal(result.mode, "submitted");
  assert.equal(result.orderUid, uid);
  assert.equal(result.status, "presignaturePending");
  assert.equal(result.analytics.expectedPriceImpactBps, "0.00");
});

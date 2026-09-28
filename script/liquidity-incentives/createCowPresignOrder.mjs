#!/usr/bin/env node

const DEFAULT_API_BASE_URL = "https://api.cow.fi/mainnet/api/v1";
const DEFAULT_PRICE_API_BASE_URL = "https://bff.cow.fi/1/tokens";
const TREASURY_SAFE = "0xa1148a1b94262540994cf9aa431a13ad39764228";
const CRVUSD = "0xf939e0a03fb07f59a73314e73794be0e57ac1b4e";
const TOKEN_METADATA = new Map([
  ["0xd533a949740bb3306d119cc777fa900ba034cd52", { symbol: "CRV", decimals: 18 }],
  ["0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b", { symbol: "CVX", decimals: 18 }],
  ["0x04acaf8d2865c0714f79da09645c13fd2888977f", { symbol: "WFRAX", decimals: 18 }],
  ["0xcacd6fd266af91b8aed52accc382b4e165586e29", { symbol: "frxUSD", decimals: 18 }],
  ["0x63d74d22e689c715a04f2c13962b1f77f443d35b", { symbol: "DUSD", decimals: 18 }],
  [CRVUSD, { symbol: "crvUSD", decimals: 18 }],
]);
const SUPPORTED_PAIRS = new Set([
  ...[...TOKEN_METADATA.keys()]
    .filter((token) => token !== CRVUSD)
    .map((token) => `${token}:${CRVUSD}`),
]);
const ADDRESS_PATTERN = /^0x[0-9a-fA-F]{40}$/;
const UID_PATTERN = /^0x[0-9a-fA-F]{112}$/;

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

function normalizeAddress(value, label) {
  requireCondition(ADDRESS_PATTERN.test(value), `${label} must be an address`);
  return value.toLowerCase();
}

function parseUnsignedInteger(value, label) {
  requireCondition(/^\d+$/.test(value), `${label} must be an unsigned integer`);
  return BigInt(value);
}

async function readJson(response, label) {
  const body = await response.text();
  if (!response.ok) throw new Error(`${label} failed (${response.status}): ${body}`);
  try {
    return JSON.parse(body);
  } catch {
    throw new Error(`${label} returned invalid JSON: ${body}`);
  }
}

function decimalToFraction(value, label) {
  const normalized = String(value).toLowerCase();
  const match = normalized.match(/^(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/);
  requireCondition(match, `${label} must be a positive decimal`);

  const fractionalDigits = match[2] || "";
  const exponent = Number(match[3] || "0");
  requireCondition(Number.isSafeInteger(exponent), `${label} exponent is invalid`);

  let numerator = BigInt(`${match[1]}${fractionalDigits}`);
  const scale = fractionalDigits.length - exponent;
  let denominator = 1n;
  if (scale >= 0) denominator = 10n ** BigInt(scale);
  else numerator *= 10n ** BigInt(-scale);

  requireCondition(numerator > 0n, `${label} must be greater than zero`);
  return { numerator, denominator, display: normalized };
}

function formatFraction(numerator, denominator, decimals) {
  requireCondition(denominator > 0n, "fraction denominator must be positive");
  const negative = numerator < 0n;
  const absolute = negative ? -numerator : numerator;
  const scale = 10n ** BigInt(decimals);
  const rounded = (absolute * scale + denominator / 2n) / denominator;
  const whole = rounded / scale;
  const fraction = decimals === 0 ? "" : `.${(rounded % scale).toString().padStart(decimals, "0")}`;
  return `${negative && rounded !== 0n ? "-" : ""}${whole}${fraction}`;
}

function formatUnits(amount, decimals) {
  const scale = 10n ** BigInt(decimals);
  const whole = amount / scale;
  const fraction = (amount % scale).toString().padStart(decimals, "0").replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole.toString();
}

async function fetchUsdPrice(token, priceApiBaseUrl, fetchImpl) {
  const response = await readJson(await fetchImpl(`${priceApiBaseUrl}/${token}/usdPrice`), `${TOKEN_METADATA.get(token).symbol} USD price`);
  requireCondition(response && (typeof response.price === "number" || typeof response.price === "string"), "USD price response is missing price");
  return decimalToFraction(response.price, `${TOKEN_METADATA.get(token).symbol} USD price`);
}

function priceImpactFraction(sellAmount, sellToken, sellPrice, buyAmount, buyToken, buyPrice) {
  const sellDecimals = TOKEN_METADATA.get(sellToken).decimals;
  const buyDecimals = TOKEN_METADATA.get(buyToken).decimals;
  const inputNumerator = sellAmount * sellPrice.numerator;
  const inputDenominator = 10n ** BigInt(sellDecimals) * sellPrice.denominator;
  const outputNumerator = buyAmount * buyPrice.numerator;
  const outputDenominator = 10n ** BigInt(buyDecimals) * buyPrice.denominator;
  return {
    numerator: inputNumerator * outputDenominator - outputNumerator * inputDenominator,
    denominator: inputNumerator * outputDenominator,
  };
}

export function buildQuoteAnalytics(order, sellPrice, buyPrice, priceReferenceTimestamp, priceApiBaseUrl) {
  const sellToken = TOKEN_METADATA.get(order.sellToken);
  const buyToken = TOKEN_METADATA.get(order.buyToken);
  requireCondition(sellToken && buyToken, "missing token metadata for quote analytics");

  const sellAmount = BigInt(order.sellAmount);
  const quotedBuyAmount = BigInt(order.quotedBuyAmount);
  const minimumBuyAmount = BigInt(order.buyAmount);
  const networkFeeAmount = BigInt(order.networkFeeAmount);
  const expectedImpact = priceImpactFraction(
    sellAmount,
    order.sellToken,
    sellPrice,
    quotedBuyAmount,
    order.buyToken,
    buyPrice,
  );
  const worstCaseImpact = priceImpactFraction(
    sellAmount,
    order.sellToken,
    sellPrice,
    minimumBuyAmount,
    order.buyToken,
    buyPrice,
  );
  const inputUsdNumerator = sellAmount * sellPrice.numerator;
  const inputUsdDenominator = 10n ** BigInt(sellToken.decimals) * sellPrice.denominator;
  const expectedUsdNumerator = quotedBuyAmount * buyPrice.numerator;
  const expectedUsdDenominator = 10n ** BigInt(buyToken.decimals) * buyPrice.denominator;
  const minimumUsdNumerator = minimumBuyAmount * buyPrice.numerator;
  const minimumUsdDenominator = 10n ** BigInt(buyToken.decimals) * buyPrice.denominator;
  const sellAmountFormatted = formatUnits(sellAmount, sellToken.decimals);
  const quotedBuyAmountFormatted = formatUnits(quotedBuyAmount, buyToken.decimals);
  const minimumBuyAmountFormatted = formatUnits(minimumBuyAmount, buyToken.decimals);
  const inputUsdValue = formatFraction(inputUsdNumerator, inputUsdDenominator, 6);
  const expectedOutputUsdValue = formatFraction(expectedUsdNumerator, expectedUsdDenominator, 6);
  const minimumOutputUsdValue = formatFraction(minimumUsdNumerator, minimumUsdDenominator, 6);

  return {
    methodology: "1 - output USD value / total input USD value; positive is value loss and negative is price improvement",
    priceReferenceSource: "CoW Swap BFF USD prices",
    priceReferenceTimestamp,
    sellTokenPriceUrl: `${priceApiBaseUrl}/${order.sellToken}/usdPrice`,
    buyTokenPriceUrl: `${priceApiBaseUrl}/${order.buyToken}/usdPrice`,
    sellTokenSymbol: sellToken.symbol,
    buyTokenSymbol: buyToken.symbol,
    sellAmountFormatted,
    quotedBuyAmountFormatted,
    minimumBuyAmountFormatted,
    networkFeeAmountFormatted: formatUnits(networkFeeAmount, sellToken.decimals),
    sellTokenUsdPrice: sellPrice.display,
    buyTokenUsdPrice: buyPrice.display,
    inputUsdValue,
    expectedOutputUsdValue,
    minimumOutputUsdValue,
    inputDisplay: `${sellAmountFormatted} ${sellToken.symbol} ($${inputUsdValue})`,
    expectedOutputDisplay: `${quotedBuyAmountFormatted} ${buyToken.symbol} ($${expectedOutputUsdValue})`,
    minimumOutputDisplay: `${minimumBuyAmountFormatted} ${buyToken.symbol} ($${minimumOutputUsdValue})`,
    expectedRate: formatFraction(
      quotedBuyAmount * 10n ** BigInt(sellToken.decimals),
      sellAmount * 10n ** BigInt(buyToken.decimals),
      8,
    ),
    minimumRate: formatFraction(
      minimumBuyAmount * 10n ** BigInt(sellToken.decimals),
      sellAmount * 10n ** BigInt(buyToken.decimals),
      8,
    ),
    networkFeeBps: formatFraction(networkFeeAmount * 10_000n, sellAmount, 2),
    expectedPriceImpactBps: formatFraction(expectedImpact.numerator * 10_000n, expectedImpact.denominator, 2),
    expectedPriceImpactPercent: `${formatFraction(expectedImpact.numerator * 100n, expectedImpact.denominator, 4)}%`,
    worstCasePriceImpactBps: formatFraction(worstCaseImpact.numerator * 10_000n, worstCaseImpact.denominator, 2),
    worstCasePriceImpactPercent: `${formatFraction(worstCaseImpact.numerator * 100n, worstCaseImpact.denominator, 4)}%`,
  };
}

export function buildPresignOrder(quoteResponse, requestedSellAmount, slippageBps) {
  const quote = quoteResponse.quote;
  requireCondition(quote && typeof quote === "object", "quote response is missing quote");
  requireCondition(Number.isInteger(slippageBps) && slippageBps >= 0 && slippageBps <= 1_000, "slippage must be 0-1000 bps");

  const requested = parseUnsignedInteger(requestedSellAmount, "sell amount");
  const quotedSell = parseUnsignedInteger(quote.sellAmount, "quoted sell amount");
  const networkFee = parseUnsignedInteger(quote.feeAmount, "network fee");
  const quotedBuy = parseUnsignedInteger(quote.buyAmount, "quoted buy amount");
  const totalSell = quotedSell + networkFee;
  const minimumBuy = quotedBuy * BigInt(10_000 - slippageBps) / 10_000n;

  requireCondition(requested > 0n, "sell amount must be non-zero");
  requireCondition(totalSell === requested, "quote does not consume the exact requested sell amount");
  requireCondition(minimumBuy > 0n, "minimum buy amount is zero");
  requireCondition(quote.kind === "sell", "quote is not a sell order");
  requireCondition(quote.signingScheme === "presign", "quote is not a presign order");

  return {
    sellToken: normalizeAddress(quote.sellToken, "quoted sell token"),
    buyToken: normalizeAddress(quote.buyToken, "quoted buy token"),
    receiver: normalizeAddress(quote.receiver, "quoted receiver"),
    sellAmount: totalSell.toString(),
    buyAmount: minimumBuy.toString(),
    validTo: quote.validTo,
    appData: quote.appData,
    feeAmount: "0",
    kind: "sell",
    partiallyFillable: false,
    sellTokenBalance: "erc20",
    buyTokenBalance: "erc20",
    from: TREASURY_SAFE,
    quoteId: quoteResponse.id,
    signingScheme: "presign",
    signature: TREASURY_SAFE,
    fullBalanceCheck: false,
    quotedBuyAmount: quotedBuy.toString(),
    networkFeeAmount: networkFee.toString(),
  };
}

function validateServerOrder(serverOrder, expected, orderUid) {
  requireCondition(UID_PATTERN.test(orderUid), "CoW API returned an invalid order UID");
  requireCondition(normalizeAddress(serverOrder.sellToken, "server sell token") === expected.sellToken, "server sell token mismatch");
  requireCondition(normalizeAddress(serverOrder.buyToken, "server buy token") === expected.buyToken, "server buy token mismatch");
  requireCondition(normalizeAddress(serverOrder.receiver, "server receiver") === TREASURY_SAFE, "server receiver mismatch");
  requireCondition(normalizeAddress(serverOrder.owner, "server owner") === TREASURY_SAFE, "server owner mismatch");
  requireCondition(serverOrder.sellAmount === expected.sellAmount, "server sell amount mismatch");
  requireCondition(serverOrder.buyAmount === expected.buyAmount, "server buy amount mismatch");
  requireCondition(serverOrder.validTo === expected.validTo, "server validity mismatch");
  requireCondition(serverOrder.feeAmount === "0", "server fee amount is not zero");
  requireCondition(serverOrder.kind === "sell", "server order is not a sell order");
  requireCondition(serverOrder.partiallyFillable === false, "server order is partially fillable");
  requireCondition(serverOrder.signingScheme === "presign", "server order is not presign");
}

export async function createCowPresignOrder({
  sellToken,
  buyToken = CRVUSD,
  sellAmount,
  slippageBps,
  validFor,
  submit = false,
  apiBaseUrl = DEFAULT_API_BASE_URL,
  priceApiBaseUrl = DEFAULT_PRICE_API_BASE_URL,
  fetchImpl = fetch,
  now = () => new Date(),
}) {
  const normalizedSellToken = normalizeAddress(sellToken, "sell token");
  const normalizedBuyToken = normalizeAddress(buyToken, "buy token");
  requireCondition(
    SUPPORTED_PAIRS.has(`${normalizedSellToken}:${normalizedBuyToken}`),
    "unsupported CoW pair",
  );
  const parsedSellAmount = parseUnsignedInteger(sellAmount, "sell amount");
  requireCondition(parsedSellAmount > 0n, "sell amount must be non-zero");
  requireCondition(Number.isInteger(validFor) && validFor >= 1_800 && validFor <= 604_800, "validity must be 1800-604800 seconds");

  const quoteRequest = {
    sellToken: normalizedSellToken,
    buyToken: normalizedBuyToken,
    from: TREASURY_SAFE,
    receiver: TREASURY_SAFE,
    sellAmountBeforeFee: parsedSellAmount.toString(),
    kind: "sell",
    signingScheme: "presign",
    validFor,
  };
  const quoteResponse = await readJson(
    await fetchImpl(`${apiBaseUrl}/quote`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(quoteRequest),
    }),
    "CoW quote",
  );
  const order = buildPresignOrder(quoteResponse, parsedSellAmount.toString(), slippageBps);

  requireCondition(order.sellToken === normalizedSellToken, "quote changed the sell token");
  requireCondition(order.buyToken === normalizedBuyToken, "quote changed the buy token");
  requireCondition(order.receiver === TREASURY_SAFE, "quote changed the receiver");

  const [sellPrice, buyPrice] = await Promise.all([
    fetchUsdPrice(order.sellToken, priceApiBaseUrl, fetchImpl),
    fetchUsdPrice(order.buyToken, priceApiBaseUrl, fetchImpl),
  ]);
  const priceReferenceTimestamp = now().toISOString();
  const analytics = buildQuoteAnalytics(order, sellPrice, buyPrice, priceReferenceTimestamp, priceApiBaseUrl);

  if (!submit) {
    return {
      mode: "quote-only",
      ...order,
      slippageBps,
      validFor,
      analytics,
    };
  }

  const orderRequest = { ...order };
  delete orderRequest.quotedBuyAmount;
  delete orderRequest.networkFeeAmount;
  const orderUid = await readJson(
    await fetchImpl(`${apiBaseUrl}/orders`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(orderRequest),
    }),
    "CoW order submission",
  );

  let serverOrder;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const response = await fetchImpl(`${apiBaseUrl}/orders/${orderUid}`);
    if (response.ok) {
      serverOrder = await readJson(response, "CoW order verification");
      break;
    }
    if (attempt === 4) await readJson(response, "CoW order verification");
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  validateServerOrder(serverOrder, order, orderUid);

  return {
    mode: "submitted",
    orderUid,
    ...order,
    status: serverOrder.status,
    slippageBps,
    validFor,
    analytics,
  };
}

function parseArguments(argv) {
  const result = { submit: false };
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === "--submit") {
      result.submit = true;
      continue;
    }
    const value = argv[index + 1];
    requireCondition(value !== undefined, `missing value for ${key}`);
    if (key === "--sell-token") result.sellToken = value;
    else if (key === "--buy-token") result.buyToken = value;
    else if (key === "--sell-amount") result.sellAmount = value;
    else if (key === "--slippage-bps") result.slippageBps = Number(value);
    else if (key === "--valid-for") result.validFor = Number(value);
    else if (key === "--api-base-url") result.apiBaseUrl = value;
    else if (key === "--price-api-base-url") result.priceApiBaseUrl = value;
    else throw new Error(`unknown argument: ${key}`);
    index += 1;
  }
  return result;
}

const isMain = process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (isMain) {
  createCowPresignOrder(parseArguments(process.argv.slice(2)))
    .then((result) => process.stdout.write(JSON.stringify(result)))
    .catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
}

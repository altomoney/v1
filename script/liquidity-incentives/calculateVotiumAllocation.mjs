#!/usr/bin/env node

const DEFAULT_PRICE_API_BASE_URL = "https://bff.cow.fi/1/tokens";
const CRVUSD = "0xf939e0a03fb07f59a73314e73794be0e57ac1b4e";
const MIN_COW_SURPLUS_CRVUSD_AMOUNT = 10n ** 18n;
const ADDRESS_PATTERN = /^0x[0-9a-fA-F]{40}$/;

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

function parseUnsignedInteger(value, label) {
  requireCondition(/^\d+$/.test(String(value)), `${label} must be an unsigned integer`);
  return BigInt(value);
}

function normalizeAddress(value, label) {
  requireCondition(ADDRESS_PATTERN.test(value), `${label} must be an address`);
  return value.toLowerCase();
}

function decimalToFraction(value, label) {
  const normalized = String(value).toLowerCase();
  const match = normalized.match(/^(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/);
  requireCondition(match, `${label} must be a non-negative decimal`);

  const fractionalDigits = match[2] || "";
  const exponent = Number(match[3] || "0");
  requireCondition(Number.isSafeInteger(exponent), `${label} exponent is invalid`);

  let numerator = BigInt(`${match[1]}${fractionalDigits}`);
  const scale = fractionalDigits.length - exponent;
  let denominator = 1n;
  if (scale >= 0) denominator = 10n ** BigInt(scale);
  else numerator *= 10n ** BigInt(-scale);
  return { numerator, denominator, display: normalized };
}

function addFractions(left, right) {
  return {
    numerator: left.numerator * right.denominator + right.numerator * left.denominator,
    denominator: left.denominator * right.denominator,
  };
}

function tokenUsdValue(amount, decimals, price) {
  return {
    numerator: amount * price.numerator,
    denominator: 10n ** BigInt(decimals) * price.denominator,
  };
}

function formatFraction(numerator, denominator, decimals) {
  requireCondition(denominator > 0n, "fraction denominator must be positive");
  const scale = 10n ** BigInt(decimals);
  const rounded = (numerator * scale + denominator / 2n) / denominator;
  const whole = rounded / scale;
  const fraction = decimals === 0 ? "" : `.${(rounded % scale).toString().padStart(decimals, "0")}`;
  return `${whole}${fraction}`;
}

function formatUnits(amount, decimals) {
  const scale = 10n ** BigInt(decimals);
  const whole = amount / scale;
  const fraction = (amount % scale).toString().padStart(decimals, "0").replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole.toString();
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

async function fetchUsdPrice(token, priceApiBaseUrl, fetchImpl) {
  const response = await readJson(
    await fetchImpl(`${priceApiBaseUrl}/${token}/usdPrice`),
    `${token} USD price`,
  );
  requireCondition(
    response && (typeof response.price === "number" || typeof response.price === "string"),
    `${token} USD price response is missing price`,
  );
  const price = decimalToFraction(response.price, `${token} USD price`);
  requireCondition(price.numerator > 0n, `${token} USD price must be greater than zero`);
  return price;
}

export function calculateVotiumAllocation({
  round,
  capUsd,
  crvUsdProceeds,
  platformFee,
  feeDenominator,
  externalIncentives,
  prices,
  priceReferenceTimestamp,
  priceApiBaseUrl = DEFAULT_PRICE_API_BASE_URL,
}) {
  const parsedRound = Number(round);
  requireCondition(Number.isSafeInteger(parsedRound) && parsedRound > 0, "round must be a positive integer");
  const cap = decimalToFraction(capUsd, "USD cap");
  requireCondition(cap.numerator > 0n, "USD cap must be greater than zero");
  const proceeds = parseUnsignedInteger(crvUsdProceeds, "crvUSD proceeds");
  requireCondition(proceeds > 0n, "crvUSD proceeds must be greater than zero");
  const fee = parseUnsignedInteger(platformFee, "platform fee");
  const denominator = parseUnsignedInteger(feeDenominator, "fee denominator");
  requireCondition(denominator > 0n && fee < denominator, "invalid Votium platform fee");

  let externalUsd = { numerator: 0n, denominator: 1n };
  const valuedExternalIncentives = externalIncentives.map((incentive, index) => {
    const token = normalizeAddress(incentive.token, `external incentive ${index} token`);
    const depositor = normalizeAddress(incentive.depositor, `external incentive ${index} depositor`);
    const amount = parseUnsignedInteger(incentive.amount, `external incentive ${index} amount`);
    const decimals = Number(incentive.decimals);
    requireCondition(Number.isInteger(decimals) && decimals >= 0 && decimals <= 255, `external incentive ${index} decimals are invalid`);
    const price = prices.get(token);
    requireCondition(price, `missing USD price for ${token}`);
    const value = tokenUsdValue(amount, decimals, price);
    externalUsd = addFractions(externalUsd, value);
    return {
      token,
      depositor,
      amount: amount.toString(),
      amountFormatted: formatUnits(amount, decimals),
      decimals,
      usdPrice: price.display,
      usdValue: formatFraction(value.numerator, value.denominator, 6),
      priceUrl: `${priceApiBaseUrl}/${token}/usdPrice`,
    };
  });

  const crvUsdPrice = prices.get(CRVUSD);
  requireCondition(crvUsdPrice, "missing crvUSD USD price");
  const capMinusExternalNumerator =
    cap.numerator * externalUsd.denominator - externalUsd.numerator * cap.denominator;
  let remainingUsd = { numerator: 0n, denominator: 1n };
  let maximumStoredCrvUsdAmount = 0n;
  if (capMinusExternalNumerator > 0n) {
    remainingUsd = {
      numerator: capMinusExternalNumerator,
      denominator: cap.denominator * externalUsd.denominator,
    };
    maximumStoredCrvUsdAmount =
      remainingUsd.numerator * crvUsdPrice.denominator * 10n ** 18n /
      (remainingUsd.denominator * crvUsdPrice.numerator);
  }

  const maximumGrossCrvUsdAmount = maximumStoredCrvUsdAmount * denominator / (denominator - fee);
  const votiumGrossAmount = proceeds < maximumGrossCrvUsdAmount ? proceeds : maximumGrossCrvUsdAmount;
  const votiumFeeAmount = votiumGrossAmount * fee / denominator;
  const votiumStoredAmount = votiumGrossAmount - votiumFeeAmount;
  requireCondition(votiumStoredAmount <= maximumStoredCrvUsdAmount, "Votium gross-up exceeded remaining cap");
  const surplusCrvUsdAmount = proceeds - votiumGrossAmount;
  const cowSurplusCrvUsdAmount = surplusCrvUsdAmount >= MIN_COW_SURPLUS_CRVUSD_AMOUNT
    ? surplusCrvUsdAmount
    : 0n;
  const retainedSurplusCrvUsdAmount = surplusCrvUsdAmount - cowSurplusCrvUsdAmount;
  const altoUsd = tokenUsdValue(votiumStoredAmount, 18, crvUsdPrice);
  const combinedUsd = addFractions(externalUsd, altoUsd);
  if (capMinusExternalNumerator > 0n) {
    requireCondition(
      combinedUsd.numerator * cap.denominator <= cap.numerator * combinedUsd.denominator,
      "combined incentives exceed USD cap",
    );
  } else {
    requireCondition(votiumGrossAmount === 0n, "Alto incentive must be zero after external cap is consumed");
  }

  return {
    version: "1.0",
    chainId: 1,
    round: parsedRound,
    methodology: "Third-party Votium stored token amounts are valued with current CoW Swap BFF USD prices. Alto's gross deposit is reduced by the current Votium platform fee before applying the USD cap.",
    priceReferenceSource: "CoW Swap BFF USD prices",
    priceReferenceTimestamp,
    capUsd: formatFraction(cap.numerator, cap.denominator, 6),
    externalIncentives: valuedExternalIncentives,
    externalUsdValue: formatFraction(externalUsd.numerator, externalUsd.denominator, 6),
    externalCapExceeded: capMinusExternalNumerator < 0n,
    remainingUsdValue: formatFraction(remainingUsd.numerator, remainingUsd.denominator, 6),
    crvUsdPrice: crvUsdPrice.display,
    crvUsdPriceUrl: `${priceApiBaseUrl}/${CRVUSD}/usdPrice`,
    crvUsdProceedsAmount: proceeds.toString(),
    crvUsdProceedsFormatted: formatUnits(proceeds, 18),
    maximumStoredCrvUsdAmount: maximumStoredCrvUsdAmount.toString(),
    maximumStoredCrvUsdFormatted: formatUnits(maximumStoredCrvUsdAmount, 18),
    maximumGrossCrvUsdAmount: maximumGrossCrvUsdAmount.toString(),
    maximumGrossCrvUsdFormatted: formatUnits(maximumGrossCrvUsdAmount, 18),
    votiumGrossAmount: votiumGrossAmount.toString(),
    votiumGrossFormatted: formatUnits(votiumGrossAmount, 18),
    votiumFeeAmount: votiumFeeAmount.toString(),
    votiumFeeFormatted: formatUnits(votiumFeeAmount, 18),
    votiumStoredAmount: votiumStoredAmount.toString(),
    votiumStoredFormatted: formatUnits(votiumStoredAmount, 18),
    votiumStoredUsdValue: formatFraction(altoUsd.numerator, altoUsd.denominator, 6),
    combinedUsdValue: formatFraction(combinedUsd.numerator, combinedUsd.denominator, 6),
    surplusCrvUsdAmount: surplusCrvUsdAmount.toString(),
    surplusCrvUsdFormatted: formatUnits(surplusCrvUsdAmount, 18),
    minimumCowSurplusCrvUsdAmount: MIN_COW_SURPLUS_CRVUSD_AMOUNT.toString(),
    cowSurplusCrvUsdAmount: cowSurplusCrvUsdAmount.toString(),
    cowSurplusCrvUsdFormatted: formatUnits(cowSurplusCrvUsdAmount, 18),
    retainedSurplusCrvUsdAmount: retainedSurplusCrvUsdAmount.toString(),
    retainedSurplusCrvUsdFormatted: formatUnits(retainedSurplusCrvUsdAmount, 18),
  };
}

export async function createVotiumAllocation({
  round,
  capUsd,
  crvUsdProceeds,
  platformFee,
  feeDenominator,
  externalIncentives,
  priceApiBaseUrl = DEFAULT_PRICE_API_BASE_URL,
  fetchImpl = fetch,
  now = () => new Date(),
}) {
  const tokens = [...new Set([
    CRVUSD,
    ...externalIncentives.map((incentive) => normalizeAddress(incentive.token, "external incentive token")),
  ])];
  const priceEntries = await Promise.all(tokens.map(async (token) => [
    token,
    await fetchUsdPrice(token, priceApiBaseUrl, fetchImpl),
  ]));
  return calculateVotiumAllocation({
    round,
    capUsd,
    crvUsdProceeds,
    platformFee,
    feeDenominator,
    externalIncentives,
    prices: new Map(priceEntries),
    priceReferenceTimestamp: now().toISOString(),
    priceApiBaseUrl,
  });
}

function parseExternalIncentive(value) {
  const [token, amount, decimals, depositor, ...extra] = value.split(":");
  requireCondition(extra.length === 0 && token && amount && decimals && depositor, "invalid external incentive");
  return { token, amount, decimals, depositor };
}

function parseArguments(argv) {
  const result = { externalIncentives: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    const value = argv[index + 1];
    requireCondition(value !== undefined, `missing value for ${key}`);
    if (key === "--round") result.round = value;
    else if (key === "--cap-usd") result.capUsd = value;
    else if (key === "--crvusd-proceeds") result.crvUsdProceeds = value;
    else if (key === "--platform-fee") result.platformFee = value;
    else if (key === "--fee-denominator") result.feeDenominator = value;
    else if (key === "--external-incentive") result.externalIncentives.push(parseExternalIncentive(value));
    else if (key === "--price-api-base-url") result.priceApiBaseUrl = value;
    else throw new Error(`unknown argument: ${key}`);
    index += 1;
  }
  return result;
}

const isMain = process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (isMain) {
  createVotiumAllocation(parseArguments(process.argv.slice(2)))
    .then((result) => process.stdout.write(JSON.stringify(result)))
    .catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
}

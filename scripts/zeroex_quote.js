#!/usr/bin/env node

// Simple script to call 0x Allowance Holder Quote API and write result to result.txt
// Note: Provide the API key via the ZEROEX_API_KEY environment variable.

const fs = require('fs');
const path = require('path');

async function main() {
  const apiKey = '';
  if (!apiKey) {
    console.error('Missing ZEROEX_API_KEY env var. Export it before running.');
    process.exit(1);
  }

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
  const CB_BTC = '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf';

  // Configure request variables here
  const requestVars1 = {
    sellAmount: '240000000000000000000000',
    sellToken: DAI,
    buyToken: CB_BTC,
  };

  const requestVars2 = {
    sellAmount: '200000000',
    sellToken: CB_BTC,
    buyToken: DAI,
  };

  const requestVars3 = {
    sellAmount: '250000000',
    sellToken: CB_BTC,
    buyToken: DAI,
  };

  const requestVars4 = {
    sellAmount: '120000000000000000000000',
    sellToken: DAI,
    buyToken: CB_BTC,
  };

  const requestVars5 = {
    sellAmount: '600000000000000000000000',
    sellToken: DAI,
    buyToken: CB_BTC,
  };

  // Fixed params per your example
  const taker = '0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f';
  const chainId = 1;
  const excludedSources = '0x_RFQ';

  const query1 = new URLSearchParams({
    sellAmount: requestVars1.sellAmount,
    taker,
    chainId: String(chainId),
    sellToken: requestVars1.sellToken,
    buyToken: requestVars1.buyToken,
    excludedSources,
  });

  const query2 = new URLSearchParams({
    sellAmount: requestVars2.sellAmount,
    taker,
    chainId: String(chainId),
    sellToken: requestVars2.sellToken,
    buyToken: requestVars2.buyToken,
    excludedSources,
  });

  const query3 = new URLSearchParams({
    sellAmount: requestVars3.sellAmount,
    taker,
    chainId: String(chainId),
    sellToken: requestVars3.sellToken,
    buyToken: requestVars3.buyToken,
    excludedSources,
  });

  const query4 = new URLSearchParams({
    sellAmount: requestVars4.sellAmount,
    taker,
    chainId: String(chainId),
    sellToken: requestVars4.sellToken,
    buyToken: requestVars4.buyToken,
    excludedSources,
  });

  const query5 = new URLSearchParams({
    sellAmount: requestVars5.sellAmount,
    taker,
    chainId: String(chainId),
    sellToken: requestVars5.sellToken,
    buyToken: requestVars5.buyToken,
    excludedSources,
  });
  const url1 = `https://api.0x.org/swap/allowance-holder/quote?${query1.toString()}`;
  const url2 = `https://api.0x.org/swap/allowance-holder/quote?${query2.toString()}`;
  const url3 = `https://api.0x.org/swap/allowance-holder/quote?${query3.toString()}`;
  const url4 = `https://api.0x.org/swap/allowance-holder/quote?${query4.toString()}`;
  const url5 = `https://api.0x.org/swap/allowance-holder/quote?${query5.toString()}`;

  const headers = {
    '0x-api-key': apiKey,
    '0x-version': 'v2',
  };

  try {
    const res1 = await fetch(url1, { headers });
    const text1 = await res1.text();

    // Attempt to pretty print JSON if possible; otherwise write raw text
    let output1 = text1;
    try {
      output1 = JSON.stringify(JSON.parse(text1), null, 2);
    } catch (_) {
      // non-JSON, keep as-is
    }

    const outPath1 = path.resolve('/workspaces/v1/test/lending/leverage/0xswapData/cbbtc/data_240000_dai_to_cbbtc.txt');
    fs.writeFileSync(outPath1, output1);
    console.log(`Wrote response to ${outPath1}`);
  } catch (err) {
    console.error('Request failed:', err);
    process.exit(1);
  }

  try {
    const res2 = await fetch(url2, { headers });
    const text2 = await res2.text();

    // Attempt to pretty print JSON if possible; otherwise write raw text
    let output2 = text2;
    try {
      output2 = JSON.stringify(JSON.parse(text2), null, 2);
    } catch (_) {
      // non-JSON, keep as-is
    }

    const outPath2 = path.resolve('/workspaces/v1/test/lending/leverage/0xswapData/cbbtc/data_2_cbbtc_to_dai.txt');
    fs.writeFileSync(outPath2, output2);
    console.log(`Wrote response to ${outPath2}`);
  } catch (err) {
    console.error('Request failed:', err);
    process.exit(1);
  }

  try {
    const res3 = await fetch(url3, { headers });
    const text3 = await res3.text();

    // Attempt to pretty print JSON if possible; otherwise write raw text
    let output3 = text3;
    try {
      output3 = JSON.stringify(JSON.parse(text3), null, 2);
    } catch (_) {
      // non-JSON, keep as-is
    }

    const outPath3 = path.resolve('/workspaces/v1/test/lending/leverage/0xswapData/cbbtc/data_2.5_cbbtc_to_dai.txt');
    fs.writeFileSync(outPath3, output3);
    console.log(`Wrote response to ${outPath3}`);
  } catch (err) {
    console.error('Request failed:', err);
    process.exit(1);
  }

  try {
    const res4 = await fetch(url4, { headers });
    const text4 = await res4.text();

    // Attempt to pretty print JSON if possible; otherwise write raw text
    let output4 = text4;
    try {
      output4 = JSON.stringify(JSON.parse(text4), null, 2);
    } catch (_) {
      // non-JSON, keep as-is
    }

      const outPath4 = path.resolve('/workspaces/v1/test/lending/leverage/0xswapData/cbbtc/data_120000_dai_to_cbbtc.txt');
    fs.writeFileSync(outPath4, output4);
    console.log(`Wrote response to ${outPath4}`);
  } catch (err) {
    console.error('Request failed:', err);
    process.exit(1);
  }

  try {
    const res5 = await fetch(url5, { headers });
    const text5 = await res5.text();

    // Attempt to pretty print JSON if possible; otherwise write raw text
    let output5 = text5;
    try {
      output5 = JSON.stringify(JSON.parse(text5), null, 2);
    } catch (_) {
      // non-JSON, keep as-is
    }

    const outPath5 = path.resolve('/workspaces/v1/test/lending/leverage/0xswapData/cbbtc/data_600000_dai_to_cbbtc.txt');
    fs.writeFileSync(outPath5, output5);
    console.log(`Wrote response to ${outPath5}`);
  } catch (err) {
    console.error('Request failed:', err);
    process.exit(1);
  }
}

main();



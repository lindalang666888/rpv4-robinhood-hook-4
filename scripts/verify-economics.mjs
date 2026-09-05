import assert from "node:assert/strict";

const ETHER = 10n ** 18n;
const TOKEN = 10n ** 18n;
const virtualNative0 = 2n * ETHER;
const virtualToken0 = 1_000_000_000n * TOKEN;
const grossBuy = 39n * ETHER / 1000n;
const buyFee = grossBuy / 100n;
const netBuy = grossBuy - buyFee;
const tokenOut = virtualToken0 * netBuy / (virtualNative0 + netBuy);
const maxWallet = 20_000_000n * TOKEN;

assert.equal(grossBuy, 39_000_000_000_000_000n);
assert.equal(buyFee, 390_000_000_000_000n);
assert(tokenOut > 18_000_000n * TOKEN, "initial buy should exceed 1.8% supply");
assert(tokenOut < 19_000_000n * TOKEN, "initial buy should remain below 1.9% supply");
assert(tokenOut < maxWallet, "initial buy must remain below the 2% wallet ceiling");

const virtualNative1 = virtualNative0 + netBuy;
const virtualToken1 = virtualToken0 - tokenOut;
const grossSell = tokenOut;
const sellFee = grossSell / 100n;
const netSell = grossSell - sellFee;
const nativeOut = virtualNative1 * netSell / (virtualToken1 + netSell);
assert(nativeOut < netBuy, "round-trip cannot extract more curve backing than the buy added");
assert(grossBuy <= 5n * ETHER / 100n, "initial buy must respect the 0.05 ETH cap");

process.stdout.write(JSON.stringify({
  grossBuyWei: grossBuy.toString(),
  buyFeeWei: buyFee.toString(),
  estimatedTokenOutRaw: tokenOut.toString(),
  estimatedSupplyPercent: Number(tokenOut * 1_000_000n / virtualToken0) / 10_000,
  roundTripNativeOutWei: nativeOut.toString(),
}, null, 2) + "\n");

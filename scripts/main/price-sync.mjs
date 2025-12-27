/**
 * Price Sync Service
 *
 * Monitors Uniswap DEX prices and syncs mock oracle prices to match.
 * This ensures the oracle price deviation check passes during local development.
 *
 * Usage: node scripts/main/price-sync.mjs
 *
 * Features:
 * - Monitors WBTC/USDC pair price on Uniswap
 * - Updates Chainlink, Pyth, and Redstone mock oracles
 * - Runs continuously with configurable polling interval
 * - Graceful shutdown on SIGINT/SIGTERM
 */

import { createPublicClient, createWalletClient, http, parseAbi } from 'viem';
import { hardhat } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import fs from 'fs';

// Configuration
const POLL_INTERVAL_MS = 3000;  // Check price every 3 seconds
const PRICE_CHANGE_THRESHOLD = 0.001;  // 0.1% change triggers update
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const DEPLOYMENT_FILE = './ignition/deployments/chain-31337/deployed_addresses.json';

// Hardhat default account #0 private key
const OWNER_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

// ABIs
const pairAbi = parseAbi([
  'function getReserves() view returns (uint112, uint112, uint32)',
  'function token0() view returns (address)',
  'function token1() view returns (address)'
]);

const chainlinkAbi = parseAbi([
  'function setAnswer(int256 answer)',
  'function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)'
]);

const pythAbi = parseAbi([
  'function setPrice(bytes32 id, int64 price, int32 expo)',
  'function getPriceNoOlderThan(bytes32 id, uint256 age) view returns ((int64 price, uint64 conf, int32 expo, uint256 publishTime))'
]);

const redstoneAbi = parseAbi([
  'function setValue(bytes32 dataFeedId, uint256 value)',
  'function getValueForDataFeed(bytes32 dataFeedId) view returns (uint256)'
]);

const oracleAbi = parseAbi([
  'function getWBTCPrice() view returns (uint256)'
]);

// State
let lastPrice = 0n;
let isRunning = true;
let updateCount = 0;

// Clients
const publicClient = createPublicClient({
  chain: hardhat,
  transport: http(RPC_URL)
});

const account = privateKeyToAccount(OWNER_PRIVATE_KEY);
const walletClient = createWalletClient({
  account,
  chain: hardhat,
  transport: http(RPC_URL)
});

// Load deployment addresses
function loadAddresses() {
  if (!fs.existsSync(DEPLOYMENT_FILE)) {
    console.error('❌ Deployment file not found:', DEPLOYMENT_FILE);
    console.error('   Please deploy contracts first.');
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, 'utf8'));
}

// Get WBTC price from Uniswap pair
async function getUniswapPrice(addresses) {
  const pairAddr = addresses['FullSystemLocal#PairWBTCUSDC'];
  const wbtcAddr = addresses['FullSystemLocal#WBTC'];

  const [reserve0, reserve1] = await publicClient.readContract({
    address: pairAddr,
    abi: pairAbi,
    functionName: 'getReserves'
  });

  const token0 = await publicClient.readContract({
    address: pairAddr,
    abi: pairAbi,
    functionName: 'token0'
  });

  // WBTC is 8 decimals, USDC is 6 decimals
  // Price = USDC amount / WBTC amount * 10^(8-6) = USDC/WBTC * 100
  let priceUSD;
  if (token0.toLowerCase() === wbtcAddr.toLowerCase()) {
    // token0 is WBTC, token1 is USDC
    // price = reserve1 / reserve0 * 10^2 (adjust for decimal difference)
    priceUSD = (BigInt(reserve1) * 100n * 10n ** 18n) / BigInt(reserve0);
  } else {
    // token0 is USDC, token1 is WBTC
    priceUSD = (BigInt(reserve0) * 100n * 10n ** 18n) / BigInt(reserve1);
  }

  return priceUSD;
}

// Update all mock oracles
async function updateOracles(addresses, priceUSD) {
  const chainlinkBtcUsd = addresses['FullSystemLocal#ChainlinkBTCUSD'];
  const chainlinkWbtcBtc = addresses['FullSystemLocal#ChainlinkWBTCBTC'];
  const mockPyth = addresses['FullSystemLocal#MockPyth'];
  const mockRedstone = addresses['FullSystemLocal#MockRedstone'];

  // Chainlink BTC/USD: 8 decimals
  const chainlinkPrice = priceUSD / 10n ** 10n;  // 18 -> 8 decimals

  // Pyth: price with expo -8 (effectively 8 decimals)
  const pythPrice = priceUSD / 10n ** 10n;  // 18 -> 8 decimals
  const PYTH_PRICE_ID = '0x505954485f575442430000000000000000000000000000000000000000000000';

  // Redstone: 18 decimals
  const redstonePrice = priceUSD;
  const REDSTONE_FEED_ID = '0x52454453544f4e455f5754424300000000000000000000000000000000000000';

  try {
    // Update Chainlink BTC/USD
    await walletClient.writeContract({
      address: chainlinkBtcUsd,
      abi: chainlinkAbi,
      functionName: 'setAnswer',
      args: [chainlinkPrice]
    });

    // Update Chainlink WBTC/BTC (keep at 1.0)
    await walletClient.writeContract({
      address: chainlinkWbtcBtc,
      abi: chainlinkAbi,
      functionName: 'setAnswer',
      args: [100000000n]  // 1.0 with 8 decimals
    });

    // Update Pyth
    await walletClient.writeContract({
      address: mockPyth,
      abi: pythAbi,
      functionName: 'setPrice',
      args: [PYTH_PRICE_ID, pythPrice, -8]
    });

    // Update Redstone
    await walletClient.writeContract({
      address: mockRedstone,
      abi: redstoneAbi,
      functionName: 'setValue',
      args: [REDSTONE_FEED_ID, redstonePrice]
    });

    updateCount++;
    return true;
  } catch (e) {
    console.error('❌ Error updating oracles:', e.shortMessage || e.message);
    return false;
  }
}

// Verify oracle price works
async function verifyOraclePrice(addresses) {
  const oracleAddr = addresses['FullSystemLocal#PriceOracle'];
  try {
    const price = await publicClient.readContract({
      address: oracleAddr,
      abi: oracleAbi,
      functionName: 'getWBTCPrice'
    });
    return price;
  } catch (e) {
    return null;
  }
}

// Format price for display
function formatPrice(price) {
  return (Number(price) / 1e18).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

// Calculate price change percentage
function priceChangePercent(oldPrice, newPrice) {
  if (oldPrice === 0n) return 100;
  return Math.abs(Number(newPrice - oldPrice) / Number(oldPrice) * 100);
}

// Main monitoring loop
async function monitorPrices() {
  const addresses = loadAddresses();

  console.log('🔄 Price Sync Service Started');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`   RPC: ${RPC_URL}`);
  console.log(`   Poll Interval: ${POLL_INTERVAL_MS}ms`);
  console.log(`   Change Threshold: ${PRICE_CHANGE_THRESHOLD * 100}%`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');

  // Initial sync
  try {
    const initialPrice = await getUniswapPrice(addresses);
    console.log(`📊 Initial DEX price: $${formatPrice(initialPrice)}`);

    await updateOracles(addresses, initialPrice);
    lastPrice = initialPrice;

    const oraclePrice = await verifyOraclePrice(addresses);
    if (oraclePrice) {
      console.log(`✅ Oracle synced: $${formatPrice(oraclePrice)}`);
    } else {
      console.log('⚠️  Oracle price verification failed');
    }
    console.log('');
  } catch (e) {
    console.error('❌ Initial sync failed:', e.message);
  }

  // Continuous monitoring
  while (isRunning) {
    try {
      const currentPrice = await getUniswapPrice(addresses);
      const changePercent = priceChangePercent(lastPrice, currentPrice);

      if (changePercent >= PRICE_CHANGE_THRESHOLD * 100) {
        const direction = currentPrice > lastPrice ? '📈' : '📉';
        console.log(`${direction} DEX price changed: $${formatPrice(lastPrice)} → $${formatPrice(currentPrice)} (${changePercent.toFixed(2)}%)`);

        const success = await updateOracles(addresses, currentPrice);
        if (success) {
          const oraclePrice = await verifyOraclePrice(addresses);
          if (oraclePrice) {
            console.log(`   ✅ Oracles synced (#${updateCount})`);
          }
        }

        lastPrice = currentPrice;
      }
    } catch (e) {
      // Silently handle connection errors during polling
      if (!e.message.includes('fetch failed')) {
        console.error('⚠️  Poll error:', e.shortMessage || e.message);
      }
    }

    await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL_MS));
  }
}

// Graceful shutdown
function shutdown() {
  console.log('\n🛑 Shutting down Price Sync Service...');
  console.log(`   Total updates: ${updateCount}`);
  isRunning = false;
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

// Start monitoring
monitorPrices().catch(e => {
  console.error('❌ Fatal error:', e);
  process.exit(1);
});

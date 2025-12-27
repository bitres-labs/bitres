/**
 * Initialize Sepolia testnet system after deployment:
 * - Read real BTC price from Chainlink
 * - Set mock Pyth/Redstone prices to match Chainlink
 * - Add UniswapV2Pair liquidity and mint LP
 * - Configure farming pools
 * - Fund test accounts (optional)
 *
 * Run:
 *   npx hardhat run scripts/sepolia/init-sepolia.mjs --network sepolia
 *
 * Prerequisite: deployed via Ignition with FullSystemSepolia module
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, keccak256, parseEther, parseUnits, stringToHex } from "viem";
import { sepolia } from "viem/chains";

const CHAIN_ID = 11155111; // Sepolia
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

const DEFAULTS = {
  pythPriceId: "0x505954485f575442430000000000000000000000000000000000000000000000",
  redstoneFeedId: "0x52454453544f4e455f5754424300000000000000000000000000000000000000",
};

function loadAddresses() {
  if (!fs.existsSync(ADDR_FILE)) {
    throw new Error(`deployed_addresses.json not found at ${ADDR_FILE}. Deploy via Ignition first.`);
  }
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    const key = k.replace("FullSystemSepolia#", "");
    map[key] = v;
  }
  return map;
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Bitres Sepolia Testnet Initialization");
  console.log("=".repeat(60));

  const addresses = loadAddresses();
  console.log("\n=> Loaded addresses from:", ADDR_FILE);

  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;
  // Use the RPC URL from hardhat config (which comes from .env)
  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org";

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  console.log(`=> Deployer: ${owner.account.address}`);

  // Contract helpers
  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;
  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);
  const write = (relPath, address, functionName, args = []) =>
    owner.writeContract({
      address,
      abi: loadAbi(relPath),
      functionName,
      args,
      account: owner.account,
    });

  // Load contracts
  const brs = await get("BRS", "contracts/BRS.sol:BRS");
  const btd = await get("BTD", "contracts/BTD.sol:BTD");
  const btb = await get("BTB", "contracts/BTB.sol:BTB");
  const wbtc = await get("WBTC", "contracts/local/MockWBTC.sol:MockWBTC");
  const usdc = await get("USDC", "contracts/local/MockUSDC.sol:MockUSDC");
  const usdt = await get("USDT", "contracts/local/MockUSDT.sol:MockUSDT");
  const weth = await get("WETH", "contracts/local/MockWETH.sol:MockWETH");
  const stBTD = await get("stBTD", "contracts/stBTD.sol:stBTD");
  const stBTB = await get("stBTB", "contracts/stBTB.sol:stBTB");
  const farming = await get("FarmingPool", "contracts/FarmingPool.sol:FarmingPool");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");

  // Chainlink WBTC/BTC mock (we deployed this)
  const chainlinkWbtcBtc = await get(
    "ChainlinkWBTCBTC",
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3"
  );
  const mockPyth = await get("MockPyth", "contracts/local/MockPyth.sol:MockPyth");
  const mockRedstone = await get("MockRedstone", "contracts/local/MockRedstone.sol:MockRedstone");

  const pairWBTCUSDC = await get("PairWBTCUSDC", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBTDUSDC = await get("PairBTDUSDC", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBTBBTD = await get("PairBTBBTD", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBRSBTD = await get("PairBRSBTD", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairAbi = loadAbi("contracts/local/UniswapV2Pair.sol/UniswapV2Pair.json");

  // =========================================================================
  // 1) Read real BTC price from Chainlink
  // =========================================================================
  console.log("\n=> Reading real BTC price from Chainlink...");
  const chainlinkAbi = [
    {
      inputs: [],
      name: "latestRoundData",
      outputs: [
        { name: "roundId", type: "uint80" },
        { name: "answer", type: "int256" },
        { name: "startedAt", type: "uint256" },
        { name: "updatedAt", type: "uint256" },
        { name: "answeredInRound", type: "uint80" },
      ],
      stateMutability: "view",
      type: "function",
    },
  ];
  const chainlinkBtcUsdAddress = addresses.ChainlinkBTCUSD;
  const [, btcPrice] = await publicClient.readContract({
    address: chainlinkBtcUsdAddress,
    abi: chainlinkAbi,
    functionName: "latestRoundData",
  });
  console.log(`   Real BTC/USD price: $${Number(btcPrice) / 1e8}`);

  // =========================================================================
  // 2) Configure roles and disable TWAP
  // =========================================================================
  console.log("\n=> Configuring roles...");
  const MINTER_ROLE = keccak256(stringToHex("MINTER_ROLE"));
  const btdAbi = loadAbi("contracts/BTD.sol/BTD.json");
  const btbAbi = loadAbi("contracts/BTB.sol/BTB.json");

  console.log("   -> Grant BTD MINTER to owner");
  const tx1 = await owner.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "grantRole",
    args: [MINTER_ROLE, owner.account.address],
    account: owner.account,
  });
  await publicClient.waitForTransactionReceipt({ hash: tx1 });

  console.log("   -> Grant BTB MINTER to owner");
  const tx2 = await owner.writeContract({
    address: addresses.BTB,
    abi: btbAbi,
    functionName: "grantRole",
    args: [MINTER_ROLE, owner.account.address],
    account: owner.account,
  });
  await publicClient.waitForTransactionReceipt({ hash: tx2 });

  // Temporarily disable TWAP (will be enabled after 30+ minutes via enable-twap.mjs)
  console.log("   -> Disable TWAP oracle (will enable after observations mature)");
  const tx3 = await priceOracle.write.setUseTWAP([false], { account: owner.account });
  await publicClient.waitForTransactionReceipt({ hash: tx3 });

  // =========================================================================
  // 3) Set mock oracle prices (Pyth/Redstone use same price as Chainlink)
  // =========================================================================
  console.log("\n=> Setting mock oracle prices...");
  // WBTC/BTC already set to 1:1 in deployment
  console.log("   -> WBTC/BTC: 1:1 (already set)");

  // Pyth: price in 8 decimals with expo -8
  const pythPrice = btcPrice;
  const pythExpo = -8n;
  await mockPyth.write.setPrice([DEFAULTS.pythPriceId, pythPrice, pythExpo], {
    account: owner.account,
  });
  console.log(`   -> Pyth BTC price: ${Number(pythPrice) / 1e8}`);

  // Redstone: price in 18 decimals
  const redstonePrice = BigInt(btcPrice) * 10n ** 10n; // 8 -> 18 decimals
  await mockRedstone.write.setValue([DEFAULTS.redstoneFeedId, redstonePrice], {
    account: owner.account,
  });
  console.log(`   -> Redstone BTC price: ${Number(redstonePrice) / 1e18}`);

  // =========================================================================
  // 4) Mint BTD/BTB for LP initialization (using system minimum amounts + buffer)
  // =========================================================================
  console.log("\n=> Minting BTD/BTB for LP (using system minimum amounts)...");
  // BTD: 0.01 (BTD/USDC) + 0.001 (BTB/BTD) + 0.001 (BRS/BTD) + 0.001 vault = ~0.013
  // BTB: 0.001 (BTB/BTD) + 0.001 vault = ~0.002
  // Use 0.02 each for safety buffer
  const mintBtdAmount = parseEther("0.02");
  const mintBtbAmount = parseEther("0.02");

  await owner.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "mint",
    args: [owner.account.address, mintBtdAmount],
    account: owner.account,
  });
  console.log(`   -> Minted ${Number(mintBtdAmount) / 1e18} BTD`);

  await owner.writeContract({
    address: addresses.BTB,
    abi: btbAbi,
    functionName: "mint",
    args: [owner.account.address, mintBtbAmount],
    account: owner.account,
  });
  console.log(`   -> Minted ${Number(mintBtbAmount) / 1e18} BTB`);

  // =========================================================================
  // 5) Add LP liquidity
  // =========================================================================
  console.log("\n=> Adding LP liquidity...");

  const addLP = async (pair, token0, token1, amt0, amt1, label) => {
    // Check if pair already has liquidity
    const [reserve0, reserve1] = await publicClient.readContract({
      address: pair.address,
      abi: pairAbi,
      functionName: "getReserves",
    });
    if (reserve0 > 0n || reserve1 > 0n) {
      console.log(`   ⏭ ${label} LP already exists (reserves: ${reserve0}, ${reserve1})`);
      // Return existing LP balance
      const lpBalance = await publicClient.readContract({
        address: pair.address,
        abi: pairAbi,
        functionName: "balanceOf",
        args: [owner.account.address],
      });
      return lpBalance;
    }

    // Real LP minting: transfer tokens to pair, then call mint
    // First get actual token0/token1 order from pair
    const actualToken0 = await publicClient.readContract({
      address: pair.address,
      abi: pairAbi,
      functionName: "token0",
    });

    // Determine correct amounts based on token order
    let transferAmt0, transferAmt1, transferToken0, transferToken1;
    if (actualToken0.toLowerCase() === token0.address.toLowerCase()) {
      transferToken0 = token0;
      transferToken1 = token1;
      transferAmt0 = amt0;
      transferAmt1 = amt1;
    } else {
      transferToken0 = token1;
      transferToken1 = token0;
      transferAmt0 = amt1;
      transferAmt1 = amt0;
    }

    // Transfer tokens to pair
    const erc20Abi = [
      {
        inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }],
        name: "transfer",
        outputs: [{ name: "", type: "bool" }],
        stateMutability: "nonpayable",
        type: "function",
      },
    ];

    const tx0 = await owner.writeContract({
      address: transferToken0.address,
      abi: erc20Abi,
      functionName: "transfer",
      args: [pair.address, transferAmt0],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: tx0 });

    const tx1 = await owner.writeContract({
      address: transferToken1.address,
      abi: erc20Abi,
      functionName: "transfer",
      args: [pair.address, transferAmt1],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: tx1 });

    // Mint LP tokens
    const mintTx = await pair.write.mint([owner.account.address], { account: owner.account });
    await publicClient.waitForTransactionReceipt({ hash: mintTx });

    // Get minted LP balance
    const lpBalance = await publicClient.readContract({
      address: pair.address,
      abi: pairAbi,
      functionName: "balanceOf",
      args: [owner.account.address],
    });

    console.log(`   ✓ ${label} LP minted: ${lpBalance} (reserves: ${transferAmt0}, ${transferAmt1})`);
    return lpBalance;
  };

  // Use system minimum amounts for LP initialization
  // MIN_BTC_AMOUNT = 1, MIN_STABLECOIN_6_AMOUNT = 1000, MIN_STABLECOIN_18_AMOUNT = 1e15
  // sqrt(amt0 * amt1) > 1000 for Uniswap MINIMUM_LIQUIDITY
  const btcPriceUsd = Number(btcPrice) / 1e8;
  // WBTC/USDC: Use amounts that satisfy both minimums and match current BTC price
  const wbtcAmount = 1000n;  // 1000 satoshi (0.00001 WBTC) - meets MIN_BTC_AMOUNT
  // Calculate matching USDC amount based on current BTC price
  const usdcForWbtc = BigInt(Math.floor(Number(wbtcAmount) * btcPriceUsd / 100)); // USDC amount in 6 decimals
  const usdcAmount = usdcForWbtc < 1000n ? 1000n : usdcForWbtc;  // At least MIN_STABLECOIN_6_AMOUNT
  console.log(`   WBTC: ${wbtcAmount} satoshi, USDC: ${usdcAmount} (ratio ~$${btcPriceUsd}/BTC)`);

  const lpWBTCUSDC = await addLP(pairWBTCUSDC, wbtc, usdc, wbtcAmount, usdcAmount, "WBTC/USDC");
  // BTD/USDC: Add buffer to compensate for MINIMUM_LIQUIDITY burn (1000 wei)
  // For mixed-decimal pairs, add proportional buffer to both tokens
  const lpBTDUSDC = await addLP(pairBTDUSDC, btd, usdc,
    1n * 10n ** 16n + 1001n,  // 0.01 BTD + buffer
    10001n,                   // 0.01 USDC + 1 buffer
    "BTD/USDC"
  );
  // BTB/BTD, BRS/BTD: slightly over 1e15 each to account for MINIMUM_LIQUIDITY burn
  const lpBTBBTD = await addLP(pairBTBBTD, btb, btd, 1n * 10n ** 15n + 1001n, 1n * 10n ** 15n + 1001n, "BTB/BTD");
  const lpBRSBTD = await addLP(pairBRSBTD, brs, btd, 1n * 10n ** 15n + 1001n, 1n * 10n ** 15n + 1001n, "BRS/BTD");

  // =========================================================================
  // 5.5) Initialize TWAP Oracle and enable immediately
  // Note: TWAP prices won't be available for first 30 minutes, but that's OK
  // FarmingPool doesn't need prices, only Minter redemption does
  // =========================================================================
  console.log("\n=> Initializing TWAP Oracle...");
  const twapOracle = await get("TWAPOracle", "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");
  const pairsList = [pairWBTCUSDC, pairBTDUSDC, pairBTBBTD, pairBRSBTD];

  for (const pair of pairsList) {
    try {
      await twapOracle.write.update([pair.address], { account: owner.account });
      console.log(`   ✓ TWAP observation recorded for ${pair.address.slice(0, 10)}...`);
    } catch (err) {
      console.log(`   ⚠ TWAP update failed for ${pair.address.slice(0, 10)}...: ${err.message?.slice(0, 50) || err}`);
    }
  }

  // Enable TWAP immediately - prices won't work for 30 min but that's acceptable
  console.log("   -> Enabling TWAP (prices available after 30 min)...");
  const enableTx = await priceOracle.write.setUseTWAP([true], { account: owner.account });
  await publicClient.waitForTransactionReceipt({ hash: enableTx });
  console.log("   ✓ TWAP enabled (Minter operations will work after 30 min)");

  // =========================================================================
  // 6) Initialize stBTD/stBTB vaults (using system minimum amounts)
  // =========================================================================
  console.log("\n=> Initializing stBTD/stBTB vaults (MIN_STABLECOIN_18_AMOUNT)...");
  const minStake = 1n * 10n ** 15n; // MIN_STABLECOIN_18_AMOUNT = 0.001 tokens

  const stBTDAbi = loadAbi("contracts/stBTD.sol/stBTD.json");
  const stBTBAbi = loadAbi("contracts/stBTB.sol/stBTB.json");

  // Helper to write and wait for confirmation
  const writeAndWait = async (relPath, address, functionName, args = []) => {
    const hash = await write(relPath, address, functionName, args);
    await publicClient.waitForTransactionReceipt({ hash });
    return hash;
  };

  // Check if stBTD already has deposits
  const stBTDSupply = await publicClient.readContract({
    address: stBTD.address,
    abi: stBTDAbi,
    functionName: "totalSupply",
  });
  if (stBTDSupply > 0n) {
    console.log(`   ⏭ stBTD vault already initialized (supply: ${stBTDSupply})`);
  } else {
    await writeAndWait("contracts/BTD.sol/BTD.json", addresses.BTD, "mint", [owner.account.address, minStake]);
    await writeAndWait("contracts/BTD.sol/BTD.json", addresses.BTD, "approve", [stBTD.address, minStake]);
    await writeAndWait("contracts/stBTD.sol/stBTD.json", addresses.stBTD, "deposit", [minStake, owner.account.address]);
    console.log("   ✓ stBTD vault initialized (0.001 BTD)");
  }

  // Check if stBTB already has deposits
  const stBTBSupply = await publicClient.readContract({
    address: stBTB.address,
    abi: stBTBAbi,
    functionName: "totalSupply",
  });
  if (stBTBSupply > 0n) {
    console.log(`   ⏭ stBTB vault already initialized (supply: ${stBTBSupply})`);
  } else {
    await writeAndWait("contracts/BTB.sol/BTB.json", addresses.BTB, "mint", [owner.account.address, minStake]);
    await writeAndWait("contracts/BTB.sol/BTB.json", addresses.BTB, "approve", [stBTB.address, minStake]);
    await writeAndWait("contracts/stBTB.sol/stBTB.json", addresses.stBTB, "deposit", [minStake, owner.account.address]);
    console.log("   ✓ stBTB vault initialized (0.001 BTB)");
  }

  // =========================================================================
  // 7) Configure farming pools
  // =========================================================================
  console.log("\n=> Configuring FarmingPool pools...");

  const farmingAbi = loadAbi("contracts/FarmingPool.sol/FarmingPool.json");
  const poolLength = await publicClient.readContract({
    address: farming.address,
    abi: farmingAbi,
    functionName: "poolLength",
  });

  if (poolLength > 0n) {
    console.log(`   ⏭ Farming pools already configured (${poolLength} pools)`);
  } else {
    const tokens = [
      pairBRSBTD,  // 0: LP
      pairBTDUSDC, // 1: LP
      pairBTBBTD,  // 2: LP
      usdc,        // 3: Single
      usdt,        // 4: Single
      wbtc,        // 5: Single
      weth,        // 6: Single
      stBTD,       // 7: Single
      stBTB,       // 8: Single
      brs,         // 9: Single
    ];
    const allocPoints = [15, 15, 15, 1, 1, 1, 1, 3, 3, 5];
    const kinds = [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]; // 0=Single, 1=LP

    await farming.write.addPools([tokens.map((t) => t.address), allocPoints, kinds], {
      account: owner.account,
    });
    console.log("   ✓ 10 farming pools configured");
  }

  // =========================================================================
  // 8) Seed staking for farming pools (using system minimum amounts)
  // Note: FarmingPool now uses token amount validation, no TWAP needed
  // =========================================================================
  console.log("\n=> Seeding staking for farming pools (using system minimum amounts)...");

  // farmingAbi already loaded above

  // System minimum amounts for each token type
  const MIN_BTC = 1n;                    // 1 satoshi
  const MIN_STABLE_6 = 1000n;            // 0.001 USDC/USDT
  const MIN_STABLE_18 = 1n * 10n ** 15n; // 0.001 BTD/BTB/BRS/stBTD/stBTB
  const MIN_ETH = 1n * 10n ** 10n;       // 0.00000001 ETH

  // For LP pools, stake all LP tokens (they're already minimal)
  const stakePlans = [
    { id: 0, token: pairBRSBTD, amount: lpBRSBTD, name: "BRS/BTD LP" },
    { id: 1, token: pairBTDUSDC, amount: lpBTDUSDC, name: "BTD/USDC LP" },
    { id: 2, token: pairBTBBTD, amount: lpBTBBTD, name: "BTB/BTD LP" },
    { id: 3, token: usdc, amount: MIN_STABLE_6, name: "USDC" },
    { id: 4, token: usdt, amount: MIN_STABLE_6, name: "USDT" },
    { id: 5, token: wbtc, amount: MIN_BTC, name: "WBTC" },
    { id: 6, token: weth, amount: MIN_ETH, name: "WETH" },
    { id: 7, token: stBTD, amount: MIN_STABLE_18, name: "stBTD" },
    { id: 8, token: stBTB, amount: MIN_STABLE_18, name: "stBTB" },
    { id: 9, token: brs, amount: MIN_STABLE_18, name: "BRS" },
  ];

  let successCount = 0;
  let skipCount = 0;

  for (const plan of stakePlans) {
    if (plan.amount === 0n) {
      console.log(`   ⏭ pool ${plan.id} (${plan.name}) skipped: no balance`);
      skipCount++;
      continue;
    }

    // Check if already staked
    const [stakedAmount] = await publicClient.readContract({
      address: farming.address,
      abi: farmingAbi,
      functionName: "userInfo",
      args: [plan.id, owner.account.address],
    });

    if (stakedAmount > 0n) {
      console.log(`   ⏭ pool ${plan.id} (${plan.name}) already staked: ${stakedAmount}`);
      skipCount++;
      continue;
    }

    try {
      // Approve
      const approveTx = await plan.token.write.approve([farming.address, plan.amount], {
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTx });

      // Deposit
      const depositTx = await farming.write.deposit([plan.id, plan.amount], {
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: depositTx });

      console.log(`   ✓ pool ${plan.id} (${plan.name}) staked: ${plan.amount}`);
      successCount++;
    } catch (err) {
      console.log(`   ❌ pool ${plan.id} (${plan.name}) failed: ${err.message?.slice(0, 60) || err}`);
    }
  }

  console.log(`\n   Staking complete: ${successCount} succeeded, ${skipCount} skipped`);

  // =========================================================================
  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Sepolia initialization complete!");
  console.log("=".repeat(60));
  console.log("\nNOTE: TWAP is enabled but prices won't be accurate for 30 minutes.");
  console.log("      - FarmingPool: Ready to use immediately");
  console.log("      - Minter mint: Ready to use immediately");
  console.log("      - Minter redeem: Will work after 30 minutes (needs TWAP prices)\n");
  console.log("Key addresses:");
  console.log(`  BTD:         ${addresses.BTD}`);
  console.log(`  BTB:         ${addresses.BTB}`);
  console.log(`  BRS:         ${addresses.BRS}`);
  console.log(`  WBTC:        ${addresses.WBTC}`);
  console.log(`  USDC:        ${addresses.USDC}`);
  console.log(`  Minter:      ${addresses.Minter}`);
  console.log(`  FarmingPool: ${addresses.FarmingPool}`);
  console.log(`  PriceOracle: ${addresses.PriceOracle}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

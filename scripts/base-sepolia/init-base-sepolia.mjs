/**
 * Initialize Base Sepolia testnet system after deployment:
 * - Read real BTC price from Chainlink
 * - Add liquidity to LP pairs (deployed via Ignition)
 * - Configure farming pools
 * - Initialize staking vaults
 *
 * Run:
 *   npx hardhat run scripts/base-sepolia/init-base-sepolia.mjs --network baseSepolia
 *
 * Prerequisite: deployed via Ignition with FullSystemBaseSepolia module
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, keccak256, parseEther, stringToHex } from "viem";
import { baseSepolia } from "viem/chains";

const CHAIN_ID = 84532; // Base Sepolia
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

const ERC20_ABI = [
  {
    inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }],
    name: "transfer",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];

const PAIR_ABI = [
  {
    inputs: [],
    name: "getReserves",
    outputs: [
      { name: "reserve0", type: "uint112" },
      { name: "reserve1", type: "uint112" },
      { name: "blockTimestampLast", type: "uint32" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "token0",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "token1",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "to", type: "address" }],
    name: "mint",
    outputs: [{ name: "liquidity", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function loadAddresses() {
  if (!fs.existsSync(ADDR_FILE)) {
    throw new Error(`deployed_addresses.json not found at ${ADDR_FILE}. Deploy via Ignition first.`);
  }
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    const key = k.replace("FullSystemBaseSepolia#", "");
    map[key] = v;
  }
  return map;
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Bitres Base Sepolia Testnet Initialization");
  console.log("=".repeat(60));

  const addresses = loadAddresses();
  console.log("\n=> Loaded addresses from:", ADDR_FILE);

  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;
  const rpcUrl = hre.network.config?.url || process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org";

  const publicClient = createPublicClient({
    chain: baseSepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  console.log(`=> Deployer: ${owner.account.address}`);

  // Contract helpers
  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;
  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);

  // Load contracts
  const brs = await get("BRS", "contracts/BRS.sol:BRS");
  const btd = await get("BTD", "contracts/BTD.sol:BTD");
  const btb = await get("BTB", "contracts/BTB.sol:BTB");
  const wbtc = await get("WBTC", "contracts/local/MockCbBTC.sol:MockCbBTC");
  const usdc = await get("USDC", "contracts/local/MockUSDC.sol:MockUSDC");
  const usdt = await get("USDT", "contracts/local/MockUSDT.sol:MockUSDT");
  const weth = await get("WETH", "contracts/interfaces/IWETH9.sol:IWETH9");
  const stBTD = await get("stBTD", "contracts/stBTD.sol:stBTD");
  const stBTB = await get("stBTB", "contracts/stBTB.sol:stBTB");
  const farming = await get("FarmingPool", "contracts/FarmingPool.sol:FarmingPool");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");
  const twapOracle = await get("TWAPOracle", "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");

  // LP Pairs (deployed via Ignition)
  const pairWBTCUSDC = addresses.PairWBTCUSDC;
  const pairBTDUSDC = addresses.PairBTDUSDC;
  const pairBTBBTD = addresses.PairBTBBTD;
  const pairBRSBTD = addresses.PairBRSBTD;

  console.log("\n=> LP Pairs (from Ignition deployment):");
  console.log(`   cbBTC/USDC: ${pairWBTCUSDC}`);
  console.log(`   BTD/USDC:  ${pairBTDUSDC}`);
  console.log(`   BTB/BTD:   ${pairBTBBTD}`);
  console.log(`   BRS/BTD:   ${pairBRSBTD}`);

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
  // 2) Configure roles and disable TWAP initially
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

  console.log("   -> Disable TWAP oracle initially");
  const tx3 = await priceOracle.write.setUseTWAP([false], { account: owner.account });
  await publicClient.waitForTransactionReceipt({ hash: tx3 });

  // =========================================================================
  // 3) Set mock oracle prices
  // =========================================================================
  console.log("\n=> Setting mock oracle prices...");
  console.log("   -> cbBTC/BTC: 1:1 (already set)");

  // =========================================================================
  // 4) Mint BTD/BTB for LP initialization
  // =========================================================================
  console.log("\n=> Minting BTD/BTB for LP initialization...");
  const mintBtdAmount = parseEther("1");
  const mintBtbAmount = parseEther("0.1");

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
  // 5) Add LP liquidity (direct transfer to pair + mint)
  // =========================================================================
  console.log("\n=> Adding LP liquidity...");

  const btcPriceUsd = Number(btcPrice) / 1e8;
  console.log(`   Current BTC price from Chainlink: $${btcPriceUsd.toLocaleString()}`);

  const addLP = async (pairAddress, tokenAAddr, tokenBAddr, amountA, amountB, label) => {
    // Check if pair already has liquidity
    const [reserve0, reserve1] = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "getReserves",
    });
    if (reserve0 > 0n || reserve1 > 0n) {
      console.log(`   skip ${label} LP already exists (reserves: ${reserve0}, ${reserve1})`);
      const lpBalance = await publicClient.readContract({
        address: pairAddress,
        abi: PAIR_ABI,
        functionName: "balanceOf",
        args: [owner.account.address],
      });
      return lpBalance;
    }

    const [token0, token1] = await Promise.all([
      publicClient.readContract({ address: pairAddress, abi: PAIR_ABI, functionName: "token0" }),
      publicClient.readContract({ address: pairAddress, abi: PAIR_ABI, functionName: "token1" }),
    ]);
    const amount0 = token0.toLowerCase() === tokenAAddr.toLowerCase() ? amountA : amountB;
    const amount1 = token1.toLowerCase() === tokenBAddr.toLowerCase() ? amountB : amountA;

    const [balance0, balance1] = await Promise.all([
      publicClient.readContract({ address: token0, abi: ERC20_ABI, functionName: "balanceOf", args: [pairAddress] }),
      publicClient.readContract({ address: token1, abi: ERC20_ABI, functionName: "balanceOf", args: [pairAddress] }),
    ]);
    const pending0 = balance0 > reserve0 ? balance0 - reserve0 : 0n;
    const pending1 = balance1 > reserve1 ? balance1 - reserve1 : 0n;
    const deficit0 = pending0 >= amount0 ? 0n : amount0 - pending0;
    const deficit1 = pending1 >= amount1 ? 0n : amount1 - pending1;

    const transferIfNeeded = async (tokenAddr, amount) => {
      if (amount === 0n) return;
      const transferTx = await owner.writeContract({
        address: tokenAddr,
        abi: ERC20_ABI,
        functionName: "transfer",
        args: [pairAddress, amount],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: transferTx });
    };

    // Transfer only the deficit so reruns after a partial failure are idempotent.
    await transferIfNeeded(token0, deficit0);
    await transferIfNeeded(token1, deficit1);

    // Public RPCs can lag right after writes. Wait until the pair balances reflect
    // the required pending liquidity before sending mint with an explicit gas cap.
    for (let attempt = 0; attempt < 10; attempt++) {
      const [latest0, latest1] = await Promise.all([
        publicClient.readContract({ address: token0, abi: ERC20_ABI, functionName: "balanceOf", args: [pairAddress] }),
        publicClient.readContract({ address: token1, abi: ERC20_ABI, functionName: "balanceOf", args: [pairAddress] }),
      ]);
      if (latest0 >= reserve0 + amount0 && latest1 >= reserve1 + amount1) break;
      await sleep(3000);
    }

    // Mint LP tokens
    const mintTx = await owner.writeContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "mint",
      args: [owner.account.address],
      account: owner.account,
      gas: 300000n,
    });
    await publicClient.waitForTransactionReceipt({ hash: mintTx });

    const lpBalance = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "balanceOf",
      args: [owner.account.address],
    });
    console.log(`   ok ${label} LP minted: ${lpBalance}`);
    return lpBalance;
  };

  // LP amounts
  const cbbtcAmount = 10000n; // 0.0001 cbBTC (10000 satoshi)
  const usdcForCbBTC = BigInt(Math.floor(Number(cbbtcAmount) * btcPriceUsd / 100));
  const usdcAmount = usdcForCbBTC < 10000n ? 10000n : usdcForCbBTC;

  const lpWBTCUSDC = await addLP(pairWBTCUSDC, wbtc.address, usdc.address, cbbtcAmount, usdcAmount, "cbBTC/USDC");
  const lpBTDUSDC = await addLP(pairBTDUSDC, btd.address, usdc.address, parseEther("0.01"), 10000n, "BTD/USDC");
  const lpBTBBTD = await addLP(pairBTBBTD, btb.address, btd.address, parseEther("0.01"), parseEther("0.01"), "BTB/BTD");
  const lpBRSBTD = await addLP(pairBRSBTD, brs.address, btd.address, parseEther("1"), parseEther("0.01"), "BRS/BTD");

  // =========================================================================
  // 6) Initialize TWAP Oracle
  // =========================================================================
  console.log("\n=> Initializing TWAP Oracle...");
  const pairsList = [pairWBTCUSDC, pairBTDUSDC, pairBTBBTD, pairBRSBTD];

  for (const pairAddr of pairsList) {
    try {
      const txHash = await twapOracle.write.updateIfNeeded([pairAddr], { account: owner.account });
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      if (receipt.status === "success") {
        console.log(`   ok TWAP observation recorded for ${pairAddr.slice(0, 10)}...`);
      } else {
        console.log(`   warn TWAP update tx reverted for ${pairAddr.slice(0, 10)}...`);
      }
    } catch (err) {
      console.log(`   warn TWAP update failed for ${pairAddr.slice(0, 10)}...: ${err.message?.slice(0, 50) || err}`);
    }
  }

  console.log("   -> Leaving TWAP disabled until warmup confirms 30+ min observations");

  // =========================================================================
  // 7) Initialize stBTD/stBTB vaults
  // =========================================================================
  console.log("\n=> Initializing stBTD/stBTB vaults...");
  const minStake = parseEther("0.001");

  const stBTDAbi = loadAbi("contracts/stBTD.sol/stBTD.json");
  const stBTBAbi = loadAbi("contracts/stBTB.sol/stBTB.json");

  const waitForAllowance = async (tokenAddress, spender, amount) => {
    for (let attempt = 0; attempt < 10; attempt++) {
      const allowance = await publicClient.readContract({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: "allowance",
        args: [owner.account.address, spender],
      });
      if (allowance >= amount) return;
      await sleep(3000);
    }
    throw new Error(`allowance not visible for ${tokenAddress} -> ${spender}`);
  };

  const writeAndWait = async (address, abi, functionName, args, opts = {}) => {
    const hash = await owner.writeContract({
      address,
      abi,
      functionName,
      args,
      account: owner.account,
      ...opts,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") {
      throw new Error(`${functionName} failed: ${hash}`);
    }
    return hash;
  };

  const stBTDSupply = await publicClient.readContract({
    address: stBTD.address,
    abi: stBTDAbi,
    functionName: "totalSupply",
  });
  if (stBTDSupply > 0n) {
    console.log(`   skip stBTD vault already initialized (supply: ${stBTDSupply})`);
  } else {
    await writeAndWait(addresses.BTD, btdAbi, "mint", [owner.account.address, minStake], { gas: 150000n });
    await writeAndWait(addresses.BTD, btdAbi, "approve", [stBTD.address, minStake], { gas: 100000n });
    await waitForAllowance(addresses.BTD, stBTD.address, minStake);
    await writeAndWait(stBTD.address, stBTDAbi, "deposit", [minStake, owner.account.address], { gas: 500000n });
    console.log("   ok stBTD vault initialized");
  }

  const stBTBSupply = await publicClient.readContract({
    address: stBTB.address,
    abi: stBTBAbi,
    functionName: "totalSupply",
  });
  if (stBTBSupply > 0n) {
    console.log(`   skip stBTB vault already initialized (supply: ${stBTBSupply})`);
  } else {
    await writeAndWait(addresses.BTB, btbAbi, "mint", [owner.account.address, minStake], { gas: 150000n });
    await writeAndWait(addresses.BTB, btbAbi, "approve", [stBTB.address, minStake], { gas: 100000n });
    await waitForAllowance(addresses.BTB, stBTB.address, minStake);
    await writeAndWait(stBTB.address, stBTBAbi, "deposit", [minStake, owner.account.address], { gas: 500000n });
    console.log("   ok stBTB vault initialized");
  }

  // =========================================================================
  // 8) Configure farming pools
  // =========================================================================
  console.log("\n=> Configuring FarmingPool pools...");

  const farmingAbi = loadAbi("contracts/FarmingPool.sol/FarmingPool.json");
  const poolLength = await publicClient.readContract({
    address: farming.address,
    abi: farmingAbi,
    functionName: "poolLength",
  });

  if (poolLength > 0n) {
    console.log(`   skip Farming pools already configured (${poolLength} pools)`);
  } else {
    const tokens = [
      pairBRSBTD,     // 0: LP - BRS/BTD
      pairBTDUSDC,    // 1: LP - BTD/USDC
      pairBTBBTD,     // 2: LP - BTB/BTD
      usdc.address,   // 3: Single
      usdt.address,   // 4: Single
      wbtc.address,   // 5: Single
      weth.address,   // 6: Single
      stBTD.address,  // 7: Single
      stBTB.address,  // 8: Single
      brs.address,    // 9: Single
    ];
    const allocPoints = [15, 15, 15, 1, 1, 1, 1, 3, 3, 5];
    const kinds = [1, 1, 1, 0, 0, 0, 0, 0, 0, 0];

    await farming.write.addPools([tokens, allocPoints, kinds], {
      account: owner.account,
    });
    console.log("   ok 10 farming pools configured");
  }

  // =========================================================================
  // 9) Seed staking for farming pools
  // =========================================================================
  console.log("\n=> Seeding staking for farming pools...");

  const MIN_BTC = 1n;
  const MIN_STABLE_6 = 1000n;
  const MIN_STABLE_18 = parseEther("0.001");
  const MIN_ETH = 10n ** 10n;

  // Deposit ETH to get WETH (official WETH9)
  const wethBalance = await publicClient.readContract({
    address: weth.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [owner.account.address],
  });
  if (wethBalance < MIN_ETH) {
    console.log("   -> Depositing ETH to get WETH...");
    const WETH9_ABI = [{ inputs: [], name: "deposit", outputs: [], stateMutability: "payable", type: "function" }];
    const depositTx = await owner.writeContract({
      address: weth.address,
      abi: WETH9_ABI,
      functionName: "deposit",
      args: [],
      value: MIN_ETH,
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log(`   ok Deposited ${MIN_ETH} wei ETH -> WETH`);
  }

  const stakePlans = [
    { id: 0, token: { address: pairBRSBTD }, amount: lpBRSBTD, name: "BRS/BTD LP" },
    { id: 1, token: { address: pairBTDUSDC }, amount: lpBTDUSDC, name: "BTD/USDC LP" },
    { id: 2, token: { address: pairBTBBTD }, amount: lpBTBBTD, name: "BTB/BTD LP" },
    { id: 3, token: usdc, amount: MIN_STABLE_6, name: "USDC" },
    { id: 4, token: usdt, amount: MIN_STABLE_6, name: "USDT" },
    { id: 5, token: wbtc, amount: MIN_BTC, name: "cbBTC" },
    { id: 6, token: weth, amount: MIN_ETH, name: "WETH" },
    { id: 7, token: stBTD, amount: MIN_STABLE_18, name: "stBTD" },
    { id: 8, token: stBTB, amount: MIN_STABLE_18, name: "stBTB" },
    { id: 9, token: brs, amount: MIN_STABLE_18, name: "BRS" },
  ];

  let successCount = 0;
  let skipCount = 0;

  for (const plan of stakePlans) {
    if (plan.amount === 0n) {
      console.log(`   skip pool ${plan.id} (${plan.name}): no balance`);
      skipCount++;
      continue;
    }

    const [stakedAmount] = await publicClient.readContract({
      address: farming.address,
      abi: farmingAbi,
      functionName: "userInfo",
      args: [plan.id, owner.account.address],
    });

    if (stakedAmount > 0n) {
      console.log(`   skip pool ${plan.id} (${plan.name}) already staked: ${stakedAmount}`);
      skipCount++;
      continue;
    }

    try {
      const tokenAddress = plan.token.address || plan.token;
      const approveTx = await owner.writeContract({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [farming.address, plan.amount],
        account: owner.account,
        gas: 100000n,
      });
      const approveReceipt = await publicClient.waitForTransactionReceipt({ hash: approveTx });
      if (approveReceipt.status !== "success") {
        throw new Error(`approve failed: ${approveTx}`);
      }
      await waitForAllowance(tokenAddress, farming.address, plan.amount);

      const depositTx = await farming.write.deposit([plan.id, plan.amount], {
        account: owner.account,
        gas: 500000n,
      });
      const depositReceipt = await publicClient.waitForTransactionReceipt({ hash: depositTx });
      if (depositReceipt.status !== "success") {
        throw new Error(`deposit failed: ${depositTx}`);
      }

      console.log(`   ok pool ${plan.id} (${plan.name}) staked: ${plan.amount}`);
      successCount++;
    } catch (err) {
      console.log(`   err pool ${plan.id} (${plan.name}) failed: ${err.message?.slice(0, 60) || err}`);
    }
  }

  console.log(`\n   Staking complete: ${successCount} succeeded, ${skipCount} skipped`);

  // =========================================================================
  console.log("\n" + "=".repeat(60));
  console.log("  Base Sepolia initialization complete!");
  console.log("=".repeat(60));
  console.log("\nPair Addresses (from Ignition deployment):");
  console.log(`  cbBTC/USDC:  ${pairWBTCUSDC}`);
  console.log(`  BTD/USDC:    ${pairBTDUSDC}`);
  console.log(`  BTB/BTD:     ${pairBTBBTD}`);
  console.log(`  BRS/BTD:     ${pairBRSBTD}`);
  console.log("\nKey addresses:");
  console.log(`  BTD:         ${addresses.BTD}`);
  console.log(`  BTB:         ${addresses.BTB}`);
  console.log(`  BRS:         ${addresses.BRS}`);
  console.log(`  cbBTC:       ${addresses.WBTC}`);
  console.log(`  USDC:        ${addresses.USDC}`);
  console.log(`  Minter:      ${addresses.Minter}`);
  console.log(`  FarmingPool: ${addresses.FarmingPool}`);
  console.log(`  PriceOracle: ${addresses.PriceOracle}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

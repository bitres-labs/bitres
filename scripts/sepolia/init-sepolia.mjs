/**
 * Initialize Sepolia testnet system after deployment:
 * - Create pairs via official Uniswap V2 Factory
 * - Set ConfigCore peripheral contracts with pair addresses
 * - Read real BTC price from Chainlink
 * - Set mock Pyth/Redstone prices to match Chainlink
 * - Add liquidity via official Uniswap V2 Router
 * - Configure farming pools
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

// Official Uniswap V2 on Sepolia
const UNISWAP_V2 = {
  FACTORY: "0xF62c03E08ada871A0bEb309762E260a7a6a880E6",
  ROUTER: "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3",
};

const DEFAULTS = {
  pythPriceId: "0x505954485f575442430000000000000000000000000000000000000000000000",
  redstoneFeedId: "0x52454453544f4e455f5754424300000000000000000000000000000000000000",
};

// Uniswap V2 ABIs
const FACTORY_ABI = [
  {
    inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }],
    name: "createPair",
    outputs: [{ name: "pair", type: "address" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }],
    name: "getPair",
    outputs: [{ name: "pair", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
];

const ROUTER_ABI = [
  {
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
      { name: "amountADesired", type: "uint256" },
      { name: "amountBDesired", type: "uint256" },
      { name: "amountAMin", type: "uint256" },
      { name: "amountBMin", type: "uint256" },
      { name: "to", type: "address" },
      { name: "deadline", type: "uint256" },
    ],
    name: "addLiquidity",
    outputs: [
      { name: "amountA", type: "uint256" },
      { name: "amountB", type: "uint256" },
      { name: "liquidity", type: "uint256" },
    ],
    stateMutability: "nonpayable",
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
];

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
];

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
  console.log("  Using Official Uniswap V2 Factory & Router");
  console.log("=".repeat(60));

  const addresses = loadAddresses();
  console.log("\n=> Loaded addresses from:", ADDR_FILE);

  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;
  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org";

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  console.log(`=> Deployer: ${owner.account.address}`);
  console.log(`=> Uniswap V2 Factory: ${UNISWAP_V2.FACTORY}`);
  console.log(`=> Uniswap V2 Router: ${UNISWAP_V2.ROUTER}`);

  // Contract helpers
  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;
  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);

  // Load contracts
  const brs = await get("BRS", "contracts/BRS.sol:BRS");
  const btd = await get("BTD", "contracts/BTD.sol:BTD");
  const btb = await get("BTB", "contracts/BTB.sol:BTB");
  const wbtc = await get("WBTC", "contracts/local/MockWBTC.sol:MockWBTC");
  const usdc = await get("USDC", "contracts/local/MockUSDC.sol:MockUSDC");
  const usdt = await get("USDT", "contracts/local/MockUSDT.sol:MockUSDT");
  // WETH is the official WETH9, not our MockWETH
  const weth = await get("WETH", "contracts/interfaces/IWETH9.sol:IWETH9");
  const stBTD = await get("stBTD", "contracts/stBTD.sol:stBTD");
  const stBTB = await get("stBTB", "contracts/stBTB.sol:stBTB");
  const farming = await get("FarmingPool", "contracts/FarmingPool.sol:FarmingPool");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");
  const configCore = await get("ConfigCore", "contracts/ConfigCore.sol:ConfigCore");
  const twapOracle = await get("TWAPOracle", "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");

  const mockPyth = await get("MockPyth", "contracts/local/MockPyth.sol:MockPyth");
  const mockRedstone = await get("MockRedstone", "contracts/local/MockRedstone.sol:MockRedstone");

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
  console.log("   -> WBTC/BTC: 1:1 (already set)");

  const pythPrice = btcPrice;
  const pythExpo = -8n;
  await mockPyth.write.setPrice([DEFAULTS.pythPriceId, pythPrice, pythExpo], {
    account: owner.account,
  });
  console.log(`   -> Pyth BTC price: ${Number(pythPrice) / 1e8}`);

  const redstonePrice = BigInt(btcPrice) * 10n ** 10n;
  await mockRedstone.write.setValue([DEFAULTS.redstoneFeedId, redstonePrice], {
    account: owner.account,
  });
  console.log(`   -> Redstone BTC price: ${Number(redstonePrice) / 1e18}`);

  // =========================================================================
  // 4) Mint BTD/BTB for LP initialization
  // =========================================================================
  console.log("\n=> Minting BTD/BTB for LP initialization...");
  const mintBtdAmount = parseEther("1"); // Need more for 100:1 BRS/BTD ratio
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
  // 5) Create pairs via official Uniswap V2 Factory
  // =========================================================================
  console.log("\n=> Creating pairs via official Uniswap V2 Factory...");

  const createOrGetPair = async (tokenA, tokenB, label) => {
    // Check if pair already exists
    const existingPair = await publicClient.readContract({
      address: UNISWAP_V2.FACTORY,
      abi: FACTORY_ABI,
      functionName: "getPair",
      args: [tokenA, tokenB],
    });

    if (existingPair !== "0x0000000000000000000000000000000000000000") {
      console.log(`   ⏭ ${label} pair already exists: ${existingPair}`);
      return existingPair;
    }

    // Create pair
    const createTx = await owner.writeContract({
      address: UNISWAP_V2.FACTORY,
      abi: FACTORY_ABI,
      functionName: "createPair",
      args: [tokenA, tokenB],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: createTx });

    const newPair = await publicClient.readContract({
      address: UNISWAP_V2.FACTORY,
      abi: FACTORY_ABI,
      functionName: "getPair",
      args: [tokenA, tokenB],
    });
    console.log(`   ✓ ${label} pair created: ${newPair}`);
    return newPair;
  };

  const pairWBTCUSDC = await createOrGetPair(wbtc.address, usdc.address, "WBTC/USDC");
  const pairBTDUSDC = await createOrGetPair(btd.address, usdc.address, "BTD/USDC");
  const pairBTBBTD = await createOrGetPair(btb.address, btd.address, "BTB/BTD");
  const pairBRSBTD = await createOrGetPair(brs.address, btd.address, "BRS/BTD");

  // Store pair addresses for later use
  const pairAddresses = {
    WBTC_USDC: pairWBTCUSDC,
    BTD_USDC: pairBTDUSDC,
    BTB_BTD: pairBTBBTD,
    BRS_BTD: pairBRSBTD,
  };

  // =========================================================================
  // 6) Set ConfigCore peripheral contracts with pair addresses
  // =========================================================================
  console.log("\n=> Setting ConfigCore peripheral contracts...");

  // Check if already set
  const peripheralSet = await publicClient.readContract({
    address: configCore.address,
    abi: loadAbi("contracts/ConfigCore.sol/ConfigCore.json"),
    functionName: "peripheralContractsSet",
  });

  if (peripheralSet) {
    console.log("   ⏭ Peripheral contracts already set");
  } else {
    const configCoreAbi = loadAbi("contracts/ConfigCore.sol/ConfigCore.json");
    const setPeripheralTx = await owner.writeContract({
      address: configCore.address,
      abi: configCoreAbi,
      functionName: "setPeripheralContracts",
      args: [
        addresses.StakingRouter,
        addresses.FarmingPool,
        addresses.stBTD,
        addresses.stBTB,
        owner.account.address, // governor
        addresses.TWAPOracle,
        pairWBTCUSDC,
        pairBTDUSDC,
        pairBTBBTD,
        pairBRSBTD,
      ],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: setPeripheralTx });
    console.log("   ✓ Peripheral contracts set with official Uniswap V2 pairs");
  }

  // =========================================================================
  // 7) Add LP liquidity via official Uniswap V2 Router
  // =========================================================================
  console.log("\n=> Adding LP liquidity via official Uniswap V2 Router...");

  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour

  const addLP = async (tokenA, tokenB, amountA, amountB, label, pairAddress) => {
    // Check if pair already has liquidity
    const [reserve0, reserve1] = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "getReserves",
    });
    if (reserve0 > 0n || reserve1 > 0n) {
      console.log(`   ⏭ ${label} LP already exists (reserves: ${reserve0}, ${reserve1})`);
      const lpBalance = await publicClient.readContract({
        address: pairAddress,
        abi: PAIR_ABI,
        functionName: "balanceOf",
        args: [owner.account.address],
      });
      return lpBalance;
    }

    // Approve tokens for Router
    const approveTxA = await owner.writeContract({
      address: tokenA.address,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [UNISWAP_V2.ROUTER, amountA],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveTxA });

    const approveTxB = await owner.writeContract({
      address: tokenB.address,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [UNISWAP_V2.ROUTER, amountB],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveTxB });

    // Add liquidity via Router
    const addLiqTx = await owner.writeContract({
      address: UNISWAP_V2.ROUTER,
      abi: ROUTER_ABI,
      functionName: "addLiquidity",
      args: [
        tokenA.address,
        tokenB.address,
        amountA,
        amountB,
        0n, // amountAMin
        0n, // amountBMin
        owner.account.address,
        deadline,
      ],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: addLiqTx });

    const lpBalance = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "balanceOf",
      args: [owner.account.address],
    });
    console.log(`   ✓ ${label} LP minted: ${lpBalance}`);
    return lpBalance;
  };

  // LP amounts (matching current BTC price for WBTC/USDC)
  const btcPriceUsd = Number(btcPrice) / 1e8;
  console.log(`   Current BTC price from Chainlink: $${btcPriceUsd.toLocaleString()}`);

  const wbtcAmount = 10000n; // 0.0001 WBTC (10000 satoshi)
  const usdcForWbtc = BigInt(Math.floor(Number(wbtcAmount) * btcPriceUsd / 100));
  const usdcAmount = usdcForWbtc < 10000n ? 10000n : usdcForWbtc;

  const lpWBTCUSDC = await addLP(wbtc, usdc, wbtcAmount, usdcAmount, "WBTC/USDC", pairWBTCUSDC);

  // BTD/USDC: ~$1 BTD (use small amounts)
  const lpBTDUSDC = await addLP(btd, usdc, parseEther("0.01"), 10000n, "BTD/USDC", pairBTDUSDC);

  // BTB/BTD: 1:1 ratio
  const lpBTBBTD = await addLP(btb, btd, parseEther("0.01"), parseEther("0.01"), "BTB/BTD", pairBTBBTD);

  // BRS/BTD: 100:1 ratio (1 BRS = 0.01 BTD)
  const lpBRSBTD = await addLP(brs, btd, parseEther("1"), parseEther("0.01"), "BRS/BTD", pairBRSBTD);

  // =========================================================================
  // 8) Initialize TWAP Oracle
  // =========================================================================
  console.log("\n=> Initializing TWAP Oracle...");
  const pairsList = [pairWBTCUSDC, pairBTDUSDC, pairBTBBTD, pairBRSBTD];

  for (const pairAddr of pairsList) {
    try {
      await twapOracle.write.updateIfNeeded([pairAddr], { account: owner.account });
      console.log(`   ✓ TWAP observation recorded for ${pairAddr.slice(0, 10)}...`);
    } catch (err) {
      console.log(`   ⚠ TWAP update failed for ${pairAddr.slice(0, 10)}...: ${err.message?.slice(0, 50) || err}`);
    }
  }

  // Enable TWAP
  console.log("   -> Enabling TWAP...");
  const enableTx = await priceOracle.write.setUseTWAP([true], { account: owner.account });
  await publicClient.waitForTransactionReceipt({ hash: enableTx });
  console.log("   ✓ TWAP enabled (prices available after 30 min)");

  // =========================================================================
  // 9) Initialize stBTD/stBTB vaults
  // =========================================================================
  console.log("\n=> Initializing stBTD/stBTB vaults...");
  const minStake = parseEther("0.001");

  const stBTDAbi = loadAbi("contracts/stBTD.sol/stBTD.json");
  const stBTBAbi = loadAbi("contracts/stBTB.sol/stBTB.json");

  const writeAndWait = async (address, abi, functionName, args) => {
    const hash = await owner.writeContract({ address, abi, functionName, args, account: owner.account });
    await publicClient.waitForTransactionReceipt({ hash });
    return hash;
  };

  const stBTDSupply = await publicClient.readContract({
    address: stBTD.address,
    abi: stBTDAbi,
    functionName: "totalSupply",
  });
  if (stBTDSupply > 0n) {
    console.log(`   ⏭ stBTD vault already initialized (supply: ${stBTDSupply})`);
  } else {
    await writeAndWait(addresses.BTD, btdAbi, "mint", [owner.account.address, minStake]);
    await writeAndWait(addresses.BTD, btdAbi, "approve", [stBTD.address, minStake]);
    await writeAndWait(stBTD.address, stBTDAbi, "deposit", [minStake, owner.account.address]);
    console.log("   ✓ stBTD vault initialized");
  }

  const stBTBSupply = await publicClient.readContract({
    address: stBTB.address,
    abi: stBTBAbi,
    functionName: "totalSupply",
  });
  if (stBTBSupply > 0n) {
    console.log(`   ⏭ stBTB vault already initialized (supply: ${stBTBSupply})`);
  } else {
    await writeAndWait(addresses.BTB, btbAbi, "mint", [owner.account.address, minStake]);
    await writeAndWait(addresses.BTB, btbAbi, "approve", [stBTB.address, minStake]);
    await writeAndWait(stBTB.address, stBTBAbi, "deposit", [minStake, owner.account.address]);
    console.log("   ✓ stBTB vault initialized");
  }

  // =========================================================================
  // 10) Configure farming pools
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
      pairBRSBTD,  // 0: LP - BRS/BTD
      pairBTDUSDC, // 1: LP - BTD/USDC
      pairBTBBTD,  // 2: LP - BTB/BTD
      usdc.address,// 3: Single
      usdt.address,// 4: Single
      wbtc.address,// 5: Single
      weth.address,// 6: Single
      stBTD.address,// 7: Single
      stBTB.address,// 8: Single
      brs.address,  // 9: Single
    ];
    const allocPoints = [15, 15, 15, 1, 1, 1, 1, 3, 3, 5];
    const kinds = [1, 1, 1, 0, 0, 0, 0, 0, 0, 0];

    await farming.write.addPools([tokens, allocPoints, kinds], {
      account: owner.account,
    });
    console.log("   ✓ 10 farming pools configured");
  }

  // =========================================================================
  // 11) Seed staking for farming pools
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
    console.log(`   ✓ Deposited ${MIN_ETH} wei ETH -> WETH`);
  }

  const stakePlans = [
    { id: 0, token: { address: pairBRSBTD }, amount: lpBRSBTD, name: "BRS/BTD LP" },
    { id: 1, token: { address: pairBTDUSDC }, amount: lpBTDUSDC, name: "BTD/USDC LP" },
    { id: 2, token: { address: pairBTBBTD }, amount: lpBTBBTD, name: "BTB/BTD LP" },
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
      const tokenAddress = plan.token.address || plan.token;
      const approveTx = await owner.writeContract({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [farming.address, plan.amount],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTx });

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
  // 12) Save pair addresses to deployed_addresses.json
  // =========================================================================
  console.log("\n=> Saving pair addresses...");
  const fullAddresses = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  fullAddresses["FullSystemSepolia#PairWBTCUSDC"] = pairWBTCUSDC;
  fullAddresses["FullSystemSepolia#PairBTDUSDC"] = pairBTDUSDC;
  fullAddresses["FullSystemSepolia#PairBTBBTD"] = pairBTBBTD;
  fullAddresses["FullSystemSepolia#PairBRSBTD"] = pairBRSBTD;
  fullAddresses["FullSystemSepolia#UniswapV2Factory"] = UNISWAP_V2.FACTORY;
  fullAddresses["FullSystemSepolia#UniswapV2Router"] = UNISWAP_V2.ROUTER;
  fs.writeFileSync(ADDR_FILE, JSON.stringify(fullAddresses, null, 2));
  console.log("   ✓ Pair addresses saved to deployed_addresses.json");

  // =========================================================================
  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Sepolia initialization complete!");
  console.log("=".repeat(60));
  console.log("\nUsing Official Uniswap V2:");
  console.log(`  Factory:     ${UNISWAP_V2.FACTORY}`);
  console.log(`  Router:      ${UNISWAP_V2.ROUTER}`);
  console.log("\nPair Addresses:");
  console.log(`  WBTC/USDC:   ${pairWBTCUSDC}`);
  console.log(`  BTD/USDC:    ${pairBTDUSDC}`);
  console.log(`  BTB/BTD:     ${pairBTBBTD}`);
  console.log(`  BRS/BTD:     ${pairBRSBTD} (ratio 100:1, 1 BRS = 0.01 BTD)`);
  console.log("\nKey addresses:");
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

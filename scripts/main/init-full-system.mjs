/**
 * Initialize local system after deployment:
 * - Set oracle prices (Chainlink/Pyth/Redstone)
 * - Add real UniswapV2Pair liquidity and mint LP
 * - Configure 10 farming pools (same weights as legacy script)
 * - Fund FarmingPool with BRS rewards
 *
 * Run:
 *   npx hardhat run scripts/main/init-full-system.mjs --network localhost
 *
 * Prerequisite: deployed via Ignition; addresses stored in ignition/deployments/chain-31337/deployed_addresses.json
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, keccak256, parseEther, parseUnits, stringToHex } from "viem";
import { hardhat as viemHardhat } from "viem/chains";

const ADDR_FILE = path.join(
  process.cwd(),
  "ignition/deployments/chain-31337/deployed_addresses.json"
);

const DEFAULTS = {
  btcPriceChainlink: 102_000n * 10n ** 8n, // Chainlink 8 decimals
  pythPrice: 102_000n * 10n ** 8n,
  pythExpo: -8n,
  redstonePrice: 102_000n * 10n ** 18n,
  pythPriceId:
    "0x505954485f575442430000000000000000000000000000000000000000000000", // "PYTH_WTBC"
  redstoneFeedId:
    "0x52454453544f4e455f5754424300000000000000000000000000000000000000", // "REDSTONE_WTBC"
};

function loadAddresses() {
  if (!fs.existsSync(ADDR_FILE)) {
    throw new Error("deployed_addresses.json not found, please deploy via Ignition first.");
  }
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  // remove prefix
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    const key = k.replace("FullSystemV2#", "");
    map[key] = v;
  }
  return map;
}

async function main() {
  const addresses = loadAddresses();
  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner, foundation, team, ...rest] = wallets;
  const users = rest.slice(0, 10);
  const rpcUrl = hre.network.config?.url ?? "http://127.0.0.1:8545";
  const publicClient = createPublicClient({
    chain: viemHardhat,
    transport: http(rpcUrl),
  });

  // contract helpers
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
  const treasury = await get("Treasury", "contracts/Treasury.sol:Treasury");
  const minter = await get("Minter", "contracts/Minter.sol:Minter");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");

  const chainlinkBtcUsd = await get(
    "ChainlinkBTCUSD",
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3"
  );
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

  // 0) enable automine (transactions are mined immediately)
  // Note: interval mining is NOT enabled here to prevent timestamp drift
  // Guardian will control mining after init completes
  const provider = hre.network?.provider ?? connection.provider;
  if (provider?.request) {
    await provider.request({ method: "evm_setAutomine", params: [true] });
  } else if (provider?.send) {
    await provider.send("evm_setAutomine", [true]);
  }

  // 0.5) roles + oracle toggles
  console.log("=> configure roles...");
  const MINTER_ROLE = keccak256(stringToHex("MINTER_ROLE"));
  const btdAbi = loadAbi("contracts/BTD.sol/BTD.json");
  const btbAbi = loadAbi("contracts/BTB.sol/BTB.json");
  console.log("   -> Grant BTD MINTER to owner");
  await owner.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "grantRole",
    args: [MINTER_ROLE, owner.account.address],
    account: owner.account,
  });
  console.log("   -> Grant BTB MINTER to owner");
  await owner.writeContract({
    address: addresses.BTB,
    abi: btbAbi,
    functionName: "grantRole",
    args: [MINTER_ROLE, owner.account.address],
    account: owner.account,
  });
  console.log("   -> Grant BTD MINTER to Minter");
  await owner.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "grantRole",
    args: [MINTER_ROLE, minter.address],
    account: owner.account,
  });
  console.log("   -> Grant BTB MINTER to Minter");
  await owner.writeContract({
    address: addresses.BTB,
    abi: btbAbi,
    functionName: "grantRole",
    args: [MINTER_ROLE, minter.address],
    account: owner.account,
  });
  // Disable TWAP during local init to avoid missing TWAP config
  await priceOracle.write.setUseTWAP([false], { account: owner.account });

  // 1) oracle prices
  console.log("=> set oracle prices...");
  await chainlinkBtcUsd.write.setAnswer([DEFAULTS.btcPriceChainlink], { account: owner.account });
  await chainlinkWbtcBtc.write.setAnswer([1n * 10n ** 8n], { account: owner.account });
  await mockPyth.write.setPrice([DEFAULTS.pythPriceId, DEFAULTS.pythPrice, DEFAULTS.pythExpo], {
    account: owner.account,
  });
  await mockRedstone.write.setValue([DEFAULTS.redstoneFeedId, DEFAULTS.redstonePrice], {
    account: owner.account,
  });

  // 1.5) mint BTD/BTB needed for LP (minimal amounts)
  // BTD: 1 (BTD/USDC) + 1 (BTB/BTD) + 1 (BRS/BTD) = 3, vault init mints separately
  // BTB: 1 (BTB/BTD), vault init mints separately
  const mintBtdAmount = parseEther("5"); // 3 needed + buffer
  const mintBtbAmount = parseEther("2"); // 1 needed + buffer
  await owner.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "mint",
    args: [owner.account.address, mintBtdAmount],
    account: owner.account,
  });
  await owner.writeContract({
    address: addresses.BTB,
    abi: btbAbi,
    functionName: "mint",
    args: [owner.account.address, mintBtbAmount],
    account: owner.account,
  });

  // 2) add real LP liquidity and mint LP
  console.log("=> add LP liquidity and mint LP...");
  const addLP = async (pair, token0, token1, amt0, amt1, label) => {
    await token0.write.transfer([pair.address, amt0], { account: owner.account });
    await token1.write.transfer([pair.address, amt1], { account: owner.account });
    await pair.write.mint([owner.account.address], { account: owner.account });
    const lpBal = await publicClient.readContract({
      address: pair.address,
      abi: pairAbi,
      functionName: "balanceOf",
      args: [owner.account.address],
    });
    console.log(`   ✓ ${label} LP minted: ${lpBal.toString()}`);
    return lpBal;
  };
  // Use minimal LP amounts - just enough to initialize pools (sqrt(a*b) > 1000)
  // Price ratio must match oracle to pass 1% deviation check
  const lpWBTCUSDC = await addLP(
    pairWBTCUSDC,
    wbtc,
    usdc,
    1n * 10n ** 3n,        // 0.00001 WBTC
    102n * 10n ** 4n,      // 1.02 USDC (exactly $102k/BTC to match oracle)
    "WBTC/USDC"
  );
  const lpBTDUSDC = await addLP(
    pairBTDUSDC,
    btd,
    usdc,
    1n * 10n ** 18n,       // 1 BTD
    1n * 10n ** 6n,        // 1 USDC
    "BTD/USDC"
  );
  const lpBTBBTD = await addLP(
    pairBTBBTD,
    btb,
    btd,
    1n * 10n ** 18n,       // 1 BTB
    1n * 10n ** 18n,       // 1 BTD
    "BTB/BTD"
  );
  // BRS/BTD LP: deployer has 1 BRS reserved in Ignition (0.1 for LP, 0.9 for pool 9)
  // BRS:BTD ratio 100:1 (1 BRS = 0.01 BTD initial price)
  const lpBRSBTD = await addLP(
    pairBRSBTD,
    brs,
    btd,
    1n * 10n ** 17n,       // 0.1 BRS (minimal for LP, rest for pool 9 staking)
    1n * 10n ** 15n,       // 0.001 BTD (ratio 100:1, so 1 BRS = 0.01 BTD)
    "BRS/BTD"
  );

  // 2.5) init stBTD/stBTB vaults (1 unit each)
  console.log("=> init stBTD/stBTB vaults...");
  const oneBTD = parseEther("1");
  const oneBTB = parseEther("1");
  await write("contracts/BTD.sol/BTD.json", addresses.BTD, "mint", [owner.account.address, oneBTD]);
  await write("contracts/BTD.sol/BTD.json", addresses.BTD, "approve", [stBTD.address, oneBTD]);
  await write("contracts/stBTD.sol/stBTD.json", addresses.stBTD, "deposit", [oneBTD, owner.account.address]);
  await write("contracts/BTB.sol/BTB.json", addresses.BTB, "mint", [owner.account.address, oneBTB]);
  await write("contracts/BTB.sol/BTB.json", addresses.BTB, "approve", [stBTB.address, oneBTB]);
  await write("contracts/stBTB.sol/stBTB.json", addresses.stBTB, "deposit", [oneBTB, owner.account.address]);

  // 3) configure farming pools (same weights)
  console.log("=> configure FarmingPool pools...");
  const tokens = [
    pairBRSBTD, // 0: LP
    pairBTDUSDC, // 1: LP
    pairBTBBTD, // 2: LP
    usdc, // 3: Single
    usdt, // 4: Single
    wbtc, // 5: Single
    weth, // 6: Single
    stBTD, // 7: Single
    stBTB, // 8: Single
    brs, // 9: Single
  ];
  const allocPoints = [15, 15, 15, 1, 1, 1, 1, 3, 3, 5];
  // PoolKind: 0 Single, 1 LP
  const kinds = [1, 1, 1, 0, 0, 0, 0, 0, 0, 0];

  await farming.write.addPools([tokens.map((t) => t.address), allocPoints, kinds], {
    account: owner.account,
  });

  // 3.5) stake small amounts to activate (LP uses real UNI-V2)
  console.log("=> seed staking for pools...");

  // Get owner's stBTD/stBTB balances from vault init (should be ~1 unit each minus dust)
  const stBTDAbi = loadAbi("contracts/stBTD.sol/stBTD.json");
  const stBTBAbi = loadAbi("contracts/stBTB.sol/stBTB.json");
  const ownerStBTD = await publicClient.readContract({
    address: stBTD.address,
    abi: stBTDAbi,
    functionName: "balanceOf",
    args: [owner.account.address],
  });
  const ownerStBTB = await publicClient.readContract({
    address: stBTB.address,
    abi: stBTBAbi,
    functionName: "balanceOf",
    args: [owner.account.address],
  });

  // Get owner's remaining BRS balance (0.5 BRS left after LP creation)
  const brsAbi = loadAbi("contracts/BRS.sol/BRS.json");
  const ownerBRS = await publicClient.readContract({
    address: brs.address,
    abi: brsAbi,
    functionName: "balanceOf",
    args: [owner.account.address],
  });

  // Use minimal stake amounts - TVL < $1 per pool (pools 3-4, 7-9 = $1)
  // Prices: WBTC=$102k, WETH=$3k, BTD/BTB/stBTD/stBTB=$1, BRS=$0.01, USDC/USDT=$1
  // LP pools need slightly larger amounts due to contract minimums
  const stakePlans = [
    { id: 0, token: pairBRSBTD, amount: lpBRSBTD / 100n, name: "BRS/BTD LP" },     // ~$0.01 TVL
    { id: 1, token: pairBTDUSDC, amount: lpBTDUSDC / 100n, name: "BTD/USDC LP" },  // ~$0.01 TVL
    { id: 2, token: pairBTBBTD, amount: lpBTBBTD / 100n, name: "BTB/BTD LP" },     // ~$0.01 TVL
    { id: 3, token: usdc, amount: parseUnits("1", 6), name: "USDC" },              // $1.00 TVL
    { id: 4, token: usdt, amount: parseUnits("1", 6), name: "USDT" },              // $1.00 TVL
    { id: 5, token: wbtc, amount: parseUnits("0.000005", 8), name: "WBTC" },       // ~$0.51 TVL
    { id: 6, token: weth, amount: parseEther("0.0002"), name: "WETH" },            // ~$0.60 TVL
    { id: 7, token: stBTD, amount: parseEther("1"), name: "stBTD" },               // $1.00 TVL
    { id: 8, token: stBTB, amount: parseEther("1"), name: "stBTB" },               // $1.00 TVL
    { id: 9, token: brs, amount: parseEther("0.9"), name: "BRS" },                 // $0.90 TVL (limited by 1 BRS total)
  ];

  for (const plan of stakePlans) {
    try {
      await plan.token.write.approve([farming.address, plan.amount], { account: owner.account });
      await farming.write.deposit([plan.id, plan.amount], { account: owner.account });
      console.log(`   ✓ pool ${plan.id} (${plan.name}) staked ${plan.amount.toString()}`);
    } catch (err) {
      console.log(`   ⚠️  pool ${plan.id} (${plan.name}) stake skipped/failed: ${err.message || err}`);
    }
  }

  // 4) BRS rewards already funded via Ignition deployment (all 2.1B BRS transferred to FarmingPool)
  console.log("=> BRS rewards already in FarmingPool (from Ignition deployment)");

  // 5) distribute test tokens to 4 specific addresses (large amounts for testing)
  console.log("=> distribute test tokens to 4 specified addresses...");
  const testRecipients = [
    "0x8F78bE5c6b41C2d7634d25C7db22b26409671ca9",
    "0xb53f41e806ab204b2525bd8b43909d47b32a04ac",
    "0x9b7cd6e80158361a513673b43ed6decc42a70eba",
    "0xc593617408c1de3561bec95cdbc316b3cb823c8d",
  ];
  const wbtcAmount = parseUnits("1000", 8);        // 1000 WBTC
  const usdcAmount = parseUnits("100000000", 6);   // 100M USDC
  const usdtAmount = parseUnits("100000000", 6);   // 100M USDT
  const ethAmount = parseEther("1000");            // 1000 ETH

  for (const recipient of testRecipients) {
    await wbtc.write.transfer([recipient, wbtcAmount], { account: owner.account });
    await usdc.write.transfer([recipient, usdcAmount], { account: owner.account });
    await usdt.write.transfer([recipient, usdtAmount], { account: owner.account });
    // Send native ETH instead of WETH
    await owner.sendTransaction({ to: recipient, value: ethAmount });
    console.log(`   ✓ ${recipient}: 1000 WBTC, 100M USDC, 100M USDT, 1000 ETH`);
  }

  console.log("✅ init done");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

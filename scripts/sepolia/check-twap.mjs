/**
 * Check TWAP Oracle status on Sepolia
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";

const CHAIN_ID = 11155111;
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

async function main() {
  const addresses = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();

  const twapOracleAddr = addresses["FullSystemSepolia#TWAPOracle"];
  console.log(`TWAP Oracle: ${twapOracleAddr}`);

  const twapOracle = await viem.getContractAt(
    "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle",
    twapOracleAddr
  );

  const pairs = [
    { name: "WBTC/USDC", addr: addresses["FullSystemSepolia#PairWBTCUSDC"] },
    { name: "BTD/USDC", addr: addresses["FullSystemSepolia#PairBTDUSDC"] },
    { name: "BTB/BTD", addr: addresses["FullSystemSepolia#PairBTBBTD"] },
    { name: "BRS/BTD", addr: addresses["FullSystemSepolia#PairBRSBTD"] },
  ];

  const now = Math.floor(Date.now() / 1000);
  console.log(`\nCurrent time: ${new Date().toISOString()}\n`);

  for (const pair of pairs) {
    if (!pair.addr) {
      console.log(`${pair.name}: No address found`);
      continue;
    }

    try {
      const [olderTs, newerTs, elapsed] = await twapOracle.read.getObservationInfo([pair.addr]);
      const ready = await twapOracle.read.isTWAPReady([pair.addr]);
      const needsUpdate = await twapOracle.read.needsUpdate([pair.addr]);

      const newerAge = now - Number(newerTs);
      const olderAge = now - Number(olderTs);

      console.log(`${pair.name}:`);
      console.log(`  Pair: ${pair.addr}`);
      console.log(`  Older observation: ${Number(olderTs) > 0 ? `${olderAge}s ago` : 'none'}`);
      console.log(`  Newer observation: ${Number(newerTs) > 0 ? `${newerAge}s ago` : 'none'}`);
      console.log(`  Time between obs: ${Number(elapsed)}s`);
      console.log(`  Ready: ${ready ? '✅ YES' : '❌ NO'}`);
      console.log(`  Needs update: ${needsUpdate ? 'YES' : 'NO'}`);

      if (!ready && Number(newerTs) > 0) {
        const readyIn = 1800 - newerAge; // 30 min = 1800s
        if (readyIn > 0) {
          console.log(`  Ready in: ~${Math.ceil(readyIn / 60)} minutes`);
        }
      }
      console.log('');
    } catch (err) {
      console.log(`${pair.name}: Error - ${err.message?.slice(0, 50)}`);
    }
  }
}

main().catch(console.error);

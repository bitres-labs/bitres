/**
 * Check for failed Minter transactions on Sepolia
 */
import { createPublicClient, http, decodeErrorResult } from 'viem';
import { sepolia } from 'viem/chains';
import fs from 'fs';
import path from 'path';

const ADDR_FILE = path.join(process.cwd(), "ignition/deployments/chain-11155111/deployed_addresses.json");

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL || 'https://sepolia.infura.io/v3/862fb5ed158f46828c02b58973fc7b48'),
});

async function main() {
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const addr = {};
  for (const [key, value] of Object.entries(raw)) {
    addr[key.replace("FullSystemSepolia#", "")] = value;
  }

  const MINTER = addr.Minter;

  console.log('=== Checking Minter transactions ===\n');
  console.log('Minter:', MINTER);

  // Get recent blocks
  const latestBlock = await publicClient.getBlockNumber();
  console.log('Latest block:', latestBlock);

  // Check last 50 blocks for Minter transactions
  console.log('\n=== Scanning last 50 blocks for Minter txs ===\n');

  let foundTx = 0;
  for (let i = 0n; i < 50n; i++) {
    try {
      const block = await publicClient.getBlock({
        blockNumber: latestBlock - i,
        includeTransactions: true
      });

      for (const tx of block.transactions) {
        if (tx.to?.toLowerCase() === MINTER.toLowerCase()) {
          foundTx++;
          const receipt = await publicClient.getTransactionReceipt({ hash: tx.hash });

          const status = receipt.status === 'success' ? '✅ Success' : '❌ FAILED';
          console.log(`${status} - Block ${block.number}`);
          console.log('  Hash:', tx.hash);
          console.log('  From:', tx.from);
          console.log('  Gas limit:', tx.gas?.toString());
          console.log('  Gas used:', receipt.gasUsed.toString());

          if (receipt.status === 'reverted') {
            console.log('  ⚠️  Transaction reverted!');

            // Try to get revert reason
            try {
              const txData = await publicClient.getTransaction({ hash: tx.hash });
              await publicClient.call({
                to: tx.to,
                data: txData.input,
                blockNumber: block.number,
              });
            } catch (e) {
              if (e.cause?.data) {
                console.log('  Revert data:', e.cause.data);
              }
              if (e.shortMessage) {
                console.log('  Error:', e.shortMessage);
              }
              if (e.message) {
                console.log('  Message:', e.message.slice(0, 200));
              }
            }
          }
          console.log('');
        }
      }
    } catch (e) {
      // Skip block errors
    }
  }

  if (foundTx === 0) {
    console.log('No Minter transactions found in last 50 blocks.');
    console.log('\nTry providing a specific transaction hash to analyze.');
  } else {
    console.log(`Found ${foundTx} Minter transaction(s).`);
  }
}

main().catch(console.error);

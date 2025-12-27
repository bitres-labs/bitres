/**
 * Update TWAP observations for all pairs on Sepolia
 * Run this periodically (every 30 min) to keep TWAP prices fresh
 */
import { createPublicClient, createWalletClient, http } from 'viem'
import { sepolia } from 'viem/chains'
import { privateKeyToAccount } from 'viem/accounts'
import 'dotenv/config'

const TWAP_ORACLE = '0x6F4B2d3b878CED1A07Fa81F1Bb0faa9f2f383cE9'
const PAIRS = [
  { name: 'WBTC/USDC', address: '0x07315bE96dfb7ac66D5357498dC31143A0784bac' },
  { name: 'BTD/USDC', address: '0xc0eA9877E3998C1C2a1a6aea1c4476533472EeBe' },
  { name: 'BTB/BTD', address: '0x351bCc368016af556c340E99ed2d195ec5505cd5' },
  { name: 'BRS/BTD', address: '0x73D5E2A60fA5Be805A4261eB57a524E9AD753321' },
]

const TWAP_ABI = [
  { inputs: [{ type: 'address' }], name: 'update', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ type: 'address' }], name: 'isTWAPReady', outputs: [{ type: 'bool' }], stateMutability: 'view', type: 'function' },
]

async function main() {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY
  if (!privateKey) {
    console.error('ERROR: DEPLOYER_PRIVATE_KEY not set in .env')
    process.exit(1)
  }

  const account = privateKeyToAccount(privateKey)
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http('https://ethereum-sepolia-rpc.publicnode.com'),
  })
  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http('https://ethereum-sepolia-rpc.publicnode.com'),
  })

  console.log('=== TWAP Oracle Update ===')
  console.log('Account:', account.address)
  console.log('TWAPOracle:', TWAP_ORACLE)
  console.log('')

  for (const pair of PAIRS) {
    console.log('Updating ' + pair.name + '...')
    try {
      const hash = await walletClient.writeContract({
        address: TWAP_ORACLE,
        abi: TWAP_ABI,
        functionName: 'update',
        args: [pair.address],
      })
      console.log('  TX: ' + hash)

      const receipt = await publicClient.waitForTransactionReceipt({ hash })
      console.log('  Status: ' + (receipt.status === 'success' ? 'Success' : 'Failed'))

      const isReady = await publicClient.readContract({
        address: TWAP_ORACLE,
        abi: TWAP_ABI,
        functionName: 'isTWAPReady',
        args: [pair.address],
      })
      console.log('  TWAP Ready: ' + isReady)
    } catch (e) {
      const msg = e.message ? e.message.slice(0, 80) : String(e)
      console.log('  ERROR: ' + msg)
    }
    console.log('')
  }

  console.log('Done!')
}

main().catch(console.error)

/**
 * Check TWAPOracle status on Sepolia
 */
import { createPublicClient, http } from 'viem'
import { sepolia } from 'viem/chains'

const TWAP_ORACLE = '0x6F4B2d3b878CED1A07Fa81F1Bb0faa9f2f383cE9'
const PAIRS = {
  'WBTC/USDC': '0x07315bE96dfb7ac66D5357498dC31143A0784bac',
  'BTD/USDC': '0xc0eA9877E3998C1C2a1a6aea1c4476533472EeBe',
  'BTB/BTD': '0x351bCc368016af556c340E99ed2d195ec5505cd5',
  'BRS/BTD': '0x73D5E2A60fA5Be805A4261eB57a524E9AD753321',
}

const TWAP_ABI = [
  { inputs: [{ type: 'address' }], name: 'getObservation', outputs: [
    { name: 'timestamp', type: 'uint32' },
    { name: 'price0Cumulative', type: 'uint256' },
    { name: 'price1Cumulative', type: 'uint256' },
  ], stateMutability: 'view', type: 'function' },
  { inputs: [{ type: 'address' }], name: 'canUpdate', outputs: [{ type: 'bool' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'PERIOD', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
]

async function main() {
  const client = createPublicClient({
    chain: sepolia,
    transport: http('https://ethereum-sepolia-rpc.publicnode.com'),
  })

  console.log('=== TWAPOracle Status ===')
  console.log('Address:', TWAP_ORACLE)
  console.log('')

  try {
    const period = await client.readContract({
      address: TWAP_ORACLE,
      abi: TWAP_ABI,
      functionName: 'PERIOD',
    })
    console.log('PERIOD:', Number(period), 'seconds (', Number(period) / 60, 'minutes)')
  } catch (e) {
    console.log('PERIOD: ERROR')
  }

  console.log('')
  console.log('=== Pair Observations ===')

  for (const [name, address] of Object.entries(PAIRS)) {
    console.log(`\n${name} (${address}):`)
    try {
      const obs = await client.readContract({
        address: TWAP_ORACLE,
        abi: TWAP_ABI,
        functionName: 'getObservation',
        args: [address],
      })
      const timestamp = Number(obs[0])
      const date = timestamp > 0 ? new Date(timestamp * 1000).toISOString() : 'Never'
      console.log(`  timestamp: ${timestamp} (${date})`)
      console.log(`  price0Cumulative: ${obs[1]}`)
      console.log(`  price1Cumulative: ${obs[2]}`)

      const canUpdate = await client.readContract({
        address: TWAP_ORACLE,
        abi: TWAP_ABI,
        functionName: 'canUpdate',
        args: [address],
      })
      console.log(`  canUpdate: ${canUpdate}`)
    } catch (e) {
      console.log(`  ERROR: ${e.message ? e.message.slice(0, 80) : e}`)
    }
  }

  // Current block timestamp
  const block = await client.getBlock()
  console.log('\n=== Current Block ===')
  console.log('Block:', Number(block.number))
  console.log('Timestamp:', Number(block.timestamp), `(${new Date(Number(block.timestamp) * 1000).toISOString()})`)
}

main().catch(console.error)

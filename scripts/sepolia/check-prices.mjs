/**
 * Check all prices from PriceOracle on Sepolia
 */
import { createPublicClient, http, formatUnits } from 'viem'
import { sepolia } from 'viem/chains'

const PRICE_ORACLE = '0xa0e776576b685F083386d286526D5d72eD988dF5'

const PRICE_ORACLE_ABI = [
  { inputs: [], name: 'getWBTCPrice', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getBTDPrice', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getBTBPrice', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getBRSPrice', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getIUSDPrice', outputs: [{ type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'useTWAP', outputs: [{ type: 'bool' }], stateMutability: 'view', type: 'function' },
]

async function main() {
  const client = createPublicClient({
    chain: sepolia,
    transport: http('https://ethereum-sepolia-rpc.publicnode.com'),
  })

  console.log('=== PriceOracle Status ===')
  console.log('Address:', PRICE_ORACLE)
  console.log('')

  try {
    const useTWAP = await client.readContract({
      address: PRICE_ORACLE,
      abi: PRICE_ORACLE_ABI,
      functionName: 'useTWAP',
    })
    console.log('useTWAP:', useTWAP)
  } catch (e) {
    console.log('useTWAP: ERROR -', e.message)
  }

  console.log('')
  console.log('=== Prices ===')

  const prices = ['getWBTCPrice', 'getBTDPrice', 'getBTBPrice', 'getBRSPrice', 'getIUSDPrice']

  for (const fn of prices) {
    try {
      const price = await client.readContract({
        address: PRICE_ORACLE,
        abi: PRICE_ORACLE_ABI,
        functionName: fn,
      })
      const formatted = Number(formatUnits(price, 18))
      console.log(`${fn}: ${price} (${formatted} USD)`)
    } catch (e) {
      const msg = e.message ? e.message.slice(0, 100) : String(e)
      console.log(`${fn}: ERROR - ${msg}`)
    }
  }
}

main().catch(console.error)

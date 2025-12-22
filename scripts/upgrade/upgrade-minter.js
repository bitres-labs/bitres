const hre = require('hardhat')
const { ethers, upgrades } = hre
const fs = require('fs')
const path = require('path')

async function main() {
  console.log('\n🚀 Starting Minter upgrade...')

  const statePath = path.join(__dirname, '../main/deployment-local-state.json')
  const state = JSON.parse(fs.readFileSync(statePath, 'utf-8'))
  if (!state.contracts || !state.contracts.minter) {
    throw new Error('Cannot find minter address in deployment state file')
  }

  const minterProxy = state.contracts.minter
  console.log('Current minter proxy:', minterProxy)

  const Minter = await ethers.getContractFactory('Minter')
  console.log('Deploying new implementation...')
  const newImpl = await upgrades.prepareUpgrade(minterProxy, Minter)
  console.log('New implementation deployed at:', newImpl)

  console.log('Upgrading proxy via UUPS...')
  await upgrades.upgradeProxy(minterProxy, Minter)
  console.log('✅ Upgrade completed')
}

main().catch(error => {
  console.error(error)
  process.exitCode = 1
})

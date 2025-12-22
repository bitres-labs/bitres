const { ethers, upgrades } = require('hardhat')

async function main() {
  const proxyAddress = '0x998abeb3E57409262aE5b751f60747921B33613E'

  console.log('\n🚀 Upgrading FarmingPool proxy at', proxyAddress)
  const FarmingPool = await ethers.getContractFactory('FarmingPool')

  const upgraded = await upgrades.upgradeProxy(proxyAddress, FarmingPool, {
    kind: 'uups',
  })

  await upgraded.waitForDeployment()
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress)
  console.log('✅ Upgrade completed. New implementation at', implementationAddress)
}

main().catch(error => {
  console.error(error)
  process.exit(1)
})

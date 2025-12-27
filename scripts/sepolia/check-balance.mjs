import hre from "hardhat";

async function main() {
  const { viem } = await hre.network.connect();
  const [deployer] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();
  const balance = await publicClient.getBalance({ address: deployer.account.address });
  console.log('Deployer:', deployer.account.address);
  console.log('Balance:', (Number(balance) / 1e18).toFixed(4), 'ETH');
}

main().catch(console.error);

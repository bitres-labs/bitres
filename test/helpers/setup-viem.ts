/**
 * Viem test setup helpers for the BRS system.
 *
 * Architecture:
 * - ConfigCore: immutable addresses (tokens, pools, stTokens) + storage addresses (core contracts)
 * - ConfigGov: governable parameters (mintFeeBP, interestFeeBP, minBTBPrice, maxBTBRate) - UUPS Proxy
 * - Minter: uses both ConfigCore and ConfigGov - UUPS Proxy
 * - PriceOracle, Treasury, FarmingPool, InterestPool, IdealUSDManager: UUPS Proxies
 */

import hre from "hardhat";
import { keccak256, toHex, encodeFunctionData, encodeAbiParameters } from "viem";

// Hardhat 3.0: Get viem and networkHelpers from network connection
const { viem, networkHelpers } = await hre.network.connect();

export { viem, networkHelpers };

/**
 * System contract interface
 */
export interface SystemContracts {
  // Tokens
  wbtc: any;
  usdc: any;
  usdt: any;
  weth: any;
  btd: any;
  btb: any;
  brs: any;

  // Config
  configCore: any;      // ConfigCore (immutable + storage addresses)
  configGov: any;       // ConfigGov (governable parameters) - Proxy
  config: any;          // Alias for configCore (backward compatibility)

  // Core contracts (all proxies)
  minter: any;
  treasury: any;
  priceOracle: any;
  idealUSDManager: any;
  interestPool: any;

  // Pools
  farmingPool: any;

  // Staking tokens
  stBTD: any;
  stBTB: any;

  // TWAP Oracle
  twapOracle: any;

  // Mock oracles
  mockBtcUsd: any;
  mockWbtcBtc: any;
  mockPce: any;
  mockPyth: any;
  mockUsdcUsd: any;
  mockUsdtUsd: any;

  // Oracle IDs
  pythId: `0x${string}`;

  // Mock pools
  mockPoolWbtcUsdc: any;
  mockPoolBtdUsdc: any;
  mockPoolBtbBtd: any;
  mockPoolBrsBtd: any;
}

/**
 * Get wallet clients
 */
export async function getWallets() {
  return await viem.getWalletClients();
}

/**
 * Deploy a UUPS upgradeable contract with proxy
 * Uses ProxyHelper to deploy ERC1967Proxy
 * @param contractName Full contract path (e.g., "contracts/Minter.sol:Minter")
 * @param initArgs Arguments for initialize() function
 * @returns Contract instance at proxy address
 */
async function deployProxy(contractName: string, initArgs: any[]) {
  const [owner] = await getWallets();

  // Deploy implementation (no constructor args for UUPS)
  const impl = await viem.deployContract(contractName, []);

  // Get ABI for encoding initialize call
  const artifact = await hre.artifacts.readArtifact(contractName.split(":")[1] || contractName);
  const initializeAbi = artifact.abi.find((item: any) => item.name === "initialize" && item.type === "function");

  if (!initializeAbi) {
    throw new Error(`No initialize function found in ${contractName}`);
  }

  // Encode initialize call
  const initData = encodeFunctionData({
    abi: [initializeAbi],
    functionName: "initialize",
    args: initArgs,
  });

  // Deploy ERC1967Proxy directly with constructor args
  const proxy = await viem.deployContract(
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
    [impl.address, initData]
  );

  // Return contract instance at proxy address
  return await viem.getContractAt(contractName, proxy.address);
}

/**
 * Deploy token contracts (BTD, BTB, BRS are upgradeable — deploy + initialize)
 */
export async function deployTokens() {
  const [owner] = await getWallets();

  // Deploy WBTC (8 decimals)
  const wbtc = await viem.deployContract("contracts/local/MockWBTC.sol:MockWBTC", [
    owner.account.address
  ]);

  // Deploy USDC (6 decimals)
  const usdc = await viem.deployContract("contracts/local/MockUSDC.sol:MockUSDC", [
    owner.account.address
  ]);

  // Deploy USDT (6 decimals)
  const usdt = await viem.deployContract("contracts/local/MockUSDT.sol:MockUSDT", [
    owner.account.address
  ]);

  // Deploy WETH (18 decimals)
  const weth = await viem.deployContract("contracts/local/MockWETH.sol:MockWETH", [
    owner.account.address
  ]);

  // Deploy BTD via proxy (upgradeable)
  const btd = await deployProxy(
    "contracts/BTD.sol:BTD",
    [owner.account.address]
  );

  // Deploy BTB via proxy (upgradeable)
  const btb = await deployProxy(
    "contracts/BTB.sol:BTB",
    [owner.account.address]
  );

  // Deploy BRS directly (non-upgradeable ERC20, constructor mints supply)
  const brs = await viem.deployContract(
    "contracts/BRS.sol:BRS",
    [owner.account.address]
  );

  return { wbtc, usdc, usdt, weth, btd, btb, brs };
}

/**
 * Deploy mock oracle contracts
 */
export async function deployOracles() {
  // Chainlink BTC/USD: $50,000 (8 decimals)
  const mockBtcUsd = await viem.deployContract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [50_000n * 10n ** 8n]
  );

  // Chainlink WBTC/BTC: 1.0 (8 decimals)
  const mockWbtcBtc = await viem.deployContract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [1n * 10n ** 8n]
  );

  // PCE: 300.0 (8 decimals)
  const mockPce = await viem.deployContract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [300_00_000_000n]
  );

  // Pyth
  const mockPyth = await viem.deployContract(
    "contracts/local/MockPyth.sol:MockPyth",
    []
  );

  // Chainlink USDC/USD: $1.0 (8 decimals)
  const mockUsdcUsd = await viem.deployContract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [1n * 10n ** 8n]
  );

  // Chainlink USDT/USD: $1.0 (8 decimals)
  const mockUsdtUsd = await viem.deployContract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [1n * 10n ** 8n]
  );

  return { mockBtcUsd, mockWbtcBtc, mockPce, mockPyth, mockUsdcUsd, mockUsdtUsd };
}

/**
 * Deploy mock Uniswap V2 pair contracts (use real pair implementation)
 */
export async function deployPools() {
  // WBTC/USDC Pool
  const mockPoolWbtcUsdc = await viem.deployContract(
    "contracts/local/UniswapV2Pair.sol:UniswapV2Pair",
    []
  );

  // BTD/USDC Pool
  const mockPoolBtdUsdc = await viem.deployContract(
    "contracts/local/UniswapV2Pair.sol:UniswapV2Pair",
    []
  );

  // BTB/BTD Pool
  const mockPoolBtbBtd = await viem.deployContract(
    "contracts/local/UniswapV2Pair.sol:UniswapV2Pair",
    []
  );

  // BRS/BTD Pool
  const mockPoolBrsBtd = await viem.deployContract(
    "contracts/local/UniswapV2Pair.sol:UniswapV2Pair",
    []
  );

  return { mockPoolWbtcUsdc, mockPoolBtdUsdc, mockPoolBtbBtd, mockPoolBrsBtd };
}

/**
 * Deploy ConfigCore (not upgradeable) and ConfigGov (UUPS proxy)
 */
export async function deployConfig(
  tokens: Awaited<ReturnType<typeof deployTokens>>,
  pools: Awaited<ReturnType<typeof deployPools>>,
  stBTD: any,
  stBTB: any
) {
  const [owner] = await getWallets();

  // Deploy ConfigCore (13 constructor params: 7 tokens + 4 pools + 2 stTokens)
  // ConfigCore is NOT upgradeable - immutable addresses
  const configCore = await viem.deployContract(
    "contracts/ConfigCore.sol:ConfigCore",
    [
      // Tokens (7)
      tokens.wbtc.address,
      tokens.btd.address,
      tokens.btb.address,
      tokens.brs.address,
      tokens.weth.address,
      tokens.usdc.address,
      tokens.usdt.address,
      // Pools (4)
      pools.mockPoolWbtcUsdc.address,
      pools.mockPoolBtdUsdc.address,
      pools.mockPoolBtbBtd.address,
      pools.mockPoolBrsBtd.address,
      // Staking tokens (2)
      stBTD.address,
      stBTB.address,
    ]
  );

  // Deploy ConfigGov via UUPS proxy
  const configGov = await deployProxy(
    "contracts/ConfigGov.sol:ConfigGov",
    [owner.account.address]  // initialize(address initialOwner)
  );

  return { core: configCore, gov: configGov };
}

/**
 * Helper: convert string to bytes32
 */
export function toBytes32(str: string): `0x${string}` {
  const encoder = new TextEncoder();
  const data = encoder.encode(str);
  const hex = Array.from(data).map(b => b.toString(16).padStart(2, '0')).join('');
  const padded = hex + '0'.repeat(64 - hex.length);
  return ('0x' + padded) as `0x${string}`;
}

/**
 * Deploy the full system.
 *
 * Deployment order (to satisfy ConfigCore constructor requirements):
 * 1. Tokens (WBTC, BTD, BTB, BRS, USDC, USDT, WETH)
 * 2. stBTD, stBTB (depend on BTD, BTB)
 * 3. LP Pools (no dependencies)
 * 4. ConfigCore (needs tokens, pools, stTokens)
 * 5. ConfigGov (UUPS proxy)
 * 6. Other contracts via UUPS proxies
 * 7. setCoreContracts() to fill circular dependencies
 *
 * @returns SystemContracts containing all deployed contracts
 */
export async function deployFullSystem(): Promise<SystemContracts> {
  const [owner] = await getWallets();

  // Step 1: Deploy tokens
  const tokens = await deployTokens();

  // Step 2: Deploy stBTD and stBTB via proxy (upgradeable — need BTD/BTB first)
  const stBTD = await deployProxy(
    "contracts/stBTD.sol:stBTD",
    [tokens.btd.address, owner.account.address]
  );
  const stBTB = await deployProxy(
    "contracts/stBTB.sol:stBTB",
    [tokens.btb.address, owner.account.address]
  );

  // Step 3: Deploy pools
  const pools = await deployPools();

  // Step 4: Deploy oracles
  const oracles = await deployOracles();

  // Step 5: Deploy ConfigCore and ConfigGov
  const config = await deployConfig(tokens, pools, stBTD, stBTB);

  // Step 6: Set ConfigGov parameters
  await config.gov.write.setAddressParam([0n, oracles.mockPce.address]); // PCE_FEED
  await config.gov.write.setParam([4n, 2n * 10n ** 16n]); // PCE_MAX_DEVIATION = 2%

  // Set oracle addresses in ConfigGov
  await config.gov.write.setAddressParam([1n, oracles.mockBtcUsd.address]);   // CHAINLINK_BTC_USD
  await config.gov.write.setAddressParam([2n, oracles.mockWbtcBtc.address]);  // CHAINLINK_WBTC_BTC
  await config.gov.write.setAddressParam([3n, oracles.mockPyth.address]);     // PYTH_WBTC
  await config.gov.write.setAddressParam([4n, oracles.mockUsdcUsd.address]);  // CHAINLINK_USDC_USD
  await config.gov.write.setAddressParam([5n, oracles.mockUsdtUsd.address]);  // CHAINLINK_USDT_USD

  // Step 7: Deploy IdealUSDManager (UUPS proxy)
  const idealUSDManager = await deployProxy(
    "contracts/IdealUSDManager.sol:IdealUSDManager",
    [owner.account.address, config.gov.address, 10n ** 18n]  // owner, configGov, initialIUSD
  );

  // Step 8: Deploy TWAP Oracle (not upgradeable)
  const twapOracle = await viem.deployContract(
    "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle",
    []
  );

  // Step 9: Deploy Treasury (UUPS proxy)
  const treasury = await deployProxy(
    "contracts/Treasury.sol:Treasury",
    [owner.account.address, config.core.address, owner.account.address]  // owner, core, router
  );

  // Step 10: Deploy PriceOracle (UUPS proxy)
  const pythId = toBytes32("PYTH_WBTC");
  await oracles.mockPyth.write.setPrice([pythId, 5_000_000_000_000n, -8]);

  const priceOracle = await deployProxy(
    "contracts/PriceOracle.sol:PriceOracle",
    [owner.account.address, config.core.address, config.gov.address, twapOracle.address]
  );

  // Disable TWAP for testing (TWAP requires 30 min observation period)
  await priceOracle.write.setUseTWAP([false], { account: owner.account });

  // Step 11: Deploy InterestPool (UUPS proxy)
  const interestPool = await deployProxy(
    "contracts/InterestPool.sol:InterestPool",
    [owner.account.address, config.core.address, config.gov.address, owner.account.address]
  );

  // Step 12: Deploy Minter (UUPS proxy)
  const minter = await deployProxy(
    "contracts/Minter.sol:Minter",
    [owner.account.address, config.core.address, config.gov.address]
  );

  // Step 13: Deploy FarmingPool (UUPS proxy)
  const farmingPool = await deployProxy(
    "contracts/FarmingPool.sol:FarmingPool",
    [owner.account.address, tokens.brs.address, config.core.address, [], []]
  );

  // Step 14: Set the 6 core contract addresses in ConfigCore
  await config.core.write.setCoreContracts([
    treasury.address,
    minter.address,
    priceOracle.address,
    idealUSDManager.address,
    interestPool.address,
    farmingPool.address
  ]);

  // Step 15: Set Governor in ConfigGov
  await config.gov.write.setGovernor([owner.account.address]);

  // Step 16: Initialize InterestPool pools (after ConfigCore has BTD/BTB)
  await interestPool.write.initializePools([]);

  // Route stToken vault assets into InterestPool so ERC4626 shares accrue policy interest.
  await stBTD.write.setInterestPool([interestPool.address], { account: owner.account });
  await stBTB.write.setInterestPool([interestPool.address], { account: owner.account });

  // Step 17: Grant MINTER_ROLE to Minter and InterestPool
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));
  const DEFAULT_ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`;

  await tokens.btd.write.grantRole([MINTER_ROLE, minter.address], { account: owner.account });
  await tokens.btb.write.grantRole([MINTER_ROLE, minter.address], { account: owner.account });
  await tokens.btd.write.grantRole([MINTER_ROLE, interestPool.address], { account: owner.account });
  await tokens.btb.write.grantRole([MINTER_ROLE, interestPool.address], { account: owner.account });

  // Deployer renounces DEFAULT_ADMIN_ROLE (complete decentralization)
  await tokens.btd.write.renounceRole([DEFAULT_ADMIN_ROLE, owner.account.address], { account: owner.account });
  await tokens.btb.write.renounceRole([DEFAULT_ADMIN_ROLE, owner.account.address], { account: owner.account });

  // Step 18: Initialize pools (CRITICAL for PriceOracle to work!)
  await pools.mockPoolWbtcUsdc.write.initialize([
    tokens.wbtc.address,
    tokens.usdc.address
  ]);
  await pools.mockPoolWbtcUsdc.write.setReserves([
    100n * 10n ** 8n,      // 100 WBTC (8 decimals)
    5_000_000n * 10n ** 6n // 5M USDC (6 decimals) -> $50k/WBTC
  ]);

  return {
    // Tokens
    wbtc: tokens.wbtc,
    usdc: tokens.usdc,
    usdt: tokens.usdt,
    weth: tokens.weth,
    btd: tokens.btd,
    btb: tokens.btb,
    brs: tokens.brs,

    // Config
    configCore: config.core,
    configGov: config.gov,
    config: config.core,  // Alias for backward compatibility

    // Core contracts (all proxies)
    minter,
    treasury,
    priceOracle,
    idealUSDManager,
    interestPool,

    // Pools
    farmingPool,
    stBTD,
    stBTB,

    // TWAP Oracle
    twapOracle,

    // Mock oracles
    mockBtcUsd: oracles.mockBtcUsd,
    mockWbtcBtc: oracles.mockWbtcBtc,
    mockPce: oracles.mockPce,
    mockPyth: oracles.mockPyth,
    mockUsdcUsd: oracles.mockUsdcUsd,
    mockUsdtUsd: oracles.mockUsdtUsd,

    // Oracle IDs (needed for price updates)
    pythId,

    // Mock pools
    mockPoolWbtcUsdc: pools.mockPoolWbtcUsdc,
    mockPoolBtdUsdc: pools.mockPoolBtdUsdc,
    mockPoolBtbBtd: pools.mockPoolBtbBtd,
    mockPoolBrsBtd: pools.mockPoolBrsBtd
  };
}

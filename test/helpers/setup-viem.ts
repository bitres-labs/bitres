/**
 * Viem test setup helpers for the BRS system.
 *
 * Architecture:
 * - ConfigCore: 28 immutable addresses (WBTC, BTD, BTB, BRS, oracles, pools, etc.)
 * - ConfigGov: 4 governable parameters (mintFeeBP, interestFeeBP, minBTBPrice, maxBTBRate)
 * - Minter: uses both ConfigCore and ConfigGov
 * - PriceOracle, Treasury, FarmingPool: use ConfigCore only
 */

import hre from "hardhat";
import { keccak256, toHex } from "viem";

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
  configCore: any;      // ConfigCore (immutable addresses)
  configGov: any;       // ConfigGov (governable parameters)
  config: any;          // Alias for configCore (backward compatibility)

  // Core contracts
  minter: any;
  treasury: any;
  priceOracle: any;
  idealUSDManager: any;

  // Pools
  farmingPool: any;

  // Mock oracles
  mockBtcUsd: any;
  mockWbtcBtc: any;
  mockPce: any;
  mockPyth: any;

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
 * Deploy token contracts
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

  // Deploy BTD (18 decimals)
  const btd = await viem.deployContract("contracts/BTD.sol:BTD", [
    owner.account.address
  ]);

  // Deploy BTB (18 decimals)
  const btb = await viem.deployContract("contracts/BTB.sol:BTB", [
    owner.account.address
  ]);

  // Deploy BRS (18 decimals)
  const brs = await viem.deployContract("contracts/BRS.sol:BRS", [
    owner.account.address
  ]);

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
 * Deploy IdealUSDManager
 *
 * @param configGovAddress ConfigGov contract address
 * @returns IdealUSDManager instance
 * @dev Inflation parameters use Constants library defaults (2% annual inflation)
 * @dev PCE feed address is pulled from ConfigGov
 * @dev PCE_FEED must be set in ConfigGov before deployment
 */
export async function deployIdealUSDManager(configGovAddress: `0x${string}`) {
  const [owner] = await getWallets();

  const idealUSDManager = await viem.deployContract(
    "contracts/IdealUSDManager.sol:IdealUSDManager",
    [
      owner.account.address,           // _owner
      configGovAddress,                // _configGov
      10n ** 18n                      // _initialIUSD (1.0)
    ]
  );

  return idealUSDManager;
}

/**
 * Deploy ConfigCore and ConfigGov
 *
 * @param tokens Token contracts
 * @param oracles Oracle contracts
 * @param pools Pool contracts
 * @param additionalAddresses Extra non-circular addresses
 * @returns {core: ConfigCore, gov: ConfigGov}
 * @dev ConfigCore constructor needs 22 params (excluding the 5 circular core contracts)
 * @dev The 5 core contracts (Treasury, Minter, PriceOracle, IdealUSDManager, InterestPool)
 *      are set later via setCoreContracts()
 */
export async function deployConfig(
  tokens: Awaited<ReturnType<typeof deployTokens>>,
  oracles: Awaited<ReturnType<typeof deployOracles>>,
  pools: Awaited<ReturnType<typeof deployPools>>,
  additionalAddresses: {
    farmingPool: `0x${string}`;
    stBTD: `0x${string}`;
    stBTB: `0x${string}`;
    governor: `0x${string}`;
    twapOracle: `0x${string}`;
  }
) {
  const [owner] = await getWallets();

  // Deploy ConfigCore (12 constructor params: tokens + oracles, Redstone removed)
  const configCore = await viem.deployContract(
    "contracts/ConfigCore.sol:ConfigCore",
    [
      tokens.wbtc.address,                                  // _wbtc
      tokens.btd.address,                                   // _btd
      tokens.btb.address,                                   // _btb
      tokens.brs.address,                                   // _brs
      tokens.weth.address,                                  // _weth
      tokens.usdc.address,                                  // _usdc
      tokens.usdt.address,                                  // _usdt
      oracles.mockBtcUsd.address,                           // _chainlinkBtcUsd
      oracles.mockWbtcBtc.address,                          // _chainlinkWbtcBtc
      oracles.mockPyth.address,                             // _pythWbtc
      oracles.mockUsdcUsd.address,                          // _chainlinkUsdcUsd
      oracles.mockUsdtUsd.address,                          // _chainlinkUsdtUsd
    ]
  );

  // Deploy ConfigGov (governance parameters)
  const configGov = await viem.deployContract(
    "contracts/ConfigGov.sol:ConfigGov",
    [
      owner.account.address                                 // initialOwner (only 1 param!)
    ]
  );

  return { core: configCore, gov: configGov };
}

/**
 * Deploy PriceOracle
 * Note: Redstone removed - using dual-source validation (Chainlink + Pyth)
 */
export async function deployPriceOracle(
  configCoreAddress: `0x${string}`,
  pythId: `0x${string}`,
  twapOracleAddress: `0x${string}` = "0x0000000000000000000000000000000000000000" as `0x${string}`
) {
  const [owner] = await getWallets();

  const priceOracle = await viem.deployContract(
    "contracts/PriceOracle.sol:PriceOracle",
    [
      owner.account.address,          // owner
      configCoreAddress,              // _core (ConfigCore)
      twapOracleAddress,              // twapOracle
      pythId,                         // pythWbtcPriceId (immutable)
    ]
  );

  return priceOracle;
}

/**
 * Deploy Treasury
 */
export async function deployTreasury(
  configCoreAddress: `0x${string}`,
  routerAddr: `0x${string}`
) {
  const [owner] = await getWallets();

  const treasury = await viem.deployContract(
    "contracts/Treasury.sol:Treasury",
    [
      owner.account.address,          // owner
      configCoreAddress,              // _core (ConfigCore)
      routerAddr                      // routerAddr (Uniswap router)
    ]
  );

  return treasury;
}

/**
 * Deploy Minter
 */
export async function deployMinter(
  configCoreAddress: `0x${string}`,
  configGovAddress: `0x${string}`
) {
  const [owner] = await getWallets();

  const minter = await viem.deployContract(
    "contracts/Minter.sol:Minter",
    [
      owner.account.address,          // owner
      configCoreAddress,              // _core (ConfigCore)
      configGovAddress                // _gov (ConfigGov)
    ]
  );

  return minter;
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
 * Note: uses owner.address as a placeholder to break circular dependencies.
 * ConfigCore requires non-zero addresses, but some contracts depend on ConfigCore to deploy.
 *
 * @returns SystemContracts containing all deployed contracts
 */
export async function deployFullSystem(): Promise<SystemContracts> {
  const [owner] = await getWallets();

  // Step 1: Deploy tokens
  const tokens = await deployTokens();

  // Step 2: Deploy oracles
  const oracles = await deployOracles();

  // Step 3: Deploy pools
  const pools = await deployPools();

  // Step 4: Deploy ConfigGov (needed by IdealUSDManager and InterestPool/Minter)
  const configGov = await viem.deployContract(
    "contracts/ConfigGov.sol:ConfigGov",
    [owner.account.address]
  );

  // Step 5: Set governance parameters in ConfigGov (required before deploying IdealUSDManager)
  await configGov.write.setAddressParam([0n, oracles.mockPce.address]); // PCE_FEED
  await configGov.write.setParam([4n, 2n * 10n ** 16n]); // PCE_MAX_DEVIATION = 2%

  // Step 6: Deploy IdealUSDManager (needs ConfigGov)
  const idealUSDManager = await deployIdealUSDManager(configGov.address);

  // Step 7: Deploy stBTD and stBTB (pure ERC4626 vaults - no dependencies)
  const stBTD = await viem.deployContract("contracts/stBTD.sol:stBTD", [
    tokens.btd.address
  ]);
  const stBTB = await viem.deployContract("contracts/stBTB.sol:stBTB", [
    tokens.btb.address
  ]);

  // Step 8: Governor placeholder (VestingVault removed - using fundShares mechanism)
  const governor = owner.account.address; // Placeholder

  // Step 9: Deploy TWAP Oracle (real contract, no constructor args)
  const twapOracle = await viem.deployContract(
    "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle",
    []
  );

  // Step 10: Deploy ConfigCore FIRST (needed by FarmingPool constructor)
  // Note: We use placeholder for farmingPool address initially, then set it via setPeripheralContracts
  const tempConfigCore = await deployConfig(tokens, oracles, pools, {
    farmingPool: owner.account.address,  // Placeholder - will be set via setPeripheralContracts
    stBTD: stBTD.address,
    stBTB: stBTB.address,
    governor: governor,
    twapOracle: twapOracle.address
  });

  // Step 11: Deploy FarmingPool with REAL ConfigCore address
  const farmingPool = await viem.deployContract(
    "contracts/FarmingPool.sol:FarmingPool",
    [
      owner.account.address,
      tokens.brs.address,
      tempConfigCore.core.address,  // Real ConfigCore address
      [],                           // initial pools
      []                            // initial alloc points
    ]
  );

  // Step 13: Deploy the 5 core contracts with the temporary ConfigCore
  const treasury = await deployTreasury(
    tempConfigCore.core.address,
    owner.account.address  // router address (using owner as placeholder)
  );

  const pythId = toBytes32("PYTH_WBTC");
  await oracles.mockPyth.write.setPrice([pythId, 5_000_000_000_000n, -8]);

  const priceOracle = await deployPriceOracle(
    tempConfigCore.core.address,
    pythId,
    twapOracle.address  // Pass real TWAP oracle address
  );

  // Disable TWAP for testing (TWAP requires 30 min observation period)
  await priceOracle.write.setUseTWAP([false], { account: owner.account });

  const interestPool = await viem.deployContract(
    "contracts/InterestPool.sol:InterestPool",
    [
      owner.account.address,        // initialOwner
      tempConfigCore.core.address,  // Real ConfigCore (with BTD/BTB)
      configGov.address,            // Real ConfigGov
      owner.account.address         // _rateOracle (placeholder)
    ]
  );

  const minter = await deployMinter(tempConfigCore.core.address, configGov.address);

  // Step 14: Set the 5 core contract addresses in ConfigCore
  await tempConfigCore.core.write.setCoreContracts([
    treasury.address,
    minter.address,
    priceOracle.address,
    idealUSDManager.address,
    interestPool.address
  ]);

  // Step 14b: Set peripheral contracts in ConfigCore
  await tempConfigCore.core.write.setPeripheralContracts([
    farmingPool.address,      // _farmingPool
    stBTD.address,            // _stBTD
    stBTB.address,            // _stBTB
    governor,                 // _governor (already an address string)
    twapOracle.address,       // _twapOracle (contract address)
    pools.mockPoolWbtcUsdc.address,  // _poolWbtcUsdc
    pools.mockPoolBtdUsdc.address,   // _poolBtdUsdc
    pools.mockPoolBtbBtd.address,    // _poolBtbBtd
    pools.mockPoolBrsBtd.address     // _poolBrsBtd
  ]);

  // Now tempConfigCore is complete with all addresses!

  // Step 13: Grant MINTER_ROLE to Minter and InterestPool (AccessControl pattern)
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));
  const DEFAULT_ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`;

  await tokens.btd.write.grantRole([MINTER_ROLE, minter.address], { account: owner.account });
  await tokens.btb.write.grantRole([MINTER_ROLE, minter.address], { account: owner.account });
  await tokens.btd.write.grantRole([MINTER_ROLE, interestPool.address], { account: owner.account });
  await tokens.btb.write.grantRole([MINTER_ROLE, interestPool.address], { account: owner.account });

  // Deployer renounces DEFAULT_ADMIN_ROLE (complete decentralization)
  await tokens.btd.write.renounceRole([DEFAULT_ADMIN_ROLE, owner.account.address], { account: owner.account });
  await tokens.btb.write.renounceRole([DEFAULT_ADMIN_ROLE, owner.account.address], { account: owner.account });

  // Step 24: Initialize pools (CRITICAL for PriceOracle to work!)
  // WBTC/USDC pool (required by getWBTCPrice)
  await pools.mockPoolWbtcUsdc.write.initialize([
    tokens.wbtc.address,  // token0 = WBTC
    tokens.usdc.address   // token1 = USDC
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

    // Config - Single ConfigCore instance! ✅
    configCore: tempConfigCore.core,
    configGov: configGov,
    config: tempConfigCore.core,  // Alias for backward compatibility

    // Core contracts
    minter,
    treasury,
    priceOracle,
    idealUSDManager,
    interestPool,

    // Pools
    farmingPool,
    stBTD,
    stBTB,

    // TWAP Oracle (real contract)
    twapOracle,

    // Mock oracles
    mockBtcUsd: oracles.mockBtcUsd,
    mockWbtcBtc: oracles.mockWbtcBtc,
    mockPce: oracles.mockPce,
    mockPyth: oracles.mockPyth,

    // Oracle IDs (needed for price updates)
    pythId,

    // Mock pools
    mockPoolWbtcUsdc: pools.mockPoolWbtcUsdc,
    mockPoolBtdUsdc: pools.mockPoolBtdUsdc,
    mockPoolBtbBtd: pools.mockPoolBtbBtd,
    mockPoolBrsBtd: pools.mockPoolBrsBtd
  };
}

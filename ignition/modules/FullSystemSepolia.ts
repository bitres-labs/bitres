import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toHex } from "viem";

/**
 * Sepolia Testnet Deployment Module
 *
 * Key differences from local (FullSystem.ts):
 * - Uses real Chainlink BTC/USD price feed on Sepolia
 * - Deploys mock WBTC/BTC oracle (1:1 ratio, no real feed on Sepolia)
 * - Uses our own UniswapV2Pair contracts for LP pools (simpler than using official Factory)
 * - Token strategy:
 *   - WETH: Uses official Uniswap WETH9 (users can wrap ETH directly)
 *   - WBTC/USDC/USDT: Deploys our own mock tokens (official faucets give too little)
 *
 * All upgradeable contracts use UUPS proxy pattern:
 *   ConfigGov, IdealUSDManager, PriceOracle, Treasury, Minter, InterestPool, FarmingPool,
 *   BTD, BTB, stBTD, stBTB, UniswapV2TWAPOracle
 *
 * Deployment order:
 * 1. Deploy tokens (WBTC, BTD, BTB, BRS, USDC, USDT) + use official WETH9
 * 2. Deploy stTokens (stBTD, stBTB)
 * 3. Deploy LP Pairs (using our MockUniswapV2Pair)
 * 4. Deploy ConfigCore (with all immutable addresses)
 * 5. Deploy other contracts via proxy (impl + ERC1967Proxy)
 * 6. Call setCoreContracts() to set circular dependency addresses
 */

// Sepolia Chainlink addresses (real feeds)
const SEPOLIA_CHAINLINK = {
  BTC_USD: "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
  ETH_USD: "0x694AA1769357215DE4FAC081bf1f309aDC325306",
};

// Official Uniswap V2 on Sepolia
export const UNISWAP_V2_SEPOLIA = {
  FACTORY: "0xF62c03E08ada871A0bEb309762E260a7a6a880E6",
  ROUTER: "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3",
  WETH9: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",  // Official WETH9 used by Uniswap
};

// Fund distribution addresses (real addresses for testnet)
const FUND_ADDRESSES = {
  foundation: "0xb53f41e806ab204B2525bD8B43909D47b32a04ac",
  team: "0x8F78bE5c6b41C2d7634d25C7db22b26409671ca9",
};

// Default parameters
const DEFAULTS = {
  initialPceFeed: "0x0000000000000000000000000000000000000001", // placeholder, set via ConfigGov
  pythPriceId: "0x505954485f575442430000000000000000000000000000000000000000000000",
  iusdInitial: 10n ** 18n,
};

export default buildModule("FullSystemSepolia", (m) => {
  const deployer = m.getAccount(0);

  // ===== Phase 1: Tokens =====

  // 1.1 Deploy mock WBTC/USDC/USDT (official faucets give too little for testing)
  const wbtc = m.contract("contracts/local/MockWBTC.sol:MockWBTC", [deployer], { id: "WBTC" });
  const usdc = m.contract("contracts/local/MockUSDC.sol:MockUSDC", [deployer], { id: "USDC" });
  const usdt = m.contract("contracts/local/MockUSDT.sol:MockUSDT", [deployer], { id: "USDT" });

  // Use official WETH9 (same as Uniswap V2 Router uses)
  const weth = m.contractAt("contracts/interfaces/IWETH9.sol:IWETH9", UNISWAP_V2_SEPOLIA.WETH9, { id: "WETH" });

  // 1.2 Core tokens (BRS is non-upgradeable governance token)
  const brs = m.contract("BRS", [deployer], { id: "BRS" });

  // 1.3 BTD/BTB as UUPS proxies
  const btdImpl = m.contract("BTD", [], { id: "BTDImpl" });
  const btdInitData = m.encodeFunctionCall(btdImpl, "initialize", [deployer], { id: "BTDInitData" });
  const btdProxy = m.contract("ERC1967Proxy", [btdImpl, btdInitData], { id: "BTDProxy" });
  const btd = m.contractAt("BTD", btdProxy, { id: "BTD" });

  const btbImpl = m.contract("BTB", [], { id: "BTBImpl" });
  const btbInitData = m.encodeFunctionCall(btbImpl, "initialize", [deployer], { id: "BTBInitData" });
  const btbProxy = m.contract("ERC1967Proxy", [btbImpl, btbInitData], { id: "BTBProxy" });
  const btb = m.contractAt("BTB", btbProxy, { id: "BTB" });

  // ===== Phase 2: Staking tokens as UUPS proxies (depend on BTD/BTB) =====
  const stBTDImpl = m.contract("stBTD", [], { id: "stBTDImpl" });
  const stBTDInitData = m.encodeFunctionCall(stBTDImpl, "initialize", [btd, deployer], { id: "stBTDInitData" });
  const stBTDProxy = m.contract("ERC1967Proxy", [stBTDImpl, stBTDInitData], { id: "stBTDProxy", after: [btdProxy] });
  const stBTD = m.contractAt("stBTD", stBTDProxy, { id: "stBTD" });

  const stBTBImpl = m.contract("stBTB", [], { id: "stBTBImpl" });
  const stBTBInitData = m.encodeFunctionCall(stBTBImpl, "initialize", [btb, deployer], { id: "stBTBInitData" });
  const stBTBProxy = m.contract("ERC1967Proxy", [stBTBImpl, stBTBInitData], { id: "stBTBProxy", after: [btbProxy] });
  const stBTB = m.contractAt("stBTB", stBTBProxy, { id: "stBTB" });

  // ===== Phase 3: LP Pairs (created before ConfigCore) =====
  const pairWbtcUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairWBTCUSDC" });
  const pairBtdUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTDUSDC", after: [btdProxy] });
  const pairBtbBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTBBTD", after: [btdProxy, btbProxy] });
  const pairBrsBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBRSBTD", after: [btdProxy] });

  m.call(pairWbtcUsdc, "initialize", [wbtc, usdc], { id: "InitPairWBTCUSDC" });
  m.call(pairBtdUsdc, "initialize", [btd, usdc], { id: "InitPairBTDUSDC", after: [btdProxy] });
  m.call(pairBtbBtd, "initialize", [btb, btd], { id: "InitPairBTBBTD", after: [btdProxy, btbProxy] });
  m.call(pairBrsBtd, "initialize", [brs, btd], { id: "InitPairBRSBTD", after: [btdProxy] });

  // ===== Phase 4: ConfigCore (with all immutable addresses) =====
  const configCore = m.contract(
    "ConfigCore",
    [
      // Tokens (7)
      wbtc, btd, btb, brs, weth, usdc, usdt,
      // Pools (4)
      pairWbtcUsdc, pairBtdUsdc, pairBtbBtd, pairBrsBtd,
      // Staking tokens (2)
      stBTD, stBTB,
    ],
    { id: "ConfigCore", after: [btdProxy, btbProxy, stBTDProxy, stBTBProxy, pairWbtcUsdc, pairBtdUsdc, pairBtbBtd, pairBrsBtd] }
  );

  // ===== Phase 5: ConfigGov (Proxy) =====
  const configGovImpl = m.contract("ConfigGov", [], { id: "ConfigGovImpl" });
  const configGovInitData = m.encodeFunctionCall(configGovImpl, "initialize", [deployer], { id: "ConfigGovInitData" });
  const configGovProxy = m.contract("ERC1967Proxy", [configGovImpl, configGovInitData], { id: "ConfigGovProxy" });
  const configGov = m.contractAt("ConfigGov", configGovProxy, { id: "ConfigGov" });

  // ===== Phase 6: Oracles =====
  // Use REAL Chainlink BTC/USD on Sepolia
  const chainlinkBtcUsd = m.contractAt(
    "contracts/interfaces/IAggregatorV3.sol:IAggregatorV3",
    SEPOLIA_CHAINLINK.BTC_USD,
    { id: "ChainlinkBTCUSD" }
  );

  // Mock WBTC/BTC oracle (no real feed on Sepolia, assume 1:1)
  const chainlinkWbtcBtc = m.contract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [BigInt(1e8)], // 1:1 ratio
    { id: "ChainlinkWBTCBTC" }
  );

  // Mock Pyth (no testnet support, use mock)
  const mockPyth = m.contract("contracts/local/MockPyth.sol:MockPyth", [], { id: "MockPyth" });

  // Mock stablecoin oracles
  const chainlinkUsdcUsd = m.contract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [BigInt(1e8)], // $1.00
    { id: "ChainlinkUSDCUSD" }
  );
  const chainlinkUsdtUsd = m.contract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [BigInt(1e8)], // $1.00
    { id: "ChainlinkUSDTUSD" }
  );

  // ===== Phase 7: IdealUSDManager (Proxy) =====
  const setPceFeed = m.call(configGov, "setAddressParam", [0, DEFAULTS.initialPceFeed], { id: "SetPceFeed" });
  const idealUSDManagerImpl = m.contract("IdealUSDManager", [], { id: "IdealUSDManagerImpl" });
  const idealUSDManagerInitData = m.encodeFunctionCall(idealUSDManagerImpl, "initialize", [deployer, configGov, DEFAULTS.iusdInitial], { id: "IdealUSDManagerInitData" });
  const idealUSDManagerProxy = m.contract("ERC1967Proxy", [idealUSDManagerImpl, idealUSDManagerInitData], { id: "IdealUSDManagerProxy", after: [setPceFeed] });
  const idealUSDManager = m.contractAt("IdealUSDManager", idealUSDManagerProxy, { id: "IdealUSDManager" });

  // ===== Phase 8: PriceOracle + TWAP (Proxy) =====
  const twapOracleImpl = m.contract("UniswapV2TWAPOracle", [], { id: "TWAPOracleImpl" });
  const twapOracleInitData = m.encodeFunctionCall(twapOracleImpl, "initialize", [deployer], { id: "TWAPOracleInitData" });
  const twapOracleProxy = m.contract("ERC1967Proxy", [twapOracleImpl, twapOracleInitData], { id: "TWAPOracleProxy" });
  const twapOracle = m.contractAt("UniswapV2TWAPOracle", twapOracleProxy, { id: "TWAPOracle" });

  const priceOracleImpl = m.contract("PriceOracle", [], { id: "PriceOracleImpl" });
  const priceOracleInitData = m.encodeFunctionCall(priceOracleImpl, "initialize", [deployer, configCore, configGov, twapOracle, DEFAULTS.pythPriceId], { id: "PriceOracleInitData" });
  const priceOracleProxy = m.contract("ERC1967Proxy", [priceOracleImpl, priceOracleInitData], { id: "PriceOracleProxy", after: [configCore, configGov, twapOracleProxy] });
  const priceOracle = m.contractAt("PriceOracle", priceOracleProxy, { id: "PriceOracle" });

  // ===== Phase 9: Treasury / Minter / InterestPool (Proxy) =====
  const treasuryImpl = m.contract("Treasury", [], { id: "TreasuryImpl" });
  const treasuryInitData = m.encodeFunctionCall(treasuryImpl, "initialize", [deployer, configCore, deployer], { id: "TreasuryInitData" });
  const treasuryProxy = m.contract("ERC1967Proxy", [treasuryImpl, treasuryInitData], { id: "TreasuryProxy", after: [configCore] });
  const treasury = m.contractAt("Treasury", treasuryProxy, { id: "Treasury" });

  const minterImpl = m.contract("Minter", [], { id: "MinterImpl" });
  const minterInitData = m.encodeFunctionCall(minterImpl, "initialize", [deployer, configCore, configGov], { id: "MinterInitData" });
  const minterProxy = m.contract("ERC1967Proxy", [minterImpl, minterInitData], { id: "MinterProxy", after: [configCore, configGov] });
  const minter = m.contractAt("Minter", minterProxy, { id: "Minter" });

  const interestPoolImpl = m.contract("InterestPool", [], { id: "InterestPoolImpl" });
  const interestPoolInitData = m.encodeFunctionCall(interestPoolImpl, "initialize", [deployer, configCore, configGov, deployer], { id: "InterestPoolInitData" });
  const interestPoolProxy = m.contract("ERC1967Proxy", [interestPoolImpl, interestPoolInitData], { id: "InterestPoolProxy", after: [configCore, configGov] });
  const interestPool = m.contractAt("InterestPool", interestPoolProxy, { id: "InterestPool" });

  // Initialize InterestPool pools (reads BTD/BTB from ConfigCore)
  m.call(interestPool, "initializePools", [], {
    id: "InterestPoolInitialize",
    after: [interestPoolProxy, configCore],
  });

  // ===== Phase 10: FarmingPool (Proxy) =====
  // FarmingPool fund split: Treasury 20%, Foundation 10%, Team 10%
  const farmingPoolImpl = m.contract("FarmingPool", [], { id: "FarmingPoolImpl" });
  const farmingPoolInitData = m.encodeFunctionCall(farmingPoolImpl, "initialize", [deployer, brs, configCore, [treasury, FUND_ADDRESSES.foundation, FUND_ADDRESSES.team], [20, 10, 10]], { id: "FarmingPoolInitData" });
  const farmingPoolProxy = m.contract("ERC1967Proxy", [farmingPoolImpl, farmingPoolInitData], { id: "FarmingPoolProxy", after: [configCore, brs, treasuryProxy] });
  const farmingPool = m.contractAt("FarmingPool", farmingPoolProxy, { id: "FarmingPool" });

  // ===== Phase 11: BRS Distribution =====
  // Reserve some BRS for LP initialization
  const totalSupply = 2100000000n * 10n ** 18n;
  const reservedForInit = 2n * 10n ** 18n; // 2 BRS reserved for LP + pool seed
  const toFarmingPool = totalSupply - reservedForInit;

  m.call(brs, "transfer", [farmingPool, toFarmingPool], {
    from: deployer,
    id: "TransferBRSToFarmingPool",
  });

  const governor = deployer;

  // ===== Phase 12: Set ConfigCore core contracts (6 addresses with circular dependencies) =====
  const setCoreContracts = m.call(
    configCore,
    "setCoreContracts",
    [treasury, minter, priceOracle, idealUSDManager, interestPool, farmingPool],
    { from: deployer, id: "SetCoreContracts" }
  );

  // Set Governor in ConfigGov (upgradable)
  m.call(configGov, "setGovernor", [governor], { id: "SetGovernor" });

  // Renounce ownership after all configuration is complete
  m.call(configCore, "renounceOwnership", [], {
    from: deployer,
    id: "RenounceOwnership",
    after: [setCoreContracts],
  });

  // ===== Phase 13: Grant MINTER_ROLE =====
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));

  m.call(btd, "grantRole", [MINTER_ROLE, minter], { id: "BTDGrantMinterRoleMinter" });
  m.call(btd, "grantRole", [MINTER_ROLE, interestPool], { id: "BTDGrantMinterRoleInterestPool" });
  m.call(btb, "grantRole", [MINTER_ROLE, minter], { id: "BTBGrantMinterRoleMinter" });
  m.call(btb, "grantRole", [MINTER_ROLE, interestPool], { id: "BTBGrantMinterRoleInterestPool" });

  // NOTE: Do NOT renounce DEFAULT_ADMIN_ROLE — needed for UUPS upgrade authorization

  // ===== Phase 14: ConfigGov params =====
  m.call(
    configGov,
    "setParamsBatch",
    [
      [0, 1, 2, 3, 4, 5, 6],
      [
        50, // mintFeeBP 0.5%
        1000, // interestFeeBP 10%
        5n * 10n ** 17n, // minBTBPrice 0.5 BTD
        2000, // maxBTBRate 20% (2000 bps, per whitepaper)
        1n * 10n ** 16n, // PCE deviation 1%
        50, // redeemFeeBP 0.5%
        2000, // maxBTDRate 20% (2000 bps, per whitepaper)
      ],
    ],
    { id: "ConfigGovSetParams" }
  );

  // Set oracle addresses on ConfigGov
  m.call(configGov, "setAddressParam", [1, chainlinkBtcUsd], { id: "SetChainlinkBtcUsd" });
  m.call(configGov, "setAddressParam", [2, chainlinkWbtcBtc], { id: "SetChainlinkWbtcBtc" });
  m.call(configGov, "setAddressParam", [3, mockPyth], { id: "SetPythWbtc" });
  m.call(configGov, "setAddressParam", [4, chainlinkUsdcUsd], { id: "SetChainlinkUsdcUsd" });
  m.call(configGov, "setAddressParam", [5, chainlinkUsdtUsd], { id: "SetChainlinkUsdtUsd" });

  // ===== Phase 15: Faucet (test token distribution) =====
  const faucet = m.contract("contracts/local/Faucet.sol:Faucet", [wbtc, usdc, usdt, deployer], {
    id: "Faucet",
    after: [wbtc, usdc, usdt],
  });

  // Transfer tokens to Faucet: 10M WBTC, 500M USDC, 500M USDT
  const FAUCET_WBTC = 10_000_000n * 10n ** 8n;
  const FAUCET_USDC = 500_000_000n * 10n ** 6n;
  const FAUCET_USDT = 500_000_000n * 10n ** 6n;

  m.call(wbtc, "transfer", [faucet, FAUCET_WBTC], {
    from: deployer,
    id: "TransferWBTCToFaucet",
    after: [faucet],
  });
  m.call(usdc, "transfer", [faucet, FAUCET_USDC], {
    from: deployer,
    id: "TransferUSDCToFaucet",
    after: [faucet],
  });
  m.call(usdt, "transfer", [faucet, FAUCET_USDT], {
    from: deployer,
    id: "TransferUSDTToFaucet",
    after: [faucet],
  });

  // Output
  return {
    tokens: { wbtc, usdc, usdt, weth, brs, btd, btb, stBTD, stBTB },
    oracles: { chainlinkBtcUsd, chainlinkWbtcBtc, mockPyth, chainlinkUsdcUsd, chainlinkUsdtUsd },
    pairs: { pairWbtcUsdc, pairBtdUsdc, pairBtbBtd, pairBrsBtd },
    configCore,
    configGov,
    treasury,
    minter,
    interestPool,
    farmingPool,
    priceOracle,
    twapOracle,
    idealUSDManager,
    governor,
    faucet,
    // Uniswap V2 addresses (for reference)
    uniswapV2: UNISWAP_V2_SEPOLIA,
  };
});

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
 * Deployment order:
 * 1. Deploy tokens (WBTC, BTD, BTB, BRS, USDC, USDT) + use official WETH9
 * 2. Deploy stTokens (stBTD, stBTB)
 * 3. Deploy LP Pairs (using our MockUniswapV2Pair)
 * 4. Deploy ConfigCore (with all immutable addresses)
 * 5. Deploy other contracts (ConfigGov, Treasury, Minter, etc.)
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
  // Users can wrap ETH directly via deposit() function
  const weth = m.contractAt("contracts/interfaces/IWETH9.sol:IWETH9", UNISWAP_V2_SEPOLIA.WETH9, { id: "WETH" });

  // 1.2 Core tokens
  const brs = m.contract("BRS", [deployer], { id: "BRS" });
  const btd = m.contract("BTD", [deployer], { id: "BTD" });
  const btb = m.contract("BTB", [deployer], { id: "BTB" });

  // ===== Phase 2: Staking tokens (depend on BTD/BTB) =====
  const stBTD = m.contract("stBTD", [btd], { id: "stBTD", after: [btd] });
  const stBTB = m.contract("stBTB", [btb], { id: "stBTB", after: [btb] });

  // ===== Phase 3: LP Pairs (created before ConfigCore) =====
  // Using our own UniswapV2Pair contracts for simplicity
  const pairWbtcUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairWBTCUSDC" });
  const pairBtdUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTDUSDC", after: [btd] });
  const pairBtbBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTBBTD", after: [btd, btb] });
  const pairBrsBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBRSBTD", after: [btd] });

  m.call(pairWbtcUsdc, "initialize", [wbtc, usdc], { id: "InitPairWBTCUSDC" });
  m.call(pairBtdUsdc, "initialize", [btd, usdc], { id: "InitPairBTDUSDC", after: [btd] });
  m.call(pairBtbBtd, "initialize", [btb, btd], { id: "InitPairBTBBTD", after: [btd, btb] });
  m.call(pairBrsBtd, "initialize", [brs, btd], { id: "InitPairBRSBTD", after: [btd] });

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
    { id: "ConfigCore", after: [btd, btb, stBTD, stBTB, pairWbtcUsdc, pairBtdUsdc, pairBtbBtd, pairBrsBtd] }
  );

  const configGov = m.contract("ConfigGov", [deployer], { id: "ConfigGov" });

  // ===== Phase 5: Oracles =====
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

  // ===== Phase 6: IdealUSDManager (uses ConfigGov) =====
  const idealUSDManager = m.contract("IdealUSDManager", [deployer, configGov, DEFAULTS.iusdInitial], {
    id: "IdealUSDManager",
    after: [m.call(configGov, "setAddressParam", [0, DEFAULTS.initialPceFeed], { id: "SetPceFeed" })],
  });

  // ===== Phase 7: PriceOracle + TWAP =====
  const twapOracle = m.contract("UniswapV2TWAPOracle", [], { id: "TWAPOracle" });
  const priceOracle = m.contract(
    "PriceOracle",
    [
      deployer,
      configCore,
      configGov,
      twapOracle,
      DEFAULTS.pythPriceId,
    ],
    { after: [configCore, configGov] }
  );

  // ===== Phase 8: Treasury / Minter / InterestPool =====
  const treasury = m.contract("Treasury", [deployer, configCore, deployer], {
    after: [configCore],
    id: "Treasury",
  });
  const minter = m.contract("Minter", [deployer, configCore, configGov], {
    after: [configCore, configGov],
    id: "Minter",
  });

  const interestPool = m.contract("InterestPool", [deployer, configCore, configGov, deployer], {
    after: [configCore, configGov],
    id: "InterestPool",
  });

  // Initialize InterestPool after deployment (reads BTD/BTB from ConfigCore)
  m.call(interestPool, "initialize", [], {
    id: "InterestPoolInitialize",
    after: [interestPool, configCore],
  });

  // ===== Phase 9: FarmingPool =====
  // FarmingPool fund split: Treasury 20%, Foundation 10%, Team 10%
  const farmingPool = m.contract("FarmingPool", [deployer, brs, configCore, [treasury, FUND_ADDRESSES.foundation, FUND_ADDRESSES.team], [20, 10, 10]], {
    after: [configCore, brs, treasury],
    id: "FarmingPool",
  });

  // ===== Phase 10: BRS Distribution =====
  // Reserve some BRS for LP initialization
  const totalSupply = 2100000000n * 10n ** 18n;
  const reservedForInit = 2n * 10n ** 18n; // 2 BRS reserved for LP + pool seed
  const toFarmingPool = totalSupply - reservedForInit;

  m.call(brs, "transfer", [farmingPool, toFarmingPool], {
    from: deployer,
    id: "TransferBRSToFarmingPool",
  });

  const governor = deployer;

  // ===== Phase 11: Set ConfigCore core contracts (6 addresses with circular dependencies) =====
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

  // ===== Phase 12: Grant MINTER_ROLE =====
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));
  const DEFAULT_ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000";

  const btdGrantMinter = m.call(btd, "grantRole", [MINTER_ROLE, minter], { id: "BTDGrantMinterRoleMinter" });
  const btdGrantInterest = m.call(btd, "grantRole", [MINTER_ROLE, interestPool], { id: "BTDGrantMinterRoleInterestPool" });
  const btbGrantMinter = m.call(btb, "grantRole", [MINTER_ROLE, minter], { id: "BTBGrantMinterRoleMinter" });
  const btbGrantInterest = m.call(btb, "grantRole", [MINTER_ROLE, interestPool], { id: "BTBGrantMinterRoleInterestPool" });

  // Renounce admin roles to permanently lock permissions
  m.call(btd, "renounceRole", [DEFAULT_ADMIN_ROLE, deployer], {
    id: "BTDRenounceAdmin",
    after: [btdGrantMinter, btdGrantInterest],
  });
  m.call(btb, "renounceRole", [DEFAULT_ADMIN_ROLE, deployer], {
    id: "BTBRenounceAdmin",
    after: [btbGrantMinter, btbGrantInterest],
  });

  // ===== Phase 13: ConfigGov params =====
  // ParamType enum: 0=MINT_FEE_BP, 1=INTEREST_FEE_BP, 2=MIN_BTB_PRICE, 3=MAX_BTB_RATE,
  //                 4=PCE_MAX_DEVIATION, 5=REDEEM_FEE_BP, 6=MAX_BTD_RATE
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
  // AddressParamType: 1=CHAINLINK_BTC_USD, 2=CHAINLINK_WBTC_BTC, 3=PYTH_WBTC, 4=CHAINLINK_USDC_USD, 5=CHAINLINK_USDT_USD
  m.call(configGov, "setAddressParam", [1, chainlinkBtcUsd], { id: "SetChainlinkBtcUsd" });
  m.call(configGov, "setAddressParam", [2, chainlinkWbtcBtc], { id: "SetChainlinkWbtcBtc" });
  m.call(configGov, "setAddressParam", [3, mockPyth], { id: "SetPythWbtc" });
  m.call(configGov, "setAddressParam", [4, chainlinkUsdcUsd], { id: "SetChainlinkUsdcUsd" });
  m.call(configGov, "setAddressParam", [5, chainlinkUsdtUsd], { id: "SetChainlinkUsdtUsd" });

  // ===== Phase 14: Faucet (test token distribution) =====
  const faucet = m.contract("contracts/local/Faucet.sol:Faucet", [wbtc, usdc, usdt, deployer], {
    id: "Faucet",
    after: [wbtc, usdc, usdt],
  });

  // Transfer tokens to Faucet: 10M WBTC, 500M USDC, 500M USDT
  const FAUCET_WBTC = 10_000_000n * 10n ** 8n;  // 10 million WBTC (8 decimals)
  const FAUCET_USDC = 500_000_000n * 10n ** 6n; // 500 million USDC (6 decimals)
  const FAUCET_USDT = 500_000_000n * 10n ** 6n; // 500 million USDT (6 decimals)

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

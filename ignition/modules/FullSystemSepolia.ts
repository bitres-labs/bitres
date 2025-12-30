import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toHex } from "viem";

/**
 * Sepolia Testnet Deployment Module
 *
 * Key differences from local (FullSystem.ts):
 * - Uses real Chainlink BTC/USD price feed on Sepolia
 * - Deploys mock WBTC/BTC oracle (1:1 ratio, no real feed on Sepolia)
 * - Uses official Uniswap V2 Factory to create pairs (done in init-sepolia.mjs)
 * - Token strategy:
 *   - WETH: Uses official Uniswap WETH9 (users can wrap ETH directly)
 *   - WBTC/USDC/USDT: Deploys our own mock tokens (official faucets give too little)
 *
 * Two-phase deployment:
 * 1. This module deploys all contracts (without setting peripheral contracts)
 * 2. init-sepolia.mjs creates pairs via official Uniswap V2 Factory and sets ConfigCore
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

  // ===== 1. Tokens =====
  // Deploy mock WBTC/USDC/USDT (official faucets give too little for testing)
  const wbtc = m.contract("contracts/local/MockWBTC.sol:MockWBTC", [deployer], { id: "WBTC" });
  const usdc = m.contract("contracts/local/MockUSDC.sol:MockUSDC", [deployer], { id: "USDC" });
  const usdt = m.contract("contracts/local/MockUSDT.sol:MockUSDT", [deployer], { id: "USDT" });
  // Use official WETH9 (same as Uniswap V2 Router uses)
  // Users can wrap ETH directly via deposit() function
  const weth = m.contractAt("contracts/interfaces/IWETH9.sol:IWETH9", UNISWAP_V2_SEPOLIA.WETH9, { id: "WETH" });

  // ===== 2. Core tokens =====
  const brs = m.contract("BRS", [deployer], { id: "BRS" });
  const btd = m.contract("BTD", [deployer], { id: "BTD" });
  const btb = m.contract("BTB", [deployer], { id: "BTB" });

  // ===== 3. stTokens (pure ERC4626) =====
  const stBTD = m.contract("stBTD", [btd], { id: "stBTD" });
  const stBTB = m.contract("stBTB", [btb], { id: "stBTB" });

  // ===== 4. Oracles =====
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
  // Note: Redstone removed - using dual-source validation (Chainlink + Pyth)
  const mockPyth = m.contract("contracts/local/MockPyth.sol:MockPyth", [], { id: "MockPyth" });

  // Mock stablecoin oracles (use chainlinkBtcUsd as placeholder)
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

  // ===== 5. Config contracts =====
  const configCore = m.contract(
    "ConfigCore",
    [wbtc, btd, btb, brs, weth, usdc, usdt, chainlinkBtcUsd, chainlinkWbtcBtc, mockPyth, chainlinkUsdcUsd, chainlinkUsdtUsd],
    { id: "ConfigCore" }
  );

  const configGov = m.contract("ConfigGov", [deployer], { id: "ConfigGov" });

  // ===== 6. IdealUSDManager (uses ConfigGov) =====
  const idealUSDManager = m.contract("IdealUSDManager", [deployer, configGov, DEFAULTS.iusdInitial], {
    id: "IdealUSDManager",
    after: [m.call(configGov, "setAddressParam", [0, DEFAULTS.initialPceFeed], { id: "SetPceFeed" })],
  });

  // ===== 7. PriceOracle + TWAP =====
  const twapOracle = m.contract("UniswapV2TWAPOracle", [], { id: "TWAPOracle" });
  const priceOracle = m.contract(
    "PriceOracle",
    [
      deployer,
      configCore,
      twapOracle,
      DEFAULTS.pythPriceId,
    ],
    { after: [configCore] }
  );

  // ===== 8. Treasury / Minter / InterestPool / FarmingPool / StakingRouter =====
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

  // FarmingPool fund split: Treasury 20%, Foundation 10%, Team 10%
  // Uses real addresses: Treasury (contract), Foundation, Team
  const farmingPool = m.contract("FarmingPool", [deployer, brs, configCore, [treasury, FUND_ADDRESSES.foundation, FUND_ADDRESSES.team], [20, 10, 10]], {
    after: [configCore, brs, treasury],
    id: "FarmingPool",
  });

  const stakingRouter = m.contract(
    "StakingRouter",
    [
      farmingPool,
      stBTD,
      stBTB,
      7, // stBTD poolId
      8, // stBTB poolId
    ],
    { after: [farmingPool, stBTD, stBTB], id: "StakingRouter" }
  );

  // ===== 9. BRS Distribution =====
  // Reserve some BRS for:
  // - LP initialization: 1 BRS (for BRS/BTD pair)
  // - Pool 9 seed: 0.001 BRS
  // Using 2 BRS to have buffer
  const totalSupply = 2100000000n * 10n ** 18n;
  const reservedForInit = 2n * 10n ** 18n; // 2 BRS reserved for LP + pool seed
  const toFarmingPool = totalSupply - reservedForInit;

  m.call(brs, "transfer", [farmingPool, toFarmingPool], {
    from: deployer,
    id: "TransferBRSToFarmingPool",
  });

  const governor = deployer;

  // ===== 10. Fill ConfigCore core addresses (peripheral contracts set in init-sepolia.mjs) =====
  m.call(configCore, "setCoreContracts", [treasury, minter, priceOracle, idealUSDManager, interestPool], {
    from: deployer,
  });

  // NOTE: setPeripheralContracts is called in init-sepolia.mjs after creating Uniswap pairs
  // This allows us to use official Uniswap V2 Factory to create pairs

  // ===== 11. ConfigGov params =====
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

  // ===== 12. Grant MINTER_ROLE =====
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));
  m.call(btd, "grantRole", [MINTER_ROLE, minter], { id: "BTDGrantMinterRoleMinter" });
  m.call(btd, "grantRole", [MINTER_ROLE, interestPool], { id: "BTDGrantMinterRoleInterestPool" });
  m.call(btb, "grantRole", [MINTER_ROLE, minter], { id: "BTBGrantMinterRoleMinter" });
  m.call(btb, "grantRole", [MINTER_ROLE, interestPool], { id: "BTBGrantMinterRoleInterestPool" });

  // ===== 13. Faucet (test token distribution) =====
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
    configCore,
    configGov,
    treasury,
    minter,
    interestPool,
    farmingPool,
    stakingRouter,
    priceOracle,
    twapOracle,
    idealUSDManager,
    governor,
    faucet,
    // Uniswap V2 addresses (for reference, pairs created in init-sepolia.mjs)
    uniswapV2: UNISWAP_V2_SEPOLIA,
  };
});

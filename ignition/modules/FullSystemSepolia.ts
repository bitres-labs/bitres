import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toHex } from "viem";

/**
 * Sepolia Testnet Deployment Module
 *
 * Differences from local (FullSystem.ts):
 * - Uses real Chainlink BTC/USD price feed on Sepolia
 * - Deploys mock WBTC/BTC oracle (1:1 ratio, no real feed on Sepolia)
 * - Uses official testnet tokens instead of deploying mocks:
 *   - WETH: Uniswap WETH9 (users can wrap ETH)
 *   - USDC: Circle official (available from faucet.circle.com)
 *   - WBTC: Aave V3 testnet token (available from Aave faucet)
 *   - USDT: Aave V3 testnet token (available from Aave faucet)
 * - Still deploys our own UniswapV2 pairs (no official V2 on Sepolia)
 * - No guardian/price-sync needed (real network)
 */

// Sepolia Chainlink addresses (real feeds)
const SEPOLIA_CHAINLINK = {
  BTC_USD: "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
  ETH_USD: "0x694AA1769357215DE4FAC081bf1f309aDC325306",
};

// Official Sepolia testnet token addresses
// Using established testnet tokens allows users to get tokens from standard faucets
const SEPOLIA_TOKENS = {
  // Uniswap official WETH9 - users can wrap ETH directly
  WETH: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
  // Circle official USDC - available from faucet.circle.com
  USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
  // Aave V3 testnet WBTC (8 decimals) - available from Aave faucet
  WBTC: "0x29f2D40B0605204364af54EC677bD022dA425d03",
  // Aave V3 testnet USDT - available from Aave faucet
  USDT: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0",
};

// Default parameters
const DEFAULTS = {
  initialPceFeed: "0x0000000000000000000000000000000000000001", // placeholder, set via ConfigGov
  pythPriceId: "0x505954485f575442430000000000000000000000000000000000000000000000",
  redstoneFeedId: "0x52454453544f4e455f5754424300000000000000000000000000000000000000",
  redstoneDecimals: 18n,
  iusdInitial: 10n ** 18n,
};

export default buildModule("FullSystemSepolia", (m) => {
  const deployer = m.getAccount(0);

  // ===== 1. Use official Sepolia testnet tokens =====
  // Users can get these from standard faucets (Circle, Aave, or wrap ETH for WETH)
  const wbtc = m.contractAt("IERC20", SEPOLIA_TOKENS.WBTC, { id: "WBTC" });
  const usdc = m.contractAt("IERC20", SEPOLIA_TOKENS.USDC, { id: "USDC" });
  const usdt = m.contractAt("IERC20", SEPOLIA_TOKENS.USDT, { id: "USDT" });
  const weth = m.contractAt("IERC20", SEPOLIA_TOKENS.WETH, { id: "WETH" });

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

  // Mock Pyth and Redstone (no testnet support, use mocks)
  const mockPyth = m.contract("contracts/local/MockPyth.sol:MockPyth", [], { id: "MockPyth" });
  const mockRedstone = m.contract("contracts/local/MockRedstone.sol:MockRedstone", [], { id: "MockRedstone" });

  // ===== 5. UniswapV2 Pairs (our own deployment) =====
  const pairWbtcUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairWBTCUSDC" });
  const pairBtdUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTDUSDC" });
  const pairBtbBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTBBTD" });
  const pairBrsBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBRSBTD" });

  // Initialize pairs token0/token1
  m.call(pairWbtcUsdc, "initialize", [wbtc, usdc], { id: "InitPairWBTCUSDC" });
  m.call(pairBtdUsdc, "initialize", [btd, usdc], { id: "InitPairBTDUSDC" });
  m.call(pairBtbBtd, "initialize", [btb, btd], { id: "InitPairBTBBTD" });
  m.call(pairBrsBtd, "initialize", [brs, btd], { id: "InitPairBRSBTD" });

  // ===== 6. Config contracts =====
  const configCore = m.contract(
    "ConfigCore",
    [wbtc, btd, btb, brs, weth, usdc, usdt, chainlinkBtcUsd, chainlinkWbtcBtc, mockPyth, mockRedstone],
    { id: "ConfigCore" }
  );

  const configGov = m.contract("ConfigGov", [deployer], { id: "ConfigGov" });

  // ===== 7. IdealUSDManager (uses ConfigGov) =====
  const idealUSDManager = m.contract("IdealUSDManager", [deployer, configGov, DEFAULTS.iusdInitial], {
    id: "IdealUSDManager",
    after: [m.call(configGov, "setAddressParam", [0, DEFAULTS.initialPceFeed], { id: "SetPceFeed" })],
  });

  // ===== 8. PriceOracle + TWAP =====
  const twapOracle = m.contract("UniswapV2TWAPOracle", [], { id: "TWAPOracle" });
  const priceOracle = m.contract(
    "PriceOracle",
    [
      deployer,
      configCore,
      twapOracle,
      DEFAULTS.pythPriceId,
      DEFAULTS.redstoneFeedId,
      Number(DEFAULTS.redstoneDecimals),
    ],
    { after: [configCore] }
  );

  // ===== 9. Treasury / Minter / InterestPool / FarmingPool / StakingRouter =====
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

  // FarmingPool fund split: Treasury 20%, Foundation(account1) 10%, Team(account2) 10%
  // On Sepolia, we use deployer for all (can be changed later)
  const farmingPool = m.contract("FarmingPool", [deployer, brs, configCore, [deployer, deployer, deployer], [20, 10, 10]], {
    after: [configCore, brs],
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

  // ===== 10. BRS Distribution =====
  const totalSupply = 2100000000n * 10n ** 18n;
  const reservedForLP = 1n * 10n ** 18n;
  const toFarmingPool = totalSupply - reservedForLP;

  m.call(brs, "transfer", [farmingPool, toFarmingPool], {
    from: deployer,
    id: "TransferBRSToFarmingPool",
  });

  const governor = deployer;

  // ===== 11. Fill ConfigCore addresses =====
  m.call(configCore, "setCoreContracts", [treasury, minter, priceOracle, idealUSDManager, interestPool], {
    from: deployer,
  });

  m.call(
    configCore,
    "setPeripheralContracts",
    [
      stakingRouter,
      farmingPool,
      stBTD,
      stBTB,
      governor,
      twapOracle,
      pairWbtcUsdc,
      pairBtdUsdc,
      pairBtbBtd,
      pairBrsBtd,
    ],
    { from: deployer }
  );

  // ===== 12. ConfigGov params =====
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

  // ===== 13. Grant MINTER_ROLE =====
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));
  m.call(btd, "grantRole", [MINTER_ROLE, minter], { id: "BTDGrantMinterRoleMinter" });
  m.call(btd, "grantRole", [MINTER_ROLE, interestPool], { id: "BTDGrantMinterRoleInterestPool" });
  m.call(btb, "grantRole", [MINTER_ROLE, minter], { id: "BTBGrantMinterRoleMinter" });
  m.call(btb, "grantRole", [MINTER_ROLE, interestPool], { id: "BTBGrantMinterRoleInterestPool" });

  // Output
  return {
    tokens: { wbtc, usdc, usdt, weth, brs, btd, btb, stBTD, stBTB },
    oracles: { chainlinkBtcUsd, chainlinkWbtcBtc, mockPyth, mockRedstone },
    pairs: { pairWbtcUsdc, pairBtdUsdc, pairBtbBtd, pairBrsBtd },
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
  };
});

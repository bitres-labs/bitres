import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toHex } from "viem";

// Default parameters (can be tuned if needed)
const DEFAULTS = {
  initialBtcPrice: BigInt(102_000 * 1e8), // Chainlink 8 decimals
  initialPceFeed: "0x0000000000000000000000000000000000000001", // placeholder, will be set via ConfigGov
  pythPriceId: "0x505954485f575442430000000000000000000000000000000000000000000000", // "PYTH_WTBC"
  iusdInitial: 10n ** 18n,
};

export default buildModule("FullSystemLocal", (m) => {
  const deployer = m.getAccount(0);

  // ===== Phase 1: Tokens (no dependencies) =====

  // 1.1 Mock external tokens
  const wbtc = m.contract("contracts/local/MockWBTC.sol:MockWBTC", [deployer], { id: "WBTC" });
  const usdc = m.contract("contracts/local/MockUSDC.sol:MockUSDC", [deployer], { id: "USDC" });
  const usdt = m.contract("contracts/local/MockUSDT.sol:MockUSDT", [deployer], { id: "USDT" });
  const weth = m.contract("contracts/local/MockWETH.sol:MockWETH", [deployer], { id: "WETH" });

  // 1.2 Core tokens
  const brs = m.contract("BRS", [deployer], { id: "BRS" });
  const btd = m.contract("BTD", [deployer], { id: "BTD" });
  const btb = m.contract("BTB", [deployer], { id: "BTB" });

  // ===== Phase 2: Staking tokens (depend on BTD/BTB) =====
  const stBTD = m.contract("stBTD", [btd], { id: "stBTD", after: [btd] });
  const stBTB = m.contract("stBTB", [btb], { id: "stBTB", after: [btb] });

  // ===== Phase 3: LP Pairs (created before ConfigCore) =====
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

  // ===== Phase 5: Mock oracles =====
  const chainlinkBtcUsd = m.contract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [DEFAULTS.initialBtcPrice],
    { id: "ChainlinkBTCUSD" }
  );
  const chainlinkWbtcBtc = m.contract(
    "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
    [BigInt(1e8)],
    { id: "ChainlinkWBTCBTC" }
  );
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
  const mockPyth = m.contract("contracts/local/MockPyth.sol:MockPyth", [], { id: "MockPyth" });

  // ===== Phase 6: ConfigGov =====
  const configGov = m.contract("ConfigGov", [deployer], { id: "ConfigGov" });

  // ===== Phase 7: IdealUSDManager =====
  const idealUSDManager = m.contract("IdealUSDManager", [deployer, configGov, DEFAULTS.iusdInitial], {
    id: "IdealUSDManager",
    after: [m.call(configGov, "setAddressParam", [0, DEFAULTS.initialPceFeed], { id: "SetPceFeed" })],
  });

  // ===== Phase 8: PriceOracle + TWAP =====
  const twapOracle = m.contract("UniswapV2TWAPOracle", [], { id: "TWAPOracle" });
  const priceOracle = m.contract(
    "PriceOracle",
    [deployer, configCore, configGov, twapOracle, DEFAULTS.pythPriceId],
    { after: [configCore, configGov] }
  );

  // ===== Phase 9: Treasury / Minter / InterestPool =====
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

  // Initialize InterestPool (reads BTD/BTB from ConfigCore)
  m.call(interestPool, "initialize", [], {
    id: "InterestPoolInitialize",
    after: [interestPool, configCore],
  });

  // ===== Phase 10: Grant MINTER_ROLE to Minter and InterestPool =====
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

  // ===== Phase 11: FarmingPool =====
  const foundation = m.getAccount(1);
  const team = m.getAccount(2);
  const farmingPool = m.contract("FarmingPool", [deployer, brs, configCore, [treasury, foundation, team], [20, 10, 10]], {
    after: [configCore, brs, treasury],
    id: "FarmingPool",
  });

  // ===== Phase 12: BRS Distribution =====
  const totalSupply = 2100000000n * 10n ** 18n;
  const reservedForLP = 1n * 10n ** 18n;
  const toFarmingPool = totalSupply - reservedForLP;

  m.call(brs, "transfer", [farmingPool, toFarmingPool], {
    from: deployer,
    id: "TransferBRSToFarmingPool",
  });

  const governor = deployer;

  // ===== Phase 13: Set ConfigCore core contracts (6 addresses with circular dependencies) =====
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

  // ===== Phase 14: ConfigGov params =====
  m.call(
    configGov,
    "setParamsBatch",
    [
      [0, 1, 2, 3, 4, 5, 6],
      [
        50,                    // mintFeeBP 0.5%
        1000,                  // interestFeeBP 10%
        5n * 10n ** 17n,       // minBTBPrice 0.5 BTD
        2000,                  // maxBTBRate 20%
        1n * 10n ** 16n,       // PCE deviation 1%
        50,                    // redeemFeeBP 0.5%
        2000,                  // maxBTDRate 20%
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

  // ===== Phase 15: Faucet =====
  const faucet = m.contract("contracts/local/Faucet.sol:Faucet", [wbtc, usdc, usdt, deployer], {
    id: "Faucet",
    after: [wbtc, usdc, usdt],
  });

  const FAUCET_WBTC = 10_000_000n * 10n ** 8n;
  const FAUCET_USDC = 500_000_000n * 10n ** 6n;
  const FAUCET_USDT = 500_000_000n * 10n ** 6n;

  m.call(wbtc, "transfer", [faucet, FAUCET_WBTC], { from: deployer, id: "TransferWBTCToFaucet", after: [faucet] });
  m.call(usdc, "transfer", [faucet, FAUCET_USDC], { from: deployer, id: "TransferUSDCToFaucet", after: [faucet] });
  m.call(usdt, "transfer", [faucet, FAUCET_USDT], { from: deployer, id: "TransferUSDTToFaucet", after: [faucet] });

  return {
    tokens: { wbtc, usdc, usdt, weth, brs, btd, btb, stBTD, stBTB },
    mocks: { chainlinkBtcUsd, chainlinkWbtcBtc, chainlinkUsdcUsd, chainlinkUsdtUsd, mockPyth },
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
  };
});

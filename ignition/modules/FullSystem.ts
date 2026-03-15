import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toHex } from "viem";

// Default parameters (can be tuned if needed)
const DEFAULTS = {
  initialBtcPrice: BigInt(102_000 * 1e8), // Chainlink 8 decimals
  initialPceFeed: "0x0000000000000000000000000000000000000001", // placeholder, will be set via ConfigGov
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

  // ===== Phase 6: ConfigGov (Proxy) =====
  const configGovImpl = m.contract("ConfigGov", [], { id: "ConfigGovImpl" });
  const configGovInitData = m.encodeFunctionCall(configGovImpl, "initialize", [deployer], { id: "ConfigGovInitData" });
  const configGovProxy = m.contract("ERC1967Proxy", [configGovImpl, configGovInitData], { id: "ConfigGovProxy" });
  const configGov = m.contractAt("ConfigGov", configGovProxy, { id: "ConfigGov" });

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
  const priceOracleInitData = m.encodeFunctionCall(priceOracleImpl, "initialize", [deployer, configCore, configGov, twapOracle], { id: "PriceOracleInitData" });
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

  // ===== Phase 10: Grant MINTER_ROLE to Minter and InterestPool =====
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));

  m.call(btd, "grantRole", [MINTER_ROLE, minter], { id: "BTDGrantMinterRoleMinter" });
  m.call(btd, "grantRole", [MINTER_ROLE, interestPool], { id: "BTDGrantMinterRoleInterestPool" });
  m.call(btb, "grantRole", [MINTER_ROLE, minter], { id: "BTBGrantMinterRoleMinter" });
  m.call(btb, "grantRole", [MINTER_ROLE, interestPool], { id: "BTBGrantMinterRoleInterestPool" });

  // NOTE: Do NOT renounce DEFAULT_ADMIN_ROLE — needed for UUPS upgrade authorization

  // ===== Phase 11: FarmingPool (Proxy) =====
  const foundation = m.getAccount(1);
  const team = m.getAccount(2);
  const farmingPoolImpl = m.contract("FarmingPool", [], { id: "FarmingPoolImpl" });
  const farmingPoolInitData = m.encodeFunctionCall(farmingPoolImpl, "initialize", [deployer, brs, configCore, [treasury, foundation, team], [20, 10, 10]], { id: "FarmingPoolInitData" });
  const farmingPoolProxy = m.contract("ERC1967Proxy", [farmingPoolImpl, farmingPoolInitData], { id: "FarmingPoolProxy", after: [configCore, brs, treasuryProxy] });
  const farmingPool = m.contractAt("FarmingPool", farmingPoolProxy, { id: "FarmingPool" });

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
    mocks: { chainlinkBtcUsd, chainlinkWbtcBtc, chainlinkUsdcUsd, chainlinkUsdtUsd },
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

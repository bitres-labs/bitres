import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toHex } from "viem";

// Default parameters (can be tuned if needed)
const DEFAULTS = {
  initialBtcPrice: BigInt(102_000 * 1e8), // Chainlink 8 decimals
  initialPceFeed: "0x0000000000000000000000000000000000000001", // placeholder, will be set via ConfigGov
  pythPriceId: "0x505954485f575442430000000000000000000000000000000000000000000000", // "PYTH_WTBC"
  redstoneFeedId:
    "0x52454453544f4e455f5754424300000000000000000000000000000000000000", // "REDSTONE_WTBC"
  redstoneDecimals: 18n,
  iusdInitial: 10n ** 18n,
};

export default buildModule("FullSystemLocal", (m) => {
  const deployer = m.getAccount(0);

  // ===== 1. Mock tokens (collateral/stable) =====
  const wbtc = m.contract("contracts/local/MockWBTC.sol:MockWBTC", [deployer], { id: "WBTC" });
  const usdc = m.contract("contracts/local/MockUSDC.sol:MockUSDC", [deployer], { id: "USDC" });
  const usdt = m.contract("contracts/local/MockUSDT.sol:MockUSDT", [deployer], { id: "USDT" });
  const weth = m.contract("contracts/local/MockWETH.sol:MockWETH", [deployer], { id: "WETH" });

  // ===== 2. Core tokens =====
  const brs = m.contract("BRS", [deployer], { id: "BRS" });
  const btd = m.contract("BTD", [deployer], { id: "BTD" });
  const btb = m.contract("BTB", [deployer], { id: "BTB" });

  // ===== 3. stTokens (pure ERC4626) =====
  const stBTD = m.contract("stBTD", [btd], { id: "stBTD" });
  const stBTB = m.contract("stBTB", [btb], { id: "stBTB" });

  // ===== 4. Mock oracles =====
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
  const mockPyth = m.contract("contracts/local/MockPyth.sol:MockPyth", [], { id: "MockPyth" });
  const mockRedstone = m.contract("contracts/local/MockRedstone.sol:MockRedstone", [], { id: "MockRedstone" });

  // ===== 5. Mock pairs (Uniswap V2) =====
  const pairWbtcUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairWBTCUSDC" });
  const pairBtdUsdc = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTDUSDC" });
  const pairBtbBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBTBBTD" });
  const pairBrsBtd = m.contract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", [], { id: "PairBRSBTD" });

  // initialize pairs token0/token1
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
  // Requires ConfigGov PCE feed to be set first
  const idealUSDManager = m.contract("IdealUSDManager", [deployer, configGov, DEFAULTS.iusdInitial], {
    id: "IdealUSDManager",
    after: [m.call(configGov, "setAddressParam", [0, DEFAULTS.initialPceFeed], { id: "SetPceFeed" })],
  });

  // ===== 8. PriceOracle + TWAP =====
  // Deploy TWAP first, then PriceOracle, then wire it via setTWAPOracle
  const twapOracle = m.contract("UniswapV2TWAPOracle", [], { id: "TWAPOracle" });
  const priceOracle = m.contract(
    "PriceOracle",
    [
      deployer,
      configCore,
      twapOracle, // initial TWAP Oracle (can be replaced later)
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

  // rateOracle uses deployer as placeholder
  const interestPool = m.contract("InterestPool", [deployer, configCore, configGov, deployer], {
    after: [configCore, configGov],
    id: "InterestPool",
  });

  // FarmingPool fund split: Treasury 20%, Foundation(account1) 10%, Team(account2) 10%
  const foundation = m.getAccount(1);
  const team = m.getAccount(2);
  const farmingPool = m.contract("FarmingPool", [deployer, brs, configCore, [treasury, foundation, team], [20, 10, 10]], {
    after: [configCore, brs],
    id: "FarmingPool",
  });

  const stakingRouter = m.contract(
    "StakingRouter",
    [
      farmingPool,
      stBTD,
      stBTB,
      7, // stBTD poolId (must match FarmingPool config)
      8, // stBTB poolId
    ],
    { after: [farmingPool, stBTD, stBTB], id: "StakingRouter" }
  );

  // ===== 10. BRS Distribution & Governor =====
  // BRS goes to FarmingPool, distributed via fundShares mechanism:
  // - 60% to miners (stakers)
  // - 20% to Treasury
  // - 10% to Foundation
  // - 10% to Team
  const totalSupply = 2100000000n * 10n ** 18n;
  const reservedForLP = 1n * 10n ** 18n; // 1 BRS for initial LP
  const toFarmingPool = totalSupply - reservedForLP;

  // Transfer most BRS to FarmingPool, keep 1 BRS for LP initialization
  m.call(brs, "transfer", [farmingPool, toFarmingPool], {
    from: deployer,
    id: "TransferBRSToFarmingPool",
  });

  // Governor placeholder: use deployer to avoid zero address
  const governor = deployer;

  // ===== 11. Fill ConfigCore core/peripheral addresses =====
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

  // ===== 13. Grant MINTER_ROLE to Minter & InterestPool =====
  const MINTER_ROLE = keccak256(toHex("MINTER_ROLE"));
  m.call(btd, "grantRole", [MINTER_ROLE, minter], { id: "BTDGrantMinterRoleMinter" });
  m.call(btd, "grantRole", [MINTER_ROLE, interestPool], { id: "BTDGrantMinterRoleInterestPool" });
  m.call(btb, "grantRole", [MINTER_ROLE, minter], { id: "BTBGrantMinterRoleMinter" });
  m.call(btb, "grantRole", [MINTER_ROLE, interestPool], { id: "BTBGrantMinterRoleInterestPool" });

  // Output
  return {
    tokens: { wbtc, usdc, usdt, weth, brs, btd, btb, stBTD, stBTB },
    mocks: { chainlinkBtcUsd, chainlinkWbtcBtc, mockPyth, mockRedstone },
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

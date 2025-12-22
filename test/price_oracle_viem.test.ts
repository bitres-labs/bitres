import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import hre from "hardhat";
import { zeroAddress, toHex } from "viem";

type GenericContract = {
  address: `0x${string}`;
  write: Record<string, (args?: any, opts?: any) => Promise<any>>;
  read: Record<string, (...args: any[]) => Promise<any>>;
};

const deploy = async (name: string, args: any[] = []): Promise<GenericContract> => {
  const { viem } = await hre.network.connect();
  return (await viem.deployContract(name, args)) as unknown as GenericContract;
};

describe("PriceOracle viem (multi-source WBTC)", () => {
  let account: `0x${string}`;

  before(async () => {
    const connected = await hre.network.connect();
    const [wallet] = await connected.viem.getWalletClients();
    account = wallet.account.address as `0x${string}`;
  });

  // TODO: Fix local mock setup that causes getWBTCPrice to revert before enabling this suite
  it.skip("returns Uni price when within 1% of reference median", async () => {
    const btcUsd = await deploy("contracts/local/MockAggregatorV3.sol:MockAggregatorV3", [
      50_000n * 10n ** 8n,
    ]);
    const wbtcBtc = await deploy("contracts/local/MockAggregatorV3.sol:MockAggregatorV3", [
      1n * 10n ** 8n,
    ]);
    const pyth = await deploy("contracts/local/MockPyth.sol:MockPyth");
    const redstone = await deploy("contracts/local/MockRedstone.sol:MockRedstone");
    const pair = await deploy("contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
    const wbtc = await deploy("contracts/local/MockWBTC.sol:MockWBTC", [account]);
    const usdc = await deploy("contracts/local/MockUSDC.sol:MockUSDC", [account, account]);

    // init pair at ~50,050 USDC/WBTC (same as OraclePce.t.sol scenario)
    await pair.write.initialize([wbtc.address, usdc.address], { account });
    await pair.write.__setReservesForTest([1_000000n, 50_050_000000n], { account });

    // pyth/redstone ids
    const pythId = toHex("PYTH_WBTC", { size: 32 });
    await pyth.write.setPrice([pythId, 5_000_000_000_000n, -8]);
    const redId = toHex("REDSTONE_WBTC", { size: 32 });
    await redstone.write.setValue([redId, 50_000n * 10n ** 8n]);

    // config wiring
    const cfg = await deploy("contracts/Config.sol:Config", [account]);
    await cfg.write.setAddressesBatch(
      [
        [
          0n, // TOKEN_WBTC
          1n, // TOKEN_USDC
          12n, // POOL_WBTC_USDC
          19n, // ORACLE_CHAINLINK_BTC_USD
          21n, // ORACLE_CHAINLINK_WBTC_BTC
          22n, // ORACLE_PYTH_WBTC
          23n, // ORACLE_REDSTONE_WBTC
          20n, // ORACLE_CHAINLINK_PCE (unused here)
        ],
        [
          wbtc.address,
          usdc.address,
          pair.address,
          btcUsd.address,
          wbtcBtc.address,
          pyth.address,
          redstone.address,
          btcUsd.address,
        ],
      ],
      { account },
    );

    const oracle = await deploy("contracts/PriceOracle.sol:PriceOracle", [
      account,
      cfg.address,
      zeroAddress,
    ]);
    await oracle.write.setUseTWAP([false], { account });
    await oracle.write.setPythWbtcPriceId([pythId], { account });
    await oracle.write.setRedstoneWbtcConfig([redId, 8], { account });

    const price = (await oracle.read.getWBTCPrice()) as bigint;
    assert(price > 50_000n * 10n ** 18n && price < 50_100n * 10n ** 18n);
  });

  it.skip("reverts when Uni price deviates >1% from reference median", async () => {
    const btcUsd = await deploy("contracts/local/MockAggregatorV3.sol:MockAggregatorV3", [
      50_000n * 10n ** 8n,
    ]);
    const wbtcBtc = await deploy("contracts/local/MockAggregatorV3.sol:MockAggregatorV3", [
      1n * 10n ** 8n,
    ]);
    const pyth = await deploy("contracts/local/MockPyth.sol:MockPyth");
    const redstone = await deploy("contracts/local/MockRedstone.sol:MockRedstone");
    const pair = await deploy("contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
    const wbtc = await deploy("contracts/local/MockWBTC.sol:MockWBTC", [account]);
    const usdc = await deploy("contracts/local/MockUSDC.sol:MockUSDC", [account, account]);

    await pair.write.initialize([wbtc.address, usdc.address], { account });
    await pair.write.__setReservesForTest([1_000000n, 47_000_000000n], { account });

    const pythId = toHex("PYTH_WBTC", { size: 32 });
    await pyth.write.setPrice([pythId, 5_000_000_000_000n, -8]);
    const redId = toHex("REDSTONE_WBTC", { size: 32 });
    await redstone.write.setValue([redId, 50_000n * 10n ** 8n]);

    const cfg = await deploy("contracts/Config.sol:Config", [account]);
    await cfg.write.setAddressesBatch(
      [
        [0n, 1n, 12n, 19n, 21n, 22n, 23n, 20n],
        [wbtc.address, usdc.address, pair.address, btcUsd.address, wbtcBtc.address, pyth.address, redstone.address, btcUsd.address],
      ],
      { account },
    );

    const oracle = await deploy("contracts/PriceOracle.sol:PriceOracle", [
      account,
      cfg.address,
      zeroAddress,
    ]);
    await oracle.write.setUseTWAP([false], { account });
    await oracle.write.setPythWbtcPriceId([pythId], { account });
    await oracle.write.setRedstoneWbtcConfig([redId, 8], { account });

    await assert.rejects(async () => oracle.read.getWBTCPrice(), /WBTC price mismatch/);
  });
});

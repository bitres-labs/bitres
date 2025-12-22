/**
 * Oracle PCE Test (Viem version)
 * Tests IdealUSDManager and PCE oracle integration.
 * IdealUSDManager now fetches the PCE feed address from ConfigGov.
 */

import { describe, it } from "node:test";
import { expect } from "chai";
import { deployFullSystem, viem, getWallets } from "./helpers/setup-viem.js";

describe("IdealUSDManager + PCE Oracle (viem)", function () {
  it("should deploy IdealUSDManager with ConfigGov", async function () {
    const [owner] = await getWallets();

    // Deploy PCE oracle
    const mockPce = await viem.deployContract(
      "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
      [300_00_000_000n] // 300.0, 8 decimals
    );

    // Deploy ConfigGov
    const configGov = await viem.deployContract(
      "contracts/ConfigGov.sol:ConfigGov",
      [owner.account.address]
    );

    // Set PCE Feed in ConfigGov
    await configGov.write.setAddressParam([0n, mockPce.address]); // AddressParamType.PCE_FEED = 0

    // Deploy IdealUSDManager with ConfigGov address
    const INITIAL_IUSD = 1_000000000000000000n; // 1.0 * 10^18

    const manager = await viem.deployContract(
      "contracts/IdealUSDManager.sol:IdealUSDManager",
      [
        owner.account.address,
        configGov.address,        // ConfigGov address instead of PCE feed
        INITIAL_IUSD
      ]
    );

    const currentIUSD = await manager.read.getCurrentIUSD();
    expect(currentIUSD).to.equal(INITIAL_IUSD);
  });

  it("should update IUSD based on PCE changes via ConfigGov", async function () {
    const [owner] = await getWallets();

    // Deploy PCE oracle
    const mockPce = await viem.deployContract(
      "contracts/local/MockAggregatorV3.sol:MockAggregatorV3",
      [300_00_000_000n] // 300.0
    );

    // Deploy ConfigGov and set PCE Feed
    const configGov = await viem.deployContract(
      "contracts/ConfigGov.sol:ConfigGov",
      [owner.account.address]
    );
    await configGov.write.setAddressParam([0n, mockPce.address]);

    const INITIAL_IUSD = 1_000000000000000000n;

    const manager = await viem.deployContract(
      "contracts/IdealUSDManager.sol:IdealUSDManager",
      [
        owner.account.address,
        configGov.address,
        INITIAL_IUSD
      ]
    );

    // Update IUSD - should drop vs target after first update
    await manager.write.updateIUSD({ account: owner.account });
    const afterFirst = await manager.read.getCurrentIUSD();
    expect(afterFirst < INITIAL_IUSD).to.be.true;

    // Increase PCE by 1%
    await mockPce.write.setAnswer([303_00_000_000n]);
    await manager.write.updateIUSD({ account: owner.account });
    const afterSecond = await manager.read.getCurrentIUSD();

    // IUSD should rise when PCE increases
    expect(afterSecond > afterFirst).to.be.true;
  });

  it("should integrate with full system", async function () {
    const system = await deployFullSystem();

    // IdealUSDManager should be deployed
    expect(system.idealUSDManager.address).to.not.equal("0x0000000000000000000000000000000000000000");

    // Should have initial IUSD value
    const iusd = await system.idealUSDManager.read.getCurrentIUSD();
    expect(iusd > 0n).to.be.true;
  });
});

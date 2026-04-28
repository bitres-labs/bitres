/**
 * Oracle PCE Test (Viem version)
 * Tests IdealUSDManager and PCE oracle integration.
 * IdealUSDManager now fetches the PCE feed address from ConfigGov.
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import { deployFullSystem, viem, getWallets, networkHelpers } from "./helpers/setup-viem.js";

describe("IdealUSDManager + PCE Oracle (viem)", function () {
  let owner: any;
  let configGov: any;
  let idealUSDManager: any;
  let mockPce: any;

  async function deployFixture() {
    const wallets = await getWallets();
    const system = await deployFullSystem();

    return {
      owner: wallets[0],
      configGov: system.configGov,
      idealUSDManager: system.idealUSDManager,
      mockPce: system.mockPce,
    };
  }

  beforeEach(async function () {
    const fixture = await networkHelpers.loadFixture(deployFixture);
    owner = fixture.owner;
    configGov = fixture.configGov;
    idealUSDManager = fixture.idealUSDManager;
    mockPce = fixture.mockPce;
  });

  it("should deploy IdealUSDManager with ConfigGov", async function () {
    // IdealUSDManager should be deployed with valid address
    expect(idealUSDManager.address).to.not.equal("0x0000000000000000000000000000000000000000");

    // Should have initial IUSD value
    const currentIUSD = await idealUSDManager.read.getCurrentIUSD();
    expect(currentIUSD > 0n).to.be.true;
    expect(currentIUSD).to.equal(1_000000000000000000n); // 1.0
  });

  it("should update IUSD based on PCE changes via ConfigGov", async function () {
    const INITIAL_IUSD = 1_000000000000000000n;

    // Get test client for time manipulation
    const testClient = await viem.getTestClient();

    // Advance time past the 25-day cooldown from initialization
    await testClient.increaseTime({ seconds: 26 * 24 * 60 * 60 });
    await testClient.mine({ blocks: 1 });

    // Update IUSD - should drop vs target after first update
    await idealUSDManager.write.updateIUSD({ account: owner.account });
    const afterFirst = await idealUSDManager.read.getCurrentIUSD();
    expect(afterFirst < INITIAL_IUSD).to.be.true;

    // Increase PCE by 1%
    await mockPce.write.setAnswer([303_00_000_000n]);

    // Advance time past 25-day cooldown again
    await testClient.increaseTime({ seconds: 26 * 24 * 60 * 60 });
    await testClient.mine({ blocks: 1 });

    await idealUSDManager.write.updateIUSD({ account: owner.account });
    const afterSecond = await idealUSDManager.read.getCurrentIUSD();

    // IUSD should rise when PCE increases
    expect(afterSecond > afterFirst).to.be.true;
  });

  it("should integrate with full system", async function () {
    // IdealUSDManager should be deployed
    expect(idealUSDManager.address).to.not.equal("0x0000000000000000000000000000000000000000");

    // Should have initial IUSD value
    const iusd = await idealUSDManager.read.getCurrentIUSD();
    expect(iusd > 0n).to.be.true;
  });
});

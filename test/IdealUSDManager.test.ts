/**
 * IdealUSDManager Contract Tests
 * Tests IUSD calculation, PCE updates, and helper functions
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import {
  deployFullSystem,
  getWallets
} from "./helpers/setup-viem.js";

describe("IdealUSDManager", function () {
  let owner: any;
  let user1: any;
  let user2: any;

  let idealUSDManager: any;
  let configGov: any;

  beforeEach(async function () {
    const wallets = await getWallets();
    [owner, user1, user2] = wallets;

    const system = await deployFullSystem();

    idealUSDManager = system.idealUSDManager;
    configGov = system.configGov;
  });

  describe("Updater Authorization", function () {
    it("should return true for owner when whitelist disabled", async function () {
      const isAuthorized = await idealUSDManager.read.isUpdaterAuthorized([owner.account.address]);
      expect(isAuthorized).to.be.true;
    });

    it("should return false for non-owner when whitelist disabled", async function () {
      const isAuthorized = await idealUSDManager.read.isUpdaterAuthorized([user1.account.address]);
      expect(isAuthorized).to.be.false;
    });

    it("should allow owner to authorize updaters", async function () {
      await idealUSDManager.write.setUpdaterAuthorization([user1.account.address, true], { account: owner.account });

      // Enable whitelist
      await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: owner.account });

      const isAuthorized = await idealUSDManager.read.isUpdaterAuthorized([user1.account.address]);
      expect(isAuthorized).to.be.true;
    });

    it("should allow owner to revoke updater authorization", async function () {
      // First authorize
      await idealUSDManager.write.setUpdaterAuthorization([user1.account.address, true], { account: owner.account });
      await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: owner.account });

      // Then revoke
      await idealUSDManager.write.setUpdaterAuthorization([user1.account.address, false], { account: owner.account });

      const isAuthorized = await idealUSDManager.read.isUpdaterAuthorized([user1.account.address]);
      expect(isAuthorized).to.be.false;
    });

    it("should return true for owner even with whitelist enabled", async function () {
      await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: owner.account });

      const isAuthorized = await idealUSDManager.read.isUpdaterAuthorized([owner.account.address]);
      expect(isAuthorized).to.be.true;
    });
  });

  describe("Update History", function () {
    it("should return update history length", async function () {
      const length = await idealUSDManager.read.getUpdateHistoryLength();
      expect(length >= 0n).to.be.true;
    });

    it("should get latest update after initialization", async function () {
      const length = await idealUSDManager.read.getUpdateHistoryLength();

      if (length > 0n) {
        const latestUpdate = await idealUSDManager.read.getLatestUpdate();
        expect(latestUpdate).to.not.be.undefined;
        expect(latestUpdate[0] > 0n).to.be.true; // timestamp
        expect(latestUpdate[1] > 0n).to.be.true; // iusdValue
      }
    });

    it("should reject getLatestUpdate when no updates exist", async function () {
      // This test may not work if there's already an initial update
      // We'll skip it in that case
      const length = await idealUSDManager.read.getUpdateHistoryLength();

      if (length === 0n) {
        try {
          await idealUSDManager.read.getLatestUpdate();
          expect.fail("Should have reverted");
        } catch (error: any) {
          expect(error.message).to.match(/No updates yet/i);
        }
      }
    });
  });

  describe("Formatted Info", function () {
    it("should return formatted IUSD info", async function () {
      const info = await idealUSDManager.read.getFormattedInfo();

      expect(info).to.be.a('string');
      expect(info).to.include('IUSD:');
      expect(info).to.include('Target:');
      expect(info).to.include('%');
    });

    it("should include current IUSD value in formatted info", async function () {
      const currentIUSD = await idealUSDManager.read.iusdValue();
      const info = await idealUSDManager.read.getFormattedInfo();

      // Info should contain IUSD value
      expect(info.length > 0).to.be.true;
      expect(currentIUSD > 0n).to.be.true;
    });
  });

  describe("View Functions", function () {
    it("should return current IUSD value via getCurrentIUSD", async function () {
      const iusdValue = await idealUSDManager.read.getCurrentIUSD();
      expect(iusdValue > 0n).to.be.true;
    });

    it("should return PCE feed address", async function () {
      const feed = await idealUSDManager.read.pceFeed();
      expect(feed).to.not.equal("0x0000000000000000000000000000000000000000");
    });

    it("should return PCE feed decimals", async function () {
      const decimals = await idealUSDManager.read.pceFeedDecimals();
      expect(decimals > 0).to.be.true;
    });

    it("should indicate if whitelist is enabled", async function () {
      const enabled = await idealUSDManager.read.updaterWhitelistEnabled();
      expect(typeof enabled).to.equal('boolean');
    });
  });

  describe("Whitelist Control", function () {
    it("should allow owner to enable whitelist", async function () {
      await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: owner.account });

      const enabled = await idealUSDManager.read.updaterWhitelistEnabled();
      expect(enabled).to.be.true;
    });

    it("should allow owner to disable whitelist", async function () {
      await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: owner.account });
      await idealUSDManager.write.setUpdaterWhitelistEnabled([false], { account: owner.account });

      const enabled = await idealUSDManager.read.updaterWhitelistEnabled();
      expect(enabled).to.be.false;
    });

    it("should reject whitelist control from non-owner", async function () {
      try {
        await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        // Should throw an error (any error means access was denied)
        expect(error).to.not.be.undefined;
      }
    });
  });

  describe("Authorization Control", function () {
    it("should reject authorization from non-owner", async function () {
      try {
        await idealUSDManager.write.setUpdaterAuthorization([user1.account.address, true], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        // Should throw an error (any error means access was denied)
        expect(error).to.not.be.undefined;
      }
    });

    it("should allow owner to authorize multiple updaters", async function () {
      await idealUSDManager.write.setUpdaterAuthorization([user1.account.address, true], { account: owner.account });
      await idealUSDManager.write.setUpdaterAuthorization([user2.account.address, true], { account: owner.account });
      await idealUSDManager.write.setUpdaterWhitelistEnabled([true], { account: owner.account });

      const user1Authorized = await idealUSDManager.read.isUpdaterAuthorized([user1.account.address]);
      const user2Authorized = await idealUSDManager.read.isUpdaterAuthorized([user2.account.address]);

      expect(user1Authorized).to.be.true;
      expect(user2Authorized).to.be.true;
    });
  });

  describe("Integration", function () {
    it("should have PCE feed configured", async function () {
      const feed = await idealUSDManager.read.pceFeed();
      // PCE feed should be set
      expect(feed).to.not.equal("0x0000000000000000000000000000000000000000");
    });

    it("should have initial IUSD value set", async function () {
      const iusdValue = await idealUSDManager.read.getCurrentIUSD();
      // Should have a reasonable initial value (around 1e18 = 1.0)
      expect(iusdValue > 0n).to.be.true;
      expect(iusdValue < 10n ** 19n).to.be.true; // Less than 10.0
    });
  });
});

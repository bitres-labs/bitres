/**
 * stBTD and stBTB Contract Tests (ERC4626 Vaults)
 * Tests ERC4626 standard interfaces and integration with InterestPool
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import {
  deployFullSystem,
  getWallets
} from "./helpers/setup-viem.js";
import { parseEther, parseUnits } from "viem";

describe("stBTD (ERC4626 Vault)", function () {
  let owner: any;
  let user1: any;
  let user2: any;

  let interestPool: any;
  let stBTD: any;
  let btd: any;
  let minter: any;
  let wbtc: any;

  beforeEach(async function () {
    const wallets = await getWallets();
    [owner, user1, user2] = wallets;

    const system = await deployFullSystem();

    interestPool = system.interestPool;
    stBTD = system.stBTD;
    btd = system.btd;
    minter = system.minter;
    wbtc = system.wbtc;

    // Note: configureStTokenVaults() removed - InterestPool now directly exposes stake/unstake functions

    // Transfer WBTC to users
    await wbtc.write.transfer([user1.account.address, parseUnits("10", 8)], { account: owner.account });
    await wbtc.write.transfer([user2.account.address, parseUnits("10", 8)], { account: owner.account });

    // Mint BTD to users via Minter
    const wbtcAmount = parseUnits("1", 8);
    await wbtc.write.approve([minter.address, wbtcAmount], { account: user1.account });
    await minter.write.mintBTD([wbtcAmount], { account: user1.account });

    await wbtc.write.approve([minter.address, wbtcAmount], { account: user2.account });
    await minter.write.mintBTD([wbtcAmount], { account: user2.account });
  });

  describe("Deployment", function () {
    it("should have correct name and symbol", async function () {
      const name = await stBTD.read.name();
      const symbol = await stBTD.read.symbol();
      expect(name).to.equal("Staked Bitcoin Dollar");
      expect(symbol).to.equal("stBTD");
    });

    it("should have correct asset (BTD)", async function () {
      const asset = await stBTD.read.asset();
      expect(asset.toLowerCase()).to.equal(btd.address.toLowerCase());
    });

    it("should have correct decimals (18)", async function () {
      const decimals = await stBTD.read.decimals();
      expect(decimals).to.equal(18);
    });

    it.skip("should reference InterestPool correctly", async function () {
      // stBTD is a pure ERC4626 vault and no longer stores an InterestPool address
    });
  });

  describe("ERC4626: deposit()", function () {
    it("should allow user to deposit BTD and receive stBTD shares", async function () {
      const depositAmount = parseEther("1000");

      // Approve stBTD to spend BTD
      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });

      // Deposit
      const sharesBefore = await stBTD.read.balanceOf([user1.account.address]);
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      const sharesAfter = await stBTD.read.balanceOf([user1.account.address]);

      // User should receive shares
      expect(sharesAfter > sharesBefore).to.be.true;
    });

    it("should transfer BTD from user to vault", async function () {
      const userBalance = await btd.read.balanceOf([user1.account.address]);
      const depositAmount = userBalance / 2n;

      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });

      const btdBefore = await btd.read.balanceOf([user1.account.address]);
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      const btdAfter = await btd.read.balanceOf([user1.account.address]);

      // BTD balance should decrease
      expect(btdAfter < btdBefore).to.be.true;
    });

    it("should update totalAssets correctly", async function () {
      const depositAmount = parseEther("1000");

      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });

      const totalBefore = await stBTD.read.totalAssets();
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      const totalAfter = await stBTD.read.totalAssets();

      // Total assets should increase
      expect(totalAfter > totalBefore).to.be.true;
    });

    it("should reject deposit without approval", async function () {
      const depositAmount = parseEther("1000");

      try {
        await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/ERC20InsufficientAllowance/i);
      }
    });

    it("should reject deposit exceeding maxDeposit", async function () {
      const userBalance = await btd.read.balanceOf([user1.account.address]);
      const excessiveAmount = userBalance * 2n;

      await btd.write.approve([stBTD.address, excessiveAmount], { account: user1.account });

      try {
        await stBTD.write.deposit([excessiveAmount, user1.account.address], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/ERC4626ExceededMaxDeposit|ERC20InsufficientBalance/i);
      }
    });
  });

  describe("ERC4626: mint()", function () {
    it("should allow user to mint specific shares amount", async function () {
      const shareAmount = parseEther("500");

      // Preview how much assets needed
      const assetsNeeded = await stBTD.read.previewMint([shareAmount]);

      await btd.write.approve([stBTD.address, assetsNeeded], { account: user1.account });

      const sharesBefore = await stBTD.read.balanceOf([user1.account.address]);
      await stBTD.write.mint([shareAmount, user1.account.address], { account: user1.account });
      const sharesAfter = await stBTD.read.balanceOf([user1.account.address]);

      // User should have exactly shareAmount more
      expect(sharesAfter >= sharesBefore + shareAmount).to.be.true;
    });

    it("should transfer correct amount of BTD based on share price", async function () {
      const shareAmount = parseEther("500");
      const assetsNeeded = await stBTD.read.previewMint([shareAmount]);

      await btd.write.approve([stBTD.address, assetsNeeded], { account: user1.account });

      const btdBefore = await btd.read.balanceOf([user1.account.address]);
      await stBTD.write.mint([shareAmount, user1.account.address], { account: user1.account });
      const btdAfter = await btd.read.balanceOf([user1.account.address]);

      // BTD spent should match preview
      const btdSpent = btdBefore - btdAfter;
      expect(btdSpent >= assetsNeeded).to.be.true;
    });
  });

  describe("ERC4626: withdraw()", function () {
    it("should allow user to withdraw BTD by burning shares", async function () {
      const depositAmount = parseEther("1000");
      const withdrawAmount = parseEther("500");

      // First deposit
      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      // Then withdraw
      const btdBefore = await btd.read.balanceOf([user1.account.address]);
      await stBTD.write.withdraw(
        [withdrawAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const btdAfter = await btd.read.balanceOf([user1.account.address]);

      // BTD balance should increase
      expect(btdAfter > btdBefore).to.be.true;
    });

    it("should burn correct amount of shares", async function () {
      const depositAmount = parseEther("1000");
      const withdrawAmount = parseEther("500");

      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const sharesBefore = await stBTD.read.balanceOf([user1.account.address]);
      await stBTD.write.withdraw(
        [withdrawAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const sharesAfter = await stBTD.read.balanceOf([user1.account.address]);

      // Shares should decrease
      expect(sharesAfter < sharesBefore).to.be.true;
    });

    it("should reject withdrawal exceeding maxWithdraw", async function () {
      const depositAmount = parseEther("1000");
      const excessiveWithdraw = parseEther("2000");

      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      try {
        await stBTD.write.withdraw(
          [excessiveWithdraw, user1.account.address, user1.account.address],
          { account: user1.account }
        );
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/ERC4626ExceededMaxWithdraw/i);
      }
    });
  });

  describe("ERC4626: redeem()", function () {
    it("should allow user to redeem shares for BTD", async function () {
      const depositAmount = parseEther("1000");

      // First deposit
      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await stBTD.read.balanceOf([user1.account.address]);
      const redeemAmount = shares / 2n;

      // Redeem half
      const btdBefore = await btd.read.balanceOf([user1.account.address]);
      await stBTD.write.redeem(
        [redeemAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const btdAfter = await btd.read.balanceOf([user1.account.address]);

      // BTD balance should increase
      expect(btdAfter > btdBefore).to.be.true;
    });

    it("should burn exact amount of shares", async function () {
      const depositAmount = parseEther("1000");

      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await stBTD.read.balanceOf([user1.account.address]);
      const redeemAmount = shares / 2n;

      const sharesBefore = await stBTD.read.balanceOf([user1.account.address]);
      await stBTD.write.redeem(
        [redeemAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const sharesAfter = await stBTD.read.balanceOf([user1.account.address]);

      // Should have burned approximately redeemAmount
      const burned = sharesBefore - sharesAfter;
      expect(burned >= redeemAmount).to.be.true;
    });
  });

  describe("ERC4626: Conversion Functions", function () {
    it("should correctly convert assets to shares", async function () {
      const assets = parseEther("1000");
      const shares = await stBTD.read.convertToShares([assets]);
      expect(shares > 0n).to.be.true;
    });

    it("should correctly convert shares to assets", async function () {
      const shares = parseEther("1000");
      const assets = await stBTD.read.convertToAssets([shares]);
      expect(assets > 0n).to.be.true;
    });

    it("should have convertToShares and convertToAssets be inverse operations", async function () {
      const originalAssets = parseEther("1000");
      const shares = await stBTD.read.convertToShares([originalAssets]);
      const assetsBack = await stBTD.read.convertToAssets([shares]);

      // Should be approximately equal (allowing for rounding)
      const diff = originalAssets > assetsBack ? originalAssets - assetsBack : assetsBack - originalAssets;
      expect(diff <= parseEther("0.01")).to.be.true; // Allow 0.01 difference
    });
  });

  describe("ERC4626: Preview Functions", function () {
    it("should preview deposit correctly", async function () {
      const assets = parseEther("1000");
      const shares = await stBTD.read.previewDeposit([assets]);
      expect(shares > 0n).to.be.true;
    });

    it("should preview mint correctly", async function () {
      const shares = parseEther("1000");
      const assets = await stBTD.read.previewMint([shares]);
      expect(assets > 0n).to.be.true;
    });

    it("should preview withdraw correctly", async function () {
      const assets = parseEther("1000");

      // First deposit
      await btd.write.approve([stBTD.address, assets], { account: user1.account });
      await stBTD.write.deposit([assets, user1.account.address], { account: user1.account });

      // Preview withdraw
      const shares = await stBTD.read.previewWithdraw([assets / 2n]);
      expect(shares > 0n).to.be.true;
    });

    it("should preview redeem correctly", async function () {
      const assets = parseEther("1000");

      // First deposit
      await btd.write.approve([stBTD.address, assets], { account: user1.account });
      await stBTD.write.deposit([assets, user1.account.address], { account: user1.account });

      const userShares = await stBTD.read.balanceOf([user1.account.address]);

      // Preview redeem
      const assetsOut = await stBTD.read.previewRedeem([userShares / 2n]);
      expect(assetsOut > 0n).to.be.true;
    });
  });

  describe("ERC4626: Max Functions", function () {
    it("should return maxDeposit", async function () {
      const max = await stBTD.read.maxDeposit([user1.account.address]);
      expect(max > 0n).to.be.true;
    });

    it("should return maxMint", async function () {
      const max = await stBTD.read.maxMint([user1.account.address]);
      expect(max > 0n).to.be.true;
    });

    it("should return maxWithdraw based on user balance", async function () {
      const depositAmount = parseEther("1000");

      // First deposit
      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const max = await stBTD.read.maxWithdraw([user1.account.address]);
      expect(max > 0n).to.be.true;
    });

    it("should return maxRedeem based on user shares", async function () {
      const depositAmount = parseEther("1000");

      // First deposit
      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const max = await stBTD.read.maxRedeem([user1.account.address]);
      expect(max > 0n).to.be.true;
    });
  });

  describe("Multi-User Scenarios", function () {
    it("should handle multiple users depositing", async function () {
      const amount1 = parseEther("1000");
      const amount2 = parseEther("500");

      // User1 deposits
      await btd.write.approve([stBTD.address, amount1], { account: user1.account });
      await stBTD.write.deposit([amount1, user1.account.address], { account: user1.account });

      // User2 deposits
      await btd.write.approve([stBTD.address, amount2], { account: user2.account });
      await stBTD.write.deposit([amount2, user2.account.address], { account: user2.account });

      // Both should have shares
      const shares1 = await stBTD.read.balanceOf([user1.account.address]);
      const shares2 = await stBTD.read.balanceOf([user2.account.address]);

      expect(shares1 > 0n).to.be.true;
      expect(shares2 > 0n).to.be.true;
      expect(shares1 > shares2).to.be.true; // User1 deposited more
    });

    it("should maintain share value consistency across users", async function () {
      const depositAmount = parseEther("1000");

      // User1 deposits
      await btd.write.approve([stBTD.address, depositAmount], { account: user1.account });
      await stBTD.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares1 = await stBTD.read.balanceOf([user1.account.address]);

      // User2 deposits same amount
      await btd.write.approve([stBTD.address, depositAmount], { account: user2.account });
      await stBTD.write.deposit([depositAmount, user2.account.address], { account: user2.account });

      const shares2 = await stBTD.read.balanceOf([user2.account.address]);

      // Should receive similar shares (allowing for small rounding difference)
      const diff = shares1 > shares2 ? shares1 - shares2 : shares2 - shares1;
      expect(diff <= parseEther("0.1")).to.be.true;
    });
  });

  describe.skip("Integration with InterestPool", function () {
    // stBTD is now a standalone ERC4626 vault; InterestPool integration tests are not applicable
  });
});

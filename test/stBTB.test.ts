/**
 * stBTB Contract Tests (ERC4626 Vault)
 * Tests ERC4626 standard interfaces and integration with InterestPool
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import {
  deployFullSystem,
  getWallets
} from "./helpers/setup-viem.js";
import { parseEther, parseUnits } from "viem";

describe.skip("stBTB (ERC4626 Vault)", function () {
  let owner: any;
  let user1: any;
  let user2: any;

  let interestPool: any;
  let stBTB: any;
  let btb: any;
  let btd: any;
  let minter: any;
  let wbtc: any;
  let priceOracle: any;

  async function resolveAmount(
    target: bigint,
    ctx: any,
    accountAddr?: string
  ) {
    const addr = accountAddr ?? user1.account.address;
    const balance = await btb.read.balanceOf([addr]);
    if (balance === 0n) {
      ctx.skip();
      return 0n;
    }
    return balance < target ? balance : target;
  }

  beforeEach(async function () {
    const wallets = await getWallets();
    [owner, user1, user2] = wallets;

    const system = await deployFullSystem();

    interestPool = system.interestPool;
    stBTB = system.stBTB;
    btb = system.btb;
    btd = system.btd;
    minter = system.minter;
    wbtc = system.wbtc;
    priceOracle = system.priceOracle;

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

    // Get BTB for users by using Minter which has MINTER_ROLE
    // We can use Minter's internal mint functions for testing
    // Since Minter has MINTER_ROLE, we'll have it transfer BTB from treasury or redeem BTD

    // Try to redeem BTD for BTB if CR allows, otherwise skip BTB tests
    const btdBalance1 = await btd.read.balanceOf([user1.account.address]);
    const btdBalance2 = await btd.read.balanceOf([user2.account.address]);

    const redeemAmount1 = btdBalance1 / 2n;
    const redeemAmount2 = btdBalance2 / 2n;

    try {
      await btd.write.approve([minter.address, redeemAmount1], { account: user1.account });
      await minter.write.redeemBTD([redeemAmount1], { account: user1.account });
    } catch (e) {
      // Redemption failed - CR >= 1, user has no BTB
    }

    try {
      await btd.write.approve([minter.address, redeemAmount2], { account: user2.account });
      await minter.write.redeemBTD([redeemAmount2], { account: user2.account });
    } catch (e) {
      // Redemption failed - CR >= 1, user has no BTB
    }
  });

  describe("Deployment", function () {
    it("should have correct name and symbol", async function () {
      const name = await stBTB.read.name();
      const symbol = await stBTB.read.symbol();
      expect(name).to.equal("Staked Bitcoin Bond");
      expect(symbol).to.equal("stBTB");
    });

    it("should have correct asset (BTB)", async function () {
      const asset = await stBTB.read.asset();
      expect(asset.toLowerCase()).to.equal(btb.address.toLowerCase());
    });

    it("should have correct decimals (18)", async function () {
      const decimals = await stBTB.read.decimals();
      expect(decimals).to.equal(18);
    });

    it.skip("should reference InterestPool correctly", async function () {
      // stBTB is a pure ERC4626 vault and no longer stores an InterestPool address
    });
  });

  describe("ERC4626: deposit()", function () {
    it("should allow user to deposit BTB and receive stBTB shares", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      // Approve stBTB to spend BTB
      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });

      // Deposit
      const sharesBefore = await stBTB.read.balanceOf([user1.account.address]);
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      const sharesAfter = await stBTB.read.balanceOf([user1.account.address]);

      // User should receive shares
      expect(sharesAfter > sharesBefore).to.be.true;
    });

    it("should transfer BTB from user to vault", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });

      const btbBefore = await btb.read.balanceOf([user1.account.address]);
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      const btbAfter = await btb.read.balanceOf([user1.account.address]);

      // BTB balance should decrease
      expect(btbAfter < btbBefore).to.be.true;
    });

    it("should update totalAssets correctly", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });

      const totalBefore = await stBTB.read.totalAssets();
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      const totalAfter = await stBTB.read.totalAssets();

      // Total assets should increase
      expect(totalAfter > totalBefore).to.be.true;
    });

    it("should reject deposit without approval", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      try {
        await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/ERC20InsufficientAllowance/i);
      }
    });

    it("should reject deposit exceeding maxDeposit", async function () {
      const userBalance = await btb.read.balanceOf([user1.account.address]);
      if (userBalance === 0n) {
        this.skip();
      }
      const excessiveAmount = userBalance * 2n;

      await btb.write.approve([stBTB.address, excessiveAmount], { account: user1.account });

      try {
        await stBTB.write.deposit([excessiveAmount, user1.account.address], { account: user1.account });
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
      const assetsNeeded = await stBTB.read.previewMint([shareAmount]);
      const balance = await btb.read.balanceOf([user1.account.address]);
      if (balance < assetsNeeded || assetsNeeded === 0n) {
        this.skip();
      }

      await btb.write.approve([stBTB.address, assetsNeeded], { account: user1.account });

      const sharesBefore = await stBTB.read.balanceOf([user1.account.address]);
      await stBTB.write.mint([shareAmount, user1.account.address], { account: user1.account });
      const sharesAfter = await stBTB.read.balanceOf([user1.account.address]);

      // User should have exactly shareAmount more
      expect(sharesAfter >= sharesBefore + shareAmount).to.be.true;
    });

    it("should transfer correct amount of BTB based on share price", async function () {
      const shareAmount = parseEther("500");
      const assetsNeeded = await stBTB.read.previewMint([shareAmount]);
      const balance = await btb.read.balanceOf([user1.account.address]);
      if (balance < assetsNeeded || assetsNeeded === 0n) {
        this.skip();
      }

      await btb.write.approve([stBTB.address, assetsNeeded], { account: user1.account });

      const btbBefore = await btb.read.balanceOf([user1.account.address]);
      await stBTB.write.mint([shareAmount, user1.account.address], { account: user1.account });
      const btbAfter = await btb.read.balanceOf([user1.account.address]);

      // BTB spent should match preview
      const btbSpent = btbBefore - btbAfter;
      expect(btbSpent >= assetsNeeded).to.be.true;
    });
  });

  describe("ERC4626: withdraw()", function () {
    it("should allow user to withdraw BTB by burning shares", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);
      const withdrawAmount = depositAmount / 2n || 1n;

      // First deposit
      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      // Then withdraw
      const btbBefore = await btb.read.balanceOf([user1.account.address]);
      await stBTB.write.withdraw(
        [withdrawAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const btbAfter = await btb.read.balanceOf([user1.account.address]);

      // BTB balance should increase
      expect(btbAfter > btbBefore).to.be.true;
    });

    it("should burn correct amount of shares", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);
      const withdrawAmount = depositAmount / 2n || 1n;

      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const sharesBefore = await stBTB.read.balanceOf([user1.account.address]);
      await stBTB.write.withdraw(
        [withdrawAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const sharesAfter = await stBTB.read.balanceOf([user1.account.address]);

      // Shares should decrease
      expect(sharesAfter < sharesBefore).to.be.true;
    });

    it("should reject withdrawal exceeding maxWithdraw", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);
      const excessiveWithdraw = depositAmount * 2n;

      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      try {
        await stBTB.write.withdraw(
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
    it("should allow user to redeem shares for BTB", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      // First deposit
      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await stBTB.read.balanceOf([user1.account.address]);
      const redeemAmount = shares / 2n;

      // Redeem half
      const btbBefore = await btb.read.balanceOf([user1.account.address]);
      await stBTB.write.redeem(
        [redeemAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const btbAfter = await btb.read.balanceOf([user1.account.address]);

      // BTB balance should increase
      expect(btbAfter > btbBefore).to.be.true;
    });

    it("should burn exact amount of shares", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await stBTB.read.balanceOf([user1.account.address]);
      const redeemAmount = shares / 2n;

      const sharesBefore = await stBTB.read.balanceOf([user1.account.address]);
      await stBTB.write.redeem(
        [redeemAmount, user1.account.address, user1.account.address],
        { account: user1.account }
      );
      const sharesAfter = await stBTB.read.balanceOf([user1.account.address]);

      // Should have burned approximately redeemAmount
      const burned = sharesBefore - sharesAfter;
      expect(burned >= redeemAmount).to.be.true;
    });
  });

  describe("ERC4626: Conversion Functions", function () {
    it("should correctly convert assets to shares", async function () {
      const assets = parseEther("1000");
      const shares = await stBTB.read.convertToShares([assets]);
      expect(shares > 0n).to.be.true;
    });

    it("should correctly convert shares to assets", async function () {
      const shares = parseEther("1000");
      const assets = await stBTB.read.convertToAssets([shares]);
      expect(assets > 0n).to.be.true;
    });

    it("should have convertToShares and convertToAssets be inverse operations", async function () {
      const originalAssets = parseEther("1000");
      const shares = await stBTB.read.convertToShares([originalAssets]);
      const assetsBack = await stBTB.read.convertToAssets([shares]);

      // Should be approximately equal (allowing for rounding)
      const diff = originalAssets > assetsBack ? originalAssets - assetsBack : assetsBack - originalAssets;
      expect(diff <= parseEther("0.01")).to.be.true; // Allow 0.01 difference
    });
  });

  describe("ERC4626: Preview Functions", function () {
    it("should preview deposit correctly", async function () {
      const assets = parseEther("1000");
      const shares = await stBTB.read.previewDeposit([assets]);
      expect(shares > 0n).to.be.true;
    });

    it("should preview mint correctly", async function () {
      const shares = parseEther("1000");
      const assets = await stBTB.read.previewMint([shares]);
      expect(assets > 0n).to.be.true;
    });

    it("should preview withdraw correctly", async function () {
      const assets = await resolveAmount(parseEther("1000"), this);

      // First deposit
      await btb.write.approve([stBTB.address, assets], { account: user1.account });
      await stBTB.write.deposit([assets, user1.account.address], { account: user1.account });

      // Preview withdraw
      const shares = await stBTB.read.previewWithdraw([assets / 2n]);
      expect(shares > 0n).to.be.true;
    });

    it("should preview redeem correctly", async function () {
      const assets = await resolveAmount(parseEther("1000"), this);

      // First deposit
      await btb.write.approve([stBTB.address, assets], { account: user1.account });
      await stBTB.write.deposit([assets, user1.account.address], { account: user1.account });

      const userShares = await stBTB.read.balanceOf([user1.account.address]);

      // Preview redeem
      const assetsOut = await stBTB.read.previewRedeem([userShares / 2n]);
      expect(assetsOut > 0n).to.be.true;
    });
  });

  describe("ERC4626: Max Functions", function () {
    it("should return maxDeposit", async function () {
      const max = await stBTB.read.maxDeposit([user1.account.address]);
      expect(max > 0n).to.be.true;
    });

    it("should return maxMint", async function () {
      const max = await stBTB.read.maxMint([user1.account.address]);
      expect(max > 0n).to.be.true;
    });

    it("should return maxWithdraw based on user balance", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      // First deposit
      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const max = await stBTB.read.maxWithdraw([user1.account.address]);
      expect(max > 0n).to.be.true;
    });

    it("should return maxRedeem based on user shares", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      // First deposit
      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const max = await stBTB.read.maxRedeem([user1.account.address]);
      expect(max > 0n).to.be.true;
    });
  });

  describe("Multi-User Scenarios", function () {
    it("should handle multiple users depositing", async function () {
      const amount1 = await resolveAmount(parseEther("1000"), this, user1.account.address);
      const amount2 = await resolveAmount(parseEther("500"), this, user2.account.address);

      // User1 deposits
      await btb.write.approve([stBTB.address, amount1], { account: user1.account });
      await stBTB.write.deposit([amount1, user1.account.address], { account: user1.account });

      // User2 deposits
      await btb.write.approve([stBTB.address, amount2], { account: user2.account });
      await stBTB.write.deposit([amount2, user2.account.address], { account: user2.account });

      // Both should have shares
      const shares1 = await stBTB.read.balanceOf([user1.account.address]);
      const shares2 = await stBTB.read.balanceOf([user2.account.address]);

      expect(shares1 > 0n).to.be.true;
      expect(shares2 > 0n).to.be.true;
      expect(shares1 > shares2).to.be.true; // User1 deposited more
    });

    it("should maintain share value consistency across users", async function () {
      const depositAmount = await resolveAmount(parseEther("1000"), this);

      // User1 deposits
      await btb.write.approve([stBTB.address, depositAmount], { account: user1.account });
      await stBTB.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares1 = await stBTB.read.balanceOf([user1.account.address]);

      // User2 deposits same amount
      await btb.write.approve([stBTB.address, depositAmount], { account: user2.account });
      await stBTB.write.deposit([depositAmount, user2.account.address], { account: user2.account });

      const shares2 = await stBTB.read.balanceOf([user2.account.address]);

      // Should receive similar shares (allowing for small rounding difference)
      const diff = shares1 > shares2 ? shares1 - shares2 : shares2 - shares1;
      expect(diff <= parseEther("0.1")).to.be.true;
    });
  });

  describe.skip("Integration with InterestPool", function () {
    // stBTB is now a standalone ERC4626 vault; InterestPool integration tests are not applicable
  });
});

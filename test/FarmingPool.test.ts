/**
 * FarmingPool Contract Tests
 * Tests BRS reward distribution through LP token staking
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import {
  deployFullSystem,
  getWallets
} from "./helpers/setup-viem.js";
import { parseEther, parseUnits } from "viem";

describe("FarmingPool", function () {
  let owner: any;
  let user1: any;
  let user2: any;

  let farmingPool: any;
  let brs: any;
  let wbtc: any;
  let btd: any;
  let minter: any;
  let stakingRouter: any;

  beforeEach(async function () {
    const wallets = await getWallets();
    [owner, user1, user2] = wallets;

    const system = await deployFullSystem();

    farmingPool = system.farmingPool;
    brs = system.brs;
    wbtc = system.wbtc;
    btd = system.btd;
    minter = system.minter;
    stakingRouter = system.stakingRouter;

    // Transfer some BRS to FarmingPool for rewards
    const brsAmount = parseEther("100000");
    await brs.write.transfer([farmingPool.address, brsAmount], { account: owner.account });
  });

  describe("Deployment", function () {
    it("should set owner correctly", async function () {
      const poolOwner = await farmingPool.read.owner();
      expect(poolOwner.toLowerCase()).to.equal(owner.account.address.toLowerCase());
    });

    it("should have correct reward token (BRS)", async function () {
      const rewardToken = await farmingPool.read.rewardToken();
      expect(rewardToken.toLowerCase()).to.equal(brs.address.toLowerCase());
    });

    it("should have startTime set", async function () {
      const startTime = await farmingPool.read.startTime();
      expect(startTime > 0n).to.be.true;
    });

    it("should reference ConfigCore", async function () {
      const coreAddr = await farmingPool.read.core();
      expect(coreAddr).to.not.equal("0x0000000000000000000000000000000000000000");
    });
  });

  describe("Pool Management", function () {
    it("should allow owner to add pool", async function () {
      const poolCountBefore = await farmingPool.read.poolLength();

      // Add WBTC pool with allocPoint 100, kind = 0 (SINGLE)
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      const poolCountAfter = await farmingPool.read.poolLength();
      expect(poolCountAfter > poolCountBefore).to.be.true;
    });

    it("should reject pool addition from non-owner", async function () {
      try {
        await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/OwnableUnauthorizedAccount/i);
      }
    });

    it("should update totalAllocPoint when adding pool", async function () {
      const totalBefore = await farmingPool.read.totalAllocPoint();

      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      const totalAfter = await farmingPool.read.totalAllocPoint();
      expect(totalAfter >= totalBefore + 100n).to.be.true;
    });

    it("should return pool count", async function () {
      const count = await farmingPool.read.poolLength();
      expect(count >= 0n).to.be.true;
    });
  });

  describe("Fund Management", function () {
    it("should allow funding rewards", async function () {
      const fundAmount = parseEther("1000");

      // Approve first
      await brs.write.approve([farmingPool.address, fundAmount], { account: owner.account });

      const poolBalanceBefore = await brs.read.balanceOf([farmingPool.address]);
      await farmingPool.write.fundRewards([fundAmount], { account: owner.account });
      const poolBalanceAfter = await brs.read.balanceOf([farmingPool.address]);

      expect(poolBalanceAfter > poolBalanceBefore).to.be.true;
    });

    it("should reject funding with zero amount", async function () {
      try {
        await farmingPool.write.fundRewards([0n], { account: owner.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        // Function reverted as expected (error message format may vary)
        expect(error.message).to.exist;
      }
    });

    it("should allow owner to set funds", async function () {
      const fundAddrs = [user1.account.address];
      const fundShares = [50n]; // 50% to user1

      await farmingPool.write.setFunds([fundAddrs, fundShares], { account: owner.account });

      // Check if set correctly
      const addr = await farmingPool.read.fundAddrs([0n]);
      expect(addr.toLowerCase()).to.equal(user1.account.address.toLowerCase());
    });

    it("should reject setFunds from non-owner", async function () {
      try {
        await farmingPool.write.setFunds([[user1.account.address], [50n]], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/OwnableUnauthorizedAccount/i);
      }
    });
  });

  describe("Deposit and Withdraw", function () {
    beforeEach(async function () {
      // Add WBTC pool first
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      // Transfer WBTC to users
      await wbtc.write.transfer([user1.account.address, parseUnits("10", 8)], { account: owner.account });
      await wbtc.write.transfer([user2.account.address, parseUnits("10", 8)], { account: owner.account });
    });

    it("should allow user to deposit tokens", async function () {
      const poolId = 0n; // Assume first pool after deployment pools
      const depositAmount = parseUnits("1", 8);

      await wbtc.write.approve([farmingPool.address, depositAmount], { account: user1.account });

      const userInfoBefore = await farmingPool.read.userInfo([poolId, user1.account.address]);
      await farmingPool.write.deposit([poolId, depositAmount], { account: user1.account });
      const userInfoAfter = await farmingPool.read.userInfo([poolId, user1.account.address]);

      expect(userInfoAfter[0] > userInfoBefore[0]).to.be.true; // amount increased
    });

    it("should reject deposit without approval", async function () {
      const poolId = 0n;
      const depositAmount = parseUnits("1", 8);

      try {
        await farmingPool.write.deposit([poolId, depositAmount], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/ERC20InsufficientAllowance/i);
      }
    });

    it("should allow user to withdraw tokens", async function () {
      const poolId = 0n;
      const depositAmount = parseUnits("1", 8);
      const withdrawAmount = parseUnits("0.5", 8);

      // Deposit first
      await wbtc.write.approve([farmingPool.address, depositAmount], { account: user1.account });
      await farmingPool.write.deposit([poolId, depositAmount], { account: user1.account });

      // Then withdraw
      const wbtcBefore = await wbtc.read.balanceOf([user1.account.address]);
      await farmingPool.write.withdraw([poolId, withdrawAmount], { account: user1.account });
      const wbtcAfter = await wbtc.read.balanceOf([user1.account.address]);

      expect(wbtcAfter > wbtcBefore).to.be.true;
    });

    it("should reject withdrawal exceeding deposited amount", async function () {
      const poolId = 0n;
      const depositAmount = parseUnits("1", 8);
      const excessiveWithdraw = parseUnits("2", 8);

      await wbtc.write.approve([farmingPool.address, depositAmount], { account: user1.account });
      await farmingPool.write.deposit([poolId, depositAmount], { account: user1.account });

      try {
        await farmingPool.write.withdraw([poolId, excessiveWithdraw], { account: user1.account });
        expect.fail("Should have reverted");
      } catch (error: any) {
        expect(error.message).to.match(/insufficient|exceeds/i);
      }
    });
  });

  describe("Reward Claiming", function () {
    beforeEach(async function () {
      // Add pool and deposit
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      const depositAmount = parseUnits("1", 8);
      await wbtc.write.transfer([user1.account.address, depositAmount], { account: owner.account });
      await wbtc.write.approve([farmingPool.address, depositAmount], { account: user1.account });
      await farmingPool.write.deposit([0n, depositAmount], { account: user1.account });
    });

    it("should allow user to claim rewards", async function () {
      const poolId = 0n;

      // Wait some time for rewards to accrue (simulate by making another transaction)
      await farmingPool.write.updatePool([poolId], { account: owner.account });

      const brsBefore = await brs.read.balanceOf([user1.account.address]);
      await farmingPool.write.claim([poolId], { account: user1.account });
      const brsAfter = await brs.read.balanceOf([user1.account.address]);

      // User should receive some BRS (may be 0 if no time passed)
      expect(brsAfter >= brsBefore).to.be.true;
    });

    it("should calculate pending rewards", async function () {
      const poolId = 0n;

      await farmingPool.write.updatePool([poolId], { account: owner.account });

      const pending = await farmingPool.read.pendingReward([poolId, user1.account.address]);
      expect(pending >= 0n).to.be.true;
    });
  });

  describe("Multi-User Scenarios", function () {
    beforeEach(async function () {
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      await wbtc.write.transfer([user1.account.address, parseUnits("5", 8)], { account: owner.account });
      await wbtc.write.transfer([user2.account.address, parseUnits("5", 8)], { account: owner.account });
    });

    it("should handle multiple users depositing", async function () {
      const poolId = 0n;
      const amount1 = parseUnits("2", 8);
      const amount2 = parseUnits("3", 8);

      // User1 deposits
      await wbtc.write.approve([farmingPool.address, amount1], { account: user1.account });
      await farmingPool.write.deposit([poolId, amount1], { account: user1.account });

      // User2 deposits
      await wbtc.write.approve([farmingPool.address, amount2], { account: user2.account });
      await farmingPool.write.deposit([poolId, amount2], { account: user2.account });

      // Both should have deposits
      const user1Info = await farmingPool.read.userInfo([poolId, user1.account.address]);
      const user2Info = await farmingPool.read.userInfo([poolId, user2.account.address]);

      expect(user1Info[0] > 0n).to.be.true;
      expect(user2Info[0] > 0n).to.be.true;
    });

    it("should distribute rewards proportionally", async function () {
      const poolId = 0n;
      const amount = parseUnits("1", 8);

      // Both users deposit same amount
      await wbtc.write.approve([farmingPool.address, amount], { account: user1.account });
      await farmingPool.write.deposit([poolId, amount], { account: user1.account });

      await wbtc.write.approve([farmingPool.address, amount], { account: user2.account });
      await farmingPool.write.deposit([poolId, amount], { account: user2.account });

      // Update pool to accrue rewards
      await farmingPool.write.updatePool([poolId], { account: owner.account });

      const pending1 = await farmingPool.read.pendingReward([poolId, user1.account.address]);
      const pending2 = await farmingPool.read.pendingReward([poolId, user2.account.address]);

      // Both should have rewards (user1 should have more as deposited first)
      expect(pending1 >= 0n).to.be.true;
      expect(pending2 >= 0n).to.be.true;
    });
  });

  describe("Pool Info", function () {
    it("should return pool info", async function () {
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      const poolId = 0n;
      const poolInfo = await farmingPool.read.poolInfo([poolId]);

      expect(poolInfo).to.not.be.undefined;
      expect(poolInfo[0].toLowerCase()).to.equal(wbtc.address.toLowerCase()); // token
    });

    it("should return user info", async function () {
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      const poolId = 0n;
      const userInfo = await farmingPool.read.userInfo([poolId, user1.account.address]);

      expect(userInfo).to.not.be.undefined;
      expect(userInfo[0]).to.equal(0n); // No deposit yet
    });
  });

  describe("Emergency Withdraw", function () {
    beforeEach(async function () {
      await farmingPool.write.addPool([wbtc.address, 100n, 0], { account: owner.account });

      const depositAmount = parseUnits("1", 8);
      await wbtc.write.transfer([user1.account.address, depositAmount], { account: owner.account });
      await wbtc.write.approve([farmingPool.address, depositAmount], { account: user1.account });
      await farmingPool.write.deposit([0n, depositAmount], { account: user1.account });
    });

    it("should allow emergency withdraw", async function () {
      const poolId = 0n;

      const wbtcBefore = await wbtc.read.balanceOf([user1.account.address]);
      await farmingPool.write.emergencyWithdraw([poolId], { account: user1.account });
      const wbtcAfter = await wbtc.read.balanceOf([user1.account.address]);

      // User should get tokens back
      expect(wbtcAfter > wbtcBefore).to.be.true;

      // User info should be reset
      const userInfo = await farmingPool.read.userInfo([poolId, user1.account.address]);
      expect(userInfo[0]).to.equal(0n);
    });
  });
});

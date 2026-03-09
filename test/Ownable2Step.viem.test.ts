/**
 * Ownable2Step Ownership Transfer Tests
 *
 * Tests the two-step ownership transfer process for ConfigCore and other Ownable2Step contracts.
 * This pattern requires:
 * 1. Current owner calls transferOwnership(newOwner) - proposes transfer
 * 2. New owner calls acceptOwnership() - accepts and completes transfer
 */

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert";
import { deployFullSystem, viem, getWallets, networkHelpers } from "./helpers/setup-viem.ts";
import { zeroAddress } from "viem";

describe("Ownable2Step Ownership Transfer", () => {
  let owner: any;
  let governor: any;  // Simulates a governance contract
  let randomUser: any;
  let configCore: any;
  let configGov: any;
  let minter: any;

  async function deployFixture() {
    const wallets = await getWallets();
    const system = await deployFullSystem();

    return {
      owner: wallets[0],
      governor: wallets[1],
      randomUser: wallets[2],
      configCore: system.configCore,
      configGov: system.configGov,
      minter: system.minter,
    };
  }

  beforeEach(async () => {
    const fixture = await networkHelpers.loadFixture(deployFixture);
    owner = fixture.owner;
    governor = fixture.governor;
    randomUser = fixture.randomUser;
    configCore = fixture.configCore;
    configGov = fixture.configGov;
    minter = fixture.minter;
  });

  describe("Initial State", () => {
    it("should have deployer as initial owner", async () => {
      // Note: ConfigCore's owner was renounced in deployFullSystem after setCoreContracts
      const configGovOwner = await configGov.read.owner();
      const minterOwner = await minter.read.owner();

      assert.strictEqual(configGovOwner.toLowerCase(), owner.account.address.toLowerCase());
      assert.strictEqual(minterOwner.toLowerCase(), owner.account.address.toLowerCase());
    });

    it("should have no pending owner initially", async () => {
      const pendingOwner = await configGov.read.pendingOwner();
      assert.strictEqual(pendingOwner, zeroAddress);
    });
  });

  describe("Step 1: transferOwnership() - Propose Transfer", () => {
    it("should allow owner to propose ownership transfer", async () => {
      // Owner proposes to transfer ownership to governor
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Check pendingOwner is set
      const pendingOwner = await configGov.read.pendingOwner();
      assert.strictEqual(pendingOwner.toLowerCase(), governor.account.address.toLowerCase());

      // Original owner is still the owner
      const currentOwner = await configGov.read.owner();
      assert.strictEqual(currentOwner.toLowerCase(), owner.account.address.toLowerCase());
    });

    it("should reject transferOwnership from non-owner", async () => {
      try {
        await configGov.write.transferOwnership([randomUser.account.address], {
          account: randomUser.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(
          err.message.includes("OwnableUnauthorizedAccount") ||
          err.message.includes("caller is not the owner"),
          `Unexpected error: ${err.message}`
        );
      }
    });
  });

  describe("Step 2: acceptOwnership() - Accept Transfer", () => {
    it("should allow pending owner to accept ownership", async () => {
      // Step 1: Owner proposes transfer
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Verify pending state
      let pendingOwner = await configGov.read.pendingOwner();
      assert.strictEqual(pendingOwner.toLowerCase(), governor.account.address.toLowerCase());

      // Step 2: Governor accepts
      await configGov.write.acceptOwnership([], {
        account: governor.account,
      });

      // Verify transfer completed
      const newOwner = await configGov.read.owner();
      assert.strictEqual(newOwner.toLowerCase(), governor.account.address.toLowerCase());

      // Pending owner should be cleared
      pendingOwner = await configGov.read.pendingOwner();
      assert.strictEqual(pendingOwner, zeroAddress);
    });

    it("should reject acceptOwnership from non-pending owner", async () => {
      // Propose transfer to governor
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Random user tries to accept
      try {
        await configGov.write.acceptOwnership([], {
          account: randomUser.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(
          err.message.includes("OwnableUnauthorizedAccount") ||
          err.message.includes("caller is not the new owner"),
          `Unexpected error: ${err.message}`
        );
      }
    });

    it("should reject acceptOwnership when no pending owner", async () => {
      try {
        await configGov.write.acceptOwnership([], {
          account: governor.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(
          err.message.includes("OwnableUnauthorizedAccount") ||
          err.message.includes("caller is not the new owner"),
          `Unexpected error: ${err.message}`
        );
      }
    });
  });

  describe("Full Ownership Transfer Flow", () => {
    it("should complete full ownership transfer for ConfigGov", async () => {
      console.log("\n=== ConfigGov Ownership Transfer ===");
      console.log(`Initial owner: ${owner.account.address}`);
      console.log(`Target governor: ${governor.account.address}`);

      // Verify initial state
      let currentOwner = await configGov.read.owner();
      assert.strictEqual(currentOwner.toLowerCase(), owner.account.address.toLowerCase());
      console.log(`\n[Before] Owner: ${currentOwner}`);

      // Step 1: Propose transfer
      console.log("\n[Step 1] Owner calls transferOwnership(governor)...");
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      const pendingOwner = await configGov.read.pendingOwner();
      currentOwner = await configGov.read.owner();
      console.log(`  Owner: ${currentOwner} (unchanged)`);
      console.log(`  Pending Owner: ${pendingOwner}`);

      // Step 2: Governor accepts
      console.log("\n[Step 2] Governor calls acceptOwnership()...");
      await configGov.write.acceptOwnership([], {
        account: governor.account,
      });

      currentOwner = await configGov.read.owner();
      const finalPendingOwner = await configGov.read.pendingOwner();
      console.log(`  New Owner: ${currentOwner}`);
      console.log(`  Pending Owner: ${finalPendingOwner} (cleared)`);

      // Verify final state
      assert.strictEqual(currentOwner.toLowerCase(), governor.account.address.toLowerCase());
      assert.strictEqual(finalPendingOwner, zeroAddress);
      console.log("\n✓ Ownership transfer complete!");
    });

    it("should complete full ownership transfer for Minter", async () => {
      console.log("\n=== Minter Ownership Transfer ===");

      // Step 1: Propose
      await minter.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      console.log("[Step 1] transferOwnership called");

      // Step 2: Accept
      await minter.write.acceptOwnership([], {
        account: governor.account,
      });
      console.log("[Step 2] acceptOwnership called");

      // Verify
      const newOwner = await minter.read.owner();
      assert.strictEqual(newOwner.toLowerCase(), governor.account.address.toLowerCase());
      console.log(`✓ Minter owner: ${newOwner}`);
    });
  });

  describe("Post-Transfer Functionality", () => {
    it("should allow new owner to call owner-only functions", async () => {
      // Transfer to governor
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      await configGov.write.acceptOwnership([], {
        account: governor.account,
      });

      // Governor (new owner) can call setParam
      await configGov.write.setParam([0n, 100n], {
        account: governor.account,
      });

      const mintFeeBP = await configGov.read.getParam([0n]);
      assert.strictEqual(mintFeeBP, 100n);
      console.log("\n✓ New owner can call setParam");
    });

    it("should reject owner-only calls from old owner", async () => {
      // Transfer to governor
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      await configGov.write.acceptOwnership([], {
        account: governor.account,
      });

      // Old owner tries to call setParam
      try {
        await configGov.write.setParam([0n, 200n], {
          account: owner.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(
          err.message.includes("OwnableUnauthorizedAccount") ||
          err.message.includes("caller is not the owner"),
          `Unexpected error: ${err.message}`
        );
      }
      console.log("\n✓ Old owner rejected from setParam");
    });
  });

  describe("Security: Preventing Accidental Transfers", () => {
    it("should not transfer ownership if new owner never accepts", async () => {
      // Propose transfer
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Governor never accepts...
      // Original owner is still the owner
      const currentOwner = await configGov.read.owner();
      assert.strictEqual(currentOwner.toLowerCase(), owner.account.address.toLowerCase());

      // Original owner can still perform owner actions
      await configGov.write.setParam([0n, 50n], {
        account: owner.account,
      });
      const mintFeeBP = await configGov.read.getParam([0n]);
      assert.strictEqual(mintFeeBP, 50n);

      console.log("\n✓ Ownership NOT transferred without acceptance");
    });

    it("should allow owner to cancel pending transfer", async () => {
      // Propose transfer to governor
      await configGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Owner changes mind, sets pending to zero address (cancel)
      await configGov.write.transferOwnership([zeroAddress], {
        account: owner.account,
      });

      const pendingOwner = await configGov.read.pendingOwner();
      assert.strictEqual(pendingOwner, zeroAddress);

      // Governor cannot accept anymore
      try {
        await configGov.write.acceptOwnership([], {
          account: governor.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(err.message.includes("OwnableUnauthorizedAccount"));
      }

      console.log("\n✓ Owner can cancel pending transfer");
    });
  });
});

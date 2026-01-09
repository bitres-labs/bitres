/**
 * Ownable2Step Ownership Transfer Tests
 *
 * Tests the two-step ownership transfer process for ConfigCore and other Ownable2Step contracts.
 * This pattern requires:
 * 1. Current owner calls transferOwnership(newOwner) - proposes transfer
 * 2. New owner calls acceptOwnership() - accepts and completes transfer
 */

import { describe, it, before } from "node:test";
import assert from "node:assert";
import { viem, getWallets } from "./helpers/setup-viem.ts";
import { keccak256, toHex, parseEther, zeroAddress } from "viem";

describe("Ownable2Step Ownership Transfer", () => {
  let owner: any;
  let governor: any;  // Simulates a governance contract
  let randomUser: any;
  let configCore: any;
  let configGov: any;
  let minter: any;

  // Deploy minimal system for testing ownership
  before(async () => {
    const wallets = await getWallets();
    owner = wallets[0];
    governor = wallets[1];  // In production, this would be a Governor contract
    randomUser = wallets[2];

    // Deploy tokens
    const wbtc = await viem.deployContract("contracts/local/MockWBTC.sol:MockWBTC", [owner.account.address]);
    const usdc = await viem.deployContract("contracts/local/MockUSDC.sol:MockUSDC", [owner.account.address]);
    const usdt = await viem.deployContract("contracts/local/MockUSDT.sol:MockUSDT", [owner.account.address]);
    const weth = await viem.deployContract("contracts/local/MockWETH.sol:MockWETH", [owner.account.address]);
    const btd = await viem.deployContract("contracts/BTD.sol:BTD", [owner.account.address]);
    const btb = await viem.deployContract("contracts/BTB.sol:BTB", [owner.account.address]);
    const brs = await viem.deployContract("contracts/BRS.sol:BRS", [owner.account.address]);

    // Deploy stTokens
    const stBTD = await viem.deployContract("contracts/stBTD.sol:stBTD", [btd.address]);
    const stBTB = await viem.deployContract("contracts/stBTB.sol:stBTB", [btb.address]);

    // Deploy pools
    const poolWbtcUsdc = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
    const poolBtdUsdc = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
    const poolBtbBtd = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
    const poolBrsBtd = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);

    // Deploy ConfigCore (uses Ownable2Step)
    configCore = await viem.deployContract("contracts/ConfigCore.sol:ConfigCore", [
      wbtc.address, btd.address, btb.address, brs.address, weth.address, usdc.address, usdt.address,
      poolWbtcUsdc.address, poolBtdUsdc.address, poolBtbBtd.address, poolBrsBtd.address,
      stBTD.address, stBTB.address,
    ]);

    // Deploy ConfigGov (uses Ownable2Step)
    configGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [owner.account.address]);

    // Deploy Minter (uses Ownable2Step)
    minter = await viem.deployContract("contracts/Minter.sol:Minter", [
      owner.account.address,
      configCore.address,
      configGov.address,
    ]);
  });

  describe("Initial State", () => {
    it("should have deployer as initial owner", async () => {
      const configCoreOwner = await configCore.read.owner();
      const configGovOwner = await configGov.read.owner();
      const minterOwner = await minter.read.owner();

      assert.strictEqual(configCoreOwner.toLowerCase(), owner.account.address.toLowerCase());
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

    it("should allow owner to change pending owner before acceptance", async () => {
      // Create fresh contract for this test
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // First proposal
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      let pendingOwner = await freshConfigGov.read.pendingOwner();
      assert.strictEqual(pendingOwner.toLowerCase(), governor.account.address.toLowerCase());

      // Owner changes mind, proposes different address
      await freshConfigGov.write.transferOwnership([randomUser.account.address], {
        account: owner.account,
      });
      pendingOwner = await freshConfigGov.read.pendingOwner();
      assert.strictEqual(pendingOwner.toLowerCase(), randomUser.account.address.toLowerCase());
    });
  });

  describe("Step 2: acceptOwnership() - Accept Transfer", () => {
    it("should allow pending owner to accept ownership", async () => {
      // Create fresh contract
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // Step 1: Owner proposes transfer
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Verify pending state
      let pendingOwner = await freshConfigGov.read.pendingOwner();
      assert.strictEqual(pendingOwner.toLowerCase(), governor.account.address.toLowerCase());

      // Step 2: Governor accepts
      await freshConfigGov.write.acceptOwnership([], {
        account: governor.account,
      });

      // Verify transfer completed
      const newOwner = await freshConfigGov.read.owner();
      assert.strictEqual(newOwner.toLowerCase(), governor.account.address.toLowerCase());

      // Pending owner should be cleared
      pendingOwner = await freshConfigGov.read.pendingOwner();
      assert.strictEqual(pendingOwner, zeroAddress);
    });

    it("should reject acceptOwnership from non-pending owner", async () => {
      // Create fresh contract
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // Propose transfer to governor
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Random user tries to accept
      try {
        await freshConfigGov.write.acceptOwnership([], {
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
      // Create fresh contract (no pending owner)
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      try {
        await freshConfigGov.write.acceptOwnership([], {
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

  describe("Full Ownership Transfer Flow: Deployer → Governor", () => {
    it("should complete full ownership transfer for ConfigGov", async () => {
      // Create fresh contract
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      console.log("\n=== ConfigGov Ownership Transfer ===");
      console.log(`Initial owner: ${owner.account.address}`);
      console.log(`Target governor: ${governor.account.address}`);

      // Verify initial state
      let currentOwner = await freshConfigGov.read.owner();
      assert.strictEqual(currentOwner.toLowerCase(), owner.account.address.toLowerCase());
      console.log(`\n[Before] Owner: ${currentOwner}`);

      // Step 1: Propose transfer
      console.log("\n[Step 1] Owner calls transferOwnership(governor)...");
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      const pendingOwner = await freshConfigGov.read.pendingOwner();
      currentOwner = await freshConfigGov.read.owner();
      console.log(`  Owner: ${currentOwner} (unchanged)`);
      console.log(`  Pending Owner: ${pendingOwner}`);

      // Step 2: Governor accepts
      console.log("\n[Step 2] Governor calls acceptOwnership()...");
      await freshConfigGov.write.acceptOwnership([], {
        account: governor.account,
      });

      currentOwner = await freshConfigGov.read.owner();
      const finalPendingOwner = await freshConfigGov.read.pendingOwner();
      console.log(`  New Owner: ${currentOwner}`);
      console.log(`  Pending Owner: ${finalPendingOwner} (cleared)`);

      // Verify final state
      assert.strictEqual(currentOwner.toLowerCase(), governor.account.address.toLowerCase());
      assert.strictEqual(finalPendingOwner, zeroAddress);
      console.log("\n✓ Ownership transfer complete!");
    });

    it("should complete full ownership transfer for Minter", async () => {
      // Create fresh Minter
      const freshMinter = await viem.deployContract("contracts/Minter.sol:Minter", [
        owner.account.address,
        configCore.address,
        configGov.address,
      ]);

      console.log("\n=== Minter Ownership Transfer ===");

      // Step 1: Propose
      await freshMinter.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      console.log("[Step 1] transferOwnership called");

      // Step 2: Accept
      await freshMinter.write.acceptOwnership([], {
        account: governor.account,
      });
      console.log("[Step 2] acceptOwnership called");

      // Verify
      const newOwner = await freshMinter.read.owner();
      assert.strictEqual(newOwner.toLowerCase(), governor.account.address.toLowerCase());
      console.log(`✓ Minter owner: ${newOwner}`);
    });
  });

  describe("Post-Transfer Functionality", () => {
    it("should allow new owner to call owner-only functions", async () => {
      // Create fresh ConfigGov and transfer ownership
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // Transfer to governor
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      await freshConfigGov.write.acceptOwnership([], {
        account: governor.account,
      });

      // Governor (new owner) can call setParam
      await freshConfigGov.write.setParam([0n, 100n], {
        account: governor.account,
      });

      const mintFeeBP = await freshConfigGov.read.getParam([0n]);
      assert.strictEqual(mintFeeBP, 100n);
      console.log("\n✓ New owner can call setParam");
    });

    it("should reject owner-only calls from old owner", async () => {
      // Create fresh ConfigGov and transfer ownership
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // Transfer to governor
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });
      await freshConfigGov.write.acceptOwnership([], {
        account: governor.account,
      });

      // Old owner tries to call setParam
      try {
        await freshConfigGov.write.setParam([0n, 200n], {
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
      // Create fresh contract
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // Propose transfer
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Governor never accepts...
      // Original owner is still the owner
      const currentOwner = await freshConfigGov.read.owner();
      assert.strictEqual(currentOwner.toLowerCase(), owner.account.address.toLowerCase());

      // Original owner can still perform owner actions
      await freshConfigGov.write.setParam([0n, 50n], {
        account: owner.account,
      });
      const mintFeeBP = await freshConfigGov.read.getParam([0n]);
      assert.strictEqual(mintFeeBP, 50n);

      console.log("\n✓ Ownership NOT transferred without acceptance");
    });

    it("should allow owner to cancel pending transfer", async () => {
      // Create fresh contract
      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [
        owner.account.address,
      ]);

      // Propose transfer to governor
      await freshConfigGov.write.transferOwnership([governor.account.address], {
        account: owner.account,
      });

      // Owner changes mind, sets pending to zero address (cancel)
      await freshConfigGov.write.transferOwnership([zeroAddress], {
        account: owner.account,
      });

      const pendingOwner = await freshConfigGov.read.pendingOwner();
      assert.strictEqual(pendingOwner, zeroAddress);

      // Governor cannot accept anymore
      try {
        await freshConfigGov.write.acceptOwnership([], {
          account: governor.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(err.message.includes("OwnableUnauthorizedAccount"));
      }

      console.log("\n✓ Owner can cancel pending transfer");
    });
  });

  describe("ConfigCore: setCoreContracts before renounceOwnership", () => {
    it("should require coreContractsSet before renounceOwnership", async () => {
      // Deploy fresh ConfigCore (coreContractsSet = false)
      const wbtc = await viem.deployContract("contracts/local/MockWBTC.sol:MockWBTC", [owner.account.address]);
      const usdc = await viem.deployContract("contracts/local/MockUSDC.sol:MockUSDC", [owner.account.address]);
      const usdt = await viem.deployContract("contracts/local/MockUSDT.sol:MockUSDT", [owner.account.address]);
      const weth = await viem.deployContract("contracts/local/MockWETH.sol:MockWETH", [owner.account.address]);
      const btd = await viem.deployContract("contracts/BTD.sol:BTD", [owner.account.address]);
      const btb = await viem.deployContract("contracts/BTB.sol:BTB", [owner.account.address]);
      const brs = await viem.deployContract("contracts/BRS.sol:BRS", [owner.account.address]);
      const stBTD = await viem.deployContract("contracts/stBTD.sol:stBTD", [btd.address]);
      const stBTB = await viem.deployContract("contracts/stBTB.sol:stBTB", [btb.address]);
      const pool1 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
      const pool2 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
      const pool3 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
      const pool4 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);

      const freshConfigCore = await viem.deployContract("contracts/ConfigCore.sol:ConfigCore", [
        wbtc.address, btd.address, btb.address, brs.address, weth.address, usdc.address, usdt.address,
        pool1.address, pool2.address, pool3.address, pool4.address,
        stBTD.address, stBTB.address,
      ]);

      // Try to renounce before setCoreContracts
      try {
        await freshConfigCore.write.renounceOwnership([], {
          account: owner.account,
        });
        assert.fail("Should have reverted");
      } catch (err: any) {
        assert.ok(
          err.message.includes("core contracts not set"),
          `Unexpected error: ${err.message}`
        );
      }
      console.log("\n✓ renounceOwnership blocked before setCoreContracts");
    });

    it("should allow renounceOwnership after setCoreContracts", async () => {
      // Deploy minimal system
      const wbtc = await viem.deployContract("contracts/local/MockWBTC.sol:MockWBTC", [owner.account.address]);
      const usdc = await viem.deployContract("contracts/local/MockUSDC.sol:MockUSDC", [owner.account.address]);
      const usdt = await viem.deployContract("contracts/local/MockUSDT.sol:MockUSDT", [owner.account.address]);
      const weth = await viem.deployContract("contracts/local/MockWETH.sol:MockWETH", [owner.account.address]);
      const btd = await viem.deployContract("contracts/BTD.sol:BTD", [owner.account.address]);
      const btb = await viem.deployContract("contracts/BTB.sol:BTB", [owner.account.address]);
      const brs = await viem.deployContract("contracts/BRS.sol:BRS", [owner.account.address]);
      const stBTD = await viem.deployContract("contracts/stBTD.sol:stBTD", [btd.address]);
      const stBTB = await viem.deployContract("contracts/stBTB.sol:stBTB", [btb.address]);
      const pool1 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
      const pool2 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
      const pool3 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);
      const pool4 = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair", []);

      const freshConfigCore = await viem.deployContract("contracts/ConfigCore.sol:ConfigCore", [
        wbtc.address, btd.address, btb.address, brs.address, weth.address, usdc.address, usdt.address,
        pool1.address, pool2.address, pool3.address, pool4.address,
        stBTD.address, stBTB.address,
      ]);

      const freshConfigGov = await viem.deployContract("contracts/ConfigGov.sol:ConfigGov", [owner.account.address]);

      // Deploy minimal contracts for setCoreContracts
      const treasury = await viem.deployContract("contracts/Treasury.sol:Treasury", [
        owner.account.address, freshConfigCore.address, owner.account.address,
      ]);
      const minterContract = await viem.deployContract("contracts/Minter.sol:Minter", [
        owner.account.address, freshConfigCore.address, freshConfigGov.address,
      ]);
      // Use a valid Pyth price id (non-zero)
      const pythId = "0x505954485f575442430000000000000000000000000000000000000000000000";
      const priceOracle = await viem.deployContract("contracts/PriceOracle.sol:PriceOracle", [
        owner.account.address, freshConfigCore.address, freshConfigGov.address, zeroAddress,
        pythId,
      ]);

      // Set PCE_FEED for IdealUSDManager
      const mockPce = await viem.deployContract("contracts/local/MockAggregatorV3.sol:MockAggregatorV3", [300_00_000_000n]);
      await freshConfigGov.write.setAddressParam([0n, mockPce.address]);

      const idealUSDManager = await viem.deployContract("contracts/IdealUSDManager.sol:IdealUSDManager", [
        owner.account.address, freshConfigGov.address, 10n ** 18n,
      ]);
      const interestPool = await viem.deployContract("contracts/InterestPool.sol:InterestPool", [
        owner.account.address, freshConfigCore.address, freshConfigGov.address, owner.account.address,
      ]);
      const farmingPool = await viem.deployContract("contracts/FarmingPool.sol:FarmingPool", [
        owner.account.address, brs.address, freshConfigCore.address, [], [],
      ]);

      // Call setCoreContracts (6 addresses, Governor moved to ConfigGov)
      await freshConfigCore.write.setCoreContracts([
        treasury.address,
        minterContract.address,
        priceOracle.address,
        idealUSDManager.address,
        interestPool.address,
        farmingPool.address,
      ], { account: owner.account });

      // Set Governor in ConfigGov (upgradable)
      await freshConfigGov.write.setGovernor([governor.account.address], { account: owner.account });

      // Now renounceOwnership should work
      await freshConfigCore.write.renounceOwnership([], {
        account: owner.account,
      });

      const finalOwner = await freshConfigCore.read.owner();
      assert.strictEqual(finalOwner, zeroAddress);
      console.log("\n✓ renounceOwnership succeeded after setCoreContracts");
    });
  });
});

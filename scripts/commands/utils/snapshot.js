/**
 * Utility Command: Create System Snapshot
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/utils/snapshot.js <snapshot-name>
 */

module.exports = async function(context) {
    const { stateManager, contracts, utils } = context;

    // Get snapshot name (from command line argument or use default)
    const snapshotName = process.argv[3] || `snapshot-${Date.now()}`;

    console.log("\n" + "=".repeat(80));
    console.log(`📸 Creating System Snapshot: ${snapshotName}`);
    console.log("=".repeat(80));

    // 1. Display current system state
    console.log(`\n1️⃣  Current System State:`);

    const blockNumber = await context.ethers.provider.getBlockNumber();
    const cr = await contracts.minter.getCollateralRatio();
    const btcPrice = await contracts.priceOracle.getWBTCPrice();

    console.log(`   Block Height: ${blockNumber}`);
    console.log(`   BTC Price: $${utils.formatUnits(btcPrice, 18)}`);
    console.log(`   Collateral Ratio: ${utils.formatEther(cr)}x`);

    // 2. Create snapshot
    console.log(`\n2️⃣  Creating Snapshot...`);
    stateManager.createSnapshot(snapshotName);

    // 3. List all snapshots
    const snapshots = stateManager.listSnapshots();

    console.log(`\n3️⃣  Existing Snapshot List:`);
    snapshots.forEach((snap, index) => {
        console.log(`   ${index + 1}. ${snap.name}`);
        console.log(`      Time: ${snap.date}`);
    });

    console.log("\n💡 To restore snapshot use:");
    console.log(`   node scripts/CommandExecutor.js commands/utils/restore.js ${snapshotName}`);

    console.log("\n" + "=".repeat(80));
    console.log("✅ Snapshot creation complete!");
    console.log("=".repeat(80) + "\n");

    return {
        snapshotName: snapshotName,
        totalSnapshots: snapshots.length
    };
};

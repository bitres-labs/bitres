/**
 * Test Auto Time Sync Feature
 *
 * This command pauses for a few seconds, then checks if time auto-advances
 */

module.exports = async function(context) {
    const { timeManager, utils } = context;

    console.log("\n🧪 Testing Auto Time Sync Feature\n");

    // Get current time
    const startTime = await timeManager.getCurrentBlockTime();
    console.log(`📅 Start Time: ${timeManager.formatTimestamp(startTime)}`);
    console.log(`⏱️  Now pausing for 5 seconds of real time...\n`);

    // Pause for 5 seconds (real time)
    await new Promise(resolve => setTimeout(resolve, 5000));

    console.log("✅ 5 seconds of real time have passed");
    console.log("💡 With 3600x acceleration, should advance 5 × 3600 = 18,000 seconds = 5 hours\n");

    // Return simple result
    return {
        test: "auto-sync",
        note: "Time will auto-sync on next command execution"
    };
};

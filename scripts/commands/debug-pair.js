/**
 * Debug Trading Pair Contract
 */

module.exports = async function(context) {
    const { contracts, ethers } = context;

    console.log("\n🔍 Debugging Trading Pair Contract\n");

    const pairAddress = await contracts.pairs.btb_btd.getAddress();
    console.log(`Pair Address: ${pairAddress}`);

    // Check contract code
    const code = await ethers.provider.getCode(pairAddress);
    console.log(`Contract Code Length: ${code.length} bytes`);
    console.log(`Has Code: ${code !== '0x'}\n`);

    // Try calling each function
    try {
        const token0 = await contracts.pairs.btb_btd.token0();
        console.log(`token0: ${token0}`);
    } catch (e) {
        console.log(`token0 call failed: ${e.message}`);
    }

    try {
        const token1 = await contracts.pairs.btb_btd.token1();
        console.log(`token1: ${token1}`);
    } catch (e) {
        console.log(`token1 call failed: ${e.message}`);
    }

    try {
        const reserves = await contracts.pairs.btb_btd.getReserves();
        console.log(`reserves: ${reserves}`);
    } catch (e) {
        console.log(`getReserves call failed: ${e.message}`);
    }

    // Try setting reserves
    try {
        console.log("\nAttempting to set reserves...");
        const tx = await contracts.pairs.btb_btd.setReserves(
            1000000000000n,
            2000000000000n
        );
        await tx.wait();
        console.log("✓ Set successful");

        const reserves = await contracts.pairs.btb_btd.getReserves();
        console.log(`New reserves: ${reserves}`);
    } catch (e) {
        console.log(`Set reserves failed: ${e.message}`);
    }

    return { debug: true };
};

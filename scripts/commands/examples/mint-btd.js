/**
 * Example Command: User Minting BTD Stablecoin
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/examples/mint-btd.js
 */

module.exports = async function(context) {
    const { contracts, accounts, utils } = context;

    console.log("\n" + "=".repeat(80));
    console.log("💎 User Minting BTD Example");
    console.log("=".repeat(80));

    const user1 = accounts.users[0];
    const wbtcAmount = utils.parseUnits("1", 8); // 1 WBTC

    // 1. Transfer WBTC to user
    console.log(`\n1️⃣  Transferring 1 WBTC to User 1...`);
    await contracts.wbtc.transfer(user1.address, wbtcAmount);
    console.log(`   ✓ User 1 Address: ${user1.address}`);
    console.log(`   ✓ WBTC Balance: 1.0`);

    // 2. Check current BTC price
    const btcPrice = await contracts.priceOracle.getWBTCPrice();
    console.log(`\n2️⃣  Current BTC Price: $${utils.formatUnits(btcPrice, 18)}`);

    // 3. Approve Treasury
    console.log(`\n3️⃣  Approving Treasury to use WBTC...`);
    await contracts.wbtc.connect(user1).approve(
        await contracts.treasury.getAddress(),
        wbtcAmount
    );
    console.log(`   ✓ Approval successful`);

    // 4. Mint BTD
    console.log(`\n4️⃣  Minting BTD...`);
    const tx = await contracts.minter.connect(user1).mintBTD(wbtcAmount);
    await tx.wait();

    // 5. View results
    const btdBalance = await contracts.btd.balanceOf(user1.address);
    const wbtcBalanceAfter = await contracts.wbtc.balanceOf(user1.address);

    console.log(`\n5️⃣  Minting Results:`);
    console.log(`   ✓ User 1 BTD Balance: ${utils.formatEther(btdBalance)}`);
    console.log(`   ✓ User 1 WBTC Balance: ${utils.formatUnits(wbtcBalanceAfter, 8)}`);

    // 6. View system state
    const cr = await contracts.minter.getCollateralRatio();
    const treasuryWBTC = await contracts.wbtc.balanceOf(await contracts.treasury.getAddress());

    console.log(`\n6️⃣  System State:`);
    console.log(`   ✓ Collateral Ratio CR: ${utils.formatEther(cr)}x (${(Number(utils.formatEther(cr)) * 100).toFixed(2)}%)`);
    console.log(`   ✓ Treasury WBTC: ${utils.formatUnits(treasuryWBTC, 8)}`);

    console.log("\n" + "=".repeat(80));
    console.log("✅ BTD minting complete!");
    console.log("=".repeat(80) + "\n");

    return {
        user: user1.address,
        btdMinted: utils.formatEther(btdBalance),
        wbtcUsed: "1.0",
        cr: utils.formatEther(cr)
    };
};

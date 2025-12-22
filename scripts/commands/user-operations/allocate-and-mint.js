/**
 * Allocate WBTC to User and Mint BTD
 *
 * Operations:
 * 1. Allocate 10 WBTC to User 1
 * 2. User 1 mints BTD with 1 WBTC
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/user-operations/allocate-and-mint.js
 */

module.exports = async function(context) {
    const { contracts, accounts, utils } = context;

    console.log("\n" + "=".repeat(80));
    console.log("💰 User Asset Allocation and BTD Minting");
    console.log("=".repeat(80));

    // Use User 1
    const user = accounts.users[0];
    const userAddr = user.address;

    console.log(`\n👤 Operating User: User 1`);
    console.log(`   Address: ${userAddr}`);

    // ============ Step 1: Allocate 10 WBTC ============
    console.log(`\n📦 Step 1: Allocating 10 WBTC to user`);

    const wbtcAmount = utils.parseUnits("10", 8); // 10 WBTC (8 decimals)

    // Transfer 10 WBTC from owner account to user (owner has some WBTC from deployment)
    // If owner doesn't have enough WBTC, mint some for owner first
    const ownerWBTCBalance = await contracts.wbtc.balanceOf(accounts.owner.address);
    console.log(`   Owner current WBTC balance: ${utils.formatUnits(ownerWBTCBalance, 8)} WBTC`);

    if (ownerWBTCBalance < wbtcAmount) {
        console.log(`   ⚠️  Owner WBTC insufficient, minting 10 WBTC for Owner...`);
        await contracts.wbtc.mint(accounts.owner.address, wbtcAmount);
        console.log(`   ✓ Minted 10 WBTC for Owner`);
    }

    // Transfer to user
    await contracts.wbtc.transfer(userAddr, wbtcAmount);
    console.log(`   ✓ Transferred 10 WBTC to user`);

    const userWBTCBalance = await contracts.wbtc.balanceOf(userAddr);
    console.log(`   💰 User current WBTC balance: ${utils.formatUnits(userWBTCBalance, 8)} WBTC`);

    // ============ Step 2: Mint BTD with 1 WBTC ============
    console.log(`\n📦 Step 2: Minting BTD with 1 WBTC`);

    const wbtcToMint = utils.parseUnits("1", 8); // 1 WBTC

    // Query pre-mint state
    console.log(`\n   Querying pre-mint state...`);
    const crBefore = await contracts.minter.getCollateralRatio();
    console.log(`   Current Collateral Ratio: ${utils.formatEther(crBefore)}`);

    // Approve Treasury to use user's WBTC (Important: not Minter!)
    console.log(`\n   Approving Treasury contract...`);
    await contracts.wbtc.connect(user).approve(
        await contracts.treasury.getAddress(),
        wbtcToMint
    );
    console.log(`   ✓ Approval complete`);

    // Mint BTD
    console.log(`\n   Minting BTD...`);
    const tx = await contracts.minter.connect(user).mintBTD(wbtcToMint);
    const receipt = await tx.wait();
    console.log(`   ✓ Mint transaction confirmed`);

    // Query post-mint balance
    const userBTDBalance = await contracts.btd.balanceOf(userAddr);
    const userWBTCBalanceAfter = await contracts.wbtc.balanceOf(userAddr);

    console.log(`\n   📊 Minting Results:`);
    console.log(`   User WBTC Balance: ${utils.formatUnits(userWBTCBalanceAfter, 8)} WBTC (${utils.formatUnits(userWBTCBalanceAfter, 8)} remaining)`);
    console.log(`   User BTD Balance: ${utils.formatEther(userBTDBalance)} BTD`);

    // Query Treasury WBTC
    const treasuryWBTC = await contracts.wbtc.balanceOf(await contracts.treasury.getAddress());
    console.log(`   Treasury WBTC: ${utils.formatUnits(treasuryWBTC, 8)} WBTC`);

    // Query system total supply
    const totalBTD = await contracts.btd.totalSupply();
    console.log(`   BTD Total Supply: ${utils.formatEther(totalBTD)} BTD`);

    // Query post-mint CR
    const crAfter = await contracts.minter.getCollateralRatio();
    console.log(`   Current Collateral Ratio: ${utils.formatEther(crAfter)}`);

    console.log("\n" + "=".repeat(80));
    console.log("✅ Operation complete!");
    console.log("=".repeat(80));
    console.log("\n📋 Summary:");
    console.log(`   User Address: ${userAddr}`);
    console.log(`   WBTC Allocated: 10 WBTC`);
    console.log(`   WBTC Used for Minting: 1 WBTC`);
    console.log(`   WBTC Remaining: ${utils.formatUnits(userWBTCBalanceAfter, 8)} WBTC`);
    console.log(`   BTD Received: ${utils.formatEther(userBTDBalance)} BTD`);
    console.log("=".repeat(80) + "\n");

    return {
        user: userAddr,
        wbtcAllocated: "10",
        wbtcUsed: "1",
        wbtcRemaining: utils.formatUnits(userWBTCBalanceAfter, 8),
        btdMinted: utils.formatEther(userBTDBalance),
        totalBTDSupply: utils.formatEther(totalBTD),
        collateralRatio: utils.formatEther(crAfter)
    };
};

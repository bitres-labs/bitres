/**
 * Query Asset Status of All Users
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/utils/check-balances.js
 */

module.exports = async function(context) {
    const { contracts, accounts, utils } = context;

    console.log("\n" + "=".repeat(80));
    console.log("📊 System User Asset Status Query");
    console.log("=".repeat(80));

    // Define all tokens
    const tokens = {
        "WBTC": { contract: contracts.wbtc, decimals: 8 },
        "USDC": { contract: contracts.usdc, decimals: 6 },
        "USDT": { contract: contracts.usdt, decimals: 6 },
        "BRS": { contract: contracts.brs, decimals: 18 },
        "BTD": { contract: contracts.btd, decimals: 18 },
        "BTB": { contract: contracts.btb, decimals: 18 },
        "stBTD": { contract: contracts.stBTD, decimals: 18 },
        "stBTB": { contract: contracts.stBTB, decimals: 18 }
    };

    // Query special addresses
    const specialAccounts = [
        { name: "Owner", signer: accounts.owner },
        { name: "Treasury", signer: accounts.treasury },
        { name: "Foundation", signer: accounts.foundation },
        { name: "Team", signer: accounts.team }
    ];

    console.log("\n🏛️  Special Address Asset Status:");
    console.log("-".repeat(80));

    for (const acc of specialAccounts) {
        const address = acc.signer.address;
        console.log(`\n${acc.name}: ${address}`);

        let hasAssets = false;
        for (const [symbol, token] of Object.entries(tokens)) {
            const balance = await token.contract.balanceOf(address);
            if (balance > 0n) {
                const formatted = utils.formatUnits(balance, token.decimals);
                console.log(`   ${symbol}: ${formatted}`);
                hasAssets = true;
            }
        }

        if (!hasAssets) {
            console.log(`   (No assets)`);
        }
    }

    // Query regular users
    console.log("\n\n👥 Regular User Asset Status:");
    console.log("-".repeat(80));

    let totalUsersWithAssets = 0;

    for (let i = 0; i < accounts.users.length; i++) {
        const userAddr = accounts.users[i].address;
        console.log(`\nUser ${i + 1}: ${userAddr}`);

        let hasAssets = false;
        for (const [symbol, token] of Object.entries(tokens)) {
            const balance = await token.contract.balanceOf(userAddr);
            if (balance > 0n) {
                const formatted = utils.formatUnits(balance, token.decimals);
                console.log(`   ${symbol}: ${formatted}`);
                hasAssets = true;
            }
        }

        if (hasAssets) {
            totalUsersWithAssets++;
        } else {
            console.log(`   (No assets)`);
        }
    }

    // Query system total supply
    console.log("\n\n💰 System Token Total Supply:");
    console.log("-".repeat(80));

    for (const [symbol, token] of Object.entries(tokens)) {
        const totalSupply = await token.contract.totalSupply();
        if (totalSupply > 0n) {
            const formatted = utils.formatUnits(totalSupply, token.decimals);
            console.log(`   ${symbol}: ${formatted}`);
        } else {
            console.log(`   ${symbol}: 0 (Not minted)`);
        }
    }

    // Query FarmingPool information
    console.log("\n\n⛏️  Farming Pool Status:");
    console.log("-".repeat(80));

    for (let poolId = 0; poolId < 9; poolId++) {
        const poolInfo = await contracts.farmingPool.poolInfo(poolId);
        const totalStaked = poolInfo.totalStaked;

        if (totalStaked > 0n) {
            const formatted = utils.formatEther(totalStaked);
            const poolConfig = context.state.config.farmingPools[poolId];
            console.log(`   Pool ${poolId} (${poolConfig.name}): ${formatted} tokens`);
        }
    }

    // Statistics
    console.log("\n\n📈 Statistics:");
    console.log("-".repeat(80));
    console.log(`   Total Users: ${accounts.users.length}`);
    console.log(`   Users With Assets: ${totalUsersWithAssets}`);
    console.log(`   Empty Account Users: ${accounts.users.length - totalUsersWithAssets}`);

    console.log("\n" + "=".repeat(80));
    console.log("✅ Asset query complete!");
    console.log("=".repeat(80) + "\n");

    return {
        totalUsers: accounts.users.length,
        usersWithAssets: totalUsersWithAssets,
        emptyUsers: accounts.users.length - totalUsersWithAssets
    };
};

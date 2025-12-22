/**
 * Initialize All Liquidity Pool Reserves
 *
 * This command sets initial liquidity reserves for all Uniswap trading pairs,
 * ensuring price oracles and trading can work properly.
 */

module.exports = async function(context) {
    const { contracts, accounts, utils } = context;

    console.log("\n💧 Initializing Liquidity Pool Reserves\n");

    const owner = accounts.owner;

    // Define initial liquidity (set reasonable reserves based on current prices)
    // BTC price = $50,000
    // 1 BTC = 50,000 BTD (assuming BTD = $1)
    // 1 BTC = 8 satoshis, BTD = 18 decimals

    const liquidityConfig = [
        {
            name: "BTB/BTD",
            pair: contracts.pairs.btb_btd,
            token0: contracts.btb,
            token1: contracts.btd,
            reserve0: utils.parseEther("1000000"),    // 1 million BTB
            reserve1: utils.parseEther("1000000")     // 1 million BTD (1:1)
        },
        {
            name: "BRS/BTD",
            pair: contracts.pairs.brs_btd,
            token0: contracts.brs,
            token1: contracts.btd,
            reserve0: utils.parseEther("1000000"),    // 1 million BRS
            reserve1: utils.parseEther("10000000")    // 10 million BTD (1:10)
        },
        {
            name: "BTD/USDC",
            pair: contracts.pairs.btd_usdc,
            token0: contracts.btd,
            token1: contracts.usdc,
            reserve0: utils.parseEther("10000000"),   // 10 million BTD
            reserve1: utils.parseUnits("10000000", 6) // 10 million USDC (1:1, USDC 6 decimals)
        },
        {
            name: "WBTC/USDC",
            pair: contracts.pairs.wbtc_usdc,
            token0: contracts.wbtc,
            token1: contracts.usdc,
            reserve0: utils.parseUnits("100", 8),     // 100 WBTC (8 decimals)
            reserve1: utils.parseUnits("5000000", 6)  // 5 million USDC ($50,000/BTC)
        }
    ];

    console.log("📝 Liquidity Pool Configuration:\n");

    for (const config of liquidityConfig) {
        console.log(`💧 ${config.name}:`);

        try {
            // Set reserves
            const tx = await config.pair.setReserves(
                config.reserve0,
                config.reserve1
            );
            await tx.wait();

            // Verify reserves
            const reserves = await config.pair.getReserves();

            console.log(`   ✓ Reserve0: ${utils.formatEther(reserves[0])}`);
            console.log(`   ✓ Reserve1: ${utils.formatEther(reserves[1])}`);

            // Calculate price
            const price = Number(reserves[1]) / Number(reserves[0]);
            console.log(`   ✓ Price: ${price.toFixed(6)} (Token1/Token0)`);
            console.log(`   ✓ Status: Initialized\n`);

        } catch (error) {
            console.log(`   ❌ Initialization failed: ${error.message}\n`);
        }
    }

    console.log("✅ Liquidity pool initialization complete!\n");

    return {
        initialized: true,
        pools: liquidityConfig.length
    };
};

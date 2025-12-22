/**
 * Check Reserve Status of All Liquidity Pools
 */

module.exports = async function(context) {
    const { contracts, utils } = context;

    console.log("\n💧 Checking Liquidity Pool Reserve Status\n");

    // Check all trading pairs
    const pairs = [
        { name: "BTB/BTD", contract: contracts.pairs.btb_btd },
        { name: "BRS/BTD", contract: contracts.pairs.brs_btd },
        { name: "BTD/USDC", contract: contracts.pairs.btd_usdc },
        { name: "WBTC/USDC", contract: contracts.pairs.wbtc_usdc }
    ];

    for (const pair of pairs) {
        try {
            const reserves = await pair.contract.getReserves();
            const token0 = await pair.contract.token0();
            const token1 = await pair.contract.token1();

            console.log(`📊 ${pair.name}:`);
            console.log(`   Token0: ${token0}`);
            console.log(`   Token1: ${token1}`);
            console.log(`   Reserve0: ${utils.formatEther(reserves[0])}`);
            console.log(`   Reserve1: ${utils.formatEther(reserves[1])}`);

            const hasLiquidity = reserves[0] > 0n && reserves[1] > 0n;
            console.log(`   Status: ${hasLiquidity ? '✅ Has Liquidity' : '❌ No Liquidity'}\n`);
        } catch (error) {
            console.log(`📊 ${pair.name}: ❌ Read Failed - ${error.message}\n`);
        }
    }

    return { checked: true };
};

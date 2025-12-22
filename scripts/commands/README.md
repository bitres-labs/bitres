# Bitres Integration Test Framework - Interactive Commands Directory

This directory contains interactive command scripts that can be executed within the Bitres integration test framework.

## Directory Structure

```
commands/
├── README.md               # This documentation file
├── examples/               # Example commands
│   ├── mint-btd.js        # Example: Mint BTD
│   ├── advance-time.js    # Example: Advance time
│   ├── price-crash.js     # Example: Simulate price crash
│   └── ...
├── scenarios/              # Complete scenario scripts
│   ├── bull-market.js     # Bull market scenario
│   ├── bear-market.js     # Bear market scenario
│   └── ...
└── utils/                  # Utility commands
    ├── snapshot.js        # Create snapshot
    ├── report.js          # Generate report
    └── ...
```

## Command Script Format

Each command script must export an async function that receives a context object as a parameter:

```javascript
module.exports = async function(context) {
    // context contains:
    // - contracts: All contract references
    // - accounts: Test accounts
    // - timeManager: Time manager
    // - priceFeeds: Price data sources
    // - stateManager: State manager
    // - ethers: ethers.js utilities
    // - state: Current system state
    // - utils: Helper functions

    // Your command logic...

    return result; // Optional return value
};
```

## Important Notes

### Correct Authorization Method When Minting BTD

**Key Point**: When users mint BTD, they must authorize the **Treasury contract**, not the Minter contract!

```javascript
// Correct approach
const { contracts, accounts, utils } = context;
const user = accounts.users[0];
const wbtcAmount = utils.parseUnits("1", 8);

// 1. Authorize Treasury
await contracts.wbtc.connect(user).approve(
    await contracts.treasury.getAddress(),  // Authorize Treasury
    wbtcAmount
);

// 2. Call Minter to mint
await contracts.minter.connect(user).mintBTD(wbtcAmount);
```

```javascript
// Wrong approach - will cause transaction failure
await contracts.wbtc.connect(user).approve(
    await contracts.minter.getAddress(),  // Wrong! Do not authorize Minter
    wbtcAmount
);
await contracts.minter.connect(user).mintBTD(wbtcAmount); // This will fail
```

**Explanation**:
- Minter contract calls `Treasury.depositWBTC(user, amount)`
- Treasury executes `WBTC.transferFrom(user, treasury, amount)`
- Therefore WBTC needs to be authorized to Treasury, not Minter

### Other Important Authorization Rules

```javascript
// Staking BTD to stBTD: Authorize stBTD contract
await contracts.btd.connect(user).approve(
    await contracts.stBTD.getAddress(),
    btdAmount
);

// Staking stBTD to farming pool: Authorize FarmingPool contract
await contracts.stBTD.connect(user).approve(
    await contracts.farmingPool.getAddress(),
    stBTDAmount
);
```

## Usage

### 1. Initialize Framework

First run the framework initialization script:

```bash
npx hardhat run scripts/IntegrationFramework.js
```

This will deploy all contracts and save state to `scripts/framework-state.json`

### 2. Execute Commands

Use CommandExecutor to execute command scripts:

```bash
node scripts/CommandExecutor.js commands/examples/mint-btd.js
```

### 3. Create Custom Commands

Create new JavaScript files in the `commands/` directory and write command logic following the format above.

## Available Command Examples

### Basic Operations

- `examples/mint-btd.js` - User mints BTD stablecoin
- `examples/redeem-btd.js` - User redeems BTD
- `examples/mint-btb.js` - Obtain BTB bonds
- `examples/stake-btd.js` - Stake BTD to get stBTD
- `examples/farm-brs.js` - Stake to farming pool to mine BRS

### Time Operations

- `examples/advance-time.js` - Advance system time
- `examples/advance-month.js` - Advance one month (update CPI)
- `examples/advance-year.js` - Advance one year

### Price Operations

- `examples/set-btc-price.js` - Set BTC price
- `examples/price-crash.js` - Simulate price crash
- `examples/price-pump.js` - Simulate price surge
- `examples/switch-scenario.js` - Switch price scenario

### Scenario Tests

- `scenarios/bull-market.js` - Complete bull market scenario
- `scenarios/bear-market.js` - Complete bear market scenario
- `scenarios/volatility-test.js` - High volatility scenario
- `scenarios/redemption-crisis.js` - Redemption crisis scenario

### Utility Commands

- `utils/snapshot.js` - Create system snapshot
- `utils/restore.js` - Restore to snapshot
- `utils/report.js` - Generate complete report
- `utils/export-data.js` - Export historical data

## Context Object Details

### contracts - Contract References

```javascript
context.contracts = {
    // Core tokens
    brs, btd, btb,

    // Mock tokens
    wbtc, usdc, usdt,

    // Core contracts
    config, treasury, minter,

    // stToken
    stBTD, stBTB, interestPool,

    // Farming and staking
    farmingPool, stakingRouter,

    // Oracles
    btcPriceFeed, cpiOracle, iusdManager,

    // Trading pairs
    pairs: { btb_btd, brs_btd, btd_usdc, wbtc_usdc }
}
```

### accounts - Test Accounts

```javascript
context.accounts = {
    owner,        // Contract owner
    treasury,     // Treasury address
    foundation,   // Foundation address
    team,         // Team address
    users: []     // Array of 10 user accounts
}
```

### timeManager - Time Manager

```javascript
// Advance time
await context.timeManager.advanceHours(24);      // Advance 24 hours
await context.timeManager.advanceDays(30);       // Advance 30 days
await context.timeManager.advanceMonths(6);      // Advance 6 months
await context.timeManager.advanceYears(1);       // Advance 1 year

// Get current time
const currentTime = await context.timeManager.getCurrentTime();
const elapsed = await context.timeManager.getElapsedTime();

// Print status
await context.timeManager.printStatus();
```

### priceFeeds - Price Data Sources

```javascript
// Manually set prices
await context.priceFeeds.setBTCPrice(60000);     // Set BTC price
await context.priceFeeds.setCPI(1020000);        // Set CPI
await context.priceFeeds.setFFR(525);            // Set FFR (5.25%)

// Update prices based on time
await context.priceFeeds.updatePricesForTime(30); // Simulate 30 days of price changes

// Simulate extreme market conditions
await context.priceFeeds.simulateCrash(30);      // Price crash -30%
await context.priceFeeds.simulatePump(50);       // Price surge +50%

// Switch scenarios
context.priceFeeds.setScenario('bullish');       // Bull market
context.priceFeeds.setScenario('bearish');       // Bear market
context.priceFeeds.setScenario('volatile');      // High volatility

// Get current prices
const prices = context.priceFeeds.getCurrentPrices();
```

### stateManager - State Manager

```javascript
// Create snapshot
context.stateManager.createSnapshot('before-crash');

// Restore snapshot
await context.stateManager.restoreSnapshot('before-crash');

// Generate report
await context.stateManager.generateReport('report.json');

// Print summary
context.stateManager.printSummary();
```

### utils - Helper Functions

```javascript
// ethers utilities
const amount = context.utils.parseEther("100");
const formatted = context.utils.formatEther(amount);
const usdc = context.utils.parseUnits("1000", 6);
```

## Development Tips

1. **Always use async/await** - All blockchain operations are asynchronous
2. **Add logging output** - Use console.log to record key steps
3. **Error handling** - Use try/catch to capture exceptions
4. **Check preconditions** - Verify balances, authorizations, etc. before operations
5. **Print results** - Print operation results at the end of commands

## Example: Complete Command Script

```javascript
/**
 * Example command: User 1 mints BTD and stakes for farming
 */
module.exports = async function(context) {
    const { contracts, accounts, utils, timeManager, priceFeeds } = context;
    const user1 = accounts.users[0];

    console.log("\n=== User 1 Mints BTD and Stakes for Farming ===\n");

    // 1. Prepare WBTC
    const wbtcAmount = utils.parseUnits("1", 8); // 1 WBTC
    await contracts.wbtc.transfer(user1.address, wbtcAmount);
    console.log("User 1 received 1 WBTC");

    // 2. Authorize and mint BTD
    await contracts.wbtc.connect(user1).approve(
        await contracts.treasury.getAddress(),
        wbtcAmount
    );
    await contracts.minter.connect(user1).mintBTD(wbtcAmount);

    const btdBalance = await contracts.btd.balanceOf(user1.address);
    console.log(`User 1 minted ${utils.formatEther(btdBalance)} BTD`);

    // 3. Stake BTD to stBTD
    await contracts.btd.connect(user1).approve(
        await contracts.stBTD.getAddress(),
        btdBalance
    );
    await contracts.stBTD.connect(user1).deposit(btdBalance, user1.address);

    const stBTDBalance = await contracts.stBTD.balanceOf(user1.address);
    console.log(`User 1 received ${utils.formatEther(stBTDBalance)} stBTD`);

    // 4. Stake stBTD to farming pool
    const poolId = 6; // stBTD pool
    await contracts.stBTD.connect(user1).approve(
        await contracts.farmingPool.getAddress(),
        stBTDBalance
    );
    await contracts.farmingPool.connect(user1).deposit(poolId, stBTDBalance);
    console.log(`User 1 staked stBTD to farming pool ${poolId}`);

    // 5. Advance time to wait for rewards
    console.log("\nAdvancing 30 days to wait for farming rewards...");
    await timeManager.advanceDays(30);

    // 6. Claim rewards
    const pendingBRS = await contracts.farmingPool.pendingReward(poolId, user1.address);
    await contracts.farmingPool.connect(user1).claim(poolId);

    const brsBalance = await contracts.brs.balanceOf(user1.address);
    console.log(`User 1 claimed ${utils.formatEther(brsBalance)} BRS rewards`);

    console.log("\n=== Operation Complete ===\n");

    return {
        btdMinted: btdBalance,
        stBTDStaked: stBTDBalance,
        brsEarned: brsBalance
    };
};
```

## FAQ

**Q: How to view current system state?**
A: Read the `scripts/framework-state.json` file

**Q: How to reset the system?**
A: Re-run `npx hardhat run scripts/IntegrationFramework.js`

**Q: What to do if command execution fails?**
A: Check error messages, ensure preconditions are met (sufficient balance, authorized, etc.)

**Q: How to debug commands?**
A: Add console.log in commands to view intermediate variable values

**Q: Can multiple commands be executed consecutively?**
A: Yes, state is automatically saved after each execution and loaded on the next run

## Additional Resources

- System design document: `whitepaper/Bitres-System-Design.tex`
- Integration test examples: `test/IntegrationTest.js`
- Hardhat documentation: https://hardhat.org/
- Ethers.js documentation: https://docs.ethers.org/

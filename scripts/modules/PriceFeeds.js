/**
 * Price Data Source Module
 *
 * Features:
 * 1. Provides simulated data sources for CPI and FFR
 * 2. Automatically updates price data based on accelerated time
 * 3. Supports historical price trend simulation
 * 4. Synchronously updates Chainlink oracles and Uniswap pools
 */

const { ethers } = require("hardhat");

class PriceFeeds {
    constructor(initialBTCPrice = 50000, initialCPI = 1000000, initialFFR = 500) {
        // Initial prices
        this.initialBTCPrice = initialBTCPrice;
        this.initialCPI = initialCPI;  // CPI stored with 6 decimal precision
        this.initialFFR = initialFFR;   // FFR stored in basis points (500 = 5.00%)

        // Current prices
        this.currentBTCPrice = initialBTCPrice;
        this.currentCPI = initialCPI;
        this.currentFFR = initialFFR;

        // Price history
        this.priceHistory = [];

        // Contract references
        this.btcPriceFeed = null;
        this.cpiOracle = null;
        this.wbtcUsdcPair = null;

        // Monthly counter (for CPI updates)
        this.monthsPassed = 0;
        this.lastCPIUpdateMonth = 0;

        // Current annual inflation rate (for display and logging)
        this.currentAnnualInflation = 0.02; // Initial 2%

        // Predefined price scenarios
        this.scenarios = {
            // Steady growth scenario
            steady: {
                btcDrift: 0.0001,  // 0.01% per day
                btcVolatility: 0.02, // 2% volatility
                cpiMonthly: 0.00165, // 0.165% monthly (2% annualized)
                ffrChangeProbability: 0.1 // 10% probability of FFR adjustment
            },
            // Bull market scenario
            bullish: {
                btcDrift: 0.002,
                btcVolatility: 0.05,
                cpiMonthly: 0.003,
                ffrChangeProbability: 0.2
            },
            // Bear market scenario
            bearish: {
                btcDrift: -0.002,
                btcVolatility: 0.08,
                cpiMonthly: 0.001,
                ffrChangeProbability: 0.3
            },
            // High volatility scenario
            volatile: {
                btcDrift: 0,
                btcVolatility: 0.15,
                cpiMonthly: 0.00165,
                ffrChangeProbability: 0.25
            }
        };

        this.currentScenario = 'steady';
    }

    /**
     * Initialize price data source (bind contracts)
     */
    async initialize(btcPriceFeed, cpiOracle, wbtcUsdcPair) {
        this.btcPriceFeed = btcPriceFeed;
        this.cpiOracle = cpiOracle;
        this.wbtcUsdcPair = wbtcUsdcPair;

        // Set initial prices
        await this.updateBTCPrice(this.initialBTCPrice);
        await this.updateCPI(this.initialCPI, this.initialCPI);

        this.recordPrice("INITIALIZED");
    }

    /**
     * Update all prices based on time elapsed
     * @param {number} daysPassed - Number of days elapsed
     */
    async updatePricesForTime(daysPassed) {
        console.log(`\n💹 Updating prices based on time elapsed (${daysPassed} days)...`);

        const scenario = this.scenarios[this.currentScenario];

        // 1. Update BTC price (daily)
        for (let day = 0; day < daysPassed; day++) {
            const newPrice = this.simulateBTCPriceChange(scenario);
            await this.updateBTCPrice(newPrice);
        }

        // 2. Update CPI (monthly)
        const newMonths = Math.floor(daysPassed / 30);
        if (newMonths > 0) {
            for (let i = 0; i < newMonths; i++) {
                this.monthsPassed++;
                const newCPI = this.simulateCPIChange(scenario);
                await this.updateCPI(this.currentCPI, newCPI);
            }
        }

        // 3. Update FFR (by probability)
        if (Math.random() < scenario.ffrChangeProbability * daysPassed) {
            const newFFR = this.simulateFFRChange(scenario);
            await this.updateFFR(newFFR);
        }

        this.recordPrice("TIME_UPDATE", { daysPassed });

        console.log(`   ✓ BTC: $${this.currentBTCPrice.toLocaleString()}`);
        console.log(`   ✓ CPI: ${(this.currentCPI / 1e6).toFixed(3)} (${this.currentCPI}) | Annual Inflation: ${(this.currentAnnualInflation * 100).toFixed(2)}%`);
        console.log(`   ✓ FFR: ${(this.currentFFR / 100).toFixed(2)}% (${this.currentFFR} bps)`);
    }

    /**
     * Simulate BTC price change
     */
    simulateBTCPriceChange(scenario) {
        // Geometric Brownian Motion
        const drift = scenario.btcDrift;
        const volatility = scenario.btcVolatility;
        const randomShock = (Math.random() - 0.5) * 2; // -1 to 1

        const priceChange = this.currentBTCPrice * (drift + volatility * randomShock);
        const newPrice = Math.max(1000, this.currentBTCPrice + priceChange); // Minimum $1000

        return Math.round(newPrice);
    }

    /**
     * Simulate CPI change
     * Randomly generates 1%-5% annual inflation rate each month
     */
    simulateCPIChange(scenario) {
        // Randomly generate 1%-5% annual inflation rate
        const minAnnualInflation = 0.01; // 1%
        const maxAnnualInflation = 0.05; // 5%
        const randomAnnualInflation = minAnnualInflation + Math.random() * (maxAnnualInflation - minAnnualInflation);

        // Save current annual inflation rate (for display)
        this.currentAnnualInflation = randomAnnualInflation;

        // Convert annual inflation rate to monthly inflation rate
        // Formula: monthlyRate = (1 + annualRate)^(1/12) - 1
        const monthlyRate = Math.pow(1 + randomAnnualInflation, 1/12) - 1;

        // Apply monthly inflation rate to CPI
        const newCPI = Math.floor(this.currentCPI * (1 + monthlyRate));

        console.log(`   📊 CPI Update: Annual Inflation=${(randomAnnualInflation * 100).toFixed(2)}%, Monthly=${(monthlyRate * 100).toFixed(3)}%`);

        return newCPI;
    }

    /**
     * Simulate FFR change
     */
    simulateFFRChange(scenario) {
        // FFR typically adjusts in 25 basis point increments
        const changes = [-50, -25, 0, 25, 50]; // Basis points
        const randomChange = changes[Math.floor(Math.random() * changes.length)];

        const newFFR = Math.max(0, Math.min(2000, this.currentFFR + randomChange)); // 0-20% range
        return newFFR;
    }

    /**
     * Update BTC price (sync Chainlink and Uniswap)
     */
    async updateBTCPrice(newPriceUSD) {
        // Update Chainlink price oracle (8 decimal precision)
        const chainlinkPrice = Math.floor(newPriceUSD * 1e8);
        await this.btcPriceFeed.setAnswer(chainlinkPrice);

        // Synchronously update WBTC/USDC Uniswap pool reserves
        const wbtcReserve = BigInt("100000000000"); // 1000 WBTC (8 decimals)
        const usdcReserve = BigInt(Math.floor(newPriceUSD * 1000 * 1e6)); // Corresponding USDC (6 decimals)
        await this.wbtcUsdcPair.setReserves(wbtcReserve, usdcReserve);

        this.currentBTCPrice = newPriceUSD;
    }

    /**
     * Update CPI
     */
    async updateCPI(lastCPI, currentCPI) {
        await this.cpiOracle.setSimpleCPI(lastCPI, currentCPI);
        this.currentCPI = currentCPI;
    }

    /**
     * Update FFR (if FFR oracle exists)
     */
    async updateFFR(newFFR) {
        // Note: In the current system, FFR is manually set via InterestPool
        // Here we only update internal state; actual application requires calling InterestPool.setBTDRate()
        this.currentFFR = newFFR;
    }

    /**
     * Manually set BTC price
     */
    async setBTCPrice(price) {
        await this.updateBTCPrice(price);
        this.recordPrice("MANUAL_BTC_SET", { price });
        console.log(`   💹 BTC price manually set to: $${price.toLocaleString()}`);
    }

    /**
     * Manually set CPI
     */
    async setCPI(cpi) {
        await this.updateCPI(this.currentCPI, cpi);
        this.recordPrice("MANUAL_CPI_SET", { cpi });
        console.log(`   💹 CPI manually set to: ${(cpi / 1e6).toFixed(3)} (${cpi})`);
    }

    /**
     * Manually set FFR
     */
    async setFFR(ffr) {
        await this.updateFFR(ffr);
        this.recordPrice("MANUAL_FFR_SET", { ffr });
        console.log(`   💹 FFR manually set to: ${(ffr / 100).toFixed(2)}% (${ffr} bps)`);
    }

    /**
     * Switch price scenario
     */
    setScenario(scenarioName) {
        if (!this.scenarios[scenarioName]) {
            throw new Error(`Unknown scenario: ${scenarioName}`);
        }

        this.currentScenario = scenarioName;
        this.recordPrice("SCENARIO_CHANGED", { scenario: scenarioName });
        console.log(`   📊 Price scenario switched to: ${scenarioName}`);
    }

    /**
     * Simulate price crash
     */
    async simulateCrash(crashPercent = 30) {
        const newPrice = Math.floor(this.currentBTCPrice * (1 - crashPercent / 100));
        await this.setBTCPrice(newPrice);
        this.recordPrice("CRASH_SIMULATED", { crashPercent, newPrice });
        console.log(`   ⚠️  Simulated price crash -${crashPercent}%: $${this.currentBTCPrice.toLocaleString()} → $${newPrice.toLocaleString()}`);
    }

    /**
     * Simulate price surge
     */
    async simulatePump(pumpPercent = 50) {
        const newPrice = Math.floor(this.currentBTCPrice * (1 + pumpPercent / 100));
        await this.setBTCPrice(newPrice);
        this.recordPrice("PUMP_SIMULATED", { pumpPercent, newPrice });
        console.log(`   📈 Simulated price surge +${pumpPercent}%: $${this.currentBTCPrice.toLocaleString()} → $${newPrice.toLocaleString()}`);
    }

    /**
     * Get all current prices
     */
    getCurrentPrices() {
        return {
            btc: this.currentBTCPrice,
            cpi: this.currentCPI,
            ffr: this.currentFFR,
            annualInflation: this.currentAnnualInflation,
            cpiFormatted: (this.currentCPI / 1e6).toFixed(3),
            ffrFormatted: (this.currentFFR / 100).toFixed(2) + "%",
            inflationFormatted: (this.currentAnnualInflation * 100).toFixed(2) + "%"
        };
    }

    /**
     * Record price to history
     */
    recordPrice(event, extra = {}) {
        const record = {
            timestamp: Date.now(),
            event: event,
            btc: this.currentBTCPrice,
            cpi: this.currentCPI,
            ffr: this.currentFFR,
            annualInflation: this.currentAnnualInflation,
            scenario: this.currentScenario,
            ...extra
        };

        this.priceHistory.push(record);

        // Keep history at reasonable length
        if (this.priceHistory.length > 10000) {
            this.priceHistory.shift();
        }
    }

    /**
     * Get price history
     */
    getPriceHistory(limit = 100) {
        return this.priceHistory.slice(-limit);
    }

    /**
     * Print price statistics
     */
    printPriceStats() {
        if (this.priceHistory.length < 2) {
            console.log("\n   Insufficient price data to display statistics");
            return;
        }

        const btcPrices = this.priceHistory.map(r => r.btc);
        const minBTC = Math.min(...btcPrices);
        const maxBTC = Math.max(...btcPrices);
        const avgBTC = btcPrices.reduce((a, b) => a + b, 0) / btcPrices.length;

        console.log("\n📊 Price Statistics:");
        console.log(`   BTC Price:`);
        console.log(`      Current: $${this.currentBTCPrice.toLocaleString()}`);
        console.log(`      Minimum: $${minBTC.toLocaleString()}`);
        console.log(`      Maximum: $${maxBTC.toLocaleString()}`);
        console.log(`      Average: $${Math.round(avgBTC).toLocaleString()}`);
        console.log(`   CPI: ${(this.currentCPI / 1e6).toFixed(3)}`);
        console.log(`   Annual Inflation Rate: ${(this.currentAnnualInflation * 100).toFixed(2)}% (1%-5% random)`);
        console.log(`   FFR: ${(this.currentFFR / 100).toFixed(2)}%`);
        console.log(`   Scenario: ${this.currentScenario}`);
        console.log(`   History Records: ${this.priceHistory.length}`);
        console.log("");
    }

    /**
     * Get state snapshot
     */
    getState() {
        return {
            currentPrices: this.getCurrentPrices(),
            scenario: this.currentScenario,
            monthsPassed: this.monthsPassed,
            historyLength: this.priceHistory.length,
            recentHistory: this.getPriceHistory(10)
        };
    }

    /**
     * Export price history to CSV
     */
    exportHistoryCSV(filePath) {
        const fs = require('fs');
        const header = "Timestamp,Event,BTC_Price,CPI,FFR,Annual_Inflation,Scenario\n";
        const rows = this.priceHistory.map(r =>
            `${r.timestamp},${r.event},${r.btc},${r.cpi},${r.ffr},${r.annualInflation || 0},${r.scenario}`
        ).join("\n");

        fs.writeFileSync(filePath, header + rows);
        console.log(`   💾 Price history exported to: ${filePath}`);
    }
}

module.exports = PriceFeeds;

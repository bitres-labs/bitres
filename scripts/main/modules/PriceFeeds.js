"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PriceFeeds = void 0;
class PriceFeeds {
    btcPrice;
    cpi;
    ffr;
    btcPriceFeed;
    cpiOracle;
    wbtcUsdcPair;
    constructor(initialBTCPrice, initialCPI, initialFFR) {
        this.btcPrice = initialBTCPrice;
        this.cpi = initialCPI;
        this.ffr = initialFFR;
    }
    /**
     * Initialize price data sources
     */
    async initialize(btcPriceFeed, cpiOracle, wbtcUsdcPair) {
        // Prices are already set during contract deployment, just record references here
        this.btcPriceFeed = btcPriceFeed;
        this.cpiOracle = cpiOracle;
        this.wbtcUsdcPair = wbtcUsdcPair;
    }
    /**
     * Update BTC price
     */
    async updateBTCPrice(newPrice) {
        this.btcPrice = newPrice;
        if (this.btcPriceFeed) {
            const priceWithDecimals = BigInt(Math.floor(newPrice * 1e8));
            await this.btcPriceFeed.write.setPrice([priceWithDecimals]);
        }
    }
    /**
     * Update CPI
     */
    async updateCPI(newCPI) {
        this.cpi = newCPI;
        if (this.cpiOracle) {
            await this.cpiOracle.write.setSimpleCPI([BigInt(newCPI), BigInt(newCPI)]);
        }
    }
    /**
     * Get state
     */
    getState() {
        return {
            btcPrice: this.btcPrice,
            cpi: this.cpi,
            ffr: this.ffr
        };
    }
}
exports.PriceFeeds = PriceFeeds;

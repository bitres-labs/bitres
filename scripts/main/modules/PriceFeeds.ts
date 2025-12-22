/**
 * Price data source module
 * Manages BTC, CPI, FFR and related price data
 */
import type { Address } from "viem";

export class PriceFeeds {
    private btcPrice: number;
    private cpi: number;
    private ffr: number;
    private btcPriceFeed: any;
    private cpiOracle: any;
    private wbtcUsdcPair: any;

    constructor(initialBTCPrice: number, initialCPI: number, initialFFR: number) {
        this.btcPrice = initialBTCPrice;
        this.cpi = initialCPI;
        this.ffr = initialFFR;
    }

    /**
     * Initialize price sources
     */
    async initialize(btcPriceFeed: any, cpiOracle: any, wbtcUsdcPair: any) {
        // Prices are set at deployment; store references here
        this.btcPriceFeed = btcPriceFeed;
        this.cpiOracle = cpiOracle;
        this.wbtcUsdcPair = wbtcUsdcPair;
    }

    /**
     * Update BTC price
     */
    async updateBTCPrice(newPrice: number) {
        this.btcPrice = newPrice;
        if (this.btcPriceFeed) {
            const priceWithDecimals = BigInt(Math.floor(newPrice * 1e8));
            await this.btcPriceFeed.write.setPrice([priceWithDecimals]);
        }
    }

    /**
     * Update CPI
     */
    async updateCPI(newCPI: number) {
        this.cpi = newCPI;
        if (this.cpiOracle) {
            await this.cpiOracle.write.setSimpleCPI([BigInt(newCPI), BigInt(newCPI)]);
        }
    }

    /**
     * Get current state
     */
    getState() {
        return {
            btcPrice: this.btcPrice,
            cpi: this.cpi,
            ffr: this.ffr
        };
    }
}

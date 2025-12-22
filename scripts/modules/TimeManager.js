/**
 * Time Management Module
 *
 * Features:
 * 1. Provides accelerated simulated time flow
 * 2. Unified management of blockchain time advancement
 * 3. Records time events and milestones
 */

const { ethers } = require("hardhat");

class TimeManager {
    constructor(accelerationFactor = 1) {
        this.accelerationFactor = accelerationFactor; // Default 1x (real time, no acceleration)
        this.startTime = null;
        this.startBlock = null;
        this.elapsedRealSeconds = 0;
        this.events = []; // Time event records

        // Auto time sync related
        this.autoSyncEnabled = false;  // Default disabled (real time mode)
        this.lastRealTimestamp = null; // Last real timestamp (milliseconds)
        this.lastSyncTime = null;      // Last synced block time
    }

    /**
     * Initialize time system
     */
    async initialize() {
        this.startTime = await this.getCurrentBlockTime();
        this.startBlock = await ethers.provider.getBlockNumber();
        this.elapsedRealSeconds = 0;

        // Record real time starting point
        this.lastRealTimestamp = Date.now();
        this.lastSyncTime = this.startTime;

        this.logEvent("TIME_SYSTEM_INITIALIZED", {
            startTime: this.startTime,
            startBlock: this.startBlock,
            accelerationFactor: this.accelerationFactor,
            autoSyncEnabled: this.autoSyncEnabled,
            realTimestamp: this.lastRealTimestamp
        });

        return this.startTime;
    }

    /**
     * Enable/disable auto time sync
     */
    setAutoSync(enabled) {
        this.autoSyncEnabled = enabled;
        console.log(`   ⏰ Auto Time Sync: ${enabled ? 'Enabled' : 'Disabled'}`);
    }

    /**
     * Auto sync time (based on real time elapsed)
     * Call before each interaction
     */
    async autoSyncTime() {
        if (!this.autoSyncEnabled) {
            return { synced: false, reason: 'disabled' };
        }

        if (!this.lastRealTimestamp) {
            // First call, initialize
            this.lastRealTimestamp = Date.now();
            this.lastSyncTime = await this.getCurrentBlockTime();
            return { synced: false, reason: 'first_call' };
        }

        // Calculate real time elapsed (milliseconds)
        const nowRealMs = Date.now();
        const realElapsedMs = nowRealMs - this.lastRealTimestamp;
        const realElapsedSeconds = Math.floor(realElapsedMs / 1000);

        // If real time elapsed is less than 1 second, don't sync
        if (realElapsedSeconds < 1) {
            return { synced: false, reason: 'too_short', realElapsed: realElapsedMs };
        }

        // Calculate how much simulated time should advance (real seconds × acceleration factor)
        const simulatedSeconds = realElapsedSeconds * this.accelerationFactor;

        // Advance blockchain time
        await ethers.provider.send("evm_increaseTime", [simulatedSeconds]);
        await ethers.provider.send("evm_mine");

        const newBlockTime = await this.getCurrentBlockTime();

        // Update records
        this.lastRealTimestamp = nowRealMs;
        this.lastSyncTime = newBlockTime;
        this.elapsedRealSeconds += realElapsedSeconds;

        this.logEvent("AUTO_TIME_SYNC", {
            realElapsedSeconds: realElapsedSeconds,
            simulatedSeconds: simulatedSeconds,
            accelerationFactor: this.accelerationFactor,
            newBlockTime: newBlockTime,
            blockNumber: await ethers.provider.getBlockNumber()
        });

        return {
            synced: true,
            realElapsedSeconds: realElapsedSeconds,
            simulatedSeconds: simulatedSeconds,
            simulatedDays: (simulatedSeconds / 86400).toFixed(2),
            newBlockTime: newBlockTime
        };
    }

    /**
     * Advance time
     * @param {number} seconds - Simulated seconds to advance
     * @returns {Promise<number>} New timestamp
     */
    async advanceTime(seconds) {
        const realSeconds = Math.floor(seconds / this.accelerationFactor);

        // Use Hardhat's time control
        await ethers.provider.send("evm_increaseTime", [seconds]);
        await ethers.provider.send("evm_mine");

        this.elapsedRealSeconds += realSeconds;

        const newTime = await this.getCurrentBlockTime();

        this.logEvent("TIME_ADVANCED", {
            simulatedSeconds: seconds,
            realSeconds: realSeconds,
            newTimestamp: newTime,
            blockNumber: await ethers.provider.getBlockNumber()
        });

        return newTime;
    }

    /**
     * Advance specified hours
     */
    async advanceHours(hours) {
        return await this.advanceTime(hours * 3600);
    }

    /**
     * Advance specified days
     */
    async advanceDays(days) {
        return await this.advanceTime(days * 86400);
    }

    /**
     * Advance specified weeks
     */
    async advanceWeeks(weeks) {
        return await this.advanceTime(weeks * 7 * 86400);
    }

    /**
     * Advance specified months (calculated as 30 days)
     */
    async advanceMonths(months) {
        return await this.advanceTime(months * 30 * 86400);
    }

    /**
     * Advance specified years (calculated as 365 days)
     */
    async advanceYears(years) {
        return await this.advanceTime(years * 365 * 86400);
    }

    /**
     * Get current block time
     */
    async getCurrentBlockTime() {
        const blockNumber = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNumber);
        return block.timestamp;
    }

    /**
     * Get current simulated time (formatted)
     */
    async getCurrentTime() {
        const timestamp = await this.getCurrentBlockTime();
        return this.formatTimestamp(timestamp);
    }

    /**
     * Get elapsed simulated time since start
     */
    async getElapsedTime() {
        const currentTime = await this.getCurrentBlockTime();
        const elapsed = currentTime - this.startTime;

        return {
            totalSeconds: elapsed,
            days: Math.floor(elapsed / 86400),
            hours: Math.floor((elapsed % 86400) / 3600),
            minutes: Math.floor((elapsed % 3600) / 60),
            formatted: this.formatDuration(elapsed)
        };
    }

    /**
     * Set to specific time point
     */
    async setTime(timestamp) {
        const currentTime = await this.getCurrentBlockTime();
        const diff = timestamp - currentTime;

        if (diff < 0) {
            throw new Error("Cannot set time to the past");
        }

        await this.advanceTime(diff);

        this.logEvent("TIME_SET", {
            targetTimestamp: timestamp,
            difference: diff
        });

        return timestamp;
    }

    /**
     * Log time event
     */
    logEvent(eventType, data) {
        const event = {
            type: eventType,
            timestamp: Date.now(),
            realElapsed: this.elapsedRealSeconds,
            data: data
        };

        this.events.push(event);

        // Keep event list at reasonable length
        if (this.events.length > 1000) {
            this.events.shift();
        }
    }

    /**
     * Get event history
     */
    getEvents(limit = 100) {
        return this.events.slice(-limit);
    }

    /**
     * Format timestamp
     */
    formatTimestamp(timestamp) {
        const date = new Date(timestamp * 1000);
        return date.toISOString().replace('T', ' ').substring(0, 19);
    }

    /**
     * Format duration
     */
    formatDuration(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;

        const parts = [];
        if (days > 0) parts.push(`${days} days`);
        if (hours > 0) parts.push(`${hours} hours`);
        if (minutes > 0) parts.push(`${minutes} minutes`);
        if (secs > 0 || parts.length === 0) parts.push(`${secs} seconds`);

        return parts.join(' ');
    }

    /**
     * Calculate real time consumption after acceleration
     */
    getRealTimeElapsed(simulatedSeconds) {
        return simulatedSeconds / this.accelerationFactor;
    }

    /**
     * Get state snapshot
     */
    async getState() {
        const currentTime = await this.getCurrentBlockTime();
        const blockNumber = await ethers.provider.getBlockNumber();

        return {
            accelerationFactor: this.accelerationFactor,
            startTime: this.startTime,
            startBlock: this.startBlock,
            currentTime: currentTime,
            currentBlock: blockNumber,
            elapsedSimulatedSeconds: currentTime - this.startTime,
            elapsedRealSeconds: this.elapsedRealSeconds,
            autoSyncEnabled: this.autoSyncEnabled,
            lastRealTimestamp: this.lastRealTimestamp,
            lastSyncTime: this.lastSyncTime,
            recentEvents: this.getEvents(10)
        };
    }

    /**
     * Restore from saved state
     */
    restoreState(savedState) {
        if (savedState.startTime) this.startTime = savedState.startTime;
        if (savedState.startBlock) this.startBlock = savedState.startBlock;
        if (savedState.elapsedRealSeconds) this.elapsedRealSeconds = savedState.elapsedRealSeconds;
        if (savedState.autoSyncEnabled !== undefined) this.autoSyncEnabled = savedState.autoSyncEnabled;
        if (savedState.lastRealTimestamp) this.lastRealTimestamp = savedState.lastRealTimestamp;
        if (savedState.lastSyncTime) this.lastSyncTime = savedState.lastSyncTime;

        console.log(`   ✓ TimeManager state restored`);
        if (this.lastRealTimestamp) {
            const elapsed = Math.floor((Date.now() - this.lastRealTimestamp) / 1000);
            console.log(`   ✓ Time since last interaction: ${elapsed} seconds ago`);
        }
    }

    /**
     * Print status report
     */
    async printStatus() {
        const state = await this.getState();
        const elapsed = await this.getElapsedTime();

        console.log("\n⏰ Time System Status:");
        console.log(`   Acceleration Factor: ${this.accelerationFactor}x`);
        console.log(`   Start Time: ${this.formatTimestamp(state.startTime)}`);
        console.log(`   Current Time: ${this.formatTimestamp(state.currentTime)}`);
        console.log(`   Block Height: ${state.currentBlock} (Start: ${state.startBlock})`);
        console.log(`   Simulated Elapsed: ${elapsed.formatted}`);
        console.log(`   Real Elapsed: ${this.formatDuration(state.elapsedRealSeconds)}`);
        console.log("");
    }

    /**
     * Create time snapshot (for rollback)
     */
    async createSnapshot() {
        const snapshotId = await ethers.provider.send("evm_snapshot");
        const currentTime = await this.getCurrentBlockTime();

        this.logEvent("SNAPSHOT_CREATED", {
            snapshotId: snapshotId,
            timestamp: currentTime
        });

        return snapshotId;
    }

    /**
     * Revert to snapshot
     */
    async revertToSnapshot(snapshotId) {
        await ethers.provider.send("evm_revert", [snapshotId]);

        this.logEvent("SNAPSHOT_REVERTED", {
            snapshotId: snapshotId
        });
    }

    /**
     * Wait for specified simulated time and print progress
     */
    async waitWithProgress(seconds, label = "Waiting") {
        const steps = 10;
        const stepTime = Math.floor(seconds / steps);

        for (let i = 1; i <= steps; i++) {
            await this.advanceTime(stepTime);
            const progress = (i / steps * 100).toFixed(0);
            process.stdout.write(`\r   ${label}: ${progress}%`);
        }
        console.log(" ✓");
    }
}

module.exports = TimeManager;

/**
 * State Manager Module
 *
 * Features:
 * 1. Save and load system state
 * 2. Record system events and operation history
 * 3. Generate state reports
 * 4. Provide state rollback capability
 */

const fs = require('fs');
const path = require('path');

class StateManager {
    constructor(stateFilePath) {
        this.stateFilePath = stateFilePath;
        this.currentState = null;
        this.stateHistory = [];
        this.events = [];
        this.snapshots = new Map();
    }

    /**
     * Save state to file
     */
    async saveState(state) {
        const timestamp = Date.now();
        const stateWithMeta = {
            ...state,
            savedAt: timestamp,
            version: "1.0.0"
        };

        this.currentState = stateWithMeta;

        // Save to history
        this.stateHistory.push({
            timestamp: timestamp,
            state: JSON.parse(JSON.stringify(stateWithMeta)) // Deep copy
        });

        // Keep history at reasonable length
        if (this.stateHistory.length > 100) {
            this.stateHistory.shift();
        }

        // Write to file
        const stateDir = path.dirname(this.stateFilePath);
        if (!fs.existsSync(stateDir)) {
            fs.mkdirSync(stateDir, { recursive: true });
        }

        fs.writeFileSync(
            this.stateFilePath,
            JSON.stringify(stateWithMeta, null, 2),
            'utf8'
        );

        this.logEvent("STATE_SAVED", { timestamp });
    }

    /**
     * Load state from file
     */
    async loadState() {
        if (!fs.existsSync(this.stateFilePath)) {
            throw new Error(`State file not found: ${this.stateFilePath}`);
        }

        const stateJSON = fs.readFileSync(this.stateFilePath, 'utf8');
        this.currentState = JSON.parse(stateJSON);

        this.logEvent("STATE_LOADED", { timestamp: this.currentState.savedAt });

        return this.currentState;
    }

    /**
     * Get current state
     */
    getCurrentState() {
        return this.currentState;
    }

    /**
     * Create state snapshot
     */
    createSnapshot(snapshotName) {
        if (!this.currentState) {
            throw new Error("No current state to snapshot");
        }

        const snapshot = {
            name: snapshotName,
            timestamp: Date.now(),
            state: JSON.parse(JSON.stringify(this.currentState))
        };

        this.snapshots.set(snapshotName, snapshot);

        this.logEvent("SNAPSHOT_CREATED", { name: snapshotName });

        console.log(`   📸 Snapshot created: ${snapshotName}`);

        return snapshotName;
    }

    /**
     * Restore to snapshot
     */
    async restoreSnapshot(snapshotName) {
        if (!this.snapshots.has(snapshotName)) {
            throw new Error(`Snapshot not found: ${snapshotName}`);
        }

        const snapshot = this.snapshots.get(snapshotName);
        this.currentState = snapshot.state;

        await this.saveState(this.currentState);

        this.logEvent("SNAPSHOT_RESTORED", { name: snapshotName });

        console.log(`   ↩️  Restored to snapshot: ${snapshotName}`);
    }

    /**
     * List all snapshots
     */
    listSnapshots() {
        return Array.from(this.snapshots.values()).map(s => ({
            name: s.name,
            timestamp: s.timestamp,
            date: new Date(s.timestamp).toISOString()
        }));
    }

    /**
     * Log event
     */
    logEvent(eventType, data = {}) {
        const event = {
            type: eventType,
            timestamp: Date.now(),
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
    getEvents(limit = 100, filterType = null) {
        let events = this.events;

        if (filterType) {
            events = events.filter(e => e.type === filterType);
        }

        return events.slice(-limit);
    }

    /**
     * Generate state report
     */
    async generateReport(outputPath = null) {
        if (!this.currentState) {
            throw new Error("No state to report");
        }

        const report = {
            generatedAt: new Date().toISOString(),
            systemInfo: {
                blockNumber: this.currentState.blockNumber,
                timestamp: this.currentState.timestamp,
                savedAt: this.currentState.savedAt
            },
            contracts: this.currentState.contracts,
            accounts: this.currentState.accounts,
            config: this.currentState.config,
            timeManager: this.currentState.timeManager,
            priceFeeds: this.currentState.priceFeeds,
            statistics: {
                totalEvents: this.events.length,
                totalSnapshots: this.snapshots.size,
                stateHistoryLength: this.stateHistory.length
            }
        };

        if (outputPath) {
            fs.writeFileSync(
                outputPath,
                JSON.stringify(report, null, 2),
                'utf8'
            );
            console.log(`   📄 State report generated: ${outputPath}`);
        }

        return report;
    }

    /**
     * Print state summary
     */
    printSummary() {
        if (!this.currentState) {
            console.log("   ⚠️  No current state");
            return;
        }

        console.log("\n📊 System State Summary:");
        console.log(`   Block Height: ${this.currentState.blockNumber}`);
        console.log(`   Saved At: ${new Date(this.currentState.savedAt).toISOString()}`);
        console.log(`   Contract Count: ${Object.keys(this.currentState.contracts || {}).length}`);
        console.log(`   Account Count: ${(this.currentState.accounts?.users || []).length}`);
        console.log(`   Total Events: ${this.events.length}`);
        console.log(`   Snapshot Count: ${this.snapshots.size}`);

        if (this.currentState.timeManager) {
            console.log(`\n   ⏰ Time System:`);
            console.log(`      Current Time: ${this.currentState.timeManager.currentTime}`);
            console.log(`      Current Block: ${this.currentState.timeManager.currentBlock}`);
            console.log(`      Acceleration Factor: ${this.currentState.timeManager.accelerationFactor}x`);
        }

        if (this.currentState.priceFeeds) {
            const prices = this.currentState.priceFeeds.currentPrices;
            console.log(`\n   💹 Current Prices:`);
            console.log(`      BTC: $${prices.btc?.toLocaleString()}`);
            console.log(`      CPI: ${prices.cpiFormatted}`);
            console.log(`      FFR: ${prices.ffrFormatted}`);
        }

        console.log("");
    }

    /**
     * Export complete history
     */
    exportHistory(outputDir) {
        if (!fs.existsSync(outputDir)) {
            fs.mkdirSync(outputDir, { recursive: true });
        }

        // Export state history
        const stateHistoryPath = path.join(outputDir, 'state-history.json');
        fs.writeFileSync(
            stateHistoryPath,
            JSON.stringify(this.stateHistory, null, 2),
            'utf8'
        );

        // Export event history
        const eventsPath = path.join(outputDir, 'events.json');
        fs.writeFileSync(
            eventsPath,
            JSON.stringify(this.events, null, 2),
            'utf8'
        );

        // Export snapshot list
        const snapshotsPath = path.join(outputDir, 'snapshots.json');
        const snapshotsList = Array.from(this.snapshots.entries());
        fs.writeFileSync(
            snapshotsPath,
            JSON.stringify(snapshotsList, null, 2),
            'utf8'
        );

        console.log(`\n   💾 History data exported to: ${outputDir}`);
        console.log(`      - State History: ${this.stateHistory.length} records`);
        console.log(`      - Event Records: ${this.events.length} records`);
        console.log(`      - Snapshot Count: ${this.snapshots.size}`);
        console.log("");
    }

    /**
     * Clean up old data
     */
    cleanup(keepDays = 7) {
        const cutoffTime = Date.now() - (keepDays * 24 * 60 * 60 * 1000);

        // Clean up state history
        this.stateHistory = this.stateHistory.filter(
            s => s.timestamp > cutoffTime
        );

        // Clean up events
        this.events = this.events.filter(
            e => e.timestamp > cutoffTime
        );

        // Clean up snapshots
        for (const [name, snapshot] of this.snapshots.entries()) {
            if (snapshot.timestamp < cutoffTime) {
                this.snapshots.delete(name);
            }
        }

        console.log(`   🧹 Cleaned up data older than ${keepDays} days`);
    }

    /**
     * Validate state integrity
     */
    validateState(state = this.currentState) {
        const requiredFields = ['contracts', 'accounts', 'config', 'timestamp'];
        const missing = [];

        for (const field of requiredFields) {
            if (!state || !state[field]) {
                missing.push(field);
            }
        }

        if (missing.length > 0) {
            throw new Error(`State validation failed. Missing fields: ${missing.join(', ')}`);
        }

        return true;
    }

    /**
     * Get state diff
     */
    getStateDiff(oldState, newState) {
        const diff = {
            added: [],
            removed: [],
            changed: []
        };

        // Compare contract addresses
        const oldContracts = new Set(Object.keys(oldState.contracts || {}));
        const newContracts = new Set(Object.keys(newState.contracts || {}));

        for (const name of newContracts) {
            if (!oldContracts.has(name)) {
                diff.added.push({ type: 'contract', name });
            } else if (oldState.contracts[name] !== newState.contracts[name]) {
                diff.changed.push({
                    type: 'contract',
                    name,
                    old: oldState.contracts[name],
                    new: newState.contracts[name]
                });
            }
        }

        for (const name of oldContracts) {
            if (!newContracts.has(name)) {
                diff.removed.push({ type: 'contract', name });
            }
        }

        return diff;
    }

    /**
     * Backup current state file
     */
    backup() {
        if (!fs.existsSync(this.stateFilePath)) {
            console.log("   ⚠️  No state file to backup");
            return null;
        }

        const timestamp = Date.now();
        const backupPath = this.stateFilePath.replace('.json', `.backup.${timestamp}.json`);

        fs.copyFileSync(this.stateFilePath, backupPath);

        console.log(`   💾 State backed up to: ${backupPath}`);

        return backupPath;
    }
}

module.exports = StateManager;

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TimeManager = void 0;
/**
 * Time Management Module
 * Used for time acceleration in test environments
 */
class TimeManager {
    accelerationFactor;
    startTime;
    constructor(accelerationFactor = 1) {
        this.accelerationFactor = accelerationFactor;
        this.startTime = Math.floor(Date.now() / 1000);
    }
    /**
     * Get current time (accelerated)
     */
    async getCurrentTime() {
        const now = Math.floor(Date.now() / 1000);
        return new Date((this.startTime + (now - this.startTime) * this.accelerationFactor) * 1000).toISOString();
    }
    /**
     * Get state
     */
    getState() {
        return {
            accelerationFactor: this.accelerationFactor,
            startTime: this.startTime,
            currentTime: Math.floor(Date.now() / 1000)
        };
    }
}
exports.TimeManager = TimeManager;

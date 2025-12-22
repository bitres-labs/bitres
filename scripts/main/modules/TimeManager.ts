/**
 * Time management module
 * Provides time acceleration for test environments
 */
export class TimeManager {
    private accelerationFactor: number;
    private startTime: number;

    constructor(accelerationFactor: number = 1) {
        this.accelerationFactor = accelerationFactor;
        this.startTime = Math.floor(Date.now() / 1000);
    }

    /**
     * Get current (accelerated) time
     */
    async getCurrentTime(): Promise<string> {
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

/**
 * State management module
 * Saves and loads system state
 */
import fs from "fs";

export class StateManager {
    private stateFilePath: string;

    constructor(stateFilePath: string) {
        this.stateFilePath = stateFilePath;
    }

    /**
     * Save state to file
     */
    async saveState(state: any): Promise<void> {
        const stateJSON = JSON.stringify(state, null, 2);
        fs.writeFileSync(this.stateFilePath, stateJSON, 'utf8');
    }

    /**
     * Load state from file
     */
    async loadState(): Promise<any | null> {
        if (!fs.existsSync(this.stateFilePath)) {
            return null;
        }
        const stateJSON = fs.readFileSync(this.stateFilePath, 'utf8');
        return JSON.parse(stateJSON);
    }

    /**
     * Check if state file exists
     */
    stateExists(): boolean {
        return fs.existsSync(this.stateFilePath);
    }
}

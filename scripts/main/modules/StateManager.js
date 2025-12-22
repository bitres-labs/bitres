"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.StateManager = void 0;
/**
 * State Management Module
 * Used for saving and loading system state
 */
const fs_1 = __importDefault(require("fs"));
class StateManager {
    stateFilePath;
    constructor(stateFilePath) {
        this.stateFilePath = stateFilePath;
    }
    /**
     * Save state to file
     */
    async saveState(state) {
        const stateJSON = JSON.stringify(state, null, 2);
        fs_1.default.writeFileSync(this.stateFilePath, stateJSON, 'utf8');
    }
    /**
     * Load state from file
     */
    async loadState() {
        if (!fs_1.default.existsSync(this.stateFilePath)) {
            return null;
        }
        const stateJSON = fs_1.default.readFileSync(this.stateFilePath, 'utf8');
        return JSON.parse(stateJSON);
    }
    /**
     * Check if state file exists
     */
    stateExists() {
        return fs_1.default.existsSync(this.stateFilePath);
    }
}
exports.StateManager = StateManager;

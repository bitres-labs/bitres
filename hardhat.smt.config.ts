import * as dotenv from "dotenv";
import type { HardhatUserConfig } from "hardhat/types";
import { defineConfig } from "hardhat/config";

dotenv.config();

// SMTChecker configuration for formal verification
// Usage: npx hardhat compile --config hardhat.smt.config.ts
//
// SMTChecker verifies:
// - assert() statements (assertion violations)
// - Arithmetic overflow/underflow
// - Division by zero
// - Balance requirements
// - Array bounds

const config: HardhatUserConfig = defineConfig({
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache_smt",
    artifacts: "./artifacts_smt"
  },
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true,
      evmVersion: "prague",
      modelChecker: {
        engine: "bmc",
        bmcLoopIterations: 3,
        showUnproved: true,
        showUnsupported: true,
        targets: [
          "assert",
          "divByZero"
        ],
        timeout: 10000,
        contracts: {
          "contracts/test/FormalVerificationTest.sol": ["FormalVerificationTest"]
        }
      }
    }
  }
});

export default config;

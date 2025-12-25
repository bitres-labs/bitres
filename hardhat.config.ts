import * as dotenv from "dotenv";
import type { HardhatUserConfig } from "hardhat/types";
import { defineConfig } from "hardhat/config";
import hardhatToolboxViem from "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-network-helpers";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-ignition";
import "@nomicfoundation/hardhat-ignition-ethers";
// import "solidity-coverage"; // Waiting for Hardhat 3.x compatible release; using custom analysis script for now

console.log("Loading Hardhat config...");

dotenv.config();

const { SEPOLIA_RPC_URL, SEPOLIA_PRIVATE_KEY, ETHERSCAN_API_KEY } = process.env;

const config: HardhatUserConfig = defineConfig({
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  solidity: {
    compilers: [
      {
        version: "0.8.30",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
          viaIR: true,
          evmVersion: "prague"
        }
      }
    ],
    overrides: {
      // SMTChecker configuration for formal verification
      // Run with: npx hardhat compile --config hardhat.smt.config.ts
      "contracts/libraries/CollateralMath.sol": {
        version: "0.8.30",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          viaIR: true,
          evmVersion: "prague"
        }
      }
    }
  },
  networks: {
    hardhat: {
      type: "edr-simulated",
      mining: {
        auto: true,
        interval: 2000
      }
    },
    localhost: {
      type: "http",
      url: "http://127.0.0.1:8545",
      timeout: 60000
    },
    sepolia: {
      type: "http",
      url: SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
      accounts: SEPOLIA_PRIVATE_KEY ? [SEPOLIA_PRIVATE_KEY] : [],
      chainId: 11155111,
      timeout: 120000
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY || ""
  },
  mocha: {
    timeout: 120000
  },
  plugins: [hardhatToolboxViem]
});

export default config;

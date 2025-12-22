# Bitres (Bitcoin Reserve System)

<div align="center">

**A Decentralized Stablecoin System Backed by Bitcoin**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.30-orange.svg)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Built%20with-Hardhat-yellow.svg)](https://hardhat.org/)

[Whitepaper](./whitepaper/whitepaper_complete.pdf) | [Documentation](./docs/)

</div>

---

## Project Overview

Bitres (Bitcoin Reserve System) is an innovative decentralized stablecoin protocol that uses Bitcoin (BTC) as collateral to issue BTD, a stablecoin pegged to the "Ideal USD" (IUSD). The system ensures price stability through a three-tier asset defense mechanism (BTC → BTB → BRS) and implements community-driven on-chain governance.

### Key Features

- **Bitcoin Collateral** - Every BTD is backed by BTC value
- **Ideal USD Peg** - Pegged to Ideal USD with 2% annual inflation adjustment, providing inflation resistance
- **Three-tier Defense** - BTC collateral + BTB bonds + BRS backstop for multi-layer protection
- **Dual Yield** - stToken vaults provide auto-compounding interest + BRS mining rewards
- **Decentralized Governance** - On-chain governance mechanism based on BRS token
- **Modular Architecture** - Separation of core and governance configurations for flexible upgrades

---

## Core Concepts

### Ideal USD (IUSD)

Ideal USD is the system's pricing anchor, representing a dollar that depreciates at a stable 2% annual inflation rate:

```
IUSD/USD = PCEn / (PCE0 x 1.02^(n/12))
```

- **PCE0**: Personal Consumption Expenditures Price Index at system launch month
- **PCEn**: Current month's Personal Consumption Expenditures Price Index
- **n**: Months since system launch

Compared to the volatile real dollar, IUSD is more stable and predictable. From 1960 to 2025, the Ideal USD appreciated approximately 3x against the real dollar.

### Three-Token System

| Token | Name | Symbol | Type | Supply | Risk Level | Yield Source |
|-------|------|--------|------|--------|------------|--------------|
| **Stablecoin** | Bitcoin Dollar | BTD | ERC20 | Unlimited | Low | Deposit rate (follows FFR) |
| **Bond** | Bitcoin Bond | BTB | ERC20 | Unlimited | Medium | Bond rate (dynamic adjustment) |
| **Governance** | Bitres Token | BRS | ERC20 | 2.1B (halving) | High | Mining rewards + Governance + Fee buyback |

---

## System Architecture

### Core Contracts

```
contracts/
├── BTD.sol                    # Stablecoin (ERC20 + Burnable + AccessControl)
├── BTB.sol                    # Bond token (ERC20 + Burnable + AccessControl)
├── BRS.sol                    # Governance token (ERC20, 2.1B fixed supply)
├── Minter.sol                 # Mint/redeem core business logic
├── Treasury.sol               # Treasury (manages WBTC and BRS reserves)
├── FarmingPool.sol            # Liquidity mining pool (10 pools)
├── InterestPool.sol           # Interest pool (BTD/BTB staking for interest)
├── stBTD.sol / stBTB.sol      # ERC4626 vaults (dual yield)
├── PriceOracle.sol            # Price oracle (TWAP + Chainlink + Pyth + Redstone)
├── ConfigCore.sol             # Core configuration (immutable addresses)
├── ConfigGov.sol              # Governance configuration (mutable parameters)
├── Governor.sol               # On-chain governance (OpenZeppelin Governor)
├── IdealUSDManager.sol        # IUSD pricing management
├── StakingRouter.sol          # Staking router (simplified user operations)
└── libraries/                 # Utility libraries (math, logic modules)
```

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   User Interaction Layer                 │
│  Mint BTD  │  Redeem BTD  │  Stake Mining  │  Governance │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   Core Business Layer                    │
│  Minter  │  FarmingPool  │  InterestPool  │  Governor   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   Asset Management Layer                 │
│  Treasury (WBTC/BRS)  │  stBTD/stBTB Vaults             │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   Data Service Layer                     │
│  PriceOracle  │  IdealUSDManager  │  Config             │
└─────────────────────────────────────────────────────────┘
```

---

## Core Mechanisms

### 1. Minting

Users deposit WBTC to mint BTD stablecoin:

```solidity
// Minting formula
btdAmount = wbtcAmount x (btcPrice / iusdPrice)

// Fee (1%, governance adjustable)
fee = btdAmount x 0.01  // Additional minting, stored in Treasury
```

**Process:**
1. User approves and transfers WBTC to Treasury
2. System calculates BTD amount at real-time exchange rate
3. Mint BTD and transfer to user
4. Mint additional 1% fee to Treasury

### 2. Redemption

Burn BTD to redeem WBTC. Three scenarios based on collateral ratio:

#### Scenario A: Collateral Ratio ≥ 100%

```
1 BTD → (iusdPrice / btcPrice) WBTC
```

#### Scenario B: Collateral Ratio < 100% and BTB Price ≥ Floor Price (0.5 BTD)

```
1 BTD → x WBTC + y BTB

Where:
x = btcReserve / btdSupply
y = (1 - collateralRatio) x iusdPrice / btbPrice
```

#### Scenario C: Collateral Ratio < 100% and BTB Price < Floor Price

```
1 BTD → x WBTC + y BTB + z BRS

Where:
x = btcReserve / btdSupply
y = (1 - CR) x iusdPrice / 0.5  // Mint BTB at floor price
z = (1 - CR) x iusdPrice x (0.5 - btbPrice) / (0.5 x brsPrice)  // BRS compensation
```

**Three-tier Defense:**
1. **First tier**: BTC collateral (priority return)
2. **Second tier**: Newly minted BTB bonds (deferred redemption)
3. **Third tier**: Treasury BRS reserves (final backstop)

### 3. Bond Redemption

When collateral ratio recovers above 100%, BTB holders can redeem 1:1 for BTD:

```
Redeemable amount = (collateralRatio - 1) x btdSupply
```

First-come-first-served basis, collateral ratio returns to 100% after redemption.

### 4. Interest Mechanism (stToken Vaults)

ERC4626 tokenized vault standard for dual yield:

```
BTD/BTB → stBTD/stBTB (vault deposit)
         ↓
    Share price auto-appreciation (interest compounding)
         ↓
    stToken → FarmingPool (further staking)
         ↓
    Earn BRS mining rewards
```

**Interest Rate Policy:**
- **BTD Rate**: Follows Federal Funds Target Rate (default)
- **BTB Rate**: Dynamic adjustment, target price range 0.99-1.01 BTD

| BTB Price | Trend | Rate Adjustment |
|-----------|-------|-----------------|
| < 0.99 BTD | Falling | Increase rate |
| < 0.99 BTD | Rising | Hold |
| 0.99-1.01 BTD | Any | Hold |
| > 1.01 BTD | Rising | Decrease rate |
| > 1.01 BTD | Falling | Hold |

### 5. Mining Mechanism

BRS total supply 2.1 billion, distributed through four-year halving mechanism:

- **First cycle**: 1.05 billion (~8.33 BRS/second)
- **Every 4 years**: Output halves
- **Distribution ratio**:
  - Stakers 60% (distributed via 10 pools)
  - Treasury 20%
  - Foundation 10%
  - Team 10%

**Pool Configuration (Initial):**

| ID | Type | Token | Weight | Share |
|----|------|-------|--------|-------|
| 0 | LP | BRS/BTD | 15 | 25% |
| 1 | LP | BTD/USDC | 15 | 25% |
| 2 | LP | BTB/BTD | 15 | 25% |
| 3 | Single | USDC | 1 | 1.7% |
| 4 | Single | USDT | 1 | 1.7% |
| 5 | Single | WBTC | 1 | 1.7% |
| 6 | Single | WETH | 1 | 1.7% |
| 7 | Single | stBTD | 3 | 5% |
| 8 | Single | stBTB | 3 | 5% |
| 9 | Single | BRS | 5 | 8.3% |

---

## On-chain Governance

Complete DAO governance based on OpenZeppelin Governor standard:

### Governance Process

```
1. Proposal creation (requires 250,000 BRS)
   ↓
2. Voting delay (1 day) - Voting power snapshot
   ↓
3. Voting period (7 days) - Community voting (For/Against/Abstain)
   ↓
4. Quorum check (≥4% total supply participation + For votes > Against votes)
   ↓
5. Timelock queue (2 days) - Community review period
   ↓
6. Proposal execution - Anyone can trigger
```

### Governance Scope

- Economic parameter adjustment (fees, rate caps, BTB floor price, etc.)
- Pool weight configuration (add/remove/adjust)
- ConfigGov parameter updates
- Role permission management
- Oracle configuration
- Emergency operations (pause Minter)

---

## Quick Start

### Requirements

- Node.js >= 18.0.0
- npm >= 9.0.0
- Hardhat

### Install Dependencies

```bash
npm install
```

### Compile Contracts

```bash
npx hardhat compile
```

### Run Tests

```bash
# Run all tests
npx hardhat test

# Run specific test file
npx hardhat test test/Minter.viem.test.ts

# Run Foundry fuzz tests
forge test

# View Gas report
REPORT_GAS=true npx hardhat test
```

### Local Deployment

```bash
# Start local node
npx hardhat node

# Deploy contracts via Hardhat Ignition
npx hardhat ignition deploy ignition/modules/FullSystem.ts --network localhost

# Initialize system (prices, pools, liquidity)
npx hardhat run scripts/main/init-full-system.mjs --network localhost
```

### Testnet Deployment

```bash
# Sepolia testnet
npx hardhat ignition deploy ignition/modules/FullSystem.ts --network sepolia

# Verify contract
npx hardhat verify --network sepolia <CONTRACT_ADDRESS>
```

---

## Development Guide

### Project Structure

```
bitres/
├── contracts/              # Smart contracts
│   ├── interfaces/         # Interface definitions
│   ├── extensions/         # Extensions (blocklist, custodian)
│   ├── libraries/          # Utility libraries (math, logic)
│   └── local/              # Test contracts (Mocks)
├── scripts/                # Deployment and management scripts
│   └── main/               # Main scripts (guardian, init)
├── test/                   # Hardhat test files
├── forge-test/             # Foundry fuzz tests
├── ignition/               # Hardhat Ignition deployment modules
├── hardhat.config.ts       # Hardhat configuration
└── package.json            # Project dependencies
```

### Contract Interaction Examples

#### Mint BTD

```javascript
const { ethers } = require("hardhat");

async function mintBTD() {
  const [user] = await ethers.getSigners();

  // Get contract instances
  const wbtc = await ethers.getContractAt("IERC20", WBTC_ADDRESS);
  const minter = await ethers.getContractAt("Minter", MINTER_ADDRESS);

  // Approve and mint
  const wbtcAmount = ethers.parseUnits("0.1", 8); // 0.1 WBTC
  await wbtc.approve(MINTER_ADDRESS, wbtcAmount);
  await minter.mintBTD(wbtcAmount);

  console.log("BTD minting successful!");
}
```

#### Stake for Dual Yield

```javascript
async function stakeBTD() {
  const [user] = await ethers.getSigners();

  const btd = await ethers.getContractAt("BTD", BTD_ADDRESS);
  const router = await ethers.getContractAt("StakingRouter", ROUTER_ADDRESS);

  // One-click stake via Router (BTD → stBTD → FarmingPool)
  const amount = ethers.parseEther("1000");
  await btd.approve(ROUTER_ADDRESS, amount);
  await router.stakeBTD(amount);

  // User now enjoys:
  // 1. BTD deposit interest (via stBTD share price appreciation)
  // 2. BRS mining rewards (stBTD staked in FarmingPool)
}
```

#### Create Governance Proposal

```javascript
async function createProposal() {
  const [proposer] = await ethers.getSigners();
  const governor = await ethers.getContractAt("Governor", GOVERNOR_ADDRESS);
  const config = await ethers.getContractAt("Config", CONFIG_ADDRESS);

  // Proposal: Change BTD minting fee to 0.5%
  const targets = [CONFIG_ADDRESS];
  const values = [0];
  const calldatas = [
    config.interface.encodeFunctionData("setMintFeeRate", [50]) // 50 basis points = 0.5%
  ];
  const description = "Reduce BTD minting fee to 0.5% to improve user experience";

  const tx = await governor.propose(targets, values, calldatas, description);
  const receipt = await tx.wait();

  console.log("Proposal created successfully! Proposal ID:", proposalId);
}
```

### Key Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mintFeeRate` | 100 bp (1%) | BTD minting fee |
| `minBTBPrice` | 0.5 BTD | BTB floor price |
| `maxBTBInterestRate` | 2000 bp (20%) | BTB maximum annual rate |
| `interestFeeRate` | 1000 bp (10%) | Interest fee |
| `priceDeviationTolerance` | 100 bp (1%) | Price deviation tolerance |

---

## Security

### Security Mechanisms

- OpenZeppelin standard contract library
- ReentrancyGuard protection
- Pausable emergency stop (Minter)
- AccessControl role permissions
- Timelock protection (2-day delay)
- Multi-oracle price validation

### Multi-layer Protection

1. **Price Security**: Multi-oracle validation (Chainlink + Pyth + Redstone + DEX TWAP), reject transaction if deviation exceeds threshold
2. **Permission Management**: Fine-grained role control, critical operations require governance authorization
3. **Emergency Response**: Pausable Minter contract for emergency situations
4. **Configuration Security**: Separation of immutable core config and governable parameters
5. **Compliance Support**: Custodian account mechanism for exchange KYC requirements

### Risk Warnings

- **Smart Contract Risk**: Despite rigorous testing, unknown vulnerabilities may exist
- **Market Risk**: Severe BTC price volatility may cause undercollateralization
- **Oracle Risk**: Reliance on external data sources creates manipulation possibilities
- **Governance Risk**: Malicious proposals may affect system parameters through voting

---

## Documentation

### Core Documents

- [Complete Whitepaper](./whitepaper/whitepaper_complete.pdf) - System design philosophy and economic model

### Technical Documents

- TWAP Integration Guide
- Governance Parameters Documentation
- Oracle Deployment Guide
- Security Audit Report

---

## Contributing

We welcome community contributions! Please follow this process:

1. Fork this repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

### Development Standards

- Follow Solidity style guide
- New features must include tests
- Update relevant documentation
- Pass all CI checks

---

## License

This project is open source under the [MIT License](LICENSE).

---

## Contact

- **GitHub**: [bitres-labs/bitres](https://github.com/bitres-labs/bitres)
- **Documentation**: [docs](./docs/)
- **Whitepaper**: [whitepaper](./whitepaper/)

---

## Acknowledgments

Bitres is built on these excellent open source projects:

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - Secure smart contract standard library
- [Hardhat](https://hardhat.org/) - Ethereum development environment
- [Chainlink](https://chain.link/) - Decentralized oracle network
- [Uniswap V2](https://uniswap.org/) - Decentralized exchange protocol

---

<div align="center">

**Building a More Stable Bitcoin Monetary System**

Made with care by Bitres Labs

</div>

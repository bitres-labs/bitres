// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Constants - BRS System Global Constants Library
 * @notice Centralized management of system-level immutable constants
 * @dev Uses library + internal constant to ensure compile-time inlining (zero gas overhead)
 *
 * Key features:
 * - internal constant is inlined by the compiler into contracts that use it
 * - Gas cost = 16 gas (same as local constant)
 * - Unified management, single source of truth
 * - Type-safe, compile-time checking
 */
library Constants {
    // ============ Precision Constants ============

    /// @notice 18 decimals precision (standard ERC20, USD prices)
    uint256 internal constant PRECISION_18 = 1e18;

    /// @notice 8 decimals precision (BTC)
    uint256 internal constant PRECISION_8 = 1e8;

    /// @notice 6 decimals precision (USDC/USDT)
    uint256 internal constant PRECISION_6 = 1e6;

    // ============ Precision Conversion Scale Constants ============

    /// @notice WBTC (8 decimals) to normalized (18 decimals) scale factor
    /// @dev 10^(18-8) = 1e10, used for explicit precision conversion, avoiding runtime EXP calculation
    uint256 internal constant SCALE_WBTC_TO_NORM = 1e10;

    /// @notice USDC (6 decimals) to normalized (18 decimals) scale factor
    /// @dev 10^(18-6) = 1e12, used for explicit precision conversion
    uint256 internal constant SCALE_USDC_TO_NORM = 1e12;

    /// @notice USDT (6 decimals) to normalized (18 decimals) scale factor
    /// @dev 10^(18-6) = 1e12, used for explicit precision conversion (same as USDC)
    uint256 internal constant SCALE_USDT_TO_NORM = 1e12;

    // Note: For normalized -> native conversion, use division by the same scale factor:
    // - Normalized to WBTC: amount / SCALE_WBTC_TO_NORM
    // - Normalized to USDC: amount / SCALE_USDC_TO_NORM
    // - Normalized to USDT: amount / SCALE_USDT_TO_NORM

    // ============ Minimum Operation Amount Constants ============

    /// @notice Minimum BTC operation amount per transaction (8 decimals)
    /// @dev 1 satoshi, prevents dust attacks
    uint256 internal constant MIN_BTC_AMOUNT = 1;

    /// @notice Minimum ETH operation amount per transaction (18 decimals)
    /// @dev 1e-8 ETH = 1e10 wei (0.00000001 ETH)
    uint256 internal constant MIN_ETH_AMOUNT = 1e10;

        /// @notice Minimum USD value for operations (18 decimals)
    /// @dev Used in Minter, Treasury, and other scenarios involving USD value conversion
    /// $0.001 USD, prevents dust attacks and precision loss
    ///
    /// Use cases:
    /// - Minter.mintBTD(): Check mint USD value >= $0.001
    /// - Minter.redeemBTD(): Check redeem USD value >= $0.001
    /// - Treasury.buyback(): Check buyback USD value >= $0.001
    uint256 internal constant MIN_USD_VALUE = 1e15;

    /// @notice Minimum operation amount for 6-decimal stablecoins
    /// @dev 0.001 USDC/USDT = 1000 units (6 decimals), prevents dust attacks
    /// Applicable to: USDC, USDT
    uint256 internal constant MIN_STABLECOIN_6_AMOUNT = 1000;

    /// @notice Minimum operation amount for 18-decimal stablecoins
    /// @dev 0.001 tokens = 1e15 (18 decimals), prevents dust attacks
    /// Applicable to: BTD, BTB, stBTD, stBTB
    ///
    /// Use cases:
    /// - InterestPool.stake(): Minimum stake amount for BTD/BTB
    /// - StakingRouter: Minimum stake amount for stBTD/stBTB
    uint256 internal constant MIN_STABLECOIN_18_AMOUNT = 1e15;

    // ============ Maximum Single Operation Limits (Prevents Hacker Attacks and Overflow) ============

    /// @notice Maximum WBTC amount per single operation
    /// @dev 10,000 BTC (8 decimals = 10000 * 1e8)
    /// Prevents hacker attacks and integer overflow, applies to all WBTC transfer/mint/redeem operations
    uint256 internal constant MAX_WBTC_AMOUNT = 10_000 * 1e8;

    /// @notice Maximum ETH amount per single operation
    /// @dev 100,000 ETH (18 decimals = 100000 * 1e18)
    /// Prevents hacker attacks and integer overflow
    uint256 internal constant MAX_ETH_AMOUNT = 100_000 * 1e18;

    /// @notice Maximum 6-decimal stablecoin amount per single operation
    /// @dev 1 billion USDC/USDT (6 decimals = 1000000000 * 1e6)
    /// Prevents hacker attacks and integer overflow
    /// Applicable to: USDC, USDT
    uint256 internal constant MAX_STABLECOIN_6_AMOUNT = 1_000_000_000 * 1e6;

    /// @notice Maximum 18-decimal stablecoin amount per single operation
    /// @dev 1 billion BTD/BTB/stBTD/stBTB (18 decimals = 1000000000 * 1e18)
    /// Prevents hacker attacks and integer overflow
    /// Applicable to: BTD, BTB, stBTD, stBTB and other 18-decimal stablecoins
    uint256 internal constant MAX_STABLECOIN_18_AMOUNT = 1_000_000_000 * 1e18;

    /// @notice Basis points base (10000 = 100.00%)
    uint256 internal constant BPS_BASE = 10000;

    // ============ Time Constants ============

    /// @notice Seconds per year
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @notice Seconds per day
    uint256 internal constant SECONDS_PER_DAY = 1 days;

    /// @notice BTC halving cycle (4 years)
    uint256 internal constant ERA_PERIOD = 4 * 365 days;

    // ============ Inflation Parameter Constants ============

    /// @notice Fixed annual inflation rate - 2%
    /// @dev Fixed inflation target specified in whitepaper, used for IUSD (Ideal USD) calculation
    /// 2% = 0.02 = 2e16 (18 decimals)
    uint256 internal constant ANNUAL_INFLATION_RATE = 2e16;

    /// @notice Monthly growth factor - (1.02)^(1/12)
    /// @dev Calculated from 2% annual inflation
    /// Formula: (1 + 0.02)^(1/12) = 1.001651581301920174
    /// Calculated off-chain with high precision and stored with 18 decimals
    uint256 internal constant MONTHLY_GROWTH_FACTOR = 1001651581301920174;

    // ============ Supply Constants ============

    /// @notice BRS maximum supply (2.1 billion, tribute to BTC's 21 million)
    /// @dev Maximum supply of BRS tokens, the only definition in the system
    uint256 internal constant BRS_MAX_SUPPLY = 2_100_000_000e18;
}

// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./ConfigCore.sol";
import "./ConfigGov.sol";
import {IMintableERC20} from "./interfaces/IMintableERC20.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IInterestPool} from "./interfaces/IInterestPool.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import "./libraries/Constants.sol";
import "./libraries/InterestMath.sol";
import "./libraries/SigmoidRate.sol";

/// @title InterestPool
/// @notice Manages interest accrual for BTD and BTB deposited via stBTD/stBTB vaults.
///         Users cannot interact with this contract directly - they must use stBTD/stBTB vault contracts.
///
///         BTD Deposit Rate (per whitepaper Section 7.1.3):
///         - Uses Sigmoid function: rBTD(P) = rmax * S(-α * (P - 1) + β)
///         - α = 25 (price sensitivity), rmax = 10%
///         - Base rate varies with CR: rbase = rdefault × (1 + ΔCR)
///         - Range: 2%-10%, with ΔCR = (1-CR)/0.8 when CR < 100%
///
///         BTB Bond Rate (per whitepaper Section 7.1.3):
///         - Uses Sigmoid function: rBTB(P, CR) = rmax * S(-α * (P - 1) + β(CR))
///         - α = 10 (price sensitivity), rmax = 20%
///         - Base rate has 3x ΔCR multiplier for higher risk compensation
///         - Range: 2%-20%, with ΔCR = 3×(1-CR)/0.8 when CR < 100%
///
/// @dev Only stBTD and stBTB vault contracts are authorized to call deposit/withdraw functions.
contract InterestPool is Ownable, ReentrancyGuard, IInterestPool {
    using SafeERC20 for IMintableERC20;

    // Fallback default rate when gov parameter is not set (5% = 500 bps)
    uint256 private constant FALLBACK_DEFAULT_RATE_BPS = 500;

    ConfigCore public immutable core;
    ConfigGov public gov;
    address public rateOracle; // Oracle address allowed to update rates

    struct Pool {
        IMintableERC20 token;
        uint256 totalStaked;
        uint256 accInterestPerShare; // Accumulated interest per token, scaled by 1e18
        uint256 lastAccrual;
        uint256 annualRateBps; // Current APR in basis points
    }

    struct UserInfo {
        uint256 amount; // Staked principal
        uint256 rewardDebt; // Tracks distributed interest
    }

    Pool public btdPool;
    Pool public btbPool;

    mapping(address => UserInfo) private btdUsers;
    mapping(address => UserInfo) private btbUsers;

    // BTD price tracking (for whitepaper-compliant rate adjustment)
    uint256 public btdLastPrice; // Last recorded BTD/IUSD price ratio (18 decimals)
    uint256 public btdLastRateUpdate; // Timestamp of the last BTD rate adjustment

    // BTB price tracking
    uint256 public btbLastPrice; // Last recorded BTB price in BTD (18 decimals)
    uint256 public btbLastRateUpdate; // Timestamp of the last BTB rate adjustment

    event RateOracleUpdated(address indexed newOracle);
    event TreasuryFeeMinted(address indexed token, uint256 amount);
    event LazyRateUpdateAttempted(bool btdUpdated, bool btbUpdated);

    modifier onlyRateOracle() {
        require(msg.sender == rateOracle, "InterestPool: only rate oracle");
        _;
    }

    constructor(
        address initialOwner,
        address _core,
        address _gov,
        address _rateOracle
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "InterestPool: invalid owner");
        require(_core != address(0), "InterestPool: core zero");
        require(_gov != address(0), "InterestPool: gov zero");
        require(_rateOracle != address(0), "InterestPool: rate oracle zero");
        core = ConfigCore(_core);
        gov = ConfigGov(_gov);
        rateOracle = _rateOracle;

        address btdAddress = core.BTD();
        address btbAddress = core.BTB();
        require(btdAddress != address(0) && btbAddress != address(0), "Token addresses not set");

        btdPool = Pool({
            token: IMintableERC20(btdAddress),
            totalStaked: 0,
            accInterestPerShare: 0,
            lastAccrual: block.timestamp,
            annualRateBps: FALLBACK_DEFAULT_RATE_BPS  // Initial rate = fallback default rate
        });

        btbPool = Pool({
            token: IMintableERC20(btbAddress),
            totalStaked: 0,
            accInterestPerShare: 0,
            lastAccrual: block.timestamp,
            annualRateBps: FALLBACK_DEFAULT_RATE_BPS  // Initial rate = fallback default rate
        });

    }

    // --- User-facing staking functions removed ---
    // Users should interact via stBTD/stBTB vault contracts instead of directly with InterestPool

    /// @notice Gets current BTB price
    /// @dev Reads TWAP-protected BTB price from PriceOracle
    /// @return BTB price in BTD terms, precision 1e18
    function getBTBPrice() external view returns (uint256) {
        return _currentBTBPrice();
    }

    // --- Rate management ---

    /// @notice Upgrades governance contract
    /// @dev Only contract owner can call, core addresses in ConfigCore cannot be changed
    /// @param newGov New ConfigGov contract address
    function upgradeGov(address newGov) external onlyOwner {
        require(newGov != address(0), "Invalid gov");
        gov = ConfigGov(newGov);
    }

    /// @notice Sets rate oracle address
    /// @dev Only contract owner can call
    /// @param newOracle New rate oracle address
    function setRateOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "InterestPool: zero oracle");
        rateOracle = newOracle;
        emit RateOracleUpdated(newOracle);
    }

    /// @notice Dynamically updates BTD annual rate (APR) based on BTD/IUSD price and CR
    /// @dev Per whitepaper Section 7.1.3:
    ///      - Uses Sigmoid function: rBTD(P) = rmax * S(-α * (P - 1) + β)
    ///      - α = 25, rmax = 10%, base rate varies with CR
    ///      - Range: 2%-10%, with ΔCR = (1-CR)/0.8 when CR < 100%
    ///      Can only adjust once per day. Only rate oracle can call.
    function updateBTDAnnualRate() external onlyRateOracle {
        if (btdLastRateUpdate != 0) {
            require(block.timestamp >= btdLastRateUpdate + Constants.SECONDS_PER_DAY, "BTD rate already updated today");
        }

        _accruePool(btdPool);

        // Get BTD/IUSD price ratio (18 decimals, 1e18 = 1.0)
        uint256 price = _currentBTDPriceInIUSD();

        // Get collateral ratio from Minter (18 decimals, 1e18 = 100%)
        uint256 cr = _getCollateralRatio();

        // Get default base rate from governance (with fallback)
        uint256 defaultRateBps = _getDefaultRate();

        uint256 oldRate = btdPool.annualRateBps;

        // Calculate new rate using Sigmoid function with CR adjustment
        uint256 newRate = SigmoidRate.calculateBTDRate(price, cr, defaultRateBps);

        // Apply governance cap if set
        uint256 maxRate = gov.maxBTDRate();
        if (maxRate > 0 && newRate > maxRate) {
            newRate = maxRate;
        }

        btdPool.annualRateBps = newRate;
        btdLastPrice = price;
        btdLastRateUpdate = block.timestamp;

        emit BTDAnnualRateUpdated(oldRate, newRate);
    }

    /// @notice Gets current BTD/IUSD price ratio
    /// @dev BTD/IUSD = BTD_USD_Price / IUSD_Price
    ///      Returns 1e18 when BTD = 1 IUSD (perfect peg)
    /// @return BTD/IUSD price ratio (18 decimals, 1e18 = 1.0)
    function _currentBTDPriceInIUSD() internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(core.PRICE_ORACLE());
        uint256 btdPriceUSD = oracle.getBTDPrice();  // BTD market price in USD
        uint256 iusdPrice = oracle.getIUSDPrice();   // IUSD price in USD

        if (iusdPrice == 0) {
            return Constants.PRECISION_18; // Default to 1.0 if IUSD price unavailable
        }

        // BTD/IUSD = BTD_USD / IUSD_USD
        return (btdPriceUSD * Constants.PRECISION_18) / iusdPrice;
    }

    /// @notice Updates BTB annual rate (APR)
    /// @dev Per whitepaper Section 7.1.3:
    ///      - Uses Sigmoid function: rBTB(P, CR) = rmax * S(-α * (P - 1) + β(CR))
    ///      - α = 10, rmax = 20%
    ///      - Base rate has 3x ΔCR multiplier: rbase = rdefault × (1 + 3×ΔCR)
    ///      - Range: 2%-20%, with ΔCR = (1-CR)/0.8 when CR < 100%
    ///      Can only adjust once per day. Only rate oracle can call.
    function updateBTBAnnualRate() external onlyRateOracle {
        if (btbLastRateUpdate != 0) {
            require(block.timestamp >= btbLastRateUpdate + Constants.SECONDS_PER_DAY, "BTB rate already updated today");
        }

        _accruePool(btbPool);

        // Get BTB/BTD price (18 decimals, 1e18 = 1.0)
        uint256 price = _currentBTBPrice();

        // Get collateral ratio from Minter (18 decimals, 1e18 = 100%)
        uint256 cr = _getCollateralRatio();

        // Get default base rate from governance (with fallback)
        uint256 defaultRateBps = _getDefaultRate();

        uint256 oldRate = btbPool.annualRateBps;

        // Calculate new rate using Sigmoid function with CR adjustment
        uint256 newRate = SigmoidRate.calculateBTBRate(price, cr, defaultRateBps);

        // Apply governance cap if set
        uint256 maxRate = gov.maxBTBRate();
        if (maxRate > 0 && newRate > maxRate) {
            newRate = maxRate;
        }

        btbPool.annualRateBps = newRate;
        btbLastPrice = price;
        btbLastRateUpdate = block.timestamp;

        // Note: changeBps is no longer used in Sigmoid calculation
        emit BTBAnnualRateUpdated(oldRate, newRate, price, 0);
    }

    // --- Lazy Rate Updates (user-triggered) ---

    /// @notice Tries to update both BTD and BTB rates if enough time has passed (lazy update)
    /// @dev Can be called by anyone, designed for stake/unstake to call during user operations
    ///      Each rate can only update once per day (SECONDS_PER_DAY)
    /// @return btdUpdated True if BTD rate was actually updated
    /// @return btbUpdated True if BTB rate was actually updated
    function tryUpdateRates() external returns (bool btdUpdated, bool btbUpdated) {
        btdUpdated = _tryUpdateBTDRateInternal();
        btbUpdated = _tryUpdateBTBRateInternal();

        if (btdUpdated || btbUpdated) {
            emit LazyRateUpdateAttempted(btdUpdated, btbUpdated);
        }
    }

    /// @notice Internal function to try updating BTD rate
    /// @dev Returns false if update is not due or if calculation fails
    /// @return updated True if rate was successfully updated
    function _tryUpdateBTDRateInternal() internal returns (bool updated) {
        // Check if update is due (once per day)
        if (btdLastRateUpdate != 0 && block.timestamp < btdLastRateUpdate + Constants.SECONDS_PER_DAY) {
            return false;
        }

        // Try to update rate, fail silently on any error
        try this.updateBTDRateLazy() {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Internal function to try updating BTB rate
    /// @dev Returns false if update is not due or if calculation fails
    /// @return updated True if rate was successfully updated
    function _tryUpdateBTBRateInternal() internal returns (bool updated) {
        // Check if update is due (once per day)
        if (btbLastRateUpdate != 0 && block.timestamp < btbLastRateUpdate + Constants.SECONDS_PER_DAY) {
            return false;
        }

        // Try to update rate, fail silently on any error
        try this.updateBTBRateLazy() {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice External entry point for lazy BTD rate update (called via try-catch)
    /// @dev Only callable by this contract itself for try-catch pattern
    function updateBTDRateLazy() external {
        require(msg.sender == address(this), "Only internal call");

        _accruePool(btdPool);

        uint256 price = _currentBTDPriceInIUSD();
        uint256 cr = _getCollateralRatio();
        uint256 defaultRateBps = _getDefaultRate();

        uint256 oldRate = btdPool.annualRateBps;
        uint256 newRate = SigmoidRate.calculateBTDRate(price, cr, defaultRateBps);

        uint256 maxRate = gov.maxBTDRate();
        if (maxRate > 0 && newRate > maxRate) {
            newRate = maxRate;
        }

        btdPool.annualRateBps = newRate;
        btdLastPrice = price;
        btdLastRateUpdate = block.timestamp;

        emit BTDAnnualRateUpdated(oldRate, newRate);
    }

    /// @notice External entry point for lazy BTB rate update (called via try-catch)
    /// @dev Only callable by this contract itself for try-catch pattern
    function updateBTBRateLazy() external {
        require(msg.sender == address(this), "Only internal call");

        _accruePool(btbPool);

        uint256 price = _currentBTBPrice();
        uint256 cr = _getCollateralRatio();
        uint256 defaultRateBps = _getDefaultRate();

        uint256 oldRate = btbPool.annualRateBps;
        uint256 newRate = SigmoidRate.calculateBTBRate(price, cr, defaultRateBps);

        uint256 maxRate = gov.maxBTBRate();
        if (maxRate > 0 && newRate > maxRate) {
            newRate = maxRate;
        }

        btbPool.annualRateBps = newRate;
        btbLastPrice = price;
        btbLastRateUpdate = block.timestamp;

        emit BTBAnnualRateUpdated(oldRate, newRate, price, 0);
    }

    // --- Internal staking logic ---
    // Direct user staking functions (_stake, _withdraw, _claim) removed
    // Only stToken vault interface is supported

    function _pendingCurrent(Pool storage pool, UserInfo storage user) internal view returns (uint256) {
        return InterestMath.pendingReward(user.amount, pool.accInterestPerShare, user.rewardDebt);
    }

    function _accruePool(Pool storage pool) internal {
        if (pool.lastAccrual == block.timestamp) {
            return;
        }

        if (pool.totalStaked == 0 || pool.annualRateBps == 0) {
            pool.lastAccrual = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastAccrual;
        if (timeElapsed == 0) {
            return;
        }

        uint256 interestPerShare = InterestMath.interestPerShareDelta(pool.annualRateBps, timeElapsed);
        if (interestPerShare > 0) {
            pool.accInterestPerShare += interestPerShare;
        }

        pool.lastAccrual = block.timestamp;
    }

    function _payout(Pool storage pool, address recipient, uint256 amount) internal {
        // Mint interest to user
        pool.token.mint(recipient, amount);

        // For BTD pool, mint additional 10% fee to treasury
        if (address(pool.token) == address(btdPool.token)) {
            address treasury = core.TREASURY();
            require(treasury != address(0), "Treasury not set");
            uint256 fee = InterestMath.feeAmount(amount, 1000); // 10% = 1000 bps
            if (fee > 0) {
                pool.token.mint(treasury, fee);
                emit TreasuryFeeMinted(address(pool.token), fee);
            }
        }
    }

    // --- Price helpers ---

    /// @notice Gets BTB price from PriceOracle (TWAP protected)
    /// @dev Uses PriceOracle.getBTBPrice() for TWAP to prevent flash loan attacks
    ///      Previous version directly used Uniswap reserves (vulnerable to manipulation)
    /// @return price BTB price in USD terms, precision 1e18
    function _currentBTBPrice() internal view returns (uint256) {
        address oracleAddr = core.PRICE_ORACLE();
        require(oracleAddr != address(0), "PriceOracle not set");

        // Get TWAP-protected price from PriceOracle
        // PriceOracle.getBTBPrice() uses 30-minute TWAP when enabled (production)
        // or spot price when TWAP is disabled (testing only)
        uint256 btbPriceUSD = IPriceOracle(oracleAddr).getBTBPrice();

        // Convert from USD to BTD terms (assuming BTD ≈ $1)
        // Both are in 18 decimals, so direct return
        return btbPriceUSD;
    }

    /// @notice Gets default base rate from governance with fallback
    /// @dev Falls back to FALLBACK_DEFAULT_RATE_BPS if governance parameter is not set
    /// @return Default base rate in basis points
    function _getDefaultRate() internal view returns (uint256) {
        uint256 rate = gov.baseRateDefault();
        return rate > 0 ? rate : FALLBACK_DEFAULT_RATE_BPS;
    }

    /// @notice Gets collateral ratio from Minter
    /// @dev Returns 100% (1e18) if Minter is not available
    /// @return Collateral ratio (18 decimals, 1e18 = 100%)
    function _getCollateralRatio() internal view returns (uint256) {
        address minterAddr = core.MINTER();
        if (minterAddr == address(0)) {
            return Constants.PRECISION_18; // Default to 100%
        }

        try IMinter(minterAddr).getCollateralRatio() returns (uint256 cr) {
            return cr;
        } catch {
            return Constants.PRECISION_18; // Default to 100% on error
        }
    }

    // --- Virtual Staking Interface (for Coinbase integration) ---

    /// @notice Gets total staked amount for a specific token (for virtual pool integration)
    /// @dev Used for virtual pool integration with platforms like Coinbase
    /// @param token Token address to query
    /// @return Total staked amount, precision 1e18
    function totalStaked(address token) external view returns (uint256) {
        if (token == address(btdPool.token)) {
            return btdPool.totalStaked;
        } else if (token == address(btbPool.token)) {
            return btbPool.totalStaked;
        }
        return 0;
    }

    /// @notice Gets user's staked amount in a specific token pool (for virtual pool integration)
    /// @dev Used for virtual pool integration with platforms like Coinbase
    /// @param token Token address to query
    /// @param user User address to query
    /// @return User's staked amount, precision 1e18
    function userStaked(address token, address user) external view returns (uint256) {
        if (token == address(btdPool.token)) {
            return btdUsers[user].amount;
        } else if (token == address(btbPool.token)) {
            return btbUsers[user].amount;
        }
        return 0;
    }

    // --- stToken Vault Interface ---


    /// @notice Stakes BTD to interest pool
    /// @dev Anyone can call, automatically accrues interest and pays out pending interest
    ///      Also triggers lazy rate update if enough time has passed
    /// @param amount BTD amount to stake, precision 1e18, must be >= minimum stake amount
    function stakeBTD(uint256 amount) external nonReentrant {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Stake amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Stake amount too large");

        // Lazy rate update - silently attempt to update BTD rate if due
        _tryUpdateBTDRateInternal();

        _accruePool(btdPool);

        UserInfo storage user = btdUsers[msg.sender];
        uint256 pendingAmount = _pendingCurrent(btdPool, user);

        // CEI Pattern: Effects before Interactions
        // Update state variables BEFORE external calls to prevent reentrancy
        btdPool.token.safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        btdPool.totalStaked += amount;
        user.rewardDebt = InterestMath.rewardDebtValue(user.amount, btdPool.accInterestPerShare);

        // Interactions: External calls after state updates
        if (pendingAmount > 0) {
            _payout(btdPool, msg.sender, pendingAmount);
            emit InterestClaimed(msg.sender, address(btdPool.token), pendingAmount);
        }

        emit Staked(msg.sender, address(btdPool.token), amount);
    }

    /// @notice Stakes BTB to interest pool
    /// @dev Anyone can call, automatically accrues interest and pays out pending interest
    ///      Also triggers lazy rate update if enough time has passed
    /// @param amount BTB amount to stake, precision 1e18, must be >= minimum stake amount
    function stakeBTB(uint256 amount) external nonReentrant {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Stake amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Stake amount too large");

        // Lazy rate update - silently attempt to update BTB rate if due
        _tryUpdateBTBRateInternal();

        _accruePool(btbPool);

        UserInfo storage user = btbUsers[msg.sender];
        uint256 pendingAmount = _pendingCurrent(btbPool, user);

        // CEI Pattern: Effects before Interactions
        // Update state variables BEFORE external calls to prevent reentrancy
        btbPool.token.safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        btbPool.totalStaked += amount;
        user.rewardDebt = InterestMath.rewardDebtValue(user.amount, btbPool.accInterestPerShare);

        // Interactions: External calls after state updates
        if (pendingAmount > 0) {
            _payout(btbPool, msg.sender, pendingAmount);
            emit InterestClaimed(msg.sender, address(btbPool.token), pendingAmount);
        }

        emit Staked(msg.sender, address(btbPool.token), amount);
    }

    /// @notice Unstakes BTD
    /// @dev Anyone can call, withdrawal amount can include pending interest
    ///      Proportionally allocates interest and principal, interest portion is minted, principal portion is transferred from contract balance
    ///      Also triggers lazy rate update if enough time has passed
    /// @param amount BTD amount to unstake (can include pending interest), precision 1e18
    function unstakeBTD(uint256 amount) external nonReentrant {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Unstake amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Unstake amount too large");

        // Lazy rate update - silently attempt to update BTD rate if due
        _tryUpdateBTDRateInternal();

        _accruePool(btdPool);

        UserInfo storage user = btdUsers[msg.sender];
        uint256 pendingAmount = _pendingCurrent(btdPool, user);

        // Total available = principal + pending interest
        uint256 totalAvailable = user.amount + pendingAmount;
        require(totalAvailable >= amount, "Unstake exceeds balance");

        // Calculate interest and principal proportionally
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount,
            pendingAmount,
            totalAvailable
        );

        // Pay out interest portion
        if (interestShare > 0) {
            _payout(btdPool, msg.sender, interestShare);
            emit InterestClaimed(msg.sender, address(btdPool.token), interestShare);
        }

        // Withdraw principal portion
        if (principalShare > 0) {
            user.amount -= principalShare;
            btdPool.totalStaked -= principalShare;
            btdPool.token.safeTransfer(msg.sender, principalShare);
            emit Withdrawn(msg.sender, address(btdPool.token), principalShare);
        }

        user.rewardDebt = InterestMath.rewardDebtValue(user.amount, btdPool.accInterestPerShare);
    }

    /// @notice Unstakes BTB
    /// @dev Anyone can call, withdrawal amount can include pending interest
    ///      Proportionally allocates interest and principal, interest portion is minted, principal portion is transferred from contract balance
    ///      Also triggers lazy rate update if enough time has passed
    /// @param amount BTB amount to unstake (can include pending interest), precision 1e18
    function unstakeBTB(uint256 amount) external nonReentrant {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Unstake amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Unstake amount too large");

        // Lazy rate update - silently attempt to update BTB rate if due
        _tryUpdateBTBRateInternal();

        _accruePool(btbPool);

        UserInfo storage user = btbUsers[msg.sender];
        uint256 pendingAmount = _pendingCurrent(btbPool, user);

        // Total available = principal + pending interest
        uint256 totalAvailable = user.amount + pendingAmount;
        require(totalAvailable >= amount, "Unstake exceeds balance");

        // Calculate interest and principal proportionally
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount,
            pendingAmount,
            totalAvailable
        );

        // Pay out interest portion
        if (interestShare > 0) {
            _payout(btbPool, msg.sender, interestShare);
            emit InterestClaimed(msg.sender, address(btbPool.token), interestShare);
        }

        // Withdraw principal portion
        if (principalShare > 0) {
            user.amount -= principalShare;
            btbPool.totalStaked -= principalShare;
            btbPool.token.safeTransfer(msg.sender, principalShare);
            emit Withdrawn(msg.sender, address(btbPool.token), principalShare);
        }

        user.rewardDebt = InterestMath.rewardDebtValue(user.amount, btbPool.accInterestPerShare);
    }
}

// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
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
/// @notice Manages interest accrual for BTD/BTB via stBTD/stBTB vaults.
/// @dev Users interact via vault contracts, not directly. Rate calculation uses
///      Sigmoid functions per whitepaper Section 7.1.3.
contract InterestPool is Ownable2Step, ReentrancyGuard, IInterestPool {
    using SafeERC20 for IMintableERC20;

    uint256 private constant FALLBACK_DEFAULT_RATE_BPS = 500; // 5%
    uint256 private constant TREASURY_FEE_BPS = 1000; // 10%

    ConfigCore public immutable core;
    ConfigGov public gov;
    address public rateOracle;

    struct Pool {
        IMintableERC20 token;
        uint256 totalStaked;
        uint256 accInterestPerShare; // Scaled by 1e18
        uint256 lastAccrual;
        uint256 annualRateBps;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    Pool public btdPool;
    Pool public btbPool;
    bool public initialized;

    mapping(address => UserInfo) private btdUsers;
    mapping(address => UserInfo) private btbUsers;

    uint256 public btdLastPrice;
    uint256 public btdLastRateUpdate;
    uint256 public btbLastPrice;
    uint256 public btbLastRateUpdate;

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
    }

    /// @notice Initialize pools after ConfigCore has BTD/BTB addresses set
    function initialize() external onlyOwner {
        require(!initialized, "InterestPool: already initialized");

        address btdAddress = core.BTD();
        address btbAddress = core.BTB();
        require(btdAddress != address(0) && btbAddress != address(0), "Token addresses not set");

        btdPool = _createPool(btdAddress);
        btbPool = _createPool(btbAddress);
        initialized = true;
    }

    function _createPool(address tokenAddr) private view returns (Pool memory) {
        return Pool({
            token: IMintableERC20(tokenAddr),
            totalStaked: 0,
            accInterestPerShare: 0,
            lastAccrual: block.timestamp,
            annualRateBps: FALLBACK_DEFAULT_RATE_BPS
        });
    }

    // --- View Functions ---

    function getBTBPrice() external view returns (uint256) {
        return _currentBTBPrice();
    }

    function totalStaked(address token) external view returns (uint256) {
        (Pool storage pool,) = _getPoolAndUsers(token);
        return address(pool.token) != address(0) ? pool.totalStaked : 0;
    }

    function userStaked(address token, address user) external view returns (uint256) {
        (, mapping(address => UserInfo) storage users) = _getPoolAndUsers(token);
        return users[user].amount;
    }

    // --- Admin Functions ---

    function upgradeGov(address newGov) external onlyOwner {
        require(newGov != address(0), "Invalid gov");
        gov = ConfigGov(newGov);
    }

    function setRateOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "InterestPool: zero oracle");
        rateOracle = newOracle;
        emit RateOracleUpdated(newOracle);
    }

    // --- Rate Updates (Oracle-triggered) ---

    function updateBTDAnnualRate() external onlyRateOracle {
        _checkRateUpdateCooldown(btdLastRateUpdate);
        _updateBTDRate();
    }

    function updateBTBAnnualRate() external onlyRateOracle {
        _checkRateUpdateCooldown(btbLastRateUpdate);
        _updateBTBRate();
    }

    function _checkRateUpdateCooldown(uint256 lastUpdate) private view {
        if (lastUpdate != 0) {
            require(block.timestamp >= lastUpdate + Constants.SECONDS_PER_DAY, "Rate already updated today");
        }
    }

    function _updateBTDRate() private {
        _accruePool(btdPool);

        uint256 price = _currentBTDPriceInIUSD();
        uint256 cr = _getCollateralRatio();
        uint256 defaultRateBps = _getDefaultRate();
        uint256 oldRate = btdPool.annualRateBps;

        uint256 newRate = SigmoidRate.calculateBTDRate(price, cr, defaultRateBps);
        newRate = _applyMaxRate(newRate, gov.maxBTDRate());

        btdPool.annualRateBps = newRate;
        btdLastPrice = price;
        btdLastRateUpdate = block.timestamp;

        emit BTDAnnualRateUpdated(oldRate, newRate);
    }

    function _updateBTBRate() private {
        _accruePool(btbPool);

        uint256 price = _currentBTBPrice();
        uint256 cr = _getCollateralRatio();
        uint256 defaultRateBps = _getDefaultRate();
        uint256 oldRate = btbPool.annualRateBps;

        uint256 newRate = SigmoidRate.calculateBTBRate(price, cr, defaultRateBps);
        newRate = _applyMaxRate(newRate, gov.maxBTBRate());

        btbPool.annualRateBps = newRate;
        btbLastPrice = price;
        btbLastRateUpdate = block.timestamp;

        emit BTBAnnualRateUpdated(oldRate, newRate, price, 0);
    }

    function _applyMaxRate(uint256 rate, uint256 maxRate) private pure returns (uint256) {
        return (maxRate > 0 && rate > maxRate) ? maxRate : rate;
    }

    // --- Lazy Rate Updates ---

    function tryUpdateRates() external returns (bool btdUpdated, bool btbUpdated) {
        btdUpdated = _tryUpdateBTDRateInternal();
        btbUpdated = _tryUpdateBTBRateInternal();

        if (btdUpdated || btbUpdated) {
            emit LazyRateUpdateAttempted(btdUpdated, btbUpdated);
        }
    }

    function _tryUpdateBTDRateInternal() internal returns (bool) {
        return _tryLazyRateUpdate(btdLastRateUpdate, this.updateBTDRateLazy);
    }

    function _tryUpdateBTBRateInternal() internal returns (bool) {
        return _tryLazyRateUpdate(btbLastRateUpdate, this.updateBTBRateLazy);
    }

    function _tryLazyRateUpdate(uint256 lastUpdate, function() external updateFn) private returns (bool) {
        if (lastUpdate != 0 && block.timestamp < lastUpdate + Constants.SECONDS_PER_DAY) {
            return false;
        }
        try updateFn() {
            return true;
        } catch {
            return false;
        }
    }

    function updateBTDRateLazy() external {
        require(msg.sender == address(this), "Only internal call");
        _updateBTDRate();
    }

    function updateBTBRateLazy() external {
        require(msg.sender == address(this), "Only internal call");
        _updateBTBRate();
    }

    // --- Staking Interface ---

    function stakeBTD(uint256 amount) external nonReentrant {
        _tryUpdateBTDRateInternal();
        _stake(btdPool, btdUsers[msg.sender], amount);
        emit Staked(msg.sender, address(btdPool.token), amount);
    }

    function stakeBTB(uint256 amount) external nonReentrant {
        _tryUpdateBTBRateInternal();
        _stake(btbPool, btbUsers[msg.sender], amount);
        emit Staked(msg.sender, address(btbPool.token), amount);
    }

    function unstakeBTD(uint256 amount) external nonReentrant {
        _tryUpdateBTDRateInternal();
        _unstake(btdPool, btdUsers[msg.sender], amount);
    }

    function unstakeBTB(uint256 amount) external nonReentrant {
        _tryUpdateBTBRateInternal();
        _unstake(btbPool, btbUsers[msg.sender], amount);
    }

    function _stake(Pool storage pool, UserInfo storage user, uint256 amount) private {
        _validateStakeAmount(amount);
        _accruePool(pool);

        uint256 pendingAmount = _pendingCurrent(pool, user);

        pool.token.safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        pool.totalStaked += amount;
        user.rewardDebt = InterestMath.rewardDebtValue(user.amount, pool.accInterestPerShare);

        if (pendingAmount > 0) {
            _payout(pool, msg.sender, pendingAmount);
            emit InterestClaimed(msg.sender, address(pool.token), pendingAmount);
        }
    }

    function _unstake(Pool storage pool, UserInfo storage user, uint256 amount) private {
        _validateStakeAmount(amount);
        _accruePool(pool);

        uint256 pendingAmount = _pendingCurrent(pool, user);
        uint256 totalAvailable = user.amount + pendingAmount;
        require(totalAvailable >= amount, "Unstake exceeds balance");

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount, pendingAmount, totalAvailable
        );

        if (interestShare > 0) {
            _payout(pool, msg.sender, interestShare);
            emit InterestClaimed(msg.sender, address(pool.token), interestShare);
        }

        if (principalShare > 0) {
            user.amount -= principalShare;
            pool.totalStaked -= principalShare;
            pool.token.safeTransfer(msg.sender, principalShare);
            emit Withdrawn(msg.sender, address(pool.token), principalShare);
        }

        user.rewardDebt = InterestMath.rewardDebtValue(user.amount, pool.accInterestPerShare);
    }

    function _validateStakeAmount(uint256 amount) private pure {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Amount too large");
    }

    // --- Internal Helpers ---

    function _getPoolAndUsers(address token) private view returns (
        Pool storage pool,
        mapping(address => UserInfo) storage users
    ) {
        if (token == address(btdPool.token)) {
            return (btdPool, btdUsers);
        } else if (token == address(btbPool.token)) {
            return (btbPool, btbUsers);
        }
        return (btdPool, btdUsers); // Default fallback
    }

    function _pendingCurrent(Pool storage pool, UserInfo storage user) internal view returns (uint256) {
        return InterestMath.pendingReward(user.amount, pool.accInterestPerShare, user.rewardDebt);
    }

    function _accruePool(Pool storage pool) internal {
        if (pool.lastAccrual == block.timestamp) return;

        if (pool.totalStaked == 0 || pool.annualRateBps == 0) {
            pool.lastAccrual = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastAccrual;
        if (timeElapsed == 0) return;

        uint256 interestPerShare = InterestMath.interestPerShareDelta(pool.annualRateBps, timeElapsed);
        if (interestPerShare > 0) {
            pool.accInterestPerShare += interestPerShare;
        }
        pool.lastAccrual = block.timestamp;
    }

    function _payout(Pool storage pool, address recipient, uint256 amount) internal {
        pool.token.mint(recipient, amount);

        // BTD pool: mint 10% treasury fee
        if (address(pool.token) == address(btdPool.token)) {
            address treasury = core.TREASURY();
            require(treasury != address(0), "Treasury not set");
            uint256 fee = InterestMath.feeAmount(amount, TREASURY_FEE_BPS);
            if (fee > 0) {
                pool.token.mint(treasury, fee);
                emit TreasuryFeeMinted(address(pool.token), fee);
            }
        }
    }

    // --- Price Helpers ---

    function _currentBTDPriceInIUSD() internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(core.PRICE_ORACLE());
        uint256 btdPriceUSD = oracle.getBTDPrice();
        uint256 iusdPrice = oracle.getIUSDPrice();

        if (iusdPrice == 0) return Constants.PRECISION_18;
        return (btdPriceUSD * Constants.PRECISION_18) / iusdPrice;
    }

    function _currentBTBPrice() internal view returns (uint256) {
        address oracleAddr = core.PRICE_ORACLE();
        require(oracleAddr != address(0), "PriceOracle not set");
        return IPriceOracle(oracleAddr).getBTBPrice();
    }

    function _getDefaultRate() internal view returns (uint256) {
        uint256 rate = gov.baseRateDefault();
        return rate > 0 ? rate : FALLBACK_DEFAULT_RATE_BPS;
    }

    function _getCollateralRatio() internal view returns (uint256) {
        address minterAddr = core.MINTER();
        if (minterAddr == address(0)) return Constants.PRECISION_18;

        try IMinter(minterAddr).getCollateralRatio() returns (uint256 cr) {
            return cr;
        } catch {
            return Constants.PRECISION_18;
        }
    }
}

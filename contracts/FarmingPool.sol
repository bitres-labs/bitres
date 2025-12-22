// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFarmingPool.sol";
import "./ConfigCore.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/Constants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/RewardMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

/// @notice Minimal Farm contract: responsible for distributing pre-minted BRS, no longer has minting or pause privileges
contract FarmingPool is Ownable, ReentrancyGuard, IFarmingPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    ConfigCore public immutable core;

    uint256 public immutable override startTime;
    uint256 public override minted; // Track distributed rewards, maintain interface compatibility

    IFarmingPool.PoolInfo[] private _poolInfo;
    mapping(uint256 => mapping(address => IFarmingPool.UserInfo)) private _userInfo;
    uint256 public totalAllocPoint;

    address[] public fundAddrs;
    uint256[] public fundShares; // Percentage (base 100)
    uint256 public constant SHARE_BASE = 100;

    event RewardsFunded(address indexed from, uint256 amount);

    /** @notice Constructor */
    constructor(
        address owner_,                   // Admin address
        address rewardToken_,             // Reward token (BRS)
        address _core,                    // ConfigCore contract
        address[] memory initialFunds,    // Initial fund addresses
        uint256[] memory initialShares    // Fund shares (base 100)
    ) Ownable(owner_) {
        require(owner_ != address(0), "FarmingPool: invalid owner");
        require(rewardToken_ != address(0), "FarmingPool: zero reward");
        require(_core != address(0), "FarmingPool: zero core");
        rewardToken = IERC20(rewardToken_);
        core = ConfigCore(_core);
        startTime = block.timestamp;
        _setFunds(initialFunds, initialShares);
    }

    // ============ Fund Management ============

    /// @notice Gets BRS reward token address
    /// @dev For interface compatibility
    /// @return BRS token contract address
    function brs() external view override returns (address) {
        return address(rewardToken);
    }

    /// @notice Fund provider injects reward tokens
    /// @dev Anyone can call to inject BRS rewards into FarmingPool
    /// @param amount Amount of BRS to inject, precision 1e18
    function fundRewards(uint256 amount) external {
        require(amount > 0, "FarmingPool: amount zero");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(msg.sender, amount);
    }

    /// @notice Sets fund shares
    /// @dev Only contract owner can call, sets reward distribution ratio to funds
    /// @param addrs Fund address array
    /// @param shares Share ratio array (base 100), total cannot exceed 100
    function setFunds(address[] calldata addrs, uint256[] calldata shares) external onlyOwner {
        _setFunds(addrs, shares);
    }

    function _setFunds(address[] memory addrs, uint256[] memory shares) internal {
        require(addrs.length == shares.length, "FarmingPool: length mismatch");
        uint256 sum;
        for (uint256 i = 0; i < shares.length; i++) {
            sum += shares[i];
        }
        require(sum <= SHARE_BASE, "FarmingPool: shares exceed 100%");
        fundAddrs = addrs;
        fundShares = shares;
    }

    // ============ Pool Management ============

    /// @notice Gets pool count
    /// @dev Returns the total number of pools currently added
    /// @return Total pool count
    function poolLength() external view override returns (uint256) {
        return _poolInfo.length;
    }

    /// @notice Gets pool detailed information
    /// @dev Returns all configuration parameters and status for the specified pool
    /// @param pid Pool ID
    /// @return lpToken Staking token address
    /// @return allocPoint Allocation points (determines reward weight)
    /// @return lastRewardTime Timestamp of last reward calculation
    /// @return accRewardPerShare Accumulated reward per share, precision 1e18
    /// @return totalStaked Total staked amount
    /// @return cachedLPValuePerToken Cached LP token unit price (LP pools only)
    /// @return lastPriceUpdate Timestamp of last price update
    /// @return kind Pool type (LP or single token)
    function poolInfo(uint256 pid)
        external
        view
        override
        returns (
            IERC20 lpToken,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 accRewardPerShare,
            uint256 totalStaked,
            uint256 cachedLPValuePerToken,
            uint256 lastPriceUpdate,
            PoolKind kind
        )
    {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        return (
            pool.lpToken,
            pool.allocPoint,
            pool.lastRewardTime,
            pool.accRewardPerShare,
            pool.totalStaked,
            pool.cachedLPValuePerToken,
            pool.lastPriceUpdate,
            pool.kind
        );
    }

    /// @notice Gets pool type
    /// @dev Returns whether the pool is an LP pool or single token pool
    /// @param pid Pool ID
    /// @return Pool type (LP or Single)
    function poolKind(uint256 pid) external view override returns (PoolKind) {
        return _poolInfo[pid].kind;
    }

    /// @notice Gets user staking info for a specific pool
    /// @dev Returns user's staked amount and reward debt
    /// @param pid Pool ID
    /// @param user User address
    /// @return amount User's staked amount, precision 1e18
    /// @return rewardDebt Reward debt, used for calculating pending rewards
    function userInfo(uint256 pid, address user)
        external
        view
        override
        returns (uint256 amount, uint256 rewardDebt)
    {
        IFarmingPool.UserInfo storage info = _userInfo[pid][user];
        return (info.amount, info.rewardDebt);
    }

    /// @notice Adds new pool (optional immediate batch update)
    /// @dev Only contract owner can call, adds a new staking pool
    /// @param token Staking token address (LP or single token)
    /// @param allocPoint Allocation points, determines the pool's weight in total rewards
    /// @param kind Pool type (LP or Single)
    /// @param withUpdate Whether to batch update all pools before adding
    function addPool(
        IERC20 token,
        uint256 allocPoint,
        PoolKind kind,
        bool withUpdate
    ) external override onlyOwner {
        _addPoolInternal(allocPoint, token, kind, withUpdate);
    }

    /// @notice Adds new pool (default no batch update)
    /// @dev Only contract owner can call, adds new pool without triggering batch update
    /// @param token Staking token address
    /// @param allocPoint Allocation points
    /// @param kind Pool type
    function addPool(IERC20 token, uint256 allocPoint, PoolKind kind) external override onlyOwner {
        _addPoolInternal(allocPoint, token, kind, false);
    }

    /// @notice Batch adds pools
    /// @dev Only contract owner can call, adds multiple pools at once
    /// @param tokens Staking token address array
    /// @param allocPoints Allocation points array
    /// @param kinds Pool type array
    function addPools(
        IERC20[] calldata tokens,
        uint256[] calldata allocPoints,
        PoolKind[] calldata kinds
    ) external override onlyOwner {
        require(tokens.length == allocPoints.length, "FarmingPool: length mismatch");
        require(tokens.length == kinds.length, "FarmingPool: kind mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            _addPoolInternal(allocPoints[i], tokens[i], kinds[i], false);
        }
    }

    function _addPoolInternal(
        uint256 allocPoint,
        IERC20 token,
        PoolKind kind,
        bool withUpdate
    ) internal {
        if (withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint += allocPoint;
        _poolInfo.push(
            IFarmingPool.PoolInfo({
                lpToken: token,
                allocPoint: allocPoint,
                lastRewardTime: block.timestamp,
                accRewardPerShare: 0,
                totalStaked: 0,
                cachedLPValuePerToken: 0,
                lastPriceUpdate: 0,
                kind: kind
            })
        );
    }

    /// @notice Modifies pool allocation points
    /// @dev Only contract owner can call, adjusts the pool's reward weight
    /// @param pid Pool ID
    /// @param allocPoint New allocation points
    /// @param withUpdate Whether to batch update all pools before modifying
    function setPool(uint256 pid, uint256 allocPoint, bool withUpdate) external override onlyOwner {
        if (withUpdate) {
            massUpdatePools();
        }
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        totalAllocPoint = totalAllocPoint - pool.allocPoint + allocPoint;
        pool.allocPoint = allocPoint;
    }

    // ============ Reward Calculation ============

    /// @notice Gets current reward rate per second
    /// @dev Calculates current epoch's reward rate based on start time, halving each epoch
    /// @return Current BRS reward per second, precision 1e18
    function currentRewardPerSecond() external view override returns (uint256) {
        return _currentRewardPerSec();
    }

    function _currentRewardPerSec() internal view returns (uint256) {
        if (totalAllocPoint == 0) return 0;
        uint256 era = (block.timestamp - startTime) / Constants.ERA_PERIOD;
        uint256 initialRate = (1_050_000_000e18) / Constants.ERA_PERIOD;
        return initialRate >> era;
    }

    /// @notice Batch updates all pools
    /// @dev Iterates through all pools and updates their accumulated rewards, recommended to call before modifying allocation points
    function massUpdatePools() public {
        uint256 length = _poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /// @notice Updates accumulated rewards for a specific pool
    /// @dev Calculates rewards since last update and updates accRewardPerShare
    ///      Also distributes fund shares to specified fund addresses
    /// @param pid Pool ID
    function updatePool(uint256 pid) public {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        if (block.timestamp <= pool.lastRewardTime) return;

        uint256 totalStaked = pool.totalStaked;
        if (totalStaked == 0 || totalAllocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 reward = RewardMath.emissionFor(
            timeElapsed,
            _currentRewardPerSec(),
            pool.allocPoint,
            totalAllocPoint
        );
        reward = RewardMath.clampToMax(minted, reward, Constants.BRS_MAX_SUPPLY);
        if (reward == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        minted += reward;

        uint256 fundDistributed;
        uint256 shareSum;
        uint256 lastFundIndex = type(uint256).max;
        for (uint256 i = 0; i < fundAddrs.length; i++) {
            if (fundAddrs[i] != address(0) && fundShares.length > i && fundShares[i] > 0) {
                shareSum += fundShares[i];
                lastFundIndex = i;
            }
        }

        for (uint256 i = 0; i < fundAddrs.length; i++) {
            address fund = fundAddrs[i];
            uint256 share = fundShares.length > i ? fundShares[i] : 0;
            if (fund != address(0) && share > 0) {
                uint256 amt;
                if (i == lastFundIndex) {
                    uint256 totalFundAmount = Math.mulDiv(reward, shareSum, SHARE_BASE);
                    amt = totalFundAmount - fundDistributed;
                } else {
                    amt = Math.mulDiv(reward, share, SHARE_BASE);
                }
                if (amt > 0) {
                    rewardToken.safeTransfer(fund, amt);
                    fundDistributed += amt;
                }
            }
        }

        uint256 poolReward = reward - fundDistributed;
        pool.accRewardPerShare = RewardMath.accRewardPerShare(
            pool.accRewardPerShare,
            poolReward,
            totalStaked
        );
        pool.lastRewardTime = block.timestamp;
    }

    /// @notice Queries user's pending BRS rewards
    /// @dev Calculates user's current claimable rewards (including unupdated accumulated rewards)
    /// @param pid Pool ID
    /// @param account User address
    /// @return Pending BRS amount, precision 1e18
    function pendingReward(uint256 pid, address account) external view override returns (uint256) {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][account];
        uint256 accReward = pool.accRewardPerShare;
        uint256 totalStaked = pool.totalStaked;

        if (block.timestamp > pool.lastRewardTime && totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            uint256 reward = RewardMath.emissionFor(
                timeElapsed,
                _currentRewardPerSec(),
                pool.allocPoint,
                totalAllocPoint
            );
            reward = RewardMath.clampToMax(minted, reward, Constants.BRS_MAX_SUPPLY);
            accReward = RewardMath.accRewardPerShare(accReward, reward, totalStaked);
        }

        return RewardMath.pending(user.amount, accReward, user.rewardDebt);
    }

    // ============ User Operations ============

    /// @notice User stakes tokens
    /// @dev Stakes tokens to a specific pool to earn BRS rewards, automatically claims accumulated rewards
    ///      Stake amount must meet minimum USD value requirement
    /// @param pid Pool ID
    /// @param amount Stake amount, precision depends on token
    function deposit(uint256 pid, uint256 amount) external override nonReentrant {
        _deposit(pid, amount, msg.sender, msg.sender);
    }

    /// @notice Stakes tokens on behalf of another user
    /// @dev Caller pays tokens, but staking record and rewards belong to onBehalfOf address
    ///      Used by StakingRouter and similar contracts for proxy staking
    /// @param pid Pool ID
    /// @param amount Stake amount
    /// @param onBehalfOf Beneficiary address, rewards will belong to this address
    function depositFor(uint256 pid, uint256 amount, address onBehalfOf) external override nonReentrant {
        require(onBehalfOf != address(0), "FarmingPool: zero address");
        _deposit(pid, amount, msg.sender, onBehalfOf);
    }

    function _deposit(uint256 pid, uint256 amount, address payer, address beneficiary) internal {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][beneficiary];
        updatePool(pid);

        if (user.amount > 0) {
            uint256 pending = RewardMath.pending(user.amount, pool.accRewardPerShare, user.rewardDebt);
            if (pending > 0) {
                rewardToken.safeTransfer(beneficiary, pending);
                emit Claim(beneficiary, pid, pending);
            }
        }

        if (amount > 0) {
            _updateLPValueIfNeeded(pid, pool.kind);
            uint256 stakeValue = _calculateStakeValueUSD(pool, amount, pool.kind);
            require(stakeValue >= Constants.MIN_USD_VALUE, "FarmingPool: stake too small");
            require(stakeValue <= Constants.MAX_USD_VALUE, "FarmingPool: stake too large");
            pool.lpToken.safeTransferFrom(payer, address(this), amount);
            user.amount += amount;
            pool.totalStaked += amount;
        }

        user.rewardDebt = RewardMath.rewardDebtValue(user.amount, pool.accRewardPerShare);
        emit Deposit(beneficiary, pid, amount);
    }

    /// @notice User withdraws staked tokens
    /// @dev Withdraws staked tokens from specified pool, automatically claims accumulated rewards
    /// @param pid Pool ID
    /// @param amount Withdraw amount, cannot exceed staked amount
    function withdraw(uint256 pid, uint256 amount) external override nonReentrant {
        _withdraw(pid, amount, msg.sender, msg.sender);
    }

    /// @notice Withdraws staked tokens on behalf of another user
    /// @dev Withdraws from onBehalfOf's stake, tokens sent to 'to' address
    ///      Used by StakingRouter and similar contracts for proxy withdrawal
    /// @param pid Pool ID
    /// @param amount Withdraw amount
    /// @param onBehalfOf Stake owner address
    /// @param to Address to receive tokens
    function withdrawFor(uint256 pid, uint256 amount, address onBehalfOf, address to) external override nonReentrant {
        require(onBehalfOf != address(0) && to != address(0), "FarmingPool: zero address");
        _withdraw(pid, amount, onBehalfOf, to);
    }

    function _withdraw(uint256 pid, uint256 amount, address ownerAddr, address recipient) internal {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][ownerAddr];
        require(user.amount >= amount, "FarmingPool: withdraw exceeds staked");

        // Validate withdraw amount USD value (prevent dust and overflow attacks)
        if (amount > 0) {
            _updateLPValueIfNeeded(pid, pool.kind);
            uint256 withdrawValue = _calculateStakeValueUSD(pool, amount, pool.kind);
            require(withdrawValue >= Constants.MIN_USD_VALUE, "FarmingPool: withdraw too small");
            require(withdrawValue <= Constants.MAX_USD_VALUE, "FarmingPool: withdraw too large");
        }

        updatePool(pid);
        uint256 pending = RewardMath.pending(user.amount, pool.accRewardPerShare, user.rewardDebt);
        if (pending > 0) {
            rewardToken.safeTransfer(ownerAddr, pending);
            emit Claim(ownerAddr, pid, pending);
        }

        if (amount > 0) {
            user.amount -= amount;
            pool.totalStaked -= amount;
            pool.lpToken.safeTransfer(recipient, amount);
        }

        user.rewardDebt = RewardMath.rewardDebtValue(user.amount, pool.accRewardPerShare);
        emit Withdraw(ownerAddr, pid, amount);
    }

    /// @notice Claims BRS rewards
    /// @dev Claims accumulated rewards from specified pool without affecting staked principal
    /// @param pid Pool ID
    function claim(uint256 pid) external override nonReentrant {
        _claim(pid, msg.sender);
    }

    /// @notice Claims BRS rewards on behalf of another user
    /// @dev Claims rewards for account from specified pool, rewards sent to account
    ///      Used by StakingRouter and similar contracts for proxy claiming
    /// @param pid Pool ID
    /// @param account Reward owner address
    function claimFor(uint256 pid, address account) external override nonReentrant {
        require(account != address(0), "FarmingPool: zero address");
        _claim(pid, account);
    }

    function _claim(uint256 pid, address account) internal {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][account];
        updatePool(pid);
        uint256 pending = RewardMath.pending(user.amount, pool.accRewardPerShare, user.rewardDebt);
        if (pending > 0) {
            rewardToken.safeTransfer(account, pending);
            emit Claim(account, pid, pending);
        }
        user.rewardDebt = RewardMath.rewardDebtValue(user.amount, pool.accRewardPerShare);
    }

    /// @notice Emergency withdrawal of all staked tokens
    /// @dev Forfeits all pending rewards, only withdraws staked principal
    ///      For emergency situations requiring quick exit
    /// @param pid Pool ID
    function emergencyWithdraw(uint256 pid) external override nonReentrant {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "FarmingPool: nothing to withdraw");

        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        pool.lpToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    // ============ LP Value Cache ============

    uint256 public constant PRICE_UPDATE_INTERVAL = 1 hours;

    /// @notice Checks if LP pool needs price cache update
    /// @dev Only applicable to LP pools, updates LP token value hourly
    /// @param pid Pool ID
    /// @return needs Whether update is needed
    /// @return timeSince Time since last update (seconds)
    function needsUpdate(uint256 pid) external view override returns (bool needs, uint256 timeSince) {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        if (pool.kind != PoolKind.LP) {
            return (false, 0);
        }
        timeSince = block.timestamp - pool.lastPriceUpdate;
        needs = timeSince >= PRICE_UPDATE_INTERVAL;
    }

    /// @notice Manually updates LP pool price cache
    /// @dev Only applicable to LP pools, calculates and caches LP token USD value
    ///      Used for minimum stake value validation
    /// @param pid Pool ID (must be LP type)
    function updateLPValue(uint256 pid) external override {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        require(pool.kind == PoolKind.LP, "FarmingPool: not LP");
        uint256 newValue = _calculateLPStakeValue(pool.lpToken, 1e18);
        pool.cachedLPValuePerToken = newValue;
        pool.lastPriceUpdate = block.timestamp;
        emit LPValueUpdated(pid, newValue, block.timestamp);
    }

    function _updateLPValueIfNeeded(uint256 pid, PoolKind kind) internal {
        if (kind != PoolKind.LP) {
            return;
        }
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        if (block.timestamp >= pool.lastPriceUpdate + PRICE_UPDATE_INTERVAL) {
            uint256 newValue = _calculateLPStakeValue(pool.lpToken, 1e18);
            pool.cachedLPValuePerToken = newValue;
            pool.lastPriceUpdate = block.timestamp;
            emit LPValueUpdated(pid, newValue, block.timestamp);
        }
    }

    function _calculateStakeValueUSD(
        IFarmingPool.PoolInfo storage pool,
        uint256 amount,
        PoolKind kind
    ) internal view returns (uint256) {
        if (kind == PoolKind.LP) {
            uint256 valuePerToken = pool.cachedLPValuePerToken;
            if (valuePerToken == 0) {
                valuePerToken = _calculateLPStakeValue(pool.lpToken, 1e18);
            }
            return Math.mulDiv(amount, valuePerToken, 1e18);
        }
        return _calculateSingleStakeValue(pool.lpToken, amount);
    }

    function _calculateSingleStakeValue(IERC20 token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(address(token)).decimals();
        uint256 price = _fetchTokenPrice(address(token));
        return Math.mulDiv(amount, price, 10 ** decimals);
    }

    function _calculateLPStakeValue(IERC20 lpToken, uint256 amount) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(address(lpToken));
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply == 0) return 0;

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        uint256 price0 = _fetchTokenPrice(token0);
        uint256 price1 = _fetchTokenPrice(token1);
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();

        uint256 value0 = Math.mulDiv(reserve0, price0, 10 ** decimals0);
        uint256 value1 = Math.mulDiv(reserve1, price1, 10 ** decimals1);
        uint256 totalValue = value0 + value1;

        return Math.mulDiv(amount, totalValue, totalSupply);
    }

    function _fetchTokenPrice(address token) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(core.PRICE_ORACLE());
        if (token == core.BTD()) {
            return oracle.getBTDPrice();
        }
        if (token == core.BTB()) {
            return oracle.getBTBPrice();
        }
        if (token == core.BRS()) {
            return oracle.getBRSPrice();
        }
        if (token == core.WBTC()) {
            return oracle.getWBTCPrice();
        }
        // stBTD price = BTD price * share value (ERC4626)
        if (token == core.ST_BTD()) {
            uint256 btdPrice = oracle.getBTDPrice();
            uint256 assetsPerShare = IERC4626(token).convertToAssets(1e18);
            return Math.mulDiv(btdPrice, assetsPerShare, 1e18);
        }
        // stBTB price = BTB price * share value (ERC4626)
        if (token == core.ST_BTB()) {
            uint256 btbPrice = oracle.getBTBPrice();
            uint256 assetsPerShare = IERC4626(token).convertToAssets(1e18);
            return Math.mulDiv(btbPrice, assetsPerShare, 1e18);
        }
        // Local/test: stablecoins fixed at $1, WETH set to $3,000
        if (token == core.USDC() || token == core.USDT()) {
            return 1e18;
        }
        if (token == core.WETH()) {
            return 3_000e18;
        }
        revert("FarmingPool: unsupported token");
    }
}

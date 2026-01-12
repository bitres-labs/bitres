// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFarmingPool.sol";
import "./interfaces/ITreasury.sol";
import "./ConfigCore.sol";
import "./libraries/Constants.sol";
import "./libraries/RewardMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

/// @notice Minimal Farm contract for distributing pre-minted BRS rewards
contract FarmingPool is Ownable2Step, ReentrancyGuard, IFarmingPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    ConfigCore public immutable core;

    uint256 public immutable override startTime;
    uint256 public override minted;

    IFarmingPool.PoolInfo[] private _poolInfo;
    mapping(uint256 => mapping(address => IFarmingPool.UserInfo)) private _userInfo;
    uint256 public totalAllocPoint;

    address[] public fundAddrs;
    uint256[] public fundShares;
    uint256 public constant SHARE_BASE = 100;

    event RewardsFunded(address indexed from, uint256 amount);

    constructor(
        address owner_,
        address rewardToken_,
        address _core,
        address[] memory initialFunds,
        uint256[] memory initialShares
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

    /// @notice Returns BRS token address
    function brs() external view override returns (address) {
        return address(rewardToken);
    }

    /// @notice Injects reward tokens into the pool
    /// @param amount Amount of BRS to inject (1e18 precision)
    function fundRewards(uint256 amount) external {
        require(amount > 0, "FarmingPool: amount zero");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(msg.sender, amount);
    }

    /// @notice Sets fund addresses and their share ratios
    /// @param addrs Fund address array
    /// @param shares Share ratios (base 100, total <= 100)
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

    /// @notice Returns total number of pools
    function poolLength() external view override returns (uint256) {
        return _poolInfo.length;
    }

    /// @notice Returns pool configuration and status
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
            pool.kind
        );
    }

    /// @notice Returns pool type (LP or Single)
    function poolKind(uint256 pid) external view override returns (PoolKind) {
        return _poolInfo[pid].kind;
    }

    /// @notice Returns user's staked amount and reward debt
    function userInfo(uint256 pid, address user)
        external
        view
        override
        returns (uint256 amount, uint256 rewardDebt)
    {
        IFarmingPool.UserInfo storage info = _userInfo[pid][user];
        return (info.amount, info.rewardDebt);
    }

    /// @notice Adds new pool with optional batch update
    function addPool(
        IERC20 token,
        uint256 allocPoint,
        PoolKind kind,
        bool withUpdate
    ) external override onlyOwner {
        _addPoolInternal(allocPoint, token, kind, withUpdate);
    }

    /// @notice Adds new pool without batch update
    function addPool(IERC20 token, uint256 allocPoint, PoolKind kind) external override onlyOwner {
        _addPoolInternal(allocPoint, token, kind, false);
    }

    /// @notice Batch adds multiple pools
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
                kind: kind
            })
        );
    }

    /// @notice Updates pool allocation points
    function setPool(uint256 pid, uint256 allocPoint, bool withUpdate) external override onlyOwner {
        if (withUpdate) {
            massUpdatePools();
        }
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        totalAllocPoint = totalAllocPoint - pool.allocPoint + allocPoint;
        pool.allocPoint = allocPoint;
    }

    // ============ Reward Calculation ============

    /// @notice Returns current reward rate per second (halves each epoch)
    function currentRewardPerSecond() external view override returns (uint256) {
        return _currentRewardPerSec();
    }

    function _currentRewardPerSec() internal view returns (uint256) {
        if (totalAllocPoint == 0) return 0;
        uint256 era = (block.timestamp - startTime) / Constants.ERA_PERIOD;
        uint256 initialRate = (1_050_000_000e18) / Constants.ERA_PERIOD;
        return initialRate >> era;
    }

    /// @notice Updates all pools' accumulated rewards
    function massUpdatePools() public {
        uint256 length = _poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /// @notice Updates a pool's accumulated rewards and distributes fund shares
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

    /// @notice Returns user's pending BRS rewards
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

    /// @notice Stakes tokens to earn BRS rewards, auto-claims pending rewards
    function deposit(uint256 pid, uint256 amount) external override nonReentrant {
        _deposit(pid, amount, msg.sender);
    }

    function _deposit(uint256 pid, uint256 amount, address account) internal {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][account];
        updatePool(pid);

        uint256 pending = 0;
        if (user.amount > 0) {
            pending = RewardMath.pending(user.amount, pool.accRewardPerShare, user.rewardDebt);
        }

        if (amount > 0) {
            _validateStakeAmount(pool, amount, pool.kind);
            pool.lpToken.safeTransferFrom(account, address(this), amount);
            user.amount += amount;
            pool.totalStaked += amount;
        }
        user.rewardDebt = RewardMath.rewardDebtValue(user.amount, pool.accRewardPerShare);

        if (pending > 0) {
            rewardToken.safeTransfer(account, pending);
            emit Claim(account, pid, pending);
            _tryLazyBuyback();
        }

        emit Deposit(account, pid, amount);
    }

    /// @notice Withdraws staked tokens, auto-claims pending rewards
    function withdraw(uint256 pid, uint256 amount) external override nonReentrant {
        _withdraw(pid, amount, msg.sender);
    }

    function _withdraw(uint256 pid, uint256 amount, address account) internal {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][account];
        require(user.amount >= amount, "FarmingPool: withdraw exceeds staked");

        if (amount > 0) {
            _validateStakeAmount(pool, amount, pool.kind);
        }

        updatePool(pid);

        uint256 pending = RewardMath.pending(user.amount, pool.accRewardPerShare, user.rewardDebt);

        if (amount > 0) {
            user.amount -= amount;
            pool.totalStaked -= amount;
        }
        user.rewardDebt = RewardMath.rewardDebtValue(user.amount, pool.accRewardPerShare);

        if (pending > 0) {
            rewardToken.safeTransfer(account, pending);
            emit Claim(account, pid, pending);
            _tryLazyBuyback();
        }
        if (amount > 0) {
            pool.lpToken.safeTransfer(account, amount);
        }

        emit Withdraw(account, pid, amount);
    }

    /// @notice Claims pending rewards without affecting staked amount
    function claim(uint256 pid) external override nonReentrant {
        _claim(pid, msg.sender);
    }

    function _claim(uint256 pid, address account) internal {
        IFarmingPool.PoolInfo storage pool = _poolInfo[pid];
        IFarmingPool.UserInfo storage user = _userInfo[pid][account];
        updatePool(pid);

        uint256 pending = RewardMath.pending(user.amount, pool.accRewardPerShare, user.rewardDebt);
        user.rewardDebt = RewardMath.rewardDebtValue(user.amount, pool.accRewardPerShare);

        if (pending > 0) {
            rewardToken.safeTransfer(account, pending);
            emit Claim(account, pid, pending);
            _tryLazyBuyback();
        }
    }

    /// @notice Emergency withdrawal forfeiting all pending rewards
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

    // ============ Token Amount Validation ============

    function _validateTokenAmount(address token, uint256 amount) internal view {
        if (token == core.WBTC()) {
            require(amount >= Constants.MIN_BTC_AMOUNT, "FarmingPool: amount too small");
            require(amount <= Constants.MAX_WBTC_AMOUNT, "FarmingPool: amount too large");
        } else if (token == core.USDC() || token == core.USDT()) {
            require(amount >= Constants.MIN_STABLECOIN_6_AMOUNT, "FarmingPool: amount too small");
            require(amount <= Constants.MAX_STABLECOIN_6_AMOUNT, "FarmingPool: amount too large");
        } else if (token == core.WETH()) {
            require(amount >= Constants.MIN_ETH_AMOUNT, "FarmingPool: amount too small");
            require(amount <= Constants.MAX_ETH_AMOUNT, "FarmingPool: amount too large");
        } else {
            require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "FarmingPool: amount too small");
            require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "FarmingPool: amount too large");
        }
    }

    function _validateLPTokenAmount(IERC20 lpToken, uint256 lpAmount) internal view {
        IUniswapV2Pair pair = IUniswapV2Pair(address(lpToken));
        uint256 totalSupply = pair.totalSupply();
        require(totalSupply > 0, "FarmingPool: zero LP supply");

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        uint256 amount0 = Math.mulDiv(lpAmount, reserve0, totalSupply);
        uint256 amount1 = Math.mulDiv(lpAmount, reserve1, totalSupply);

        _validateTokenAmount(token0, amount0);
        _validateTokenAmount(token1, amount1);
    }

    function _validateStakeAmount(
        IFarmingPool.PoolInfo storage pool,
        uint256 amount,
        PoolKind kind
    ) internal view {
        if (kind == PoolKind.LP) {
            _validateLPTokenAmount(pool.lpToken, amount);
        } else {
            _validateTokenAmount(address(pool.lpToken), amount);
        }
    }

    // ============ Lazy BRS Buyback ============

    /// @notice Triggers lazy BRS buyback via Treasury (gas compensated)
    function _tryLazyBuyback() internal {
        address treasury = core.TREASURY();
        if (treasury != address(0)) {
            try ITreasury(treasury).tryLazyBuyback() {} catch {}
        }
    }
}

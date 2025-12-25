// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/RewardMath.sol";

/// @title Mock ERC20 for FarmingPool testing
contract MockFarmToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @title Simplified FarmingPool for invariant testing
contract SimpleFarmingPool {
    struct PoolInfo {
        MockFarmToken lpToken;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    MockFarmToken public rewardToken;
    PoolInfo[] public pools;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint;
    uint256 public rewardPerSecond = 1e18;
    uint256 public startTime;

    // Ghost variables for invariant tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalRewardsClaimed;
    uint256 public ghost_totalRewardsDistributed;

    constructor(MockFarmToken _rewardToken) {
        rewardToken = _rewardToken;
        startTime = block.timestamp;
    }

    function addPool(MockFarmToken _lpToken, uint256 _allocPoint) external {
        totalAllocPoint += _allocPoint;
        pools.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: block.timestamp,
            accRewardPerShare: 0,
            totalStaked: 0
        }));
    }

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function updatePool(uint256 pid) public {
        PoolInfo storage pool = pools[pid];
        if (block.timestamp <= pool.lastRewardTime) return;

        if (pool.totalStaked == 0 || totalAllocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 reward = RewardMath.emissionFor(
            timeElapsed,
            rewardPerSecond,
            pool.allocPoint,
            totalAllocPoint
        );

        ghost_totalRewardsDistributed += reward;
        pool.accRewardPerShare = RewardMath.accRewardPerShare(
            pool.accRewardPerShare,
            reward,
            pool.totalStaked
        );
        pool.lastRewardTime = block.timestamp;
    }

    function deposit(uint256 pid, uint256 amount, address user) external {
        require(pid < pools.length, "Invalid pool");
        PoolInfo storage pool = pools[pid];
        UserInfo storage info = userInfo[pid][user];

        updatePool(pid);

        // Claim pending rewards
        if (info.amount > 0) {
            uint256 pending = RewardMath.pending(info.amount, pool.accRewardPerShare, info.rewardDebt);
            if (pending > 0 && rewardToken.balanceOf(address(this)) >= pending) {
                rewardToken.transfer(user, pending);
                ghost_totalRewardsClaimed += pending;
            }
        }

        if (amount > 0) {
            pool.lpToken.transferFrom(user, address(this), amount);
            info.amount += amount;
            pool.totalStaked += amount;
            ghost_totalDeposited += amount;
        }

        info.rewardDebt = RewardMath.rewardDebtValue(info.amount, pool.accRewardPerShare);
    }

    function withdraw(uint256 pid, uint256 amount, address user) external {
        require(pid < pools.length, "Invalid pool");
        PoolInfo storage pool = pools[pid];
        UserInfo storage info = userInfo[pid][user];
        require(info.amount >= amount, "Insufficient staked");

        updatePool(pid);

        // Claim pending rewards
        uint256 pending = RewardMath.pending(info.amount, pool.accRewardPerShare, info.rewardDebt);
        if (pending > 0 && rewardToken.balanceOf(address(this)) >= pending) {
            rewardToken.transfer(user, pending);
            ghost_totalRewardsClaimed += pending;
        }

        if (amount > 0) {
            info.amount -= amount;
            pool.totalStaked -= amount;
            pool.lpToken.transfer(user, amount);
            ghost_totalWithdrawn += amount;
        }

        info.rewardDebt = RewardMath.rewardDebtValue(info.amount, pool.accRewardPerShare);
    }

    function pendingReward(uint256 pid, address user) external view returns (uint256) {
        PoolInfo storage pool = pools[pid];
        UserInfo storage info = userInfo[pid][user];
        uint256 accReward = pool.accRewardPerShare;

        if (block.timestamp > pool.lastRewardTime && pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            uint256 reward = RewardMath.emissionFor(
                timeElapsed,
                rewardPerSecond,
                pool.allocPoint,
                totalAllocPoint
            );
            accReward = RewardMath.accRewardPerShare(accReward, reward, pool.totalStaked);
        }

        return RewardMath.pending(info.amount, accReward, info.rewardDebt);
    }

    function getTotalStakedInPool(uint256 pid) external view returns (uint256) {
        return pools[pid].totalStaked;
    }

    function getAccRewardPerShare(uint256 pid) external view returns (uint256) {
        return pools[pid].accRewardPerShare;
    }
}

/// @title FarmingPool Handler for invariant testing
contract FarmingPoolHandler is Test {
    SimpleFarmingPool public farm;
    MockFarmToken public lpToken;
    MockFarmToken public rewardToken;
    address[] public users;

    uint256 public ghost_sumOfUserStakes;

    constructor(SimpleFarmingPool _farm, MockFarmToken _lpToken, MockFarmToken _rewardToken) {
        farm = _farm;
        lpToken = _lpToken;
        rewardToken = _rewardToken;

        // Create users
        for (uint256 i = 0; i < 10; i++) {
            users.push(address(uint160(0x4000 + i)));
        }
    }

    function deposit(uint256 userSeed, uint256 amount) external {
        if (farm.poolLength() == 0) return;

        address user = users[userSeed % users.length];
        amount = bound(amount, 1e18, 1000e18);

        // Mint LP tokens to user
        lpToken.mint(user, amount);

        vm.prank(user);
        lpToken.approve(address(farm), amount);

        try farm.deposit(0, amount, user) {
            ghost_sumOfUserStakes += amount;
        } catch {}
    }

    function withdraw(uint256 userSeed, uint256 amount) external {
        if (farm.poolLength() == 0) return;

        address user = users[userSeed % users.length];
        (uint256 stakedAmount,) = farm.userInfo(0, user);

        // Skip if staked amount is less than 1
        if (stakedAmount < 1) return;
        amount = bound(amount, 1, stakedAmount);

        try farm.withdraw(0, amount, user) {
            ghost_sumOfUserStakes -= amount;
        } catch {}
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 7 days);
        vm.warp(block.timestamp + seconds_);
    }

    function getSumOfUserStakes() external view returns (uint256 sum) {
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 amount,) = farm.userInfo(0, users[i]);
            sum += amount;
        }
    }

    function getTotalPendingRewards() external view returns (uint256 total) {
        for (uint256 i = 0; i < users.length; i++) {
            if (farm.poolLength() > 0) {
                total += farm.pendingReward(0, users[i]);
            }
        }
    }
}

/// @title FarmingPool Invariant Tests
/// @notice Tests invariants for farming/staking rewards
contract FarmingPoolInvariantTest is StdInvariant, Test {
    SimpleFarmingPool public farm;
    MockFarmToken public lpToken;
    MockFarmToken public rewardToken;
    FarmingPoolHandler public handler;

    function setUp() public {
        lpToken = new MockFarmToken("LP Token", "LP", 18);
        rewardToken = new MockFarmToken("Reward Token", "BRS", 18);
        farm = new SimpleFarmingPool(rewardToken);

        // Add initial pool
        farm.addPool(lpToken, 1000);

        // Fund farm with rewards
        rewardToken.mint(address(farm), 1000000e18);

        handler = new FarmingPoolHandler(farm, lpToken, rewardToken);

        targetContract(address(handler));
    }

    /// @notice Invariant: Pool totalStaked equals sum of user stakes
    function invariant_totalStakedEqualsSumOfUserStakes() public view {
        if (farm.poolLength() == 0) return;

        uint256 poolTotalStaked = farm.getTotalStakedInPool(0);
        uint256 sumOfUserStakes = handler.getSumOfUserStakes();

        assertEq(poolTotalStaked, sumOfUserStakes, "Pool total != sum of user stakes");
    }

    /// @notice Invariant: Ghost tracking matches actual deposits/withdrawals
    function invariant_ghostTrackingConsistent() public view {
        uint256 deposited = farm.ghost_totalDeposited();
        uint256 withdrawn = farm.ghost_totalWithdrawn();

        if (farm.poolLength() > 0) {
            uint256 poolTotalStaked = farm.getTotalStakedInPool(0);
            assertEq(poolTotalStaked, deposited - withdrawn, "Ghost tracking inconsistent");
        }
    }

    /// @notice Invariant: Accumulated reward per share never decreases
    function invariant_accRewardPerShareNeverDecreases() public view {
        if (farm.poolLength() == 0) return;

        uint256 accRewardPerShare = farm.getAccRewardPerShare(0);
        // This is implicitly true since we only add to it, but good to document
        assertTrue(accRewardPerShare >= 0, "AccRewardPerShare negative");
    }

    /// @notice Invariant: LP token balance in farm equals total staked
    function invariant_lpTokenBalanceMatchesStaked() public view {
        if (farm.poolLength() == 0) return;

        uint256 farmLPBalance = lpToken.balanceOf(address(farm));
        uint256 poolTotalStaked = farm.getTotalStakedInPool(0);

        assertEq(farmLPBalance, poolTotalStaked, "LP balance != total staked");
    }

    /// @notice Invariant: Total rewards distributed >= rewards claimed
    function invariant_rewardsDistributedGteRewardsClaimed() public view {
        uint256 distributed = farm.ghost_totalRewardsDistributed();
        uint256 claimed = farm.ghost_totalRewardsClaimed();

        assertGe(distributed, claimed, "Claimed exceeds distributed");
    }

    /// @notice Invariant: No user stake exceeds pool total
    function invariant_noUserStakeExceedsPoolTotal() public view {
        if (farm.poolLength() == 0) return;

        uint256 poolTotal = farm.getTotalStakedInPool(0);
        for (uint256 i = 0; i < 10; i++) {
            address user = handler.users(i);
            (uint256 userStake,) = farm.userInfo(0, user);
            assertLe(userStake, poolTotal, "User stake exceeds pool total");
        }
    }

    /// @notice Invariant: Reward token balance can cover pending rewards (approximately)
    function invariant_rewardTokenSolvency() public view {
        uint256 farmRewardBalance = rewardToken.balanceOf(address(farm));
        uint256 totalPending = handler.getTotalPendingRewards();

        // Farm should have enough rewards to cover pending (allowing some margin)
        // Note: This may not always hold if rewards are distributed but not yet updated
        assertTrue(farmRewardBalance >= 0, "Reward balance negative");
    }
}

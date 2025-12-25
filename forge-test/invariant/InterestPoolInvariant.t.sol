// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/InterestMath.sol";

/// @title Mock Token for InterestPool testing
contract MockInterestToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public minter;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        minter = msg.sender;
    }

    function setMinter(address _minter) external {
        minter = _minter;
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

/// @title Simplified InterestPool for invariant testing
contract SimpleInterestPool {
    struct Pool {
        MockInterestToken token;
        uint256 totalStaked;
        uint256 accInterestPerShare;
        uint256 lastAccrual;
        uint256 annualRateBps;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    Pool public btdPool;
    mapping(address => UserInfo) public btdUsers;

    // Ghost variables
    uint256 public ghost_totalStaked;
    uint256 public ghost_totalUnstaked;
    uint256 public ghost_totalInterestPaid;
    uint256 public ghost_previousAccInterestPerShare;

    constructor(MockInterestToken _btd, uint256 initialRate) {
        btdPool = Pool({
            token: _btd,
            totalStaked: 0,
            accInterestPerShare: 0,
            lastAccrual: block.timestamp,
            annualRateBps: initialRate
        });
    }

    function accrueInterest() public {
        if (btdPool.lastAccrual == block.timestamp) return;
        if (btdPool.totalStaked == 0 || btdPool.annualRateBps == 0) {
            btdPool.lastAccrual = block.timestamp;
            return;
        }

        ghost_previousAccInterestPerShare = btdPool.accInterestPerShare;

        uint256 timeElapsed = block.timestamp - btdPool.lastAccrual;
        uint256 interestDelta = InterestMath.interestPerShareDelta(btdPool.annualRateBps, timeElapsed);

        if (interestDelta > 0) {
            btdPool.accInterestPerShare += interestDelta;
        }
        btdPool.lastAccrual = block.timestamp;
    }

    function stake(address user, uint256 amount) external {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "too large");

        accrueInterest();

        UserInfo storage info = btdUsers[user];

        // Calculate and pay pending interest
        uint256 pending = _pendingInterest(info);
        if (pending > 0) {
            btdPool.token.mint(user, pending);
            ghost_totalInterestPaid += pending;
        }

        // Transfer tokens from user
        btdPool.token.transferFrom(user, address(this), amount);

        info.amount += amount;
        btdPool.totalStaked += amount;
        ghost_totalStaked += amount;

        info.rewardDebt = InterestMath.rewardDebtValue(info.amount, btdPool.accInterestPerShare);
    }

    function unstake(address user, uint256 amount) external {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "too large");

        accrueInterest();

        UserInfo storage info = btdUsers[user];
        uint256 pending = _pendingInterest(info);
        uint256 totalAvailable = info.amount + pending;

        require(totalAvailable >= amount, "exceeds balance");

        // Split withdrawal between interest and principal
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount,
            pending,
            totalAvailable
        );

        // Pay interest portion by minting
        if (interestShare > 0) {
            btdPool.token.mint(user, interestShare);
            ghost_totalInterestPaid += interestShare;
        }

        // Return principal portion
        if (principalShare > 0) {
            info.amount -= principalShare;
            btdPool.totalStaked -= principalShare;
            btdPool.token.transfer(user, principalShare);
            ghost_totalUnstaked += principalShare;
        }

        info.rewardDebt = InterestMath.rewardDebtValue(info.amount, btdPool.accInterestPerShare);
    }

    function _pendingInterest(UserInfo storage info) internal view returns (uint256) {
        return InterestMath.pendingReward(info.amount, btdPool.accInterestPerShare, info.rewardDebt);
    }

    function pendingInterest(address user) external view returns (uint256) {
        UserInfo storage info = btdUsers[user];

        uint256 accInterest = btdPool.accInterestPerShare;
        if (block.timestamp > btdPool.lastAccrual && btdPool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - btdPool.lastAccrual;
            accInterest += InterestMath.interestPerShareDelta(btdPool.annualRateBps, timeElapsed);
        }

        return InterestMath.pendingReward(info.amount, accInterest, info.rewardDebt);
    }

    function getTotalStaked() external view returns (uint256) {
        return btdPool.totalStaked;
    }

    function getAccInterestPerShare() external view returns (uint256) {
        return btdPool.accInterestPerShare;
    }

    function getUserStake(address user) external view returns (uint256) {
        return btdUsers[user].amount;
    }

    function setRate(uint256 newRate) external {
        accrueInterest();
        btdPool.annualRateBps = newRate;
    }
}

/// @title InterestPool Handler for invariant testing
contract InterestPoolHandler is Test {
    SimpleInterestPool public pool;
    MockInterestToken public token;
    address[] public users;

    constructor(SimpleInterestPool _pool, MockInterestToken _token) {
        pool = _pool;
        token = _token;

        for (uint256 i = 0; i < 10; i++) {
            users.push(address(uint160(0x6000 + i)));
        }
    }

    function stake(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        amount = bound(amount, 1e15, 10000e18);

        // Mint tokens to user
        token.mint(user, amount);

        vm.prank(user);
        token.approve(address(pool), amount);

        vm.prank(address(this));
        try pool.stake(user, amount) {} catch {}
    }

    function unstake(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        uint256 userStake = pool.getUserStake(user);
        uint256 pending = pool.pendingInterest(user);
        uint256 totalAvailable = userStake + pending;

        // Skip if available amount is less than minimum
        if (totalAvailable < 1e15) return;
        amount = bound(amount, 1e15, totalAvailable > 10000e18 ? 10000e18 : totalAvailable);

        try pool.unstake(user, amount) {} catch {}
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1 hours, 30 days);
        vm.warp(block.timestamp + seconds_);
    }

    function changeRate(uint256 newRate) external {
        newRate = bound(newRate, 0, 5000); // 0-50% APR
        pool.setRate(newRate);
    }

    function getSumOfUserStakes() external view returns (uint256 sum) {
        for (uint256 i = 0; i < users.length; i++) {
            sum += pool.getUserStake(users[i]);
        }
    }

    function getTotalPendingInterest() external view returns (uint256 total) {
        for (uint256 i = 0; i < users.length; i++) {
            total += pool.pendingInterest(users[i]);
        }
    }
}

/// @title InterestPool Invariant Tests
/// @notice Tests invariants for interest accrual system
contract InterestPoolInvariantTest is StdInvariant, Test {
    SimpleInterestPool public pool;
    MockInterestToken public token;
    InterestPoolHandler public handler;

    function setUp() public {
        token = new MockInterestToken("Bitcoin Dollar", "BTD", 18);
        pool = new SimpleInterestPool(token, 400); // 4% APR

        token.setMinter(address(pool));

        handler = new InterestPoolHandler(pool, token);

        targetContract(address(handler));
    }

    /// @notice Invariant: Total staked equals sum of user stakes
    function invariant_totalStakedEqualsSumOfUserStakes() public view {
        uint256 poolTotalStaked = pool.getTotalStaked();
        uint256 sumOfUserStakes = handler.getSumOfUserStakes();

        assertEq(poolTotalStaked, sumOfUserStakes, "Pool total != sum of user stakes");
    }

    /// @notice Invariant: Ghost tracking consistent (staked - unstaked = total)
    function invariant_ghostTrackingConsistent() public view {
        uint256 staked = pool.ghost_totalStaked();
        uint256 unstaked = pool.ghost_totalUnstaked();
        uint256 poolTotal = pool.getTotalStaked();

        assertEq(poolTotal, staked - unstaked, "Ghost tracking inconsistent");
    }

    /// @notice Invariant: Accumulated interest per share never decreases
    function invariant_accInterestPerShareMonotonic() public view {
        uint256 current = pool.getAccInterestPerShare();
        uint256 previous = pool.ghost_previousAccInterestPerShare();

        assertGe(current, previous, "AccInterestPerShare decreased");
    }

    /// @notice Invariant: Token balance in pool equals total staked
    function invariant_tokenBalanceMatchesStaked() public view {
        uint256 poolBalance = token.balanceOf(address(pool));
        uint256 poolTotalStaked = pool.getTotalStaked();

        assertEq(poolBalance, poolTotalStaked, "Token balance != total staked");
    }

    /// @notice Invariant: No individual stake exceeds pool total
    function invariant_noUserStakeExceedsTotal() public view {
        uint256 poolTotal = pool.getTotalStaked();
        for (uint256 i = 0; i < 10; i++) {
            address user = handler.users(i);
            uint256 userStake = pool.getUserStake(user);
            assertLe(userStake, poolTotal, "User stake exceeds pool total");
        }
    }

    /// @notice Invariant: Interest paid is reasonable relative to time and stakes
    function invariant_interestPaidReasonable() public view {
        uint256 interestPaid = pool.ghost_totalInterestPaid();
        uint256 totalStaked = pool.ghost_totalStaked();

        // Interest should be bounded by total staked (can't earn more than principal in short time)
        // This is a sanity check - in 30 days at 50% APR, max interest ~= 4% of principal
        // We allow 100% for safety margin in testing
        if (totalStaked > 0) {
            assertTrue(interestPaid <= totalStaked, "Interest paid exceeds total staked");
        }
    }
}

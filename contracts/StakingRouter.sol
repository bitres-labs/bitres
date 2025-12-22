// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFarmingPool.sol";
import "./libraries/Constants.sol";

/// @title StakingRouter
/// @notice Users interact with InterestPool/FarmingPool through this unified staking entry to receive dual rewards
/// @dev Logic:
///      - BTD/BTB: First deposit to stBTD/stBTB (vault accrues interest), then stake stToken to FarmingPool to earn BRS
///      - Other pools: Directly stake to FarmingPool, only earn BRS
contract StakingRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IFarmingPool public immutable farmingPool;

    // stToken vault contracts
    IERC4626 public immutable stBTD;
    IERC4626 public immutable stBTB;

    // Pool IDs for stBTD and stBTB in FarmingPool (regular pools, not virtual)
    uint256 public stBTDPoolId;
    uint256 public stBTBPoolId;

    // Track user's pool participation for batch operations
    mapping(address => uint256[]) private userPools;

    event Staked(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 btdInterest, uint256 btbInterest, uint256 brsReward);

    /** @notice Constructor */
    constructor(
        address _farmingPool,    // FarmingPool address
        address _stBTD,          // stBTD vault
        address _stBTB,          // stBTB vault
        uint256 _stBTDPoolId,    // stBTD pool ID in FarmingPool
        uint256 _stBTBPoolId     // stBTB pool ID in FarmingPool
    ) Ownable(msg.sender) {
        require(_farmingPool != address(0), "Invalid FarmingPool address");
        require(_stBTD != address(0), "Invalid stBTD address");
        require(_stBTB != address(0), "Invalid stBTB address");

        farmingPool = IFarmingPool(_farmingPool);
        stBTD = IERC4626(_stBTD);
        stBTB = IERC4626(_stBTB);
        stBTDPoolId = _stBTDPoolId;
        stBTBPoolId = _stBTBPoolId;
    }

    // --- BTD Staking (Dual Rewards: BTD Interest + BRS) ---

    /// @notice Stakes BTD to earn dual rewards
    /// @dev Flow: BTD -> deposit to stBTD vault -> stake stBTD to FarmingPool
    ///      Earns BTD interest (via stBTD appreciation) + BRS mining rewards
    /// @param amount BTD amount to stake, precision 1e18, must be >= minimum stake amount
    function stakeBTD(uint256 amount) external nonReentrant {
        _stakeViaVault(stBTD, stBTDPoolId, amount);
    }

    /// @notice Redeems BTD
    /// @dev Flow: withdraw stBTD from FarmingPool -> redeem BTD from vault -> transfer to user
    ///      Redemption amount includes accumulated BTD interest
    /// @param amount BTD amount to redeem, precision 1e18
    function withdrawBTD(uint256 amount) external nonReentrant {
        _withdrawViaVault(stBTD, stBTDPoolId, amount);
    }

    // --- BTB Staking (Dual Rewards: BTB Interest + BRS) ---

    /// @notice Stakes BTB to earn dual rewards
    /// @dev Flow: BTB -> deposit to stBTB vault -> stake stBTB to FarmingPool
    ///      Earns BTB interest (via stBTB appreciation) + BRS mining rewards
    /// @param amount BTB amount to stake, precision 1e18, must be >= minimum stake amount
    function stakeBTB(uint256 amount) external nonReentrant {
        _stakeViaVault(stBTB, stBTBPoolId, amount);
    }

    /// @notice Redeems BTB
    /// @dev Flow: withdraw stBTB from FarmingPool -> redeem BTB from vault -> transfer to user
    ///      Redemption amount includes accumulated BTB interest
    /// @param amount BTB amount to redeem, precision 1e18
    function withdrawBTB(uint256 amount) external nonReentrant {
        _withdrawViaVault(stBTB, stBTBPoolId, amount);
    }

    // --- Single Token Staking (BRS Rewards Only) ---

    /// @notice Stakes other tokens to earn BRS rewards
    /// @dev Supports staking stBTD, stBTB, USDC, USDT, WBTC, BRS, LP tokens, etc.
    ///      Only earns BRS mining rewards (unlike BTD/BTB which have dual rewards)
    ///      Note: min/max USD value checks are handled by FarmingPool._deposit
    /// @param poolId Pool ID in FarmingPool
    /// @param amount Stake amount, precision depends on token
    function stakeToken(uint256 poolId, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        // Note: Due to different token precisions (6/8/18 decimals),
        // specific min/max USD value validation is handled by FarmingPool._deposit

        // Get pool token
        (IERC20 lpToken, , , , , , , ) = farmingPool.poolInfo(poolId);

        // Transfer token from user to this router (using SafeERC20)
        IERC20(address(lpToken)).safeTransferFrom(msg.sender, address(this), amount);

        // Approve and deposit to FarmingPool (on behalf of user)
        IERC20(address(lpToken)).forceApprove(address(farmingPool), amount);
        farmingPool.depositFor(poolId, amount, msg.sender);

        // Track user's pool participation
        _addUserPool(msg.sender, poolId);

        emit Staked(msg.sender, address(lpToken), amount);
    }

    /// @notice Withdraws staked tokens from specified pool
    /// @dev Withdraws staked tokens, automatically claims accumulated BRS rewards
    ///      Note: min USD value check is handled by FarmingPool._withdraw
    /// @param poolId Pool ID in FarmingPool
    /// @param amount Withdraw amount
    function withdrawToken(uint256 poolId, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        // Note: Due to different token precisions (6/8/18 decimals),
        // specific min USD value validation is handled by FarmingPool._withdraw

        // Get pool token
        (IERC20 lpToken, , , , , , , ) = farmingPool.poolInfo(poolId);

        // Withdraw from FarmingPool (on behalf of user, send to router)
        farmingPool.withdrawFor(poolId, amount, msg.sender, address(this));

        // Transfer token back to user (using SafeERC20)
        IERC20(address(lpToken)).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, address(lpToken), amount);
    }

    // --- Reward Claiming ---

    // NOTE: BTD/BTB interest is auto-accrued in stBTD/stBTB tokens.
    // When you withdraw, you automatically receive the appreciated BTD/BTB amount.
    // No separate interest claiming needed!

    /// @notice Claims BRS rewards from stToken pools
    /// @dev Claims BRS rewards from stBTD pool and stBTB pool
    ///      Note: BTD/BTB interest auto-accumulates in stBTD/stBTB shares, no separate claiming needed
    function claimBRSFromStTokenPools() external nonReentrant {
        // Claim from stBTD pool (on behalf of user, rewards sent directly to them)
        try farmingPool.claimFor(stBTDPoolId, msg.sender) {} catch {}

        // Claim from stBTB pool (on behalf of user, rewards sent directly to them)
        try farmingPool.claimFor(stBTBPoolId, msg.sender) {} catch {}
    }

    /// @notice Claims BRS rewards from specified pool
    /// @dev Claims BRS rewards from a single pool without affecting staked principal
    /// @param poolId Pool ID in FarmingPool
    function claimBRSFromPool(uint256 poolId) external nonReentrant {
        // Claim on behalf of user, rewards sent directly to them
        farmingPool.claimFor(poolId, msg.sender);
    }

    /// @notice One-click claim all BRS rewards
    /// @dev Claims BRS rewards from all pools the user participates in
    ///      BTD/BTB interest auto-accumulates in stBTD/stBTB, no separate claiming needed
    ///      Rewards sent directly to user via claimFor
    function claimAll() external nonReentrant {
        // Claim BRS from stToken pools (rewards sent directly to user)
        try farmingPool.claimFor(stBTDPoolId, msg.sender) {} catch {}
        try farmingPool.claimFor(stBTBPoolId, msg.sender) {} catch {}

        // Claim BRS from user's other pools (rewards sent directly to user)
        uint256[] memory pools = userPools[msg.sender];
        for (uint256 i = 0; i < pools.length; i++) {
            try farmingPool.claimFor(pools[i], msg.sender) {} catch {}
        }
    }

    // --- View Functions ---

    /// @notice Queries all pending BRS rewards for user
    /// @dev Aggregates pending BRS rewards from all pools the user participates in
    ///      Note: BTD/BTB interest is automatically reflected in stBTD/stBTB exchange rate
    /// @param user User address
    /// @return pendingBRS Total pending BRS amount, precision 1e18
    function pendingRewards(address user) external view returns (uint256 pendingBRS) {
        // Pending BRS from stToken pools
        pendingBRS = farmingPool.pendingReward(stBTDPoolId, user)
                   + farmingPool.pendingReward(stBTBPoolId, user);

        // Pending BRS from user's other pools
        uint256[] memory pools = userPools[user];
        for (uint256 i = 0; i < pools.length; i++) {
            pendingBRS += farmingPool.pendingReward(pools[i], user);
        }
    }

    /// @notice Queries user's staked BTD/BTB equivalent amounts
    /// @dev Converts stBTD/stBTB shares to equivalent BTD/BTB amounts (includes accumulated interest)
    /// @param user User address
    /// @return stakedBTD BTD equivalent amount (stBTD shares x exchange rate), precision 1e18
    /// @return stakedBTB BTB equivalent amount (stBTB shares x exchange rate), precision 1e18
    function stakedAmounts(address user) external view returns (
        uint256 stakedBTD,
        uint256 stakedBTB
    ) {
        // Get user's stBTD shares in FarmingPool
        (uint256 stBTDShares, ) = farmingPool.userInfo(stBTDPoolId, user);
        // Convert stBTD shares to BTD amount
        stakedBTD = stBTD.convertToAssets(stBTDShares);

        // Get user's stBTB shares in FarmingPool
        (uint256 stBTBShares, ) = farmingPool.userInfo(stBTBPoolId, user);
        // Convert stBTB shares to BTB amount
        stakedBTB = stBTB.convertToAssets(stBTBShares);
    }

    /// @notice Queries user's staked amount in specified pool
    /// @dev Returns user's staked amount in FarmingPool specified pool
    /// @param user User address
    /// @param poolId Pool ID
    /// @return Staked amount, precision depends on token
    function stakedInPool(address user, uint256 poolId) external view returns (uint256) {
        (uint256 amount, ) = farmingPool.userInfo(poolId, user);
        return amount;
    }

    // --- Internal Functions ---

    /// @dev Internal function to stake tokens via ERC4626 vault for dual rewards
    /// @param vault ERC4626 vault contract (stBTD or stBTB)
    /// @param poolId Pool ID in FarmingPool
    /// @param amount Underlying asset amount to stake (BTD or BTB)
    function _stakeViaVault(
        IERC4626 vault,
        uint256 poolId,
        uint256 amount
    ) internal {
        require(amount > 0, "Amount must be > 0");

        // Check min/max operation value (BTD/BTB are 18 decimal stablecoins)
        require(
            amount >= Constants.MIN_STABLECOIN_18_AMOUNT,
            "Stake amount too small"
        );
        require(
            amount <= Constants.MAX_STABLECOIN_18_AMOUNT,
            "Stake amount too large"
        );

        address assetAddress = address(vault.asset());
        IERC20 asset = IERC20(assetAddress);

        // Transfer asset from user to this router (using SafeERC20)
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Approve vault to take asset (using SafeERC20)
        asset.forceApprove(address(vault), amount);

        // Deposit asset to vault and receive shares
        uint256 shares = vault.deposit(amount, address(this));

        // Approve FarmingPool to take vault shares (using SafeERC20)
        IERC20(address(vault)).forceApprove(address(farmingPool), shares);

        // Stake vault shares in FarmingPool to earn BRS (on behalf of user)
        farmingPool.depositFor(poolId, shares, msg.sender);

        // Track user's pool participation
        _addUserPool(msg.sender, poolId);

        emit Staked(msg.sender, assetAddress, amount);
    }

    /// @dev Internal function to withdraw tokens via ERC4626 vault
    /// @param vault ERC4626 vault contract (stBTD or stBTB)
    /// @param poolId Pool ID in FarmingPool
    /// @param amount Underlying asset amount to withdraw (BTD or BTB)
    function _withdrawViaVault(
        IERC4626 vault,
        uint256 poolId,
        uint256 amount
    ) internal {
        require(amount > 0, "Amount must be > 0");

        // Check min operation value (BTD/BTB are 18 decimal stablecoins)
        require(
            amount >= Constants.MIN_STABLECOIN_18_AMOUNT,
            "Withdraw amount too small"
        );

        // Calculate vault shares needed for this amount of asset
        uint256 shares = vault.previewWithdraw(amount);

        // Withdraw vault shares from FarmingPool (on behalf of user, send to router)
        farmingPool.withdrawFor(poolId, shares, msg.sender, address(this));

        // Redeem vault shares for asset (send asset directly to user)
        vault.redeem(shares, msg.sender, address(this));

        emit Withdrawn(msg.sender, address(vault.asset()), amount);
    }

    function _addUserPool(address user, uint256 poolId) internal {
        uint256[] storage pools = userPools[user];
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] == poolId) return; // Already tracked
        }
        pools.push(poolId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IFarmingPool - Standard interface for yield farming contract
 * @notice Defines the core functionality interface for the yield farming contract
 */
interface IFarmingPool {
    enum PoolKind {
        Single,
        LP
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        PoolKind kind;                  // Pool type
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // --- Mining Operations ---
    /**
     * @notice User deposits tokens to specified mining pool
     * @param _pid Pool ID
     * @param _amount Deposit amount
     */
    function deposit(uint256 _pid, uint256 _amount) external;

    /**
     * @notice User withdraws tokens from specified mining pool
     * @param _pid Pool ID
     * @param _amount Withdrawal amount
     */
    function withdraw(uint256 _pid, uint256 _amount) external;

    /**
     * @notice User claims rewards from specified mining pool
     * @param _pid Pool ID
     */
    function claim(uint256 _pid) external;

    /**
     * @notice Emergency withdrawal, forfeit rewards and retrieve principal
     * @param _pid Pool ID
     */
    function emergencyWithdraw(uint256 _pid) external;

    // --- Proxy Operations (for Router contract) ---
    /**
     * @notice Deposit tokens on behalf of another user (called by Router contract)
     * @param _pid Pool ID
     * @param _amount Deposit amount
     * @param _onBehalfOf Actual beneficiary address
     */
    function depositFor(uint256 _pid, uint256 _amount, address _onBehalfOf) external;

    /**
     * @notice Withdraw tokens on behalf of another user (called by Router contract)
     * @param _pid Pool ID
     * @param _amount Withdrawal amount
     * @param _onBehalfOf Token owner address
     * @param _to Recipient address
     */
    function withdrawFor(uint256 _pid, uint256 _amount, address _onBehalfOf, address _to) external;

    /**
     * @notice Claim rewards on behalf of another user (called by Router contract)
     * @param _pid Pool ID
     * @param _onBehalfOf Actual beneficiary address
     */
    function claimFor(uint256 _pid, address _onBehalfOf) external;

    /**
     * @notice Inject BRS reward tokens into reward pool
     * @param amount BRS amount
     */
    function fundRewards(uint256 amount) external;

    // --- Pool Management ---
    /**
     * @notice Add new mining pool
     * @param _token Staking token (single token or LP token)
     * @param _allocPoint Allocation points, determines reward distribution weight for this pool
     * @param _kind Pool type (Single=single token pool, LP=liquidity pool)
     * @param _withUpdate Whether to update rewards for all pools first
     */
    function addPool(IERC20 _token, uint256 _allocPoint, PoolKind _kind, bool _withUpdate) external;

    /**
     * @notice Add new mining pool (default: don't update other pools)
     * @param _token Staking token (single token or LP token)
     * @param _allocPoint Allocation points
     * @param _kind Pool type
     */
    function addPool(IERC20 _token, uint256 _allocPoint, PoolKind _kind) external;

    /**
     * @notice Batch add multiple mining pools
     * @param _tokens Array of staking tokens
     * @param _allocPoints Array of allocation points
     * @param _kinds Array of pool types
     */
    function addPools(
        IERC20[] calldata _tokens,
        uint256[] calldata _allocPoints,
        PoolKind[] calldata _kinds
    ) external;

    /**
     * @notice Modify allocation points for specified mining pool
     * @param _pid Pool ID
     * @param _allocPoint New allocation points
     * @param _withUpdate Whether to update rewards for all pools first
     */
    function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

    // --- Query Functions ---
    /**
     * @notice Get total number of mining pools
     * @return Number of mining pools
     */
    function poolLength() external view returns (uint256);

    /**
     * @notice Query user's pending rewards
     * @param _pid Pool ID
     * @param _user User address
     * @return Pending BRS reward amount
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256);

    // Auto-generated getter functions (from public storage variables)
    /**
     * @notice Get user info for specified pool
     * @param _pid Pool ID
     * @param _user User address
     * @return amount User's staked token amount
     * @return rewardDebt Debt value used for reward calculation
     */
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, uint256 rewardDebt);

    /**
     * @notice Get detailed info for specified pool
     * @param _pid Pool ID
     * @return lpToken Staking token contract
     * @return allocPoint Allocation points
     * @return lastRewardTime Last reward calculation timestamp
     * @return accRewardPerShare Accumulated reward per share
     * @return totalStaked Total staked amount
     * @return kind Pool type
     */
    function poolInfo(uint256 _pid) external view returns (
        IERC20 lpToken,
        uint256 allocPoint,
        uint256 lastRewardTime,
        uint256 accRewardPerShare,
        uint256 totalStaked,
        PoolKind kind
    );

    /**
     * @notice Get pool type for specified pool
     * @param _pid Pool ID
     * @return Pool type (Single or LP)
     */
    function poolKind(uint256 _pid) external view returns (PoolKind);


    // --- Reward Parameters ---
    /**
     * @notice Get current reward rate per second
     * @return Current BRS reward produced per second
     */
    function currentRewardPerSecond() external view returns (uint256);

    /**
     * @notice Get BRS token contract address
     * @return BRS token address
     */
    function brs() external view returns (address);

    /**
     * @notice Get mining start time
     * @return Block timestamp when mining started
     */
    function startTime() external view returns (uint256);

    /**
     * @notice Get total minted BRS
     * @return Cumulative minted BRS amount
     */
    function minted() external view returns (uint256);

    // --- Events ---
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
}

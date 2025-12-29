// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Faucet
 * @notice Test token faucet for Bitres testnet
 * @dev Distributes WBTC, USDC, and USDT with a 10-minute cooldown per address
 */
contract Faucet is Ownable {
    // Token addresses
    IERC20 public immutable wbtc;
    IERC20 public immutable usdc;
    IERC20 public immutable usdt;

    // Faucet amounts
    uint256 public constant WBTC_AMOUNT = 10000; // 0.0001 WBTC (8 decimals)
    uint256 public constant USDC_AMOUNT = 10_000_000; // 10 USDC (6 decimals)
    uint256 public constant USDT_AMOUNT = 10_000_000; // 10 USDT (6 decimals)

    // Cooldown period: 10 minutes
    uint256 public constant COOLDOWN = 10 minutes;

    // Track last claim time per address
    mapping(address => uint256) public lastClaimTime;

    // Events
    event Claimed(address indexed recipient, uint256 wbtcAmount, uint256 usdcAmount, uint256 usdtAmount);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 amount);

    // Errors
    error CooldownNotElapsed(uint256 remainingTime);
    error InsufficientFaucetBalance(string token);

    constructor(
        address _wbtc,
        address _usdc,
        address _usdt,
        address _owner
    ) Ownable(_owner) {
        wbtc = IERC20(_wbtc);
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
    }

    /**
     * @notice Claim test tokens from the faucet
     * @dev Each address can claim once every 10 minutes
     */
    function claim() external {
        uint256 lastClaim = lastClaimTime[msg.sender];
        if (lastClaim != 0 && block.timestamp < lastClaim + COOLDOWN) {
            revert CooldownNotElapsed(lastClaim + COOLDOWN - block.timestamp);
        }

        // Check balances
        if (wbtc.balanceOf(address(this)) < WBTC_AMOUNT) {
            revert InsufficientFaucetBalance("WBTC");
        }
        if (usdc.balanceOf(address(this)) < USDC_AMOUNT) {
            revert InsufficientFaucetBalance("USDC");
        }
        if (usdt.balanceOf(address(this)) < USDT_AMOUNT) {
            revert InsufficientFaucetBalance("USDT");
        }

        // Update last claim time
        lastClaimTime[msg.sender] = block.timestamp;

        // Transfer tokens
        wbtc.transfer(msg.sender, WBTC_AMOUNT);
        usdc.transfer(msg.sender, USDC_AMOUNT);
        usdt.transfer(msg.sender, USDT_AMOUNT);

        emit Claimed(msg.sender, WBTC_AMOUNT, USDC_AMOUNT, USDT_AMOUNT);
    }

    /**
     * @notice Get remaining cooldown time for an address
     * @param account The address to check
     * @return Remaining cooldown in seconds (0 if can claim)
     */
    function getRemainingCooldown(address account) external view returns (uint256) {
        uint256 lastClaim = lastClaimTime[account];
        if (lastClaim == 0) return 0;
        uint256 elapsed = block.timestamp - lastClaim;
        if (elapsed >= COOLDOWN) return 0;
        return COOLDOWN - elapsed;
    }

    /**
     * @notice Check if an address can claim
     * @param account The address to check
     * @return True if the address can claim
     */
    function canClaim(address account) external view returns (bool) {
        uint256 lastClaim = lastClaimTime[account];
        return lastClaim == 0 || block.timestamp >= lastClaim + COOLDOWN;
    }

    /**
     * @notice Get faucet token balances
     * @return wbtcBalance WBTC balance
     * @return usdcBalance USDC balance
     * @return usdtBalance USDT balance
     */
    function getFaucetBalances() external view returns (
        uint256 wbtcBalance,
        uint256 usdcBalance,
        uint256 usdtBalance
    ) {
        return (
            wbtc.balanceOf(address(this)),
            usdc.balanceOf(address(this)),
            usdt.balanceOf(address(this))
        );
    }

    /**
     * @notice Withdraw tokens from the faucet (owner only)
     * @param token Token address to withdraw
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
        emit TokensWithdrawn(token, to, amount);
    }
}

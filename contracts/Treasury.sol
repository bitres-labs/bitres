// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ConfigCore.sol";
import "./interfaces/ITreasury.sol";
import "./libraries/Constants.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

/**
 * @title Treasury - Bitres System Treasury Contract
 * @notice Manages WBTC/BTD/BRS assets, provides liquidity support for Minter
 * @dev Core functions: WBTC deposit/withdraw, BRS compensation, BTD buyback BRS
 */
contract Treasury is Ownable, ReentrancyGuard, ITreasury {
    using SafeERC20 for IERC20;

    ConfigCore public immutable core;
    address public override router;

    /// @notice Router address update event
    /// @param oldRouter Old Router address
    /// @param newRouter New Router address
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    /**
     * @notice Constructor
     * @dev Initializes treasury with owner, Config contract and Uniswap Router
     */
    constructor(
        address initialOwner,  // Contract owner address, cannot be zero address
        address _core,         // ConfigCore contract address, cannot be zero address
        address routerAddr     // Uniswap V2 Router address (for swap), cannot be zero address
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Treasury: invalid owner");
        require(_core != address(0), "Treasury: invalid core");
        require(routerAddr != address(0), "Treasury: invalid router");
        core = ConfigCore(_core);
        router = routerAddr;
    }

    /**
     * @notice Modifier allowing only Minter contract to call
     * @dev Protects core functions like WBTC deposit/withdraw and BRS compensation
     * @dev Production must strictly limit - only Minter can call
     */
    modifier onlyMint() {
        require(
            msg.sender == core.MINTER(),
            "Treasury: only Minter"
        );
        _;
    }

    /**
     * @notice Get ConfigCore contract address
     * @dev Implements ITreasury interface
     * @return ConfigCore contract address
     */
    function configCore() public view override returns (address) {
        return address(core);
    }

    /**
     * @notice Get WBTC token contract instance
     * @dev Reads WBTC address from ConfigCore
     * @return WBTC token contract interface
     */
    function WBTC() internal view returns (IERC20) {
        return IERC20(core.WBTC());
    }

    /**
     * @notice Get BRS token contract instance
     * @dev Reads BRS address from ConfigCore
     * @return BRS token contract interface
     */
    function BRS() internal view returns (IERC20) {
        return IERC20(core.BRS());
    }

    /**
     * @notice Get BTD token contract instance
     * @dev Reads BTD address from ConfigCore
     * @return BTD token contract interface
     */
    function BTD() internal view returns (IERC20) {
        return IERC20(core.BTD());
    }

    /**
     * @notice Deposit WBTC to treasury
     * @dev Only Minter can call, used for storing collateral when minting BTD
     * @dev Security: onlyMint modifier, reentrancy guard, amount validation, anti-hack limits
     * @param amt WBTC amount (8 decimals)
     */
    function depositWBTC(uint256 amt) external override onlyMint nonReentrant {
        require(amt >= Constants.MIN_BTC_AMOUNT, "Treasury: amount too small");
        require(amt <= Constants.MAX_WBTC_AMOUNT, "Treasury: exceeds max WBTC");
        WBTC().safeTransferFrom(msg.sender, address(this), amt);
        emit ITreasury.WBTCDeposited(msg.sender, amt);
    }

    /**
     * @notice Withdraw WBTC from treasury
     * @dev Only Minter can call, used for returning collateral when redeeming BTD
     * @dev Security: onlyMint modifier, reentrancy guard, balance check, anti-hack limits
     * @param amt WBTC amount (8 decimals)
     */
    function withdrawWBTC(uint256 amt) external override onlyMint nonReentrant {
        require(amt >= Constants.MIN_BTC_AMOUNT, "Treasury: amount too small");
        require(amt <= Constants.MAX_WBTC_AMOUNT, "Treasury: exceeds max WBTC");
        require(WBTC().balanceOf(address(this)) >= amt, "Treasury: insufficient WBTC");
        WBTC().safeTransfer(msg.sender, amt);
        emit ITreasury.WBTCWithdrawn(msg.sender, amt);
    }

    /**
     * @notice Compensate users with BRS
     * @dev Only Minter can call, used for compensation when CR<100%, actual payout limited by treasury BRS balance
     * @dev Security: onlyMint modifier, reentrancy guard, address validation, amount validation, balance clamping
     * @param to Address receiving compensation
     * @param amt Requested BRS compensation amount (18 decimals), actual payout may be less
     */
    function compensate(address to, uint256 amt) external override onlyMint nonReentrant {
        require(to != address(0), "Treasury: zero address");
        require(amt >= Constants.MIN_STABLECOIN_18_AMOUNT, "Treasury: amount too small");
        require(amt <= Constants.MAX_STABLECOIN_18_AMOUNT, "Treasury: exceeds max BRS");
        uint256 balance = BRS().balanceOf(address(this));
        uint256 payout = amt > balance ? balance : amt;
        if (payout > 0) {
            BRS().safeTransfer(to, payout);
            emit ITreasury.BRSCompensated(to, payout);
        }
    }

    /**
     * @notice Buyback BRS with BTD on Uniswap
     * @dev Only owner can call, used to replenish treasury BRS reserves when market conditions allow
     * @dev Security: onlyOwner modifier, reentrancy guard, amount validation, slippage protection
     * @param btdAmount BTD amount for buyback (18 decimals)
     * @param minBRSOut Minimum BRS to receive (18 decimals), slippage protection
     */
    function buybackBRS(uint256 btdAmount, uint256 minBRSOut) external override onlyOwner nonReentrant {
        require(btdAmount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Treasury: BTD amount too small");
        require(btdAmount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Treasury: BTD amount too large");
        require(minBRSOut >= Constants.MIN_STABLECOIN_18_AMOUNT, "Treasury: minBRSOut too small");
        require(minBRSOut <= Constants.MAX_STABLECOIN_18_AMOUNT, "Treasury: minBRSOut too large");
        require(BTD().balanceOf(address(this)) >= btdAmount, "Treasury: insufficient BTD");

        BTD().forceApprove(router, btdAmount);
        address[] memory path = new address[](2);
        path[0] = core.BTD();
        path[1] = core.BRS();

        uint256 beforeBal = BRS().balanceOf(address(this));
        IUniswapV2Router(router).swapExactTokensForTokens(
            btdAmount,
            minBRSOut,
            path,
            address(this),
            block.timestamp + 600
        );
        uint256 received = BRS().balanceOf(address(this)) - beforeBal;
        emit ITreasury.BRSBuyback(btdAmount, received);
    }

    /**
     * @notice Set Uniswap Router address
     * @dev Only owner can call, used to update or fix Router configuration
     * @param newRouter New Uniswap V2 Router address, cannot be zero address
     */
    function setRouter(address newRouter) external override onlyOwner {
        require(newRouter != address(0), "Treasury: invalid router");
        address old = router;
        router = newRouter;
        emit RouterUpdated(old, newRouter);
    }

    /**
     * @notice Query all token balances in treasury
     * @dev Returns WBTC, BRS, BTD balances at once
     * @return wbtcBalance WBTC balance (8 decimals)
     * @return brsBalance BRS balance (18 decimals)
     * @return btdBalance BTD balance (18 decimals)
     */
    function getBalances()
        external
        view
        override
        returns (uint256 wbtcBalance, uint256 brsBalance, uint256 btdBalance)
    {
        wbtcBalance = WBTC().balanceOf(address(this));
        brsBalance = BRS().balanceOf(address(this));
        btdBalance = BTD().balanceOf(address(this));
    }
}

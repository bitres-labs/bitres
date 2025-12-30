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

    function WETH() external pure returns (address);
}

interface IPriceOracleForTreasury {
    function getBRSPrice() external view returns (uint256);
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

    // ============ Lazy Buyback Parameters ============

    /// @notice Minimum BTD balance to trigger buyback (default: 10,000 BTD)
    uint256 public minBuybackAmount = 10_000e18;

    /// @notice Maximum BTD amount per buyback (default: 50,000 BTD)
    uint256 public maxBuybackAmount = 50_000e18;

    /// @notice Cooldown period between buybacks (default: 24 hours)
    uint256 public buybackCooldown = 24 hours;

    /// @notice Trigger probability in percentage (default: 10 = 10%)
    uint256 public buybackProbability = 10;

    /// @notice Maximum slippage in basis points (default: 200 = 2%)
    uint256 public maxSlippageBps = 200;

    /// @notice Minimum ETH reserve for gas compensation (default: 0.5 ETH)
    uint256 public minEthReserve = 0.5 ether;

    /// @notice ETH amount to buy when reserve is low (default: 0.5 ETH)
    uint256 public ethTopupAmount = 0.5 ether;

    /// @notice Timestamp of last buyback execution
    uint256 public lastBuybackTime;

    // ============ Events ============

    /// @notice Router address update event
    /// @param oldRouter Old Router address
    /// @param newRouter New Router address
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    /// @notice Lazy buyback executed
    event LazyBuybackExecuted(
        address indexed triggeredBy,
        uint256 btdSpent,
        uint256 brsReceived,
        uint256 gasCompensation
    );

    /// @notice ETH reserve topped up
    event EthReserveToppedUp(uint256 btdSpent, uint256 ethReceived);

    /// @notice Buyback parameters updated
    event BuybackParamsUpdated(
        uint256 minBuybackAmount,
        uint256 maxBuybackAmount,
        uint256 buybackCooldown,
        uint256 buybackProbability,
        uint256 maxSlippageBps
    );

    /// @notice ETH reserve parameters updated
    event EthReserveParamsUpdated(uint256 minEthReserve, uint256 ethTopupAmount);

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

    // ============ Lazy Buyback Functions ============

    /**
     * @notice Attempts lazy buyback of BRS using BTD
     * @dev Called by Minter during mint/redeem operations
     *      Executes buyback if conditions are met:
     *      1. BTD balance >= minBuybackAmount
     *      2. Cooldown period has passed (24 hours)
     *      3. Random trigger (10% probability)
     *      Compensates caller with actual gas cost in ETH
     * @return executed True if buyback was executed
     */
    function tryLazyBuyback() external nonReentrant returns (bool executed) {
        uint256 startGas = gasleft();

        // 1. Check cooldown
        if (block.timestamp < lastBuybackTime + buybackCooldown) {
            return false;
        }

        // 2. Check BTD balance
        uint256 btdBalance = BTD().balanceOf(address(this));
        if (btdBalance < minBuybackAmount) {
            return false;
        }

        // 3. Random trigger check
        uint256 random = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            block.timestamp,
            btdBalance
        ))) % 100;

        if (random >= buybackProbability) {
            return false;
        }

        // 4. Execute buyback
        uint256 buybackAmount = btdBalance > maxBuybackAmount ? maxBuybackAmount : btdBalance;
        uint256 brsReceived = _executeLazyBuyback(buybackAmount);

        // 5. Top up ETH reserve if needed
        _tryTopupEthReserve();

        // 6. Compensate gas to caller
        uint256 gasUsed = startGas - gasleft();
        gasUsed += 21000;  // Base transaction gas
        gasUsed += 10000;  // Buffer for compensation transfer
        uint256 compensation = gasUsed * tx.gasprice;

        if (address(this).balance >= compensation) {
            (bool success, ) = msg.sender.call{value: compensation}("");
            if (success) {
                emit LazyBuybackExecuted(msg.sender, buybackAmount, brsReceived, compensation);
            } else {
                emit LazyBuybackExecuted(msg.sender, buybackAmount, brsReceived, 0);
            }
        } else {
            emit LazyBuybackExecuted(msg.sender, buybackAmount, brsReceived, 0);
        }

        return true;
    }

    /**
     * @notice Internal function to execute BRS buyback with TWAP price protection
     * @param btdAmount BTD amount to spend
     * @return brsReceived Amount of BRS received
     */
    function _executeLazyBuyback(uint256 btdAmount) internal returns (uint256 brsReceived) {
        // Get TWAP price for slippage protection
        address priceOracle = core.PRICE_ORACLE();
        uint256 brsPrice = IPriceOracleForTreasury(priceOracle).getBRSPrice();

        // Calculate expected BRS output: btdAmount / brsPrice (both 18 decimals)
        // BTD is ~$1, so btdAmount in BTD = btdAmount in USD value
        // brsPrice is BRS price in USD (18 decimals)
        uint256 expectedBRS = (btdAmount * Constants.PRECISION_18) / brsPrice;

        // Apply slippage protection
        uint256 minBRSOut = (expectedBRS * (10000 - maxSlippageBps)) / 10000;

        // Execute swap
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

        brsReceived = BRS().balanceOf(address(this)) - beforeBal;
        lastBuybackTime = block.timestamp;

        emit ITreasury.BRSBuyback(btdAmount, brsReceived);
    }

    /**
     * @notice Top up ETH reserve if below minimum
     * @dev Uses BTD to buy ETH via router
     */
    function _tryTopupEthReserve() internal {
        if (address(this).balance >= minEthReserve) {
            return;
        }

        uint256 btdBalance = BTD().balanceOf(address(this));
        if (btdBalance < 100e18) {
            // Need at least 100 BTD to buy ETH
            return;
        }

        // Calculate BTD needed to buy ethTopupAmount
        // Assume ETH price ~$2500, so 0.5 ETH needs ~$1250 BTD
        // Use a rough estimate, actual amount determined by swap
        uint256 btdForEth = ethTopupAmount * 3000; // Assume max $3000/ETH for safety

        if (btdForEth > btdBalance) {
            btdForEth = btdBalance;
        }

        BTD().forceApprove(router, btdForEth);

        address[] memory path = new address[](2);
        path[0] = core.BTD();
        path[1] = IUniswapV2Router(router).WETH();

        uint256 beforeBal = address(this).balance;

        try IUniswapV2Router(router).swapExactTokensForTokens(
            btdForEth,
            0, // Accept any amount of ETH (we're just topping up)
            path,
            address(this),
            block.timestamp + 600
        ) {
            uint256 ethReceived = address(this).balance - beforeBal;
            emit EthReserveToppedUp(btdForEth, ethReceived);
        } catch {
            // Silently fail - ETH topup is not critical
        }
    }

    // ============ Governance Functions ============

    /**
     * @notice Set buyback parameters
     * @dev Only owner can call
     * @param _minBuybackAmount Minimum BTD balance to trigger buyback
     * @param _maxBuybackAmount Maximum BTD per buyback
     * @param _buybackCooldown Cooldown period in seconds
     * @param _buybackProbability Trigger probability (0-100)
     * @param _maxSlippageBps Maximum slippage in basis points
     */
    function setBuybackParams(
        uint256 _minBuybackAmount,
        uint256 _maxBuybackAmount,
        uint256 _buybackCooldown,
        uint256 _buybackProbability,
        uint256 _maxSlippageBps
    ) external onlyOwner {
        require(_minBuybackAmount >= 1000e18, "Min buyback too small");
        require(_maxBuybackAmount >= _minBuybackAmount, "Max must >= min");
        require(_maxBuybackAmount <= 1_000_000e18, "Max buyback too large");
        require(_buybackCooldown >= 1 hours, "Cooldown too short");
        require(_buybackCooldown <= 7 days, "Cooldown too long");
        require(_buybackProbability > 0 && _buybackProbability <= 100, "Invalid probability");
        require(_maxSlippageBps >= 50 && _maxSlippageBps <= 1000, "Slippage out of range");

        minBuybackAmount = _minBuybackAmount;
        maxBuybackAmount = _maxBuybackAmount;
        buybackCooldown = _buybackCooldown;
        buybackProbability = _buybackProbability;
        maxSlippageBps = _maxSlippageBps;

        emit BuybackParamsUpdated(
            _minBuybackAmount,
            _maxBuybackAmount,
            _buybackCooldown,
            _buybackProbability,
            _maxSlippageBps
        );
    }

    /**
     * @notice Set ETH reserve parameters
     * @dev Only owner can call
     * @param _minEthReserve Minimum ETH to maintain
     * @param _ethTopupAmount ETH amount to buy when topping up
     */
    function setEthReserveParams(
        uint256 _minEthReserve,
        uint256 _ethTopupAmount
    ) external onlyOwner {
        require(_minEthReserve >= 0.1 ether, "Min reserve too small");
        require(_minEthReserve <= 10 ether, "Min reserve too large");
        require(_ethTopupAmount >= 0.1 ether, "Topup amount too small");
        require(_ethTopupAmount <= 5 ether, "Topup amount too large");

        minEthReserve = _minEthReserve;
        ethTopupAmount = _ethTopupAmount;

        emit EthReserveParamsUpdated(_minEthReserve, _ethTopupAmount);
    }

    /**
     * @notice Receive ETH for gas compensation reserve
     */
    receive() external payable {}

    /**
     * @notice Withdraw excess ETH (emergency function)
     * @dev Only owner can call
     * @param amount ETH amount to withdraw
     * @param to Recipient address
     */
    function withdrawEth(uint256 amount, address payable to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(address(this).balance >= amount, "Insufficient ETH");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
}

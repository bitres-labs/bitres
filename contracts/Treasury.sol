// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
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

/// @title Treasury - Bitres System Treasury Contract
/// @notice Manages WBTC/BTD/BRS assets, provides liquidity support for Minter
/// @dev Core functions: WBTC deposit/withdraw, BRS compensation, BTD buyback BRS
contract Treasury is Ownable2Step, ReentrancyGuard, ITreasury {
    using SafeERC20 for IERC20;

    ConfigCore public immutable core;
    address public override router;

    // ============ Lazy Buyback Parameters ============

    uint256 public minBuybackAmount = 10_000e18;    // Min BTD balance to trigger buyback
    uint256 public maxBuybackAmount = 50_000e18;    // Max BTD per buyback
    uint256 public buybackCooldown = 24 hours;      // Cooldown between buybacks
    uint256 public buybackProbability = 10;         // Trigger probability (10%)
    uint256 public maxSlippageBps = 200;            // Max slippage (2%)
    uint256 public minEthReserve = 0.5 ether;       // Min ETH reserve for gas
    uint256 public ethTopupAmount = 0.5 ether;      // ETH to buy when reserve low
    uint256 public lastBuybackTime;

    // ============ Events ============

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event LazyBuybackExecuted(address indexed triggeredBy, uint256 btdSpent, uint256 brsReceived, uint256 gasCompensation);
    event EthReserveToppedUp(uint256 btdSpent, uint256 ethReceived);
    event BuybackParamsUpdated(uint256 minBuybackAmount, uint256 maxBuybackAmount, uint256 buybackCooldown, uint256 buybackProbability, uint256 maxSlippageBps);
    event EthReserveParamsUpdated(uint256 minEthReserve, uint256 ethTopupAmount);

    constructor(
        address initialOwner,
        address _core,
        address routerAddr
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Treasury: invalid owner");
        require(_core != address(0), "Treasury: invalid core");
        require(routerAddr != address(0), "Treasury: invalid router");
        core = ConfigCore(_core);
        router = routerAddr;
    }

    /// @notice Only Minter contract can call
    modifier onlyMint() {
        require(msg.sender == core.MINTER(), "Treasury: only Minter");
        _;
    }

    /// @notice Get ConfigCore contract address
    function configCore() public view override returns (address) {
        return address(core);
    }

    function WBTC() internal view returns (IERC20) {
        return IERC20(core.WBTC());
    }

    function BRS() internal view returns (IERC20) {
        return IERC20(core.BRS());
    }

    function BTD() internal view returns (IERC20) {
        return IERC20(core.BTD());
    }

    /// @notice Deposit WBTC to treasury (only Minter)
    /// @param amt WBTC amount (8 decimals)
    function depositWBTC(uint256 amt) external override onlyMint nonReentrant {
        require(amt >= Constants.MIN_BTC_AMOUNT, "Treasury: amount too small");
        require(amt <= Constants.MAX_WBTC_AMOUNT, "Treasury: exceeds max WBTC");
        WBTC().safeTransferFrom(msg.sender, address(this), amt);
        emit ITreasury.WBTCDeposited(msg.sender, amt);
    }

    /// @notice Withdraw WBTC from treasury (only Minter)
    /// @param amt WBTC amount (8 decimals)
    function withdrawWBTC(uint256 amt) external override onlyMint nonReentrant {
        require(amt >= Constants.MIN_BTC_AMOUNT, "Treasury: amount too small");
        require(amt <= Constants.MAX_WBTC_AMOUNT, "Treasury: exceeds max WBTC");
        require(WBTC().balanceOf(address(this)) >= amt, "Treasury: insufficient WBTC");
        WBTC().safeTransfer(msg.sender, amt);
        emit ITreasury.WBTCWithdrawn(msg.sender, amt);
    }

    /// @notice Compensate users with BRS (only Minter, used when CR<100%)
    /// @param to Address receiving compensation
    /// @param amt Requested BRS amount (18 decimals), actual payout may be less
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

    /// @notice Buyback BRS with BTD on Uniswap (only owner)
    /// @param btdAmount BTD amount for buyback (18 decimals)
    /// @param minBRSOut Minimum BRS to receive (slippage protection)
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

    /// @notice Set Uniswap Router address (only owner)
    /// @param newRouter New router address
    function setRouter(address newRouter) external override onlyOwner {
        require(newRouter != address(0), "Treasury: invalid router");
        address old = router;
        router = newRouter;
        emit RouterUpdated(old, newRouter);
    }

    /// @notice Query all token balances in treasury
    /// @return wbtcBalance WBTC balance (8 decimals)
    /// @return brsBalance BRS balance (18 decimals)
    /// @return btdBalance BTD balance (18 decimals)
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

    /// @notice Attempts lazy buyback of BRS using BTD (called by Minter)
    /// @dev Executes if: BTD >= min, cooldown passed, random trigger (10%)
    /// @return executed True if buyback was executed
    function tryLazyBuyback() external nonReentrant returns (bool executed) {
        uint256 startGas = gasleft();

        if (block.timestamp < lastBuybackTime + buybackCooldown) {
            return false;
        }

        uint256 btdBalance = BTD().balanceOf(address(this));
        if (btdBalance < minBuybackAmount) {
            return false;
        }

        uint256 random = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            msg.sender,
            block.timestamp,
            btdBalance
        ))) % 100;

        if (random >= buybackProbability) {
            return false;
        }

        uint256 buybackAmount = btdBalance > maxBuybackAmount ? maxBuybackAmount : btdBalance;
        uint256 brsReceived = _executeLazyBuyback(buybackAmount);

        _tryTopupEthReserve();

        uint256 gasUsed = startGas - gasleft() + 21000 + 10000;
        uint256 compensation = gasUsed * tx.gasprice;

        if (address(this).balance >= compensation) {
            (bool success, ) = msg.sender.call{value: compensation}("");
            emit LazyBuybackExecuted(msg.sender, buybackAmount, brsReceived, success ? compensation : 0);
        } else {
            emit LazyBuybackExecuted(msg.sender, buybackAmount, brsReceived, 0);
        }

        return true;
    }

    /// @notice Execute BRS buyback with TWAP price protection
    function _executeLazyBuyback(uint256 btdAmount) internal returns (uint256 brsReceived) {
        address priceOracle = core.PRICE_ORACLE();
        uint256 brsPrice = IPriceOracleForTreasury(priceOracle).getBRSPrice();

        // btdAmount / brsPrice (both 18 decimals)
        uint256 expectedBRS = (btdAmount * Constants.PRECISION_18) / brsPrice;
        uint256 minBRSOut = (expectedBRS * (10000 - maxSlippageBps)) / 10000;

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

    /// @notice Top up ETH reserve if below minimum
    function _tryTopupEthReserve() internal {
        if (address(this).balance >= minEthReserve) {
            return;
        }

        uint256 btdBalance = BTD().balanceOf(address(this));
        if (btdBalance < 100e18) {
            return;
        }

        // Assume max $3000/ETH for safety
        uint256 btdForEth = ethTopupAmount * 3000;
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
            0,
            path,
            address(this),
            block.timestamp + 600
        ) {
            uint256 ethReceived = address(this).balance - beforeBal;
            emit EthReserveToppedUp(btdForEth, ethReceived);
        } catch {
            // ETH topup is not critical
        }
    }

    // ============ Governance Functions ============

    /// @notice Set buyback parameters (only owner)
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

        emit BuybackParamsUpdated(_minBuybackAmount, _maxBuybackAmount, _buybackCooldown, _buybackProbability, _maxSlippageBps);
    }

    /// @notice Set ETH reserve parameters (only owner)
    function setEthReserveParams(uint256 _minEthReserve, uint256 _ethTopupAmount) external onlyOwner {
        require(_minEthReserve >= 0.1 ether, "Min reserve too small");
        require(_minEthReserve <= 10 ether, "Min reserve too large");
        require(_ethTopupAmount >= 0.1 ether, "Topup amount too small");
        require(_ethTopupAmount <= 5 ether, "Topup amount too large");

        minEthReserve = _minEthReserve;
        ethTopupAmount = _ethTopupAmount;

        emit EthReserveParamsUpdated(_minEthReserve, _ethTopupAmount);
    }

    /// @notice Receive ETH for gas compensation reserve
    receive() external payable {}

    /// @notice Withdraw excess ETH (emergency, only owner)
    function withdrawEth(uint256 amount, address payable to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(address(this).balance >= amount, "Insufficient ETH");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
}

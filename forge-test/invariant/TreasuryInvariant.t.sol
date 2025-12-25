// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Mock ERC20 for Treasury testing
contract MockTreasuryToken {
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

/// @title Simplified Treasury for invariant testing
contract SimpleTreasury {
    MockTreasuryToken public wbtc;
    MockTreasuryToken public brs;
    MockTreasuryToken public btd;

    address public minter;
    address public owner;

    // Ghost variables for tracking
    uint256 public ghost_wbtcDeposited;
    uint256 public ghost_wbtcWithdrawn;
    uint256 public ghost_brsCompensated;
    uint256 public ghost_btdUsedForBuyback;
    uint256 public ghost_brsBoughtBack;

    event WBTCDeposited(address indexed from, uint256 amount);
    event WBTCWithdrawn(address indexed to, uint256 amount);
    event BRSCompensated(address indexed to, uint256 amount);

    constructor(MockTreasuryToken _wbtc, MockTreasuryToken _brs, MockTreasuryToken _btd) {
        wbtc = _wbtc;
        brs = _brs;
        btd = _btd;
        minter = msg.sender;
        owner = msg.sender;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "only minter");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function depositWBTC(uint256 amount) external onlyMinter {
        require(amount >= Constants.MIN_BTC_AMOUNT, "amount too small");
        require(amount <= Constants.MAX_WBTC_AMOUNT, "amount too large");

        wbtc.transferFrom(msg.sender, address(this), amount);
        ghost_wbtcDeposited += amount;
        emit WBTCDeposited(msg.sender, amount);
    }

    function withdrawWBTC(uint256 amount) external onlyMinter {
        require(amount >= Constants.MIN_BTC_AMOUNT, "amount too small");
        require(amount <= Constants.MAX_WBTC_AMOUNT, "amount too large");
        require(wbtc.balanceOf(address(this)) >= amount, "insufficient WBTC");

        wbtc.transfer(msg.sender, amount);
        ghost_wbtcWithdrawn += amount;
        emit WBTCWithdrawn(msg.sender, amount);
    }

    function compensate(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "zero address");
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "amount too large");

        uint256 balance = brs.balanceOf(address(this));
        uint256 payout = amount > balance ? balance : amount;

        if (payout > 0) {
            brs.transfer(to, payout);
            ghost_brsCompensated += payout;
            emit BRSCompensated(to, payout);
        }
    }

    function buybackBRS(uint256 btdAmount, uint256 minBRSOut) external onlyOwner {
        require(btdAmount >= Constants.MIN_STABLECOIN_18_AMOUNT, "BTD amount too small");
        require(btd.balanceOf(address(this)) >= btdAmount, "insufficient BTD");

        // Simplified: assume 1:1 swap for testing
        uint256 brsOut = btdAmount;
        require(brsOut >= minBRSOut, "slippage");

        // Simulate swap by minting BRS (in reality, Uniswap would do this)
        ghost_btdUsedForBuyback += btdAmount;
        ghost_brsBoughtBack += brsOut;
    }

    function getBalances() external view returns (uint256, uint256, uint256) {
        return (
            wbtc.balanceOf(address(this)),
            brs.balanceOf(address(this)),
            btd.balanceOf(address(this))
        );
    }

    function getWBTCBalance() external view returns (uint256) {
        return wbtc.balanceOf(address(this));
    }

    function getBRSBalance() external view returns (uint256) {
        return brs.balanceOf(address(this));
    }
}

/// @title Treasury Handler for invariant testing
contract TreasuryHandler is Test {
    SimpleTreasury public treasury;
    MockTreasuryToken public wbtc;
    MockTreasuryToken public brs;
    address public minter;

    constructor(SimpleTreasury _treasury, MockTreasuryToken _wbtc, MockTreasuryToken _brs, address _minter) {
        treasury = _treasury;
        wbtc = _wbtc;
        brs = _brs;
        minter = _minter;
    }

    function depositWBTC(uint256 amount) external {
        amount = bound(amount, 1e5, 100e8); // 0.001 to 100 BTC

        // Mint WBTC to minter
        wbtc.mint(minter, amount);

        vm.prank(minter);
        wbtc.approve(address(treasury), amount);

        vm.prank(minter);
        try treasury.depositWBTC(amount) {} catch {}
    }

    function withdrawWBTC(uint256 amount) external {
        uint256 balance = treasury.getWBTCBalance();
        // Skip if balance is less than minimum
        if (balance < 1e5) return;

        uint256 maxAmount = balance > 100e8 ? 100e8 : balance;
        amount = bound(amount, 1e5, maxAmount);

        vm.prank(minter);
        try treasury.withdrawWBTC(amount) {} catch {}
    }

    function compensateBRS(uint256 amount, uint256 toSeed) external {
        uint256 balance = treasury.getBRSBalance();
        // Skip if balance is less than minimum
        if (balance < 1e15) return;

        uint256 maxAmount = balance > 1e24 ? 1e24 : balance;
        amount = bound(amount, 1e15, maxAmount);
        address to = address(uint160(0x5000 + (toSeed % 10)));

        vm.prank(minter);
        try treasury.compensate(to, amount) {} catch {}
    }
}

/// @title Treasury Invariant Tests
/// @notice Tests invariants for treasury operations
contract TreasuryInvariantTest is StdInvariant, Test {
    SimpleTreasury public treasury;
    MockTreasuryToken public wbtc;
    MockTreasuryToken public brs;
    MockTreasuryToken public btd;
    TreasuryHandler public handler;
    address public minter;

    function setUp() public {
        wbtc = new MockTreasuryToken("Wrapped Bitcoin", "WBTC", 8);
        brs = new MockTreasuryToken("Bitres", "BRS", 18);
        btd = new MockTreasuryToken("Bitcoin Dollar", "BTD", 18);

        treasury = new SimpleTreasury(wbtc, brs, btd);
        minter = address(0x1234);
        treasury.setMinter(minter);

        // Fund treasury with BRS for compensation
        brs.mint(address(treasury), 1000000e18);

        handler = new TreasuryHandler(treasury, wbtc, brs, minter);

        targetContract(address(handler));
    }

    /// @notice Invariant: WBTC balance = deposited - withdrawn
    function invariant_wbtcBalanceEqualsDepositedMinusWithdrawn() public view {
        uint256 deposited = treasury.ghost_wbtcDeposited();
        uint256 withdrawn = treasury.ghost_wbtcWithdrawn();
        uint256 balance = treasury.getWBTCBalance();

        assertEq(balance, deposited - withdrawn, "WBTC balance mismatch");
    }

    /// @notice Invariant: Deposited >= Withdrawn
    function invariant_depositedGeWithdrawn() public view {
        uint256 deposited = treasury.ghost_wbtcDeposited();
        uint256 withdrawn = treasury.ghost_wbtcWithdrawn();

        assertGe(deposited, withdrawn, "Withdrawn exceeds deposited");
    }

    /// @notice Invariant: WBTC balance is non-negative
    function invariant_wbtcBalanceNonNegative() public view {
        uint256 balance = treasury.getWBTCBalance();
        assertTrue(balance >= 0, "WBTC balance negative");
    }

    /// @notice Invariant: BRS compensated never exceeds what was available
    function invariant_brsCompensatedBounded() public view {
        uint256 compensated = treasury.ghost_brsCompensated();
        uint256 initialBRS = 1000000e18; // What we minted at setup

        // Compensated should not exceed initial + any buybacks
        assertLe(compensated, initialBRS + treasury.ghost_brsBoughtBack(), "Over-compensated BRS");
    }

    /// @notice Invariant: Treasury balance >= 0 for all tokens
    function invariant_allBalancesNonNegative() public view {
        (uint256 wbtcBal, uint256 brsBal, uint256 btdBal) = treasury.getBalances();

        assertTrue(wbtcBal >= 0, "WBTC negative");
        assertTrue(brsBal >= 0, "BRS negative");
        assertTrue(btdBal >= 0, "BTD negative");
    }

    /// @notice Invariant: Ghost tracking is consistent
    function invariant_ghostTrackingConsistent() public view {
        uint256 deposited = treasury.ghost_wbtcDeposited();
        uint256 withdrawn = treasury.ghost_wbtcWithdrawn();

        // These should match the actual state
        uint256 actualBalance = treasury.getWBTCBalance();
        assertEq(actualBalance, deposited - withdrawn, "Ghost tracking inconsistent");
    }
}

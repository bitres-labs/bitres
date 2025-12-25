// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Mock WBTC Token (8 decimals)
contract MockWBTCSimple {
    uint8 public constant decimals = 8;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "allowance");
            allowance[from][msg.sender] -= amount;
        }
        require(balanceOf[from] >= amount, "insufficient");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @title Mock BTD Token (18 decimals)
contract MockBTDSimple {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "allowance");
            allowance[from][msg.sender] -= amount;
        }
        require(balanceOf[from] >= amount, "insufficient");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @title Mock BRS Token (18 decimals)
contract MockBRSSimple {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @title SimpleTreasuryLogic - Simplified treasury logic for testing
contract SimpleTreasuryLogic {
    MockWBTCSimple public wbtc;
    MockBTDSimple public btd;
    MockBRSSimple public brs;
    address public minter;
    address public owner;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalCompensated;

    event WBTCDeposited(address indexed from, uint256 amount);
    event WBTCWithdrawn(address indexed to, uint256 amount);
    event BRSCompensated(address indexed to, uint256 amount);

    constructor(address _wbtc, address _btd, address _brs, address _minter) {
        wbtc = MockWBTCSimple(_wbtc);
        btd = MockBTDSimple(_btd);
        brs = MockBRSSimple(_brs);
        minter = _minter;
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

    function depositWBTC(uint256 amount) external onlyMinter {
        require(amount >= Constants.MIN_BTC_AMOUNT, "amount too small");
        require(amount <= Constants.MAX_WBTC_AMOUNT, "exceeds max");
        wbtc.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
        emit WBTCDeposited(msg.sender, amount);
    }

    function withdrawWBTC(uint256 amount) external onlyMinter {
        require(amount >= Constants.MIN_BTC_AMOUNT, "amount too small");
        require(amount <= Constants.MAX_WBTC_AMOUNT, "exceeds max");
        require(wbtc.balanceOf(address(this)) >= amount, "insufficient");
        wbtc.transfer(msg.sender, amount);
        totalWithdrawn += amount;
        emit WBTCWithdrawn(msg.sender, amount);
    }

    function compensate(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "zero address");
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "amount too small");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "exceeds max");

        uint256 balance = brs.balanceOf(address(this));
        uint256 payout = amount > balance ? balance : amount;
        if (payout > 0) {
            brs.transfer(to, payout);
            totalCompensated += payout;
            emit BRSCompensated(to, payout);
        }
    }

    function getBalances() external view returns (uint256, uint256, uint256) {
        return (
            wbtc.balanceOf(address(this)),
            brs.balanceOf(address(this)),
            btd.balanceOf(address(this))
        );
    }
}

/// @title Treasury Integration Test
contract TreasuryIntegrationTest is Test {
    SimpleTreasuryLogic public treasury;
    MockWBTCSimple public wbtc;
    MockBTDSimple public btd;
    MockBRSSimple public brs;

    address public owner = address(this);
    address public minter = address(0x1);
    address public user1 = address(0x2);

    function setUp() public {
        wbtc = new MockWBTCSimple();
        btd = new MockBTDSimple();
        brs = new MockBRSSimple();
        treasury = new SimpleTreasuryLogic(address(wbtc), address(btd), address(brs), minter);
    }

    // ============ Deposit Tests ============

    function test_depositWBTC_success() public {
        uint256 amount = 1e8;

        wbtc.mint(minter, amount);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amount);
        treasury.depositWBTC(amount);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), amount);
        assertEq(treasury.totalDeposited(), amount);
    }

    function test_depositWBTC_onlyMinter() public {
        wbtc.mint(user1, 1e8);
        vm.startPrank(user1);
        wbtc.approve(address(treasury), 1e8);
        vm.expectRevert("only minter");
        treasury.depositWBTC(1e8);
        vm.stopPrank();
    }

    function test_depositWBTC_revertTooSmall() public {
        // MIN_BTC_AMOUNT is 1, so 0 should fail
        wbtc.mint(minter, 0);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), 0);
        vm.expectRevert("amount too small");
        treasury.depositWBTC(0);
        vm.stopPrank();
    }

    function test_depositWBTC_revertTooLarge() public {
        uint256 amount = Constants.MAX_WBTC_AMOUNT + 1;
        wbtc.mint(minter, amount);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amount);
        vm.expectRevert("exceeds max");
        treasury.depositWBTC(amount);
        vm.stopPrank();
    }

    // ============ Withdraw Tests ============

    function test_withdrawWBTC_success() public {
        // Deposit first
        wbtc.mint(minter, 2e8);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), 2e8);
        treasury.depositWBTC(2e8);

        // Withdraw half
        treasury.withdrawWBTC(1e8);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), 1e8);
        assertEq(wbtc.balanceOf(minter), 1e8);
        assertEq(treasury.totalWithdrawn(), 1e8);
    }

    function test_withdrawWBTC_onlyMinter() public {
        wbtc.mint(address(treasury), 1e8);
        vm.prank(user1);
        vm.expectRevert("only minter");
        treasury.withdrawWBTC(1e8);
    }

    function test_withdrawWBTC_revertInsufficientBalance() public {
        wbtc.mint(minter, 1e8);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), 1e8);
        treasury.depositWBTC(1e8);
        vm.expectRevert("insufficient");
        treasury.withdrawWBTC(2e8);
        vm.stopPrank();
    }

    // ============ Compensate Tests ============

    function test_compensate_fullPayout() public {
        brs.mint(address(treasury), 1000e18);

        vm.prank(minter);
        treasury.compensate(user1, 500e18);

        assertEq(brs.balanceOf(user1), 500e18);
        assertEq(treasury.totalCompensated(), 500e18);
    }

    function test_compensate_partialPayout() public {
        brs.mint(address(treasury), 500e18);

        vm.prank(minter);
        treasury.compensate(user1, 1000e18);

        // Should only receive what's available
        assertEq(brs.balanceOf(user1), 500e18);
    }

    function test_compensate_onlyMinter() public {
        brs.mint(address(treasury), 1000e18);
        vm.prank(user1);
        vm.expectRevert("only minter");
        treasury.compensate(user1, 100e18);
    }

    function test_compensate_revertZeroAddress() public {
        brs.mint(address(treasury), 1000e18);
        vm.prank(minter);
        vm.expectRevert("zero address");
        treasury.compensate(address(0), 100e18);
    }

    // ============ GetBalances Tests ============

    function test_getBalances_initial() public view {
        (uint256 wbtcBal, uint256 brsBal, uint256 btdBal) = treasury.getBalances();
        assertEq(wbtcBal, 0);
        assertEq(brsBal, 0);
        assertEq(btdBal, 0);
    }

    function test_getBalances_afterDeposits() public {
        wbtc.mint(address(treasury), 5e8);
        brs.mint(address(treasury), 1000e18);
        btd.mint(address(treasury), 500e18);

        (uint256 wbtcBal, uint256 brsBal, uint256 btdBal) = treasury.getBalances();
        assertEq(wbtcBal, 5e8);
        assertEq(brsBal, 1000e18);
        assertEq(btdBal, 500e18);
    }

    // ============ Fuzz Tests ============

    function testFuzz_depositWBTC_validAmount(uint256 amount) public {
        amount = bound(amount, Constants.MIN_BTC_AMOUNT, Constants.MAX_WBTC_AMOUNT);

        wbtc.mint(minter, amount);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amount);
        treasury.depositWBTC(amount);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), amount);
    }

    function testFuzz_withdrawWBTC_validAmount(uint256 deposit, uint256 withdraw) public {
        deposit = bound(deposit, Constants.MIN_BTC_AMOUNT * 2, Constants.MAX_WBTC_AMOUNT);
        withdraw = bound(withdraw, Constants.MIN_BTC_AMOUNT, deposit);

        wbtc.mint(minter, deposit);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), deposit);
        treasury.depositWBTC(deposit);
        treasury.withdrawWBTC(withdraw);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), deposit - withdraw);
    }

    function testFuzz_compensate_clampsToPayout(uint256 available, uint256 requested) public {
        available = bound(available, 0, 10000e18);
        requested = bound(requested, Constants.MIN_STABLECOIN_18_AMOUNT, Constants.MAX_STABLECOIN_18_AMOUNT);

        brs.mint(address(treasury), available);

        vm.prank(minter);
        treasury.compensate(user1, requested);

        uint256 expected = requested > available ? available : requested;
        assertEq(brs.balanceOf(user1), expected);
    }

    // ============ Accounting Invariants ============

    function test_accounting_depositWithdrawBalance() public {
        wbtc.mint(minter, 10e8);

        vm.startPrank(minter);
        wbtc.approve(address(treasury), 10e8);

        treasury.depositWBTC(3e8);
        treasury.depositWBTC(2e8);
        treasury.withdrawWBTC(1e8);
        treasury.depositWBTC(1e8);
        treasury.withdrawWBTC(2e8);
        vm.stopPrank();

        // Balance = deposited - withdrawn
        uint256 balance = wbtc.balanceOf(address(treasury));
        assertEq(balance, treasury.totalDeposited() - treasury.totalWithdrawn());
    }

    function test_accounting_multipleOperations() public {
        wbtc.mint(minter, 100e8);

        vm.startPrank(minter);
        wbtc.approve(address(treasury), 100e8);

        for (uint256 i = 0; i < 5; i++) {
            treasury.depositWBTC(5e8);
        }

        for (uint256 i = 0; i < 3; i++) {
            treasury.withdrawWBTC(3e8);
        }
        vm.stopPrank();

        assertEq(treasury.totalDeposited(), 25e8);
        assertEq(treasury.totalWithdrawn(), 9e8);
        assertEq(wbtc.balanceOf(address(treasury)), 16e8);
    }

    // ============ Event Tests ============

    function test_depositWBTC_emitsEvent() public {
        wbtc.mint(minter, 1e8);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), 1e8);

        vm.expectEmit(true, false, false, true);
        emit SimpleTreasuryLogic.WBTCDeposited(minter, 1e8);
        treasury.depositWBTC(1e8);
        vm.stopPrank();
    }

    function test_withdrawWBTC_emitsEvent() public {
        wbtc.mint(minter, 1e8);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), 1e8);
        treasury.depositWBTC(1e8);

        vm.expectEmit(true, false, false, true);
        emit SimpleTreasuryLogic.WBTCWithdrawn(minter, 1e8);
        treasury.withdrawWBTC(1e8);
        vm.stopPrank();
    }

    function test_compensate_emitsEvent() public {
        brs.mint(address(treasury), 1000e18);

        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit SimpleTreasuryLogic.BRSCompensated(user1, 500e18);
        treasury.compensate(user1, 500e18);
    }
}

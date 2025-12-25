// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Mock ERC20 for invariant testing
contract MockToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
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

/// @title Token Handler for invariant testing
contract TokenHandler is Test {
    MockToken public token;
    address[] public holders;

    uint256 public ghost_mintedSum;
    uint256 public ghost_burnedSum;
    uint256 public ghost_transferCount;

    constructor(MockToken _token) {
        token = _token;

        // Create holders
        for (uint256 i = 0; i < 10; i++) {
            holders.push(address(uint160(0x2000 + i)));
        }
    }

    function mint(uint256 holderSeed, uint256 amount) external {
        address holder = holders[holderSeed % holders.length];
        amount = bound(amount, 1, 1e24);

        vm.prank(token.owner());
        token.mint(holder, amount);
        ghost_mintedSum += amount;
    }

    function burn(uint256 holderSeed, uint256 amount) external {
        address holder = holders[holderSeed % holders.length];
        uint256 balance = token.balanceOf(holder);

        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(token.owner());
        token.burn(holder, amount);
        ghost_burnedSum += amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];

        uint256 balance = token.balanceOf(from);
        if (balance == 0 || from == to) return;

        amount = bound(amount, 1, balance);

        vm.prank(from);
        token.transfer(to, amount);
        ghost_transferCount++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];

        amount = bound(amount, 0, type(uint256).max);

        vm.prank(owner);
        token.approve(spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        address to = holders[toSeed % holders.length];

        uint256 balance = token.balanceOf(owner);
        uint256 allowed = token.allowance(owner, spender);

        if (balance == 0 || allowed == 0) return;

        amount = bound(amount, 1, balance < allowed ? balance : allowed);

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            ghost_transferCount++;
        } catch {}
    }

    /// @notice Get sum of all holder balances
    function getSumOfBalances() external view returns (uint256 sum) {
        for (uint256 i = 0; i < holders.length; i++) {
            sum += token.balanceOf(holders[i]);
        }
    }
}

/// @title Token Invariant Tests
/// @notice Tests ERC20 token invariants
contract TokenInvariantTest is StdInvariant, Test {
    MockToken public token;
    TokenHandler public handler;

    function setUp() public {
        token = new MockToken("Test Token", "TST", 18);
        handler = new TokenHandler(token);

        // Transfer ownership to handler for minting
        // Note: In this simplified version, the test contract owns the token

        // Target the handler for invariant testing
        targetContract(address(handler));
    }

    /// @notice Invariant: Total supply == sum of all balances
    function invariant_supplyEqualsSumOfBalances() public view {
        uint256 sumOfBalances = handler.getSumOfBalances();
        assertEq(token.totalSupply(), sumOfBalances, "Supply != sum of balances");
    }

    /// @notice Invariant: Total supply == minted - burned
    function invariant_supplyEqualsMintedMinusBurned() public view {
        uint256 expectedSupply = handler.ghost_mintedSum() - handler.ghost_burnedSum();
        assertEq(token.totalSupply(), expectedSupply, "Supply != minted - burned");
    }

    /// @notice Invariant: Individual balances are non-negative (always true for uint)
    function invariant_balancesNonNegative() public view {
        // This is inherently true for uint256, but good to document
        for (uint256 i = 0; i < 10; i++) {
            address holder = handler.holders(i);
            assertTrue(token.balanceOf(holder) >= 0, "Balance is negative");
        }
    }

    /// @notice Invariant: No balance exceeds total supply
    function invariant_noBalanceExceedsTotalSupply() public view {
        uint256 supply = token.totalSupply();
        for (uint256 i = 0; i < 10; i++) {
            address holder = handler.holders(i);
            assertLe(token.balanceOf(holder), supply, "Balance exceeds supply");
        }
    }

    /// @notice Invariant: Transfers are zero-sum (don't create or destroy tokens)
    function invariant_transfersZeroSum() public view {
        // This is implicitly tested by invariant_supplyEqualsSumOfBalances
        // Transfers should not affect total supply
        uint256 expectedSupply = handler.ghost_mintedSum() - handler.ghost_burnedSum();
        assertEq(token.totalSupply(), expectedSupply);
    }
}

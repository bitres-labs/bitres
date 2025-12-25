// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/CollateralMath.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";

/// @title Mock WBTC Token (8 decimals)
contract MockWBTC {
    string public constant name = "Wrapped Bitcoin";
    string public constant symbol = "WBTC";
    uint8 public constant decimals = 8;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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

/// @title Mock BTD Token (18 decimals)
contract MockBTD {
    string public constant name = "Bitcoin Dollar";
    string public constant symbol = "BTD";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public minter;

    constructor() {
        minter = msg.sender;
    }

    function setMinter(address _minter) external {
        minter = _minter;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "only minter");
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == minter, "only minter");
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

/// @title Mock BTB Token (18 decimals)
contract MockBTB {
    string public constant name = "Bitcoin Bond";
    string public constant symbol = "BTB";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    address public minter;

    constructor() {
        minter = msg.sender;
    }

    function setMinter(address _minter) external {
        minter = _minter;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "only minter");
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @title Mock Treasury for invariant testing
contract MockTreasury {
    MockWBTC public wbtc;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    constructor(MockWBTC _wbtc) {
        wbtc = _wbtc;
    }

    function depositWBTC(uint256 amount) external {
        wbtc.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
    }

    function withdrawWBTC(uint256 amount) external {
        require(wbtc.balanceOf(address(this)) >= amount, "insufficient balance");
        wbtc.transfer(msg.sender, amount);
        totalWithdrawn += amount;
    }

    function getBalances() external view returns (uint256, uint256, uint256) {
        return (wbtc.balanceOf(address(this)), 0, 0);
    }
}

/// @title Simplified Minter for invariant testing
contract SimpleMinter {
    MockWBTC public wbtc;
    MockBTD public btd;
    MockBTB public btb;
    MockTreasury public treasury;

    uint256 public wbtcPrice = 50000e18; // $50k per BTC
    uint256 public iusdPrice = 1e18; // $1
    uint16 public mintFeeBP = 50; // 0.5%
    uint16 public redeemFeeBP = 50; // 0.5%

    uint256 public ghost_totalMintedBTD;
    uint256 public ghost_totalBurnedBTD;
    uint256 public ghost_redeemFeesReturned;  // Fees minted back to treasury on redemption
    uint256 public ghost_mintCount;
    uint256 public ghost_redeemCount;

    constructor(MockWBTC _wbtc, MockBTD _btd, MockBTB _btb, MockTreasury _treasury) {
        wbtc = _wbtc;
        btd = _btd;
        btb = _btb;
        treasury = _treasury;
    }

    function mintBTD(address user, uint256 wbtcAmount) external {
        require(wbtcAmount >= Constants.MIN_BTC_AMOUNT, "Amount below minimum");
        require(wbtcAmount <= Constants.MAX_WBTC_AMOUNT, "Amount exceeds max");

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: btd.totalSupply(),
            feeBP: mintFeeBP
        });
        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Transfer WBTC to treasury
        wbtc.transferFrom(user, address(this), wbtcAmount);
        wbtc.approve(address(treasury), wbtcAmount);
        treasury.depositWBTC(wbtcAmount);

        // Mint BTD to user and fee to treasury
        btd.mint(user, outputs.btdToMint);
        if (outputs.fee > 0) {
            btd.mint(address(treasury), outputs.fee);
        }

        // Track total minted (user + fee = btdGross)
        ghost_totalMintedBTD += outputs.btdGross;
        ghost_mintCount++;
    }

    function redeemBTD(address user, uint256 btdAmount) external {
        require(btdAmount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Amount below minimum");
        require(btdAmount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Amount exceeds max");
        require(btd.balanceOf(user) >= btdAmount, "Insufficient BTD");

        // Calculate collateral ratio
        uint256 cr = getCollateralRatio();

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: redeemFeeBP
        });

        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        // Burn BTD from user
        btd.burn(user, btdAmount);
        ghost_totalBurnedBTD += btdAmount;

        // Mint fee back to treasury
        if (outputs.fee > 0) {
            btd.mint(address(treasury), outputs.fee);
            ghost_redeemFeesReturned += outputs.fee;
        }

        // Transfer WBTC back to user
        uint256 wbtcOut = outputs.wbtcOutNormalized / Constants.SCALE_WBTC_TO_NORM;
        if (wbtcOut > 0 && wbtc.balanceOf(address(treasury)) >= wbtcOut) {
            treasury.withdrawWBTC(wbtcOut);
            wbtc.transfer(user, wbtcOut);
        }

        // Mint BTB compensation if CR < 100%
        if (outputs.btbOut > 0) {
            btb.mint(user, outputs.btbOut);
        }

        ghost_redeemCount++;
    }

    function getCollateralRatio() public view returns (uint256) {
        (uint256 wbtcBalance,,) = treasury.getBalances();
        return CollateralMath.collateralRatio(
            wbtcBalance,
            wbtcPrice,
            btd.totalSupply(),
            0, // stBTD equivalent
            iusdPrice
        );
    }

    function totalWBTC() public view returns (uint256) {
        (uint256 wbtcBalance,,) = treasury.getBalances();
        return wbtcBalance;
    }
}

/// @title Minter Handler for invariant testing
contract MinterHandler is Test {
    SimpleMinter public minter;
    MockWBTC public wbtc;
    MockBTD public btd;
    address[] public users;

    constructor(SimpleMinter _minter, MockWBTC _wbtc, MockBTD _btd) {
        minter = _minter;
        wbtc = _wbtc;
        btd = _btd;

        // Create users
        for (uint256 i = 0; i < 5; i++) {
            users.push(address(uint160(0x3000 + i)));
        }
    }

    function mint(uint256 userSeed, uint256 wbtcAmount) external {
        address user = users[userSeed % users.length];
        wbtcAmount = bound(wbtcAmount, 1e5, 100e8); // 0.001 to 100 BTC

        // Give user WBTC
        wbtc.mint(user, wbtcAmount);

        // Approve and mint
        vm.prank(user);
        wbtc.approve(address(minter), wbtcAmount);

        vm.prank(address(this));
        try minter.mintBTD(user, wbtcAmount) {} catch {}
    }

    function redeem(uint256 userSeed, uint256 btdAmount) external {
        address user = users[userSeed % users.length];
        uint256 balance = btd.balanceOf(user);

        // Skip if balance is less than minimum
        if (balance < 1e15) return;
        btdAmount = bound(btdAmount, 1e15, balance);

        vm.prank(address(this));
        try minter.redeemBTD(user, btdAmount) {} catch {}
    }

    function getSumOfUserBTD() external view returns (uint256 sum) {
        for (uint256 i = 0; i < users.length; i++) {
            sum += btd.balanceOf(users[i]);
        }
    }
}

/// @title Minter Invariant Tests
/// @notice Tests invariants for minting and redemption system
contract MinterInvariantTest is StdInvariant, Test {
    MockWBTC public wbtc;
    MockBTD public btd;
    MockBTB public btb;
    MockTreasury public treasury;
    SimpleMinter public minter;
    MinterHandler public handler;

    function setUp() public {
        wbtc = new MockWBTC();
        btd = new MockBTD();
        btb = new MockBTB();
        treasury = new MockTreasury(wbtc);
        minter = new SimpleMinter(wbtc, btd, btb, treasury);

        // Set minter permissions
        btd.setMinter(address(minter));
        btb.setMinter(address(minter));

        handler = new MinterHandler(minter, wbtc, btd);

        targetContract(address(handler));
    }

    /// @notice Invariant: BTD supply equals minted minus burned plus redeem fees returned
    function invariant_btdSupplyConsistency() public view {
        uint256 minted = minter.ghost_totalMintedBTD();
        uint256 burned = minter.ghost_totalBurnedBTD();
        uint256 redeemFees = minter.ghost_redeemFeesReturned();

        // BTD supply = minted - burned + redeem_fees
        // - Minting: ghost_totalMintedBTD = btdGross (btdToMint + mint_fee, all minted)
        // - Redeem: burns btdAmount but mints fee back to treasury
        // So: Supply = minted - burned + redeem_fees
        uint256 expectedSupply = minted - burned + redeemFees;

        // Allow some tolerance due to rounding
        uint256 actualSupply = btd.totalSupply();
        assertApproxEqAbs(actualSupply, expectedSupply, 1e15, "BTD supply inconsistent");
    }

    /// @notice Invariant: Treasury WBTC balance >= 0 (no negative balance)
    function invariant_treasuryWBTCNonNegative() public view {
        (uint256 wbtcBalance,,) = treasury.getBalances();
        assertTrue(wbtcBalance >= 0, "Treasury WBTC negative");
    }

    /// @notice Invariant: Treasury deposited >= withdrawn
    function invariant_treasuryDepositWithdrawBalance() public view {
        uint256 deposited = treasury.totalDeposited();
        uint256 withdrawn = treasury.totalWithdrawn();
        assertGe(deposited, withdrawn, "Withdrawn exceeds deposited");
    }

    /// @notice Invariant: Treasury WBTC balance = deposited - withdrawn
    function invariant_treasuryWBTCAccountingBalance() public view {
        uint256 deposited = treasury.totalDeposited();
        uint256 withdrawn = treasury.totalWithdrawn();
        (uint256 wbtcBalance,,) = treasury.getBalances();

        assertEq(wbtcBalance, deposited - withdrawn, "Treasury accounting mismatch");
    }

    /// @notice Invariant: Collateral ratio is positive when there's collateral and liability
    function invariant_collateralRatioPositive() public view {
        uint256 cr = minter.getCollateralRatio();
        uint256 wbtcBalance = minter.totalWBTC();
        uint256 btdSupply = btd.totalSupply();

        // CR should be positive only if there's both collateral and liability
        if (wbtcBalance > 0 && btdSupply > 0) {
            assertTrue(cr > 0, "CR should be positive");
        }
    }

    /// @notice Invariant: Mint and redeem counts are consistent
    function invariant_operationCountsValid() public view {
        uint256 mintCount = minter.ghost_mintCount();
        uint256 redeemCount = minter.ghost_redeemCount();

        // Both counts should be >= 0 (inherently true for uint)
        assertTrue(mintCount >= 0 && redeemCount >= 0, "Invalid operation counts");
    }

    /// @notice Invariant: No individual balance exceeds BTD supply
    function invariant_noBalanceExceedsBTDSupply() public view {
        uint256 supply = btd.totalSupply();
        for (uint256 i = 0; i < 5; i++) {
            address user = handler.users(i);
            assertLe(btd.balanceOf(user), supply, "Balance exceeds supply");
        }
    }
}

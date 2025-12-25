// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title Mock ERC20 Permit Token for testing
 */
contract MockPermitToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address public minter;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        minter = msg.sender;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
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

    function burnFrom(address from, uint256 amount) external {
        if (msg.sender != from) {
            require(allowance[from][msg.sender] >= amount, "insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
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

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
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

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "permit expired");

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline)
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);

        require(signer != address(0), "invalid signature");
        require(signer == owner, "invalid signer");

        allowance[owner][spender] = value;
    }
}

/**
 * @title Mock Minter for permit testing
 */
contract MockMinterWithPermit {
    MockPermitToken public btd;
    MockPermitToken public btb;
    address public treasury;

    uint256 public btdRedeemed;
    uint256 public btbRedeemed;

    constructor(MockPermitToken _btd, MockPermitToken _btb, address _treasury) {
        btd = _btd;
        btb = _btb;
        treasury = _treasury;
    }

    function redeemBTDWithPermit(
        uint256 btdAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        btd.permit(msg.sender, address(this), btdAmount, deadline, v, r, s);
        btd.burnFrom(msg.sender, btdAmount);
        btdRedeemed += btdAmount;
    }

    function redeemBTBWithPermit(
        uint256 btbAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        btb.permit(msg.sender, address(this), btbAmount, deadline, v, r, s);
        btb.burnFrom(msg.sender, btbAmount);
        btbRedeemed += btbAmount;
    }
}

/**
 * @title Permit Function Fuzz Tests
 * @notice Tests for EIP-2612 permit signature functionality
 */
contract PermitFuzzTest is Test {
    MockPermitToken public btd;
    MockPermitToken public btb;
    MockMinterWithPermit public minter;
    address public treasury;

    uint256 internal constant ALICE_PK = 0xA11CE;
    uint256 internal constant BOB_PK = 0xB0B;
    address internal alice;
    address internal bob;

    function setUp() public {
        alice = vm.addr(ALICE_PK);
        bob = vm.addr(BOB_PK);
        treasury = address(0x7777);

        btd = new MockPermitToken("Bitcoin Dollar", "BTD");
        btb = new MockPermitToken("Bitcoin Bond", "BTB");
        minter = new MockMinterWithPermit(btd, btb, treasury);

        // Mint tokens to alice
        btd.mint(alice, 1000e18);
        btb.mint(alice, 1000e18);
    }

    // ============ BTD Permit Tests ============

    /// @notice Test valid permit signature for BTD redemption
    function testFuzz_RedeemBTDWithPermit_ValidSignature(uint64 amount) public {
        amount = uint64(bound(amount, 1e18, 1000e18));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount,
            0, // nonce
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        vm.prank(alice);
        minter.redeemBTDWithPermit(amount, deadline, v, r, s);

        assertEq(minter.btdRedeemed(), amount, "BTD should be redeemed");
        assertEq(btd.balanceOf(alice), 1000e18 - amount, "Alice balance should decrease");
    }

    /// @notice Test permit with expired deadline
    function testFuzz_RedeemBTDWithPermit_ExpiredDeadline(uint64 amount, uint32 expiredTime) public {
        amount = uint64(bound(amount, 1e18, 1000e18));
        expiredTime = uint32(bound(expiredTime, 1, 365 days));

        // Warp to a future time first to avoid underflow
        vm.warp(block.timestamp + 1000 days);

        uint256 deadline = block.timestamp - expiredTime; // Expired deadline

        bytes32 permitHash = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount,
            0,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        vm.prank(alice);
        vm.expectRevert("permit expired");
        minter.redeemBTDWithPermit(amount, deadline, v, r, s);
    }

    /// @notice Test permit with wrong signer
    function testFuzz_RedeemBTDWithPermit_WrongSigner(uint64 amount) public {
        amount = uint64(bound(amount, 1e18, 1000e18));
        uint256 deadline = block.timestamp + 1 hours;

        // Sign with Bob's key for Alice's tokens
        bytes32 permitHash = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount,
            0,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BOB_PK, permitHash); // Wrong signer

        vm.prank(alice);
        vm.expectRevert("invalid signer");
        minter.redeemBTDWithPermit(amount, deadline, v, r, s);
    }

    /// @notice Test permit replay attack (using same signature twice)
    function testFuzz_RedeemBTDWithPermit_ReplayAttack(uint64 amount) public {
        amount = uint64(bound(amount, 1e18, 500e18)); // Use half to allow second attempt
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount,
            0,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        // First redemption should succeed
        vm.prank(alice);
        minter.redeemBTDWithPermit(amount, deadline, v, r, s);

        // Second redemption with same signature should fail (nonce increased)
        vm.prank(alice);
        vm.expectRevert("invalid signer");
        minter.redeemBTDWithPermit(amount, deadline, v, r, s);
    }

    /// @notice Test permit with sequential nonces
    function testFuzz_RedeemBTDWithPermit_SequentialNonces(uint256 seed1, uint256 seed2) public {
        // Use uint256 for bounds, then convert to safe range
        uint256 amount1 = bound(seed1, 1e18, 450e18);
        uint256 maxAmount2 = 1000e18 - amount1;
        uint256 amount2 = bound(seed2, 1e18, maxAmount2 > 1e18 ? maxAmount2 : 1e18);
        uint256 deadline = block.timestamp + 1 hours;

        // First permit with nonce 0
        bytes32 permitHash1 = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount1,
            0, // nonce 0
            deadline
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ALICE_PK, permitHash1);

        vm.prank(alice);
        minter.redeemBTDWithPermit(amount1, deadline, v1, r1, s1);

        // Second permit with nonce 1
        bytes32 permitHash2 = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount2,
            1, // nonce 1
            deadline
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ALICE_PK, permitHash2);

        vm.prank(alice);
        minter.redeemBTDWithPermit(amount2, deadline, v2, r2, s2);

        assertEq(minter.btdRedeemed(), amount1 + amount2, "Total redeemed should match");
    }

    // ============ BTB Permit Tests ============

    /// @notice Test valid permit signature for BTB redemption
    function testFuzz_RedeemBTBWithPermit_ValidSignature(uint64 amount) public {
        amount = uint64(bound(amount, 1e18, 1000e18));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            address(btb),
            alice,
            address(minter),
            amount,
            0,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        vm.prank(alice);
        minter.redeemBTBWithPermit(amount, deadline, v, r, s);

        assertEq(minter.btbRedeemed(), amount, "BTB should be redeemed");
        assertEq(btb.balanceOf(alice), 1000e18 - amount, "Alice balance should decrease");
    }

    /// @notice Test BTB permit with expired deadline
    function testFuzz_RedeemBTBWithPermit_ExpiredDeadline(uint64 amount) public {
        amount = uint64(bound(amount, 1e18, 1000e18));
        uint256 deadline = block.timestamp - 1; // Expired

        bytes32 permitHash = _getPermitHash(
            address(btb),
            alice,
            address(minter),
            amount,
            0,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        vm.prank(alice);
        vm.expectRevert("permit expired");
        minter.redeemBTBWithPermit(amount, deadline, v, r, s);
    }

    /// @notice Test permit with invalid v value
    function testFuzz_PermitInvalidV(uint64 amount, uint8 badV) public {
        vm.assume(badV != 27 && badV != 28);
        amount = uint64(bound(amount, 1e18, 1000e18));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            amount,
            0,
            deadline
        );

        (, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        vm.prank(alice);
        vm.expectRevert(); // Will fail signature recovery
        minter.redeemBTDWithPermit(amount, deadline, badV, r, s);
    }

    /// @notice Test permit with tampered amount
    function testFuzz_PermitTamperedAmount(uint64 signedAmount, uint64 tamperedAmount) public {
        signedAmount = uint64(bound(signedAmount, 1e18, 500e18));
        tamperedAmount = uint64(bound(tamperedAmount, 501e18, 1000e18));
        vm.assume(signedAmount != tamperedAmount);

        uint256 deadline = block.timestamp + 1 hours;

        // Sign for signedAmount
        bytes32 permitHash = _getPermitHash(
            address(btd),
            alice,
            address(minter),
            signedAmount,
            0,
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, permitHash);

        // Try to redeem tamperedAmount with signature for signedAmount
        vm.prank(alice);
        vm.expectRevert("invalid signer");
        minter.redeemBTDWithPermit(tamperedAmount, deadline, v, r, s);
    }

    // ============ Helper Functions ============

    function _getPermitHash(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
        );

        bytes32 domainSeparator = MockPermitToken(token).DOMAIN_SEPARATOR();

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

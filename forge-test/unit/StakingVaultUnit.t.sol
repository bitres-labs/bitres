// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/BTD.sol";
import "../../contracts/BTB.sol";
import "../../contracts/stBTD.sol";
import "../../contracts/stBTB.sol";
import "../helpers/ProxyTestHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title StakingVaultUnit - Unit tests for stBTD and stBTB ERC4626 vaults
contract StakingVaultUnit is Test {
    BTD public btd;
    BTB public btb;
    stBTD public stbtd;
    stBTB public stbtb;

    address public deployer;

    uint256 public alicePk = 0xa11ce;
    address public alice;

    uint256 public bobPk = 0xb0b;
    address public bob;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        deployer = address(this);
        alice = vm.addr(alicePk);
        bob = vm.addr(bobPk);

        // Deploy tokens via proxy
        btd = ProxyTestHelper.deployBTD(deployer);
        btb = ProxyTestHelper.deployBTB(deployer);

        // Grant minter role to deployer
        btd.grantRole(MINTER_ROLE, deployer);
        btb.grantRole(MINTER_ROLE, deployer);

        // Deploy vaults via proxy
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);

        // Mint tokens to test users
        btd.mint(alice, 1000 ether);
        btd.mint(bob, 1000 ether);
        btb.mint(alice, 1000 ether);
        btb.mint(bob, 1000 ether);
    }

    // ========================================================================
    // Basic ERC4626 tests for stBTD
    // ========================================================================

    function test_deposit_basic() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        btd.approve(address(stbtd), amount);
        uint256 shares = stbtd.deposit(amount, alice);
        vm.stopPrank();

        // 1:1 ratio initially
        assertEq(shares, amount, "Shares should equal deposit amount initially");
        assertEq(stbtd.balanceOf(alice), amount, "Alice should hold 100 stBTD shares");
        assertEq(btd.balanceOf(address(stbtd)), amount, "Vault should hold 100 BTD");
    }

    function test_withdraw_basic() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        btd.approve(address(stbtd), amount);
        stbtd.deposit(amount, alice);

        uint256 btdBefore = btd.balanceOf(alice);
        stbtd.withdraw(amount, alice, alice);
        vm.stopPrank();

        assertEq(btd.balanceOf(alice) - btdBefore, amount, "Alice should receive 100 BTD back");
        assertEq(stbtd.balanceOf(alice), 0, "Alice should have 0 shares after withdrawal");
    }

    function test_redeem_basic() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        btd.approve(address(stbtd), amount);
        uint256 shares = stbtd.deposit(amount, alice);

        uint256 btdBefore = btd.balanceOf(alice);
        uint256 assets = stbtd.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(assets, amount, "Redeemed assets should equal deposited amount");
        assertEq(btd.balanceOf(alice) - btdBefore, amount, "Alice should receive 100 BTD back");
        assertEq(stbtd.balanceOf(alice), 0, "Alice should have 0 shares after redeem");
    }

    function test_convertToShares_initial() public view {
        uint256 shares = stbtd.convertToShares(1 ether);
        assertEq(shares, 1 ether, "1:1 conversion initially");
    }

    function test_convertToAssets_initial() public view {
        uint256 assets = stbtd.convertToAssets(1 ether);
        assertEq(assets, 1 ether, "1:1 conversion initially");
    }

    function test_convertToShares_afterInterest() public {
        // Alice deposits 100 BTD
        vm.startPrank(alice);
        btd.approve(address(stbtd), 100 ether);
        stbtd.deposit(100 ether, alice);
        vm.stopPrank();

        // Simulate interest: transfer 100 BTD directly to vault (doubles the assets)
        btd.mint(address(stbtd), 100 ether);

        // Now 100 shares back 200 BTD, so 1 BTD = 0.5 shares
        uint256 shares = stbtd.convertToShares(100 ether);
        assertEq(shares, 50 ether, "100 BTD should convert to 50 shares after 2x interest");
    }

    function test_convertToAssets_afterInterest() public {
        // Alice deposits 100 BTD
        vm.startPrank(alice);
        btd.approve(address(stbtd), 100 ether);
        stbtd.deposit(100 ether, alice);
        vm.stopPrank();

        // Simulate interest: transfer 100 BTD directly to vault (doubles the assets)
        btd.mint(address(stbtd), 100 ether);

        // Now 100 shares back 200 BTD, so 1 share = 2 BTD
        // Note: ERC4626 virtual shares offset causes up to 1 wei rounding
        uint256 assets = stbtd.convertToAssets(50 ether);
        assertApproxEqAbs(assets, 100 ether, 1, "50 shares should convert to ~100 BTD after 2x interest");
    }

    function test_decimals() public view {
        assertEq(stbtd.decimals(), 18, "stBTD decimals should be 18");
        assertEq(stbtb.decimals(), 18, "stBTB decimals should be 18");
    }

    function test_maxDeposit() public view {
        assertEq(stbtd.maxDeposit(alice), type(uint256).max, "maxDeposit should return max uint256");
    }

    function test_maxRedeem() public {
        // Before deposit, max redeem is 0
        assertEq(stbtd.maxRedeem(alice), 0, "maxRedeem should be 0 before deposit");

        // After deposit
        vm.startPrank(alice);
        btd.approve(address(stbtd), 100 ether);
        stbtd.deposit(100 ether, alice);
        vm.stopPrank();

        assertEq(stbtd.maxRedeem(alice), 100 ether, "maxRedeem should equal user's share balance");
    }

    function test_totalAssets() public {
        assertEq(stbtd.totalAssets(), 0, "totalAssets should be 0 initially");

        vm.startPrank(alice);
        btd.approve(address(stbtd), 100 ether);
        stbtd.deposit(100 ether, alice);
        vm.stopPrank();

        assertEq(stbtd.totalAssets(), 100 ether, "totalAssets should match deposited BTD");

        // Direct transfer also increases totalAssets
        btd.mint(address(stbtd), 50 ether);
        assertEq(stbtd.totalAssets(), 150 ether, "totalAssets should include directly transferred BTD");
    }

    // ========================================================================
    // Interest accumulation
    // ========================================================================

    function test_interestAccumulation() public {
        // Alice deposits 100 BTD
        vm.startPrank(alice);
        btd.approve(address(stbtd), 100 ether);
        stbtd.deposit(100 ether, alice);
        vm.stopPrank();

        // Simulate interest: 10 BTD transferred to vault
        btd.mint(address(stbtd), 10 ether);

        // Alice's 100 shares should now be worth 110 BTD
        // Note: ERC4626 virtual shares offset causes up to 1 wei rounding
        uint256 redeemable = stbtd.convertToAssets(stbtd.balanceOf(alice));
        assertApproxEqAbs(redeemable, 110 ether, 1, "Alice's shares should be worth ~110 BTD after 10 BTD interest");

        // Actually redeem and verify
        vm.startPrank(alice);
        uint256 assets = stbtd.redeem(stbtd.balanceOf(alice), alice, alice);
        vm.stopPrank();

        assertApproxEqAbs(assets, 110 ether, 1, "Alice should redeem ~110 BTD");
    }

    // ========================================================================
    // stBTB basic tests
    // ========================================================================

    function test_stBTB_deposit_withdraw() public {
        uint256 amount = 100 ether;

        // Deposit
        vm.startPrank(alice);
        btb.approve(address(stbtb), amount);
        uint256 shares = stbtb.deposit(amount, alice);
        vm.stopPrank();

        assertEq(shares, amount, "stBTB shares should equal deposit amount initially");
        assertEq(stbtb.balanceOf(alice), amount, "Alice should hold 100 stBTB shares");

        // Withdraw
        vm.startPrank(alice);
        uint256 btbBefore = btb.balanceOf(alice);
        stbtb.withdraw(amount, alice, alice);
        vm.stopPrank();

        assertEq(btb.balanceOf(alice) - btbBefore, amount, "Alice should receive 100 BTB back");
        assertEq(stbtb.balanceOf(alice), 0, "Alice should have 0 stBTB shares");
    }

    function test_stBTB_convertToShares() public {
        // Initial 1:1
        assertEq(stbtb.convertToShares(1 ether), 1 ether, "stBTB 1:1 conversion initially");

        // After deposit and interest
        vm.startPrank(alice);
        btb.approve(address(stbtb), 200 ether);
        stbtb.deposit(200 ether, alice);
        vm.stopPrank();

        btb.mint(address(stbtb), 100 ether);

        // 200 shares back 300 BTB => 1 BTB = 200/300 = 2/3 shares
        uint256 shares = stbtb.convertToShares(300 ether);
        assertEq(shares, 200 ether, "300 BTB should convert to 200 shares after interest");
    }

    function test_stBTB_redeem() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        btb.approve(address(stbtb), amount);
        uint256 shares = stbtb.deposit(amount, alice);

        uint256 btbBefore = btb.balanceOf(alice);
        uint256 assets = stbtb.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(assets, amount, "Redeemed assets should equal deposited amount");
        assertEq(btb.balanceOf(alice) - btbBefore, amount, "Alice should receive 100 BTB back");
        assertEq(stbtb.balanceOf(alice), 0, "Alice should have 0 stBTB shares after redeem");
    }

    function test_stBTB_convertToAssets_afterInterest() public {
        // Alice deposits 100 BTB
        vm.startPrank(alice);
        btb.approve(address(stbtb), 100 ether);
        stbtb.deposit(100 ether, alice);
        vm.stopPrank();

        // Simulate interest: transfer 100 BTB directly to vault (doubles the assets)
        btb.mint(address(stbtb), 100 ether);

        // Now 100 shares back 200 BTB, so 1 share = 2 BTB
        // Note: ERC4626 virtual shares offset causes up to 1 wei rounding
        uint256 assets = stbtb.convertToAssets(50 ether);
        assertApproxEqAbs(assets, 100 ether, 1, "50 shares should convert to ~100 BTB after 2x interest");
    }

    function test_stBTB_totalAssets() public {
        assertEq(stbtb.totalAssets(), 0, "totalAssets should be 0 initially");

        vm.startPrank(alice);
        btb.approve(address(stbtb), 100 ether);
        stbtb.deposit(100 ether, alice);
        vm.stopPrank();

        assertEq(stbtb.totalAssets(), 100 ether, "totalAssets should match deposited BTB");

        // Direct transfer also increases totalAssets
        btb.mint(address(stbtb), 50 ether);
        assertEq(stbtb.totalAssets(), 150 ether, "totalAssets should include directly transferred BTB");
    }

    function test_stBTB_maxDeposit() public view {
        assertEq(stbtb.maxDeposit(alice), type(uint256).max, "maxDeposit should return max uint256");
    }

    function test_stBTB_maxRedeem() public {
        // Before deposit, max redeem is 0
        assertEq(stbtb.maxRedeem(alice), 0, "maxRedeem should be 0 before deposit");

        // After deposit
        vm.startPrank(alice);
        btb.approve(address(stbtb), 100 ether);
        stbtb.deposit(100 ether, alice);
        vm.stopPrank();

        assertEq(stbtb.maxRedeem(alice), 100 ether, "maxRedeem should equal user's share balance");
    }

    function test_stBTB_interestAccumulation() public {
        // Alice deposits 100 BTB
        vm.startPrank(alice);
        btb.approve(address(stbtb), 100 ether);
        stbtb.deposit(100 ether, alice);
        vm.stopPrank();

        // Simulate interest: 10 BTB transferred to vault
        btb.mint(address(stbtb), 10 ether);

        // Alice's 100 shares should now be worth 110 BTB
        // Note: ERC4626 virtual shares offset causes up to 1 wei rounding
        uint256 redeemable = stbtb.convertToAssets(stbtb.balanceOf(alice));
        assertApproxEqAbs(redeemable, 110 ether, 1, "Alice's shares should be worth ~110 BTB after 10 BTB interest");

        // Actually redeem and verify
        vm.startPrank(alice);
        uint256 assets = stbtb.redeem(stbtb.balanceOf(alice), alice, alice);
        vm.stopPrank();

        assertApproxEqAbs(assets, 110 ether, 1, "Alice should redeem ~110 BTB");
    }

    function test_stBTB_depositWithPermit() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Build permit digest for BTB
        bytes32 domainSeparator = btb.DOMAIN_SEPARATOR();
        uint256 nonce = btb.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, address(stbtb), amount, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        // Deposit with permit (alice calls)
        vm.prank(alice);
        uint256 shares = stbtb.depositWithPermit(amount, alice, deadline, v, r, s);

        assertEq(shares, amount, "Shares should equal deposit amount");
        assertEq(stbtb.balanceOf(alice), amount, "Alice should hold shares");
        assertEq(btb.balanceOf(address(stbtb)), amount, "Vault should hold BTB");
    }

    function test_stBTB_mintWithPermit() public {
        uint256 sharesToMint = 100 ether;
        // At 1:1 ratio, assets required equals shares
        uint256 assetsRequired = stbtb.previewMint(sharesToMint);
        uint256 deadline = block.timestamp + 1 hours;

        // Build permit digest for BTB
        bytes32 domainSeparator = btb.DOMAIN_SEPARATOR();
        uint256 nonce = btb.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, address(stbtb), assetsRequired, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        // Mint with permit (alice calls)
        vm.prank(alice);
        uint256 assets = stbtb.mintWithPermit(sharesToMint, alice, deadline, v, r, s);

        assertEq(assets, assetsRequired, "Assets deposited should match preview");
        assertEq(stbtb.balanceOf(alice), sharesToMint, "Alice should hold minted shares");
        assertEq(btb.balanceOf(address(stbtb)), assetsRequired, "Vault should hold BTB");
    }

    function test_stBTB_multipleDepositors() public {
        // Alice deposits 100 BTB
        vm.startPrank(alice);
        btb.approve(address(stbtb), 100 ether);
        stbtb.deposit(100 ether, alice);
        vm.stopPrank();

        // Interest accrues: 50 BTB added to vault
        btb.mint(address(stbtb), 50 ether);

        // Vault state: 150 BTB total, 100 shares total
        // 1 share = 1.5 BTB, so 100 BTB buys 100/1.5 = 66.666... shares
        vm.startPrank(bob);
        btb.approve(address(stbtb), 100 ether);
        uint256 bobShares = stbtb.deposit(100 ether, bob);
        vm.stopPrank();

        // Bob should get fewer shares than alice
        assertLt(bobShares, 100 ether, "Bob should receive fewer shares due to accrued interest");

        // Verify exact share count: 100 * 100 / 150 = 66.666...
        uint256 expectedBobShares = uint256(100 ether) * uint256(100 ether) / uint256(150 ether);
        assertEq(bobShares, expectedBobShares, "Bob's shares should reflect the current exchange rate");

        // Alice's shares are still worth more than Bob's per share
        uint256 aliceAssets = stbtb.convertToAssets(stbtb.balanceOf(alice));
        uint256 bobAssets = stbtb.convertToAssets(stbtb.balanceOf(bob));

        // Note: ERC4626 virtual shares offset causes up to 1 wei rounding
        assertApproxEqAbs(aliceAssets, 150 ether, 1, "Alice's shares should be worth ~150 BTB (including interest)");
        assertApproxEqAbs(bobAssets, 100 ether, 1, "Bob's shares should be worth ~100 BTB (no interest gain)");
    }

    // ========================================================================
    // depositWithPermit
    // ========================================================================

    function test_depositWithPermit() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Build permit digest for BTD
        bytes32 domainSeparator = btd.DOMAIN_SEPARATOR();
        uint256 nonce = btd.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, address(stbtd), amount, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        // Deposit with permit (alice calls)
        vm.prank(alice);
        uint256 shares = stbtd.depositWithPermit(amount, alice, deadline, v, r, s);

        assertEq(shares, amount, "Shares should equal deposit amount");
        assertEq(stbtd.balanceOf(alice), amount, "Alice should hold shares");
        assertEq(btd.balanceOf(address(stbtd)), amount, "Vault should hold BTD");
    }

    // ========================================================================
    // mintWithPermit
    // ========================================================================

    function test_mintWithPermit() public {
        uint256 sharesToMint = 100 ether;
        // At 1:1 ratio, assets required equals shares
        uint256 assetsRequired = stbtd.previewMint(sharesToMint);
        uint256 deadline = block.timestamp + 1 hours;

        // Build permit digest for BTD
        bytes32 domainSeparator = btd.DOMAIN_SEPARATOR();
        uint256 nonce = btd.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, address(stbtd), assetsRequired, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        // Mint with permit (alice calls)
        vm.prank(alice);
        uint256 assets = stbtd.mintWithPermit(sharesToMint, alice, deadline, v, r, s);

        assertEq(assets, assetsRequired, "Assets deposited should match preview");
        assertEq(stbtd.balanceOf(alice), sharesToMint, "Alice should hold minted shares");
        assertEq(btd.balanceOf(address(stbtd)), assetsRequired, "Vault should hold BTD");
    }

    // ========================================================================
    // Multiple depositors
    // ========================================================================

    function test_multipleDepositors() public {
        // Alice deposits 100 BTD
        vm.startPrank(alice);
        btd.approve(address(stbtd), 100 ether);
        stbtd.deposit(100 ether, alice);
        vm.stopPrank();

        // Interest accrues: 50 BTD added to vault
        btd.mint(address(stbtd), 50 ether);

        // Vault state: 150 BTD total, 100 shares total
        vm.startPrank(bob);
        btd.approve(address(stbtd), 100 ether);
        uint256 bobShares = stbtd.deposit(100 ether, bob);
        vm.stopPrank();

        // Bob should get fewer shares than alice
        assertLt(bobShares, 100 ether, "Bob should receive fewer shares due to accrued interest");

        // Verify exact share count: 100 * 100 / 150 = 66.666...
        uint256 expectedBobShares = uint256(100 ether) * uint256(100 ether) / uint256(150 ether);
        assertEq(bobShares, expectedBobShares, "Bob's shares should reflect the current exchange rate");

        uint256 aliceAssets = stbtd.convertToAssets(stbtd.balanceOf(alice));
        uint256 bobAssets = stbtd.convertToAssets(stbtd.balanceOf(bob));

        // Note: ERC4626 virtual shares offset causes up to 1 wei rounding
        assertApproxEqAbs(aliceAssets, 150 ether, 1, "Alice's shares should be worth ~150 BTD (including interest)");
        assertApproxEqAbs(bobAssets, 100 ether, 1, "Bob's shares should be worth ~100 BTD (no interest gain)");
    }
}

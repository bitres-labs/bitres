// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInterestPool} from "./interfaces/IInterestPool.sol";

/**
 * @title stBTD - BTD Staking Receipt (Pure ERC4626 Implementation)
 * @notice UUPS upgradeable standard ERC4626 vault, holding BTD as underlying asset
 * @dev Contains no business logic, serves only as share token
 *      - Users deposit BTD, receive stBTD shares
 *      - stBTD can be transferred, traded, used in DeFi composables
 *      - Redeeming stBTD returns BTD
 *      - Interest logic is managed by external contracts (e.g., InterestPool)
 *      - Supports EIP-2612 permit for gasless approvals via depositWithPermit
 */
contract stBTD is
    Initializable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    IInterestPool public interestPool;

    event InterestPoolUpdated(address indexed oldInterestPool, address indexed newInterestPool);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize stBTD vault
     * @param btd BTD token address
     * @param initialOwner Owner address for upgrade authorization
     */
    function initialize(IERC20 btd, address initialOwner) public initializer {
        require(address(btd) != address(0), "stBTD: zero asset");
        require(initialOwner != address(0), "stBTD: zero owner");

        __ERC20_init("Staked Bitcoin Dollar", "stBTD");
        __ERC4626_init(btd);
        __ERC20Permit_init("Staked Bitcoin Dollar");
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setInterestPool(address newInterestPool) external onlyOwner {
        address oldInterestPool = address(interestPool);
        interestPool = IInterestPool(newInterestPool);
        emit InterestPoolUpdated(oldInterestPool, newInterestPool);
    }

    function stakeIdleAssets(uint256 assets) external onlyOwner {
        _stakeIdleAssets(assets);
    }

    /**
     * @notice Gets token decimals (18 digits)
     * @dev Overrides decimals function from ERC20Upgradeable and ERC4626Upgradeable
     * @return Decimal places
     */
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return super.decimals();
    }

    function totalAssets() public view override returns (uint256) {
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        if (address(interestPool) == address(0)) {
            return idleAssets;
        }
        return idleAssets + interestPool.totalAssetsOf(asset(), address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override nonReentrant {
        IERC20 assetToken = IERC20(asset());
        assetToken.safeTransferFrom(caller, address(this), assets);
        _stakeIdleAssets(assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        _ensureAssetsAvailable(assets);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _stakeIdleAssets(uint256 assets) internal {
        if (assets == 0 || address(interestPool) == address(0)) {
            return;
        }

        IERC20 assetToken = IERC20(asset());
        assetToken.forceApprove(address(interestPool), assets);
        interestPool.stakeBTD(assets);
    }

    function _ensureAssetsAvailable(uint256 assets) internal {
        IERC20 assetToken = IERC20(asset());
        uint256 balance = assetToken.balanceOf(address(this));
        if (balance >= assets || address(interestPool) == address(0)) {
            return;
        }

        interestPool.unstakeBTD(assets - balance);
        require(assetToken.balanceOf(address(this)) >= assets, "stBTD: insufficient assets");
    }

    /**
     * @notice Deposit BTD with permit (gasless approval)
     * @dev Uses EIP-2612 permit to approve and deposit in one transaction
     * @param assets Amount of BTD to deposit
     * @param receiver Address to receive stBTD shares
     * @param deadline Permit deadline timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
     * @return shares Amount of stBTD shares minted
     */
    function depositWithPermit(
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        // Use permit to set allowance
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);
        // Deposit assets
        return deposit(assets, receiver);
    }

    /**
     * @notice Mint stBTD shares with permit (gasless approval)
     * @dev Uses EIP-2612 permit to approve and mint in one transaction
     * @param shares Amount of stBTD shares to mint
     * @param receiver Address to receive stBTD shares
     * @param deadline Permit deadline timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
     * @return assets Amount of BTD deposited
     */
    function mintWithPermit(
        uint256 shares,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 assets) {
        // Calculate required assets
        assets = previewMint(shares);
        // Use permit to set allowance
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);
        // Mint shares
        return mint(shares, receiver);
    }

    // ============ Storage Gap ============

    uint256[49] private __gap;
}

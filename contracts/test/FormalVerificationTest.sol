// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title FormalVerificationTest
 * @notice Test contract for SMTChecker formal verification
 * @dev Contains assertions that SMTChecker should verify
 */
contract FormalVerificationTest {

    /**
     * @notice Test addition overflow protection
     * @dev SMTChecker should verify that this cannot overflow due to bounds
     */
    function safeAdd(uint128 a, uint128 b) public pure returns (uint256) {
        uint256 result = uint256(a) + uint256(b);
        // SMTChecker should prove this assertion always holds
        // because uint128 + uint128 <= type(uint256).max
        assert(result >= a);
        assert(result >= b);
        return result;
    }

    /**
     * @notice Test multiplication overflow protection
     * @dev SMTChecker should verify bounds are respected
     */
    function safeMul(uint128 a, uint128 b) public pure returns (uint256) {
        uint256 result = uint256(a) * uint256(b);
        // If a != 0, then result / a == b (no overflow)
        if (a != 0) {
            assert(result / a == b);
        }
        return result;
    }

    /**
     * @notice Test division safety
     * @dev SMTChecker should verify no division by zero
     */
    function safeDiv(uint256 a, uint256 b) public pure returns (uint256) {
        require(b > 0, "Division by zero");
        uint256 result = a / b;
        // Result should not exceed numerator
        assert(result <= a);
        return result;
    }

    /**
     * @notice Test collateral ratio invariant
     * @dev CR = collateral / debt, should be >= 1e18 when overcollateralized
     */
    function collateralRatioInvariant(
        uint256 collateralValue,
        uint256 debtValue
    ) public pure returns (uint256 cr) {
        require(debtValue > 0, "Zero debt");
        require(collateralValue <= type(uint256).max / 1e18, "Overflow prevention");

        cr = (collateralValue * 1e18) / debtValue;

        // If collateral >= debt, then CR >= 1e18
        if (collateralValue >= debtValue) {
            assert(cr >= 1e18);
        }

        // If collateral < debt, then CR < 1e18
        if (collateralValue < debtValue) {
            assert(cr < 1e18);
        }

        return cr;
    }

    /**
     * @notice Test share value invariant for ERC4626-like vaults
     * @dev shares * totalAssets / totalSupply should round down
     */
    function shareValueInvariant(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalSupply
    ) public pure returns (uint256 assets) {
        require(totalSupply > 0, "Zero supply");
        require(shares <= totalSupply, "Shares exceed supply");

        assets = (shares * totalAssets) / totalSupply;

        // Individual share value <= total assets (no creation of value)
        assert(assets <= totalAssets);

        // If you have all shares, you get all assets (minus rounding)
        if (shares == totalSupply) {
            assert(assets == totalAssets);
        }

        return assets;
    }
}

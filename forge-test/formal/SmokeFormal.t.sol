// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/OracleMath.sol";

/// @notice Fast symbolic smoke checks used by CI to ensure Halmos runs and fails
///         the workflow on counterexamples or timeouts.
contract FormalSmokeTest is Test {
    function check_smoke_normalize_18_identity(uint32 amount) public pure {
        assert(OracleMath.normalizeAmount(amount, 18) == amount);
    }

    function check_smoke_deviation_reflexive(uint32 price, uint16 maxBps) public pure {
        vm.assume(price > 0);
        vm.assume(maxBps > 0);
        assert(OracleMath.deviationWithin(price, price, maxBps));
    }

    function check_smoke_bps_constant_positive() public pure {
        assert(Constants.BPS_BASE == 10_000);
    }
}

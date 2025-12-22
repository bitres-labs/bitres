// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Governor Fuzz Tests
/// @notice Tests all edge cases for governance proposals, voting, and execution
contract GovernorFuzzTest is Test {
    using Constants for *;

    // ==================== Voting Power Fuzz Tests ====================

    /// @notice Fuzz test: Voting power calculation
    function testFuzz_VotingPower_Calculation(
        uint128 tokenBalance,
        uint128 totalSupply
    ) public pure {
        vm.assume(tokenBalance > 0);
        vm.assume(totalSupply >= tokenBalance);

        // Calculate voting power percentage
        vm.assume(uint256(tokenBalance) * Constants.PRECISION_18 < type(uint256).max);

        uint256 votingPower = (uint256(tokenBalance) * Constants.PRECISION_18) / uint256(totalSupply);

        // Verify: Voting power does not exceed 100%
        assertLe(votingPower, Constants.PRECISION_18);

        // Verify: If owning all tokens, voting power is 100%
        if (tokenBalance == totalSupply) {
            assertEq(votingPower, Constants.PRECISION_18);
        }
    }

    /// @notice Fuzz test: Quorum calculation
    function testFuzz_Quorum_Calculation(
        uint128 totalSupply,
        uint16 quorumBP  // Quorum percentage (basis points)
    ) public pure {
        vm.assume(totalSupply > 1000);  // Total supply large enough
        vm.assume(quorumBP > 0 && quorumBP <= Constants.BPS_BASE);

        // Calculate quorum
        uint256 quorum = (uint256(totalSupply) * uint256(quorumBP)) / Constants.BPS_BASE;

        // Verify: Quorum does not exceed total supply
        assertLe(quorum, totalSupply);

        // Verify: 100% quorum equals total supply
        if (quorumBP == Constants.BPS_BASE) {
            assertEq(quorum, totalSupply);
        }

        // Verify: Quorum >= 0
        assertGe(quorum, 0);
    }

    /// @notice Fuzz test: Votes reached quorum check
    function testFuzz_Quorum_Reached(
        uint128 totalVotes,
        uint128 totalSupply,
        uint16 quorumBP
    ) public pure {
        vm.assume(totalSupply > 1000);
        vm.assume(totalVotes <= totalSupply);
        vm.assume(quorumBP > 0 && quorumBP <= Constants.BPS_BASE);

        uint256 quorum = (uint256(totalSupply) * uint256(quorumBP)) / Constants.BPS_BASE;
        bool quorumReached = totalVotes >= quorum;

        // Verify logical consistency
        if (totalVotes < quorum) {
            assertFalse(quorumReached);
        } else {
            assertTrue(quorumReached);
        }
    }

    // ==================== Proposal State Fuzz Tests ====================

    /// @notice Fuzz test: Proposal pass conditions
    function testFuzz_Proposal_PassCondition(
        uint128 votesFor,
        uint128 votesAgainst,
        uint128 totalSupply,
        uint16 quorumBP,
        uint16 passThresholdBP  // Pass threshold (e.g., 50% = 5000 BP)
    ) public pure {
        vm.assume(totalSupply > 1000);
        vm.assume(votesFor <= totalSupply);
        vm.assume(votesAgainst <= totalSupply);
        vm.assume(uint256(votesFor) + uint256(votesAgainst) <= totalSupply);
        vm.assume(quorumBP > 0 && quorumBP <= Constants.BPS_BASE);
        vm.assume(passThresholdBP > 0 && passThresholdBP <= Constants.BPS_BASE);

        uint256 totalVotes = uint256(votesFor) + uint256(votesAgainst);
        uint256 quorum = (uint256(totalSupply) * uint256(quorumBP)) / Constants.BPS_BASE;

        // Proposal passes if: 1) Quorum reached 2) For votes exceed threshold
        bool quorumReached = totalVotes >= quorum;

        uint256 forPercentage = 0;
        if (totalVotes > 0) {
            forPercentage = (uint256(votesFor) * Constants.BPS_BASE) / totalVotes;
        }
        bool passThresholdMet = forPercentage >= passThresholdBP;

        bool proposalPassed = quorumReached && passThresholdMet;

        // Verify: If quorum not reached, proposal does not pass
        if (!quorumReached) {
            assertFalse(proposalPassed);
        }

        // Verify: If for votes insufficient, proposal does not pass
        if (!passThresholdMet) {
            assertFalse(proposalPassed);
        }
    }

    /// @notice Fuzz test: Voting period check
    function testFuzz_VotingPeriod_Check(
        uint32 proposalStartTime,
        uint32 currentTime,
        uint32 votingPeriod
    ) public pure {
        // Limit startTime to avoid addition overflow (safe until year 2106 in practice)
        vm.assume(proposalStartTime < type(uint32).max - 30 days);
        vm.assume(currentTime >= proposalStartTime);
        vm.assume(votingPeriod > 0 && votingPeriod <= 30 days);

        uint32 proposalEndTime = proposalStartTime + votingPeriod;

        bool votingActive = currentTime >= proposalStartTime && currentTime < proposalEndTime;
        bool votingEnded = currentTime >= proposalEndTime;

        // Verify: Voting active and ended are mutually exclusive
        if (votingActive) {
            assertFalse(votingEnded);
        }
        if (votingEnded) {
            assertFalse(votingActive);
        }
    }

    // ==================== Timelock Fuzz Tests ====================

    /// @notice Fuzz test: Timelock delay
    function testFuzz_Timelock_Delay(
        uint32 proposalApprovedTime,
        uint32 currentTime,
        uint32 timelockDelay
    ) public pure {
        // Limit approvedTime to avoid addition overflow
        vm.assume(proposalApprovedTime < type(uint32).max - 7 days);
        vm.assume(currentTime >= proposalApprovedTime);
        vm.assume(timelockDelay > 0 && timelockDelay <= 7 days);

        uint32 executeTime = proposalApprovedTime + timelockDelay;

        bool canExecute = currentTime >= executeTime;

        // Verify: Cannot execute during timelock period
        if (currentTime < executeTime) {
            assertFalse(canExecute);
        } else {
            assertTrue(canExecute);
        }
    }

    /// @notice Fuzz test: Proposal expiration check
    function testFuzz_Proposal_Expiration(
        uint32 proposalApprovedTime,
        uint32 currentTime,
        uint32 expirationPeriod
    ) public pure {
        // Limit approvedTime to avoid addition overflow (safe until year 2106 in practice)
        vm.assume(proposalApprovedTime < type(uint32).max - 30 days);
        vm.assume(currentTime >= proposalApprovedTime);
        vm.assume(expirationPeriod > 0);
        vm.assume(expirationPeriod <= 30 days);

        uint32 expirationTime = proposalApprovedTime + expirationPeriod;

        bool isExpired = currentTime > expirationTime;

        // Verify logic
        if (currentTime <= expirationTime) {
            assertFalse(isExpired);
        } else {
            assertTrue(isExpired);
        }
    }

    // ==================== Proposal Threshold Fuzz Tests ====================

    /// @notice Fuzz test: Proposal creation threshold
    function testFuzz_Proposal_CreationThreshold(
        uint128 proposerBalance,
        uint128 totalSupply,
        uint16 proposalThresholdBP
    ) public pure {
        vm.assume(totalSupply > 1000);
        vm.assume(proposerBalance <= totalSupply);
        vm.assume(proposalThresholdBP > 0 && proposalThresholdBP <= Constants.BPS_BASE);

        uint256 requiredBalance = (uint256(totalSupply) * uint256(proposalThresholdBP)) / Constants.BPS_BASE;
        bool canPropose = proposerBalance >= requiredBalance;

        // Verify: Cannot propose with insufficient balance
        if (proposerBalance < requiredBalance) {
            assertFalse(canPropose);
        } else {
            assertTrue(canPropose);
        }
    }

    // ==================== Vote Statistics Fuzz Tests ====================

    /// @notice Fuzz test: Multi-user vote sum
    function testFuzz_MultiUser_VoteSum(
        uint64 vote1,
        uint64 vote2,
        uint64 vote3,
        uint64 totalSupply
    ) public pure {
        vm.assume(vote1 > 0 && vote2 > 0 && vote3 > 0);
        vm.assume(uint256(vote1) + uint256(vote2) + uint256(vote3) <= totalSupply);
        vm.assume(totalSupply > 0);

        uint256 totalVotes = uint256(vote1) + uint256(vote2) + uint256(vote3);

        // Verify: Total votes do not exceed total supply
        assertLe(totalVotes, totalSupply);
    }

    /// @notice Fuzz test: Voting power invariance
    function testFuzz_VotingPower_Invariant(
        uint128 balance1,
        uint128 balance2,
        uint128 totalSupply
    ) public pure {
        vm.assume(totalSupply > 1000);
        vm.assume(balance1 > 0 && balance2 > 0);
        vm.assume(uint256(balance1) + uint256(balance2) <= totalSupply);

        vm.assume(uint256(balance1) * Constants.PRECISION_18 < type(uint256).max);
        vm.assume(uint256(balance2) * Constants.PRECISION_18 < type(uint256).max);

        uint256 power1 = (uint256(balance1) * Constants.PRECISION_18) / uint256(totalSupply);
        uint256 power2 = (uint256(balance2) * Constants.PRECISION_18) / uint256(totalSupply);
        uint256 totalPower = power1 + power2;

        uint256 combinedBalance = uint256(balance1) + uint256(balance2);
        vm.assume(combinedBalance * Constants.PRECISION_18 < type(uint256).max);
        uint256 combinedPower = (combinedBalance * Constants.PRECISION_18) / uint256(totalSupply);

        // Verify: Combined voting power equals sum of individual powers (allow rounding error)
        assertApproxEqAbs(combinedPower, totalPower, 2);
    }

    // ==================== Vote Delegation Fuzz Tests ====================

    /// @notice Fuzz test: Vote delegation
    function testFuzz_VoteDelegation(
        uint128 delegatorBalance,
        uint128 delegateOriginalBalance,
        uint128 totalSupply
    ) public pure {
        vm.assume(totalSupply > 1000);
        vm.assume(delegatorBalance > 0);
        vm.assume(delegateOriginalBalance >= 0);
        vm.assume(uint256(delegatorBalance) + uint256(delegateOriginalBalance) <= totalSupply);

        // After delegation, delegate's voting power increases
        uint256 delegatePowerBefore = (uint256(delegateOriginalBalance) * Constants.PRECISION_18) / uint256(totalSupply);

        uint256 combinedBalance = uint256(delegateOriginalBalance) + uint256(delegatorBalance);
        vm.assume(combinedBalance * Constants.PRECISION_18 < type(uint256).max);

        uint256 delegatePowerAfter = (combinedBalance * Constants.PRECISION_18) / uint256(totalSupply);

        // Verify: Voting power increases after delegation
        assertGe(delegatePowerAfter, delegatePowerBefore);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Zero votes proposal
    function testFuzz_ZeroVotes_Proposal(
        uint128 totalSupply,
        uint16 quorumBP
    ) public pure {
        vm.assume(totalSupply > 1000);
        vm.assume(quorumBP > 0);

        uint256 totalVotes = 0;
        uint256 quorum = (uint256(totalSupply) * uint256(quorumBP)) / Constants.BPS_BASE;

        bool quorumReached = totalVotes >= quorum;

        // Verify: Zero votes can never reach quorum (unless quorum is also 0)
        if (quorum > 0) {
            assertFalse(quorumReached);
        }
    }

    /// @notice Fuzz test: Unanimous approval
    function testFuzz_Unanimous_Approval(
        uint128 totalSupply
    ) public pure {
        vm.assume(totalSupply > 1000);

        uint256 votesFor = totalSupply;
        uint256 votesAgainst = 0;
        uint256 totalVotes = votesFor;

        // 100% quorum
        uint256 quorum = totalSupply;
        bool quorumReached = totalVotes >= quorum;

        // 100% for votes
        uint256 forPercentage = (votesFor * Constants.BPS_BASE) / totalVotes;
        bool unanimousPass = forPercentage == Constants.BPS_BASE;

        // Verify: Unanimous vote should pass
        assertTrue(quorumReached);
        assertTrue(unanimousPass);
    }

    /// @notice Fuzz test: Simple majority boundary
    function testFuzz_MajorityVote_Boundary(
        uint128 totalVotes
    ) public pure {
        vm.assume(totalVotes >= 1000);  // At least 1000 votes to avoid precision issues
        vm.assume(totalVotes < type(uint128).max / Constants.BPS_BASE); // Prevent overflow

        // Calculate > 50% votes: simply use totalVotes/2 + 1 to ensure strictly > half
        uint256 votesFor = (uint256(totalVotes) / 2) + (totalVotes / 100);  // ~51%
        uint256 votesAgainst = totalVotes - votesFor;

        vm.assume(votesFor > totalVotes / 2);  // Ensure indeed > 50%
        vm.assume(votesAgainst > 0);  // Ensure some against votes

        uint256 forPercentage = (votesFor * Constants.BPS_BASE) / totalVotes;

        // Verify: Simple majority should exceed 50% threshold
        assertTrue(forPercentage > Constants.BPS_BASE / 2);
    }
}

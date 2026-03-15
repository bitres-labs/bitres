// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/Governor.sol";
import "../../contracts/BRS.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/// @title Governor Unit Tests
/// @notice Tests initialization, settings, quorum, and access control for Governor
contract GovernorUnitTest is Test {
    Governor public gov;
    BRS public brs;
    TimelockControllerUpgradeable public timelock;

    address public deployer = address(this);

    function setUp() public {
        // Deploy BRS token with all supply to deployer
        brs = new BRS(deployer);

        // Deploy TimelockController via proxy
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // will be set to governor later
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute

        TimelockControllerUpgradeable timelockImpl = new TimelockControllerUpgradeable();
        ERC1967Proxy timelockProxy = new ERC1967Proxy(
            address(timelockImpl),
            abi.encodeCall(TimelockControllerUpgradeable.initialize, (1 days, proposers, executors, deployer))
        );
        timelock = TimelockControllerUpgradeable(payable(address(timelockProxy)));

        // Deploy Governor via proxy
        Governor impl = new Governor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Governor.initialize, (IVotes(address(brs)), TimelockControllerUpgradeable(payable(address(timelock)))))
        );
        gov = Governor(payable(address(proxy)));
    }

    /// @notice Governor name should be "Governor" after initialization
    function test_initialize_valid() public view {
        assertEq(gov.name(), "Governor");
    }

    /// @notice Voting delay should be 1 day (86400 seconds)
    function test_votingDelay() public view {
        assertEq(gov.votingDelay(), 86400);
    }

    /// @notice Voting period should be 1 week (604800 seconds)
    function test_votingPeriod() public view {
        assertEq(gov.votingPeriod(), 604800);
    }

    /// @notice Proposal threshold should be 250,000 BRS (250_000e18)
    function test_proposalThreshold() public view {
        assertEq(gov.proposalThreshold(), 250_000e18);
    }

    /// @notice Quorum should be 4% of BRS total supply = 84,000,000e18
    function test_quorum() public {
        // Delegate votes so totalSupply checkpoint is recorded
        brs.delegate(deployer);

        // Roll forward one block so the checkpoint is available
        vm.roll(block.number + 1);

        uint256 expectedQuorum = (2_100_000_000e18 * 4) / 100; // 84_000_000e18
        assertEq(gov.quorum(block.number - 1), expectedQuorum);
    }

    /// @notice Non-governance address cannot upgrade the Governor
    function test_authorizeUpgrade_nonGovernance_reverts() public {
        Governor newImpl = new Governor();
        vm.expectRevert();
        gov.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Governance Lifecycle Tests ============

    /// @notice Helper: prepare proposal arrays for a no-op call
    function _proposalParams()
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        )
    {
        targets = new address[](1);
        targets[0] = address(brs);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("name()");
        description = "Unit test proposal";
    }

    /// @notice Helper: grant timelock PROPOSER_ROLE to the governor and delegate deployer tokens
    function _setupGovernanceRoles() internal {
        // Grant PROPOSER_ROLE to governor so it can schedule operations on the timelock
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        timelock.grantRole(proposerRole, address(gov));

        // Also grant CANCELLER_ROLE to governor for cancel flows
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        timelock.grantRole(cancellerRole, address(gov));

        // Delegate all deployer BRS to self for voting power + proposal threshold
        brs.delegate(deployer);

        // Advance 1 block so checkpoints are recorded
        vm.roll(block.number + 1);
    }

    /// @notice Full lifecycle: propose -> vote -> queue -> execute
    function test_fullLifecycle_proposeVoteQueueExecute() public {
        _setupGovernanceRoles();

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _proposalParams();

        // 1. Create proposal (exercises _propose and proposalThreshold)
        uint256 proposalId = gov.propose(targets, values, calldatas, description);
        assertTrue(proposalId != 0, "proposal ID should be nonzero");

        // State should be Pending (exercises state())
        assertEq(uint256(gov.state(proposalId)), 0); // Pending = 0

        // 2. Advance past voting delay -> Active
        vm.roll(block.number + gov.votingDelay() + 1);
        assertEq(uint256(gov.state(proposalId)), 1); // Active = 1

        // 3. Cast vote (exercises GovernorCountingSimple)
        gov.castVote(proposalId, 1); // vote For

        // 4. Advance past voting period -> Succeeded
        vm.roll(block.number + gov.votingPeriod());
        assertEq(uint256(gov.state(proposalId)), 4); // Succeeded = 4

        // 5. Queue (exercises _queueOperations and proposalNeedsQueuing)
        bytes32 descriptionHash = keccak256(bytes(description));
        gov.queue(targets, values, calldatas, descriptionHash);
        assertEq(uint256(gov.state(proposalId)), 5); // Queued = 5

        // 6. Warp forward timelock delay + 1 second
        vm.warp(block.timestamp + 1 days + 1);

        // 7. Execute (exercises _executeOperations)
        gov.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint256(gov.state(proposalId)), 7); // Executed = 7
    }

    /// @notice Cancel a pending proposal (exercises _cancel)
    function test_cancel_proposal() public {
        _setupGovernanceRoles();

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _proposalParams();

        uint256 proposalId = gov.propose(targets, values, calldatas, description);
        assertEq(uint256(gov.state(proposalId)), 0); // Pending

        // Cancel via proposalId (GovernorStorageUpgradeable convenience function)
        gov.cancel(proposalId);
        assertEq(uint256(gov.state(proposalId)), 2); // Canceled = 2
    }

    /// @notice Verify executor returns the timelock address (exercises _executor indirectly)
    function test_executor_isTimelock() public view {
        // timelock() is the public accessor that returns the same address as _executor()
        assertEq(gov.timelock(), address(timelock));
    }

    /// @notice Verify proposalNeedsQueuing returns true for a passed proposal
    function test_proposalNeedsQueuing_returnsTrue() public {
        _setupGovernanceRoles();

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _proposalParams();

        uint256 proposalId = gov.propose(targets, values, calldatas, description);

        // Advance to active, vote, advance past voting period
        vm.roll(block.number + gov.votingDelay() + 1);
        gov.castVote(proposalId, 1);
        vm.roll(block.number + gov.votingPeriod());

        // proposalNeedsQueuing should return true (timelock-controlled governor)
        assertTrue(gov.proposalNeedsQueuing(proposalId), "proposal should need queuing");
    }
}

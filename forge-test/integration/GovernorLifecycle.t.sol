// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title Mock Governance Token for testing
 */
contract MockGovToken {
    string public name = "Bitres Governance";
    string public symbol = "BRS";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => address) public delegates;
    mapping(address => uint256) public numCheckpoints;
    mapping(address => mapping(uint256 => Checkpoint)) public checkpoints;

    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        _moveVotingPower(address(0), delegates[to], amount);
    }

    function delegate(address delegatee) external {
        address currentDelegate = delegates[msg.sender];
        uint256 balance = balanceOf[msg.sender];
        delegates[msg.sender] = delegatee;
        _moveVotingPower(currentDelegate, delegatee, balance);
    }

    function getVotes(address account) external view returns (uint256) {
        uint256 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "block not yet mined");
        uint256 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) return 0;

        // Binary search
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function getPastTotalSupply(uint256) external view returns (uint256) {
        return totalSupply;
    }

    function _moveVotingPower(address from, address to, uint256 amount) internal {
        if (from != address(0) && from != to && amount > 0) {
            uint256 nCheckpoints = numCheckpoints[from];
            uint256 oldVotes = nCheckpoints > 0 ? checkpoints[from][nCheckpoints - 1].votes : 0;
            uint256 newVotes = oldVotes - amount;
            _writeCheckpoint(from, nCheckpoints, newVotes);
        }

        if (to != address(0) && from != to && amount > 0) {
            uint256 nCheckpoints = numCheckpoints[to];
            uint256 oldVotes = nCheckpoints > 0 ? checkpoints[to][nCheckpoints - 1].votes : 0;
            uint256 newVotes = oldVotes + amount;
            _writeCheckpoint(to, nCheckpoints, newVotes);
        }
    }

    function _writeCheckpoint(address account, uint256 nCheckpoints, uint256 newVotes) internal {
        if (nCheckpoints > 0 && checkpoints[account][nCheckpoints - 1].fromBlock == block.number) {
            checkpoints[account][nCheckpoints - 1].votes = uint224(newVotes);
        } else {
            checkpoints[account][nCheckpoints] = Checkpoint(uint32(block.number), uint224(newVotes));
            numCheckpoints[account] = nCheckpoints + 1;
        }
    }
}

/**
 * @title Mock Governor for lifecycle testing
 */
contract MockGovernor {
    MockGovToken public token;

    uint256 public votingDelay = 1; // 1 block
    uint256 public votingPeriod = 50400; // ~1 week
    uint256 public proposalThreshold = 1000e18; // 1000 tokens
    uint256 public quorumNumerator = 4; // 4%

    uint256 public proposalCount;

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        uint256 eta; // execution time
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    uint256 public constant TIMELOCK_DELAY = 2 days;

    event ProposalCreated(uint256 id, address proposer);
    event VoteCast(address voter, uint256 proposalId, uint8 support, uint256 weight);
    event ProposalQueued(uint256 id, uint256 eta);
    event ProposalExecuted(uint256 id);
    event ProposalCanceled(uint256 id);

    constructor(MockGovToken _token) {
        token = _token;
    }

    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) external returns (uint256) {
        require(token.getVotes(msg.sender) >= proposalThreshold, "below threshold");

        proposalCount++;
        uint256 startBlock = block.number + votingDelay;
        uint256 endBlock = startBlock + votingPeriod;

        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            canceled: false,
            executed: false,
            eta: 0
        });

        emit ProposalCreated(proposalCount, msg.sender);
        return proposalCount;
    }

    function castVote(uint256 proposalId, uint8 support) external returns (uint256) {
        Proposal storage proposal = proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "voting closed");
        require(!hasVoted[proposalId][msg.sender], "already voted");

        uint256 weight = token.getPastVotes(msg.sender, proposal.startBlock);
        require(weight > 0, "no voting power");

        hasVoted[proposalId][msg.sender] = true;

        if (support == 0) {
            proposal.againstVotes += weight;
        } else if (support == 1) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight);
        return weight;
    }

    function queue(uint256 proposalId) external {
        require(state(proposalId) == ProposalState.Succeeded, "not succeeded");
        Proposal storage proposal = proposals[proposalId];
        proposal.eta = block.timestamp + TIMELOCK_DELAY;
        emit ProposalQueued(proposalId, proposal.eta);
    }

    function execute(uint256 proposalId) external {
        require(state(proposalId) == ProposalState.Queued, "not queued");
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.eta, "timelock not passed");
        proposal.executed = true;
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "already executed");
        require(
            msg.sender == proposal.proposer ||
            token.getVotes(proposal.proposer) < proposalThreshold,
            "cannot cancel"
        );
        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "unknown proposal");

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        }

        if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        }

        // After voting period
        if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        }

        if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        }

        if (block.timestamp >= proposal.eta + 14 days) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        uint256 totalSupply = token.getPastTotalSupply(proposal.startBlock);
        uint256 requiredQuorum = (totalSupply * quorumNumerator) / 100;
        return proposal.forVotes + proposal.abstainVotes >= requiredQuorum;
    }

    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes;
    }

    function quorum(uint256 blockNumber) external view returns (uint256) {
        return (token.getPastTotalSupply(blockNumber) * quorumNumerator) / 100;
    }
}

/**
 * @title Governor Lifecycle Integration Tests
 * @notice Tests the complete proposal lifecycle: create -> vote -> queue -> execute
 */
contract GovernorLifecycleTest is Test {
    MockGovToken public token;
    MockGovernor public governor;

    address public alice;
    address public bob;
    address public carol;
    address public proposer;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        proposer = makeAddr("proposer");

        token = new MockGovToken();
        governor = new MockGovernor(token);

        // Distribute tokens and delegate
        token.mint(proposer, 2000e18);
        token.mint(alice, 100000e18);
        token.mint(bob, 50000e18);
        token.mint(carol, 25000e18);

        vm.prank(proposer);
        token.delegate(proposer);
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);

        // Advance a block for delegation to take effect
        vm.roll(block.number + 1);
    }

    // ============ Proposal Creation Tests ============

    /// @notice Test successful proposal creation
    function test_ProposalCreation_Success() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test Proposal");

        assertEq(proposalId, 1, "First proposal should have ID 1");
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Pending);
    }

    /// @notice Test proposal creation fails below threshold
    function test_ProposalCreation_BelowThreshold() public {
        address lowBalance = makeAddr("lowBalance");
        token.mint(lowBalance, 100e18); // Below 1000e18 threshold
        vm.prank(lowBalance);
        token.delegate(lowBalance);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(lowBalance);
        vm.expectRevert("below threshold");
        governor.propose(targets, values, calldatas, "Test");
    }

    // ============ Voting Tests ============

    /// @notice Test successful vote casting
    function test_Voting_Success() public {
        uint256 proposalId = _createProposal();

        // Move to active state
        vm.roll(block.number + 2);
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Active);

        // Cast votes
        vm.prank(alice);
        uint256 aliceWeight = governor.castVote(proposalId, 1); // For
        assertEq(aliceWeight, 100000e18, "Alice should have 100k votes");

        vm.prank(bob);
        uint256 bobWeight = governor.castVote(proposalId, 0); // Against
        assertEq(bobWeight, 50000e18, "Bob should have 50k votes");

        vm.prank(carol);
        uint256 carolWeight = governor.castVote(proposalId, 2); // Abstain
        assertEq(carolWeight, 25000e18, "Carol should have 25k votes");
    }

    /// @notice Test voting before active period
    function test_Voting_BeforeActive() public {
        uint256 proposalId = _createProposal();
        // Still in pending state

        vm.prank(alice);
        vm.expectRevert("voting closed");
        governor.castVote(proposalId, 1);
    }

    /// @notice Test voting after period ends
    function test_Voting_AfterPeriod() public {
        uint256 proposalId = _createProposal();

        // Move past voting period
        vm.roll(block.number + 50500);

        vm.prank(alice);
        vm.expectRevert("voting closed");
        governor.castVote(proposalId, 1);
    }

    /// @notice Test double voting prevention
    function test_Voting_DoubleVote() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + 2);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(alice);
        vm.expectRevert("already voted");
        governor.castVote(proposalId, 0);
    }

    // ============ Proposal State Transitions ============

    /// @notice Test proposal succeeds with quorum and majority
    function test_Proposal_Succeeds() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + 2);

        // Vote for
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Move past voting period
        vm.roll(block.number + 50500);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Succeeded);
    }

    /// @notice Test proposal defeated (no quorum)
    function test_Proposal_DefeatedNoQuorum() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + 2);

        // Only proposer votes (2k out of 177k total = ~1.1%, below 4% quorum)
        vm.prank(proposer);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 50500);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Defeated);
    }

    /// @notice Test proposal defeated (more against votes)
    function test_Proposal_DefeatedMajorityAgainst() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + 2);

        // Carol votes for (25k)
        vm.prank(carol);
        governor.castVote(proposalId, 1);

        // Bob votes against (50k)
        vm.prank(bob);
        governor.castVote(proposalId, 0);

        // Alice abstains (100k) - quorum reached but against > for
        vm.prank(alice);
        governor.castVote(proposalId, 2);

        vm.roll(block.number + 50500);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Defeated);
    }

    // ============ Queue and Execute Tests ============

    /// @notice Test proposal queuing
    function test_Proposal_Queue() public {
        uint256 proposalId = _createAndPassProposal();

        governor.queue(proposalId);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Queued);
    }

    /// @notice Test proposal execution
    function test_Proposal_Execute() public {
        uint256 proposalId = _createAndPassProposal();

        governor.queue(proposalId);

        // Wait for timelock
        vm.warp(block.timestamp + 2 days + 1);

        governor.execute(proposalId);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Executed);
    }

    /// @notice Test execution before timelock
    function test_Proposal_ExecuteBeforeTimelock() public {
        uint256 proposalId = _createAndPassProposal();
        governor.queue(proposalId);

        vm.expectRevert("timelock not passed");
        governor.execute(proposalId);
    }

    /// @notice Test proposal expiration
    function test_Proposal_Expired() public {
        uint256 proposalId = _createAndPassProposal();
        governor.queue(proposalId);

        // Wait past grace period (14 days)
        vm.warp(block.timestamp + 2 days + 14 days + 1);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Expired);
    }

    // ============ Cancel Tests ============

    /// @notice Test proposer can cancel
    function test_Proposal_CancelByProposer() public {
        uint256 proposalId = _createProposal();

        vm.prank(proposer);
        governor.cancel(proposalId);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Canceled);
    }

    /// @notice Test cancel when proposer loses voting power
    function test_Proposal_CancelWhenBelowThreshold() public {
        // Create new token with transferable balance
        uint256 proposalId = _createProposal();

        // Simulate proposer losing voting power (delegate away)
        vm.prank(proposer);
        token.delegate(address(0));
        vm.roll(block.number + 1);

        // Anyone can cancel now
        vm.prank(alice);
        governor.cancel(proposalId);

        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Canceled);
    }

    /// @notice Test cannot cancel executed proposal
    function test_Proposal_CannotCancelExecuted() public {
        uint256 proposalId = _createAndPassProposal();
        governor.queue(proposalId);
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(proposalId);

        vm.prank(proposer);
        vm.expectRevert("already executed");
        governor.cancel(proposalId);
    }

    // ============ Full Lifecycle Test ============

    /// @notice Test complete proposal lifecycle
    function test_FullLifecycle() public {
        // 1. Create proposal
        uint256 proposalId = _createProposal();
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Pending);

        // 2. Move to active
        vm.roll(block.number + 2);
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Active);

        // 3. Cast votes
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // 4. End voting
        vm.roll(block.number + 50500);
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Succeeded);

        // 5. Queue
        governor.queue(proposalId);
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Queued);

        // 6. Wait for timelock
        vm.warp(block.timestamp + 2 days + 1);

        // 7. Execute
        governor.execute(proposalId);
        assertTrue(governor.state(proposalId) == MockGovernor.ProposalState.Executed);
    }

    // ============ Fuzz Tests ============

    /// @notice Fuzz test voting with various vote distributions
    function testFuzz_VoteDistribution(
        uint64 forVotes,
        uint64 againstVotes,
        uint64 abstainVotes
    ) public {
        forVotes = uint64(bound(forVotes, 0, 100));
        againstVotes = uint64(bound(againstVotes, 0, 100));
        abstainVotes = uint64(bound(abstainVotes, 0, 100));

        // Create voters with specified vote distributions
        address[] memory forVoters = new address[](forVotes);
        address[] memory againstVoters = new address[](againstVotes);
        address[] memory abstainVoters = new address[](abstainVotes);

        uint256 voteAmount = 1000e18;

        for (uint256 i = 0; i < forVotes; i++) {
            forVoters[i] = address(uint160(0x10000 + i));
            token.mint(forVoters[i], voteAmount);
            vm.prank(forVoters[i]);
            token.delegate(forVoters[i]);
        }

        for (uint256 i = 0; i < againstVotes; i++) {
            againstVoters[i] = address(uint160(0x20000 + i));
            token.mint(againstVoters[i], voteAmount);
            vm.prank(againstVoters[i]);
            token.delegate(againstVoters[i]);
        }

        for (uint256 i = 0; i < abstainVotes; i++) {
            abstainVoters[i] = address(uint160(0x30000 + i));
            token.mint(abstainVoters[i], voteAmount);
            vm.prank(abstainVoters[i]);
            token.delegate(abstainVoters[i]);
        }

        vm.roll(block.number + 1);

        uint256 proposalId = _createProposal();
        vm.roll(block.number + 2);

        // Cast votes
        for (uint256 i = 0; i < forVotes; i++) {
            vm.prank(forVoters[i]);
            governor.castVote(proposalId, 1);
        }
        for (uint256 i = 0; i < againstVotes; i++) {
            vm.prank(againstVoters[i]);
            governor.castVote(proposalId, 0);
        }
        for (uint256 i = 0; i < abstainVotes; i++) {
            vm.prank(abstainVoters[i]);
            governor.castVote(proposalId, 2);
        }

        vm.roll(block.number + 50500);

        // Verify outcome
        MockGovernor.ProposalState finalState = governor.state(proposalId);

        uint256 totalParticipating = (forVotes + abstainVotes) * voteAmount;
        uint256 totalSupply = token.totalSupply();
        uint256 quorumRequired = (totalSupply * 4) / 100;

        if (totalParticipating < quorumRequired) {
            // Not enough quorum
            assertTrue(finalState == MockGovernor.ProposalState.Defeated, "should be defeated (no quorum)");
        } else if (forVotes <= againstVotes) {
            // More against than for
            assertTrue(finalState == MockGovernor.ProposalState.Defeated, "should be defeated (majority against)");
        } else {
            // Passed
            assertTrue(finalState == MockGovernor.ProposalState.Succeeded, "should succeed");
        }
    }

    // ============ Helper Functions ============

    function _createProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(proposer);
        return governor.propose(targets, values, calldatas, "Test Proposal");
    }

    function _createAndPassProposal() internal returns (uint256) {
        uint256 proposalId = _createProposal();

        vm.roll(block.number + 2);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 50500);

        return proposalId;
    }
}

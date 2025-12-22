// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {GovernorVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Governor - BRS Governance Contract
 * @notice On-chain governance system based on OpenZeppelin Governor, supports proposals, voting, timelock execution
 * @dev Upgradeable contract (UUPS pattern), integrates voting, proposal storage, timelock control, and other features
 *      - Voting delay: 1 day
 *      - Voting period: 1 week
 *      - Proposal threshold: 250,000 BRS
 *      - Quorum: 4% (based on total supply)
 */
contract Governor is Initializable, GovernorUpgradeable, GovernorSettingsUpgradeable, GovernorCountingSimpleUpgradeable, GovernorStorageUpgradeable, GovernorVotesUpgradeable, GovernorVotesQuorumFractionUpgradeable, GovernorTimelockControlUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes governance contract
     * @param _token Voting token (BRS)
     * @param _timelock Timelock controller contract
     * @dev Can only be called once, sets:
     *      - Voting delay: 1 day
     *      - Voting period: 1 week
     *      - Proposal threshold: 250,000 BRS
     *      - Quorum: 4%
     */
    function initialize(IVotes _token, TimelockControllerUpgradeable _timelock)
        public
        initializer
    {
        __Governor_init("Governor");
        __GovernorSettings_init(1 days, 1 weeks, 250000e18);
        __GovernorCountingSimple_init();
        __GovernorStorage_init();
        __GovernorVotes_init(_token);
        __GovernorVotesQuorumFraction_init(4);
        __GovernorTimelockControl_init(_timelock);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Authorizes contract upgrade (only governance-approved proposals can call)
     * @param newImplementation New implementation contract address
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyGovernance
    {}

    // The following functions are override functions required by Solidity

    /**
     * @notice Queries proposal state
     * @param proposalId Proposal ID
     * @return Proposal state (Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed)
     */
    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /**
     * @notice Checks if proposal needs to be queued to timelock
     * @param proposalId Proposal ID
     * @return Whether queuing is needed
     */
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @notice Gets proposal threshold (minimum voting power required to create proposals)
     * @return Proposal threshold (250,000 BRS)
     */
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /**
     * @notice Internal proposal creation function
     * @param targets Target contract address array
     * @param values ETH amounts to send with calls array
     * @param calldatas Call data array
     * @param description Proposal description
     * @param proposer Proposer address
     * @return Proposal ID
     */
    function _propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, address proposer)
        internal
        override(GovernorUpgradeable, GovernorStorageUpgradeable)
        returns (uint256)
    {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    /**
     * @notice Queues proposal operations to timelock
     * @param proposalId Proposal ID
     * @param targets Target contract address array
     * @param values ETH amounts to send with calls array
     * @param calldatas Call data array
     * @param descriptionHash Proposal description hash
     * @return Execution timestamp
     */
    function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (uint48)
    {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Executes proposal operations
     * @param proposalId Proposal ID
     * @param targets Target contract address array
     * @param values ETH amounts to send with calls array
     * @param calldatas Call data array
     * @param descriptionHash Proposal description hash
     */
    function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
    {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Cancels proposal
     * @param targets Target contract address array
     * @param values ETH amounts to send with calls array
     * @param calldatas Call data array
     * @param descriptionHash Proposal description hash
     * @return Proposal ID
     */
    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Gets executor address (timelock contract)
     * @return Executor address
     */
    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }
}

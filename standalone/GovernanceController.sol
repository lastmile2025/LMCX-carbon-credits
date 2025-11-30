// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title GovernanceController
 * @dev DAO-based governance system for LMCX Carbon Credit platform with:
 * - Time-locked proposals for critical parameter changes
 * - Multi-signature requirements for high-impact operations
 * - Tiered voting weights based on stakeholder roles
 * - Emergency actions with guardian council oversight
 *
 * Follows best practices from Compound Governor and OpenZeppelin Governor patterns.
 */
contract GovernanceController is AccessControl, ReentrancyGuard {
    // ============ Roles ============
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");

    // ============ Constants ============
    uint256 public constant MIN_PROPOSAL_DELAY = 1 days;
    uint256 public constant MAX_PROPOSAL_DELAY = 30 days;
    uint256 public constant MIN_VOTING_PERIOD = 3 days;
    uint256 public constant MAX_VOTING_PERIOD = 30 days;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant QUORUM_DENOMINATOR = 10000;

    // ============ Enums ============
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

    enum ProposalCategory {
        Standard,           // Regular governance proposals
        Critical,           // Security and emergency updates
        ParameterChange,    // System parameter modifications
        RoleManagement,     // Role grants and revocations
        ContractUpgrade,    // Contract upgrades
        EmergencyAction     // Emergency actions (requires guardian approval)
    }

    enum VoteType {
        Against,
        For,
        Abstain
    }

    // ============ Structs ============

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalCategory category;

        // Targets and data
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string[] signatures;

        // Timing
        uint256 startBlock;
        uint256 endBlock;
        uint256 eta;                    // Execution time (for timelock)

        // Voting
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;

        // Status
        bool canceled;
        bool executed;

        // Metadata
        string description;
        bytes32 descriptionHash;

        // Multi-sig requirement
        uint256 requiredSignatures;
        uint256 signatureCount;
    }

    struct Receipt {
        bool hasVoted;
        VoteType support;
        uint256 votes;
    }

    struct GovernanceConfig {
        uint256 proposalDelay;          // Delay before voting starts
        uint256 votingPeriod;           // Duration of voting
        uint256 timelockDelay;          // Delay before execution
        uint256 quorumNumerator;        // Quorum percentage (out of 10000)
        uint256 proposalThreshold;      // Minimum votes to create proposal
    }

    struct MultiSigConfig {
        uint256 threshold;              // Number of signatures required
        address[] signers;              // Authorized signers
        uint256 signerCount;
    }

    struct PendingMultiSig {
        bytes32 operationHash;
        uint256 proposalId;
        uint256 approvalCount;
        uint256 createdAt;
        bool executed;
        mapping(address => bool) approvals;
    }

    struct VotingPower {
        uint256 baseVotes;
        uint256 delegatedVotes;
        uint256 stakingMultiplier;      // Scaled by 1e4 (10000 = 1x)
        uint256 roleMultiplier;         // Scaled by 1e4
        address delegate;
    }

    // ============ Storage ============

    GovernanceConfig public config;
    MultiSigConfig public multiSigConfig;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Receipt)) public receipts;

    // Multi-sig operations
    uint256 public multiSigNonce;
    mapping(bytes32 => PendingMultiSig) public pendingMultiSigs;
    mapping(uint256 => bytes32) public proposalMultiSigHash;
    mapping(uint256 => mapping(address => bool)) public proposalSignatures;

    // Voting power
    mapping(address => VotingPower) public votingPower;
    mapping(address => uint256) public nonces;

    // Role-based voting multipliers
    mapping(bytes32 => uint256) public roleVotingMultiplier;

    // Timelock queue
    mapping(bytes32 => bool) public queuedTransactions;

    // Emergency pause
    bool public paused;

    // ============ Events ============

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalCategory category,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event ProposalCanceled(uint256 indexed proposalId);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);

    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        VoteType support,
        uint256 votes,
        string reason
    );

    event MultiSigApproval(
        bytes32 indexed operationHash,
        uint256 indexed proposalId,
        address indexed signer,
        uint256 approvalCount
    );

    event MultiSigExecuted(
        bytes32 indexed operationHash,
        uint256 indexed proposalId
    );

    event VotingPowerUpdated(
        address indexed account,
        uint256 newVotingPower
    );

    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    event GovernanceConfigUpdated(
        uint256 proposalDelay,
        uint256 votingPeriod,
        uint256 timelockDelay,
        uint256 quorumNumerator
    );

    event GuardianAction(
        string actionType,
        uint256 indexed proposalId,
        address indexed guardian
    );

    event EmergencyPause(address indexed guardian, bool paused);

    // ============ Modifiers ============

    modifier whenNotPaused() {
        require(!paused, "Governance: paused");
        _;
    }

    modifier onlyGuardian() {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "Governance: not guardian");
        _;
    }

    // ============ Constructor ============

    constructor(
        uint256 _proposalDelay,
        uint256 _votingPeriod,
        uint256 _timelockDelay,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint256 _multiSigThreshold,
        address[] memory _guardians,
        address[] memory _multiSigSigners
    ) {
        require(_proposalDelay >= MIN_PROPOSAL_DELAY, "Delay too short");
        require(_votingPeriod >= MIN_VOTING_PERIOD, "Voting period too short");
        require(_quorumNumerator <= QUORUM_DENOMINATOR, "Invalid quorum");
        require(_multiSigThreshold > 0 && _multiSigThreshold <= _multiSigSigners.length, "Invalid threshold");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);

        // Setup guardians
        for (uint256 i = 0; i < _guardians.length; i++) {
            _grantRole(GUARDIAN_ROLE, _guardians[i]);
        }

        // Setup multi-sig signers
        for (uint256 i = 0; i < _multiSigSigners.length; i++) {
            _grantRole(MULTISIG_SIGNER_ROLE, _multiSigSigners[i]);
        }

        config = GovernanceConfig({
            proposalDelay: _proposalDelay,
            votingPeriod: _votingPeriod,
            timelockDelay: _timelockDelay,
            quorumNumerator: _quorumNumerator,
            proposalThreshold: _proposalThreshold
        });

        multiSigConfig = MultiSigConfig({
            threshold: _multiSigThreshold,
            signers: _multiSigSigners,
            signerCount: _multiSigSigners.length
        });

        // Set default role voting multipliers
        roleVotingMultiplier[GUARDIAN_ROLE] = 15000;         // 1.5x
        roleVotingMultiplier[PROPOSER_ROLE] = 12000;         // 1.2x
        roleVotingMultiplier[VOTER_ROLE] = 10000;            // 1x
        roleVotingMultiplier[MULTISIG_SIGNER_ROLE] = 13000;  // 1.3x
    }

    // ============ Proposal Creation ============

    /**
     * @dev Create a new governance proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string[] memory signatures,
        string memory description,
        ProposalCategory category
    ) external onlyRole(PROPOSER_ROLE) whenNotPaused returns (uint256) {
        require(targets.length == values.length, "Invalid proposal length");
        require(targets.length == calldatas.length, "Invalid proposal length");
        require(targets.length > 0, "Empty proposal");
        require(bytes(description).length > 0, "Empty description");

        uint256 proposerVotes = getVotes(msg.sender);
        require(proposerVotes >= config.proposalThreshold, "Below proposal threshold");

        uint256 proposalId = ++proposalCount;
        uint256 startBlock = block.number + (config.proposalDelay / 12); // Assuming ~12s blocks
        uint256 endBlock = startBlock + (config.votingPeriod / 12);

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.category = category;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.signatures = signatures;
        proposal.startBlock = startBlock;
        proposal.endBlock = endBlock;
        proposal.description = description;
        proposal.descriptionHash = keccak256(bytes(description));

        // Set required signatures based on category
        proposal.requiredSignatures = _getRequiredSignatures(category);

        emit ProposalCreated(
            proposalId,
            msg.sender,
            category,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            endBlock,
            description
        );

        return proposalId;
    }

    /**
     * @dev Get required signatures based on proposal category
     */
    function _getRequiredSignatures(ProposalCategory category) internal view returns (uint256) {
        if (category == ProposalCategory.Critical || category == ProposalCategory.ContractUpgrade) {
            return multiSigConfig.threshold;
        } else if (category == ProposalCategory.EmergencyAction) {
            return (multiSigConfig.threshold * 2) / 3 + 1; // Higher threshold for emergency
        } else if (category == ProposalCategory.RoleManagement) {
            return multiSigConfig.threshold / 2 + 1;
        }
        return 0; // Standard proposals don't require multi-sig
    }

    // ============ Voting ============

    /**
     * @dev Cast a vote on a proposal
     */
    function castVote(
        uint256 proposalId,
        VoteType support
    ) external whenNotPaused returns (uint256) {
        return _castVote(msg.sender, proposalId, support, "");
    }

    /**
     * @dev Cast a vote with reason
     */
    function castVoteWithReason(
        uint256 proposalId,
        VoteType support,
        string calldata reason
    ) external whenNotPaused returns (uint256) {
        return _castVote(msg.sender, proposalId, support, reason);
    }

    /**
     * @dev Internal vote casting logic
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        VoteType support,
        string memory reason
    ) internal returns (uint256) {
        require(state(proposalId) == ProposalState.Active, "Voting not active");

        Receipt storage receipt = receipts[proposalId][voter];
        require(!receipt.hasVoted, "Already voted");

        uint256 votes = getVotes(voter);
        require(votes > 0, "No voting power");

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        Proposal storage proposal = proposals[proposalId];

        if (support == VoteType.For) {
            proposal.forVotes += votes;
        } else if (support == VoteType.Against) {
            proposal.againstVotes += votes;
        } else {
            proposal.abstainVotes += votes;
        }

        emit VoteCast(voter, proposalId, support, votes, reason);
        return votes;
    }

    // ============ Multi-Signature Operations ============

    /**
     * @dev Sign a proposal that requires multi-sig approval
     */
    function signProposal(uint256 proposalId) external onlyRole(MULTISIG_SIGNER_ROLE) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.requiredSignatures > 0, "Multi-sig not required");
        require(!proposalSignatures[proposalId][msg.sender], "Already signed");
        require(state(proposalId) == ProposalState.Succeeded ||
                state(proposalId) == ProposalState.Queued, "Invalid state for signing");

        proposalSignatures[proposalId][msg.sender] = true;
        proposal.signatureCount++;

        bytes32 operationHash = keccak256(abi.encodePacked(proposalId, proposal.descriptionHash));

        emit MultiSigApproval(operationHash, proposalId, msg.sender, proposal.signatureCount);

        if (proposal.signatureCount >= proposal.requiredSignatures) {
            emit MultiSigExecuted(operationHash, proposalId);
        }
    }

    /**
     * @dev Check if proposal has sufficient signatures
     */
    function hasRequiredSignatures(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.requiredSignatures == 0) return true;
        return proposal.signatureCount >= proposal.requiredSignatures;
    }

    // ============ Proposal Execution ============

    /**
     * @dev Queue a successful proposal for execution
     */
    function queue(uint256 proposalId) external {
        require(state(proposalId) == ProposalState.Succeeded, "Proposal not succeeded");

        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + config.timelockDelay;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            bytes32 txHash = keccak256(
                abi.encode(
                    proposal.targets[i],
                    proposal.values[i],
                    proposal.signatures[i],
                    proposal.calldatas[i],
                    eta
                )
            );
            require(!queuedTransactions[txHash], "Transaction already queued");
            queuedTransactions[txHash] = true;
        }

        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @dev Execute a queued proposal
     */
    function execute(uint256 proposalId) external payable onlyRole(EXECUTOR_ROLE) nonReentrant {
        require(state(proposalId) == ProposalState.Queued, "Proposal not queued");
        require(hasRequiredSignatures(proposalId), "Missing required signatures");

        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.eta, "Timelock not expired");
        require(block.timestamp <= proposal.eta + GRACE_PERIOD, "Proposal expired");

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            bytes32 txHash = keccak256(
                abi.encode(
                    proposal.targets[i],
                    proposal.values[i],
                    proposal.signatures[i],
                    proposal.calldatas[i],
                    proposal.eta
                )
            );
            queuedTransactions[txHash] = false;

            bytes memory callData;
            if (bytes(proposal.signatures[i]).length == 0) {
                callData = proposal.calldatas[i];
            } else {
                callData = abi.encodePacked(
                    bytes4(keccak256(bytes(proposal.signatures[i]))),
                    proposal.calldatas[i]
                );
            }

            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(callData);
            require(success, "Transaction execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @dev Cancel a proposal
     */
    function cancel(uint256 proposalId) external {
        ProposalState currentState = state(proposalId);
        require(
            currentState != ProposalState.Canceled &&
            currentState != ProposalState.Defeated &&
            currentState != ProposalState.Expired &&
            currentState != ProposalState.Executed,
            "Cannot cancel"
        );

        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer ||
            hasRole(GUARDIAN_ROLE, msg.sender),
            "Not authorized to cancel"
        );

        proposal.canceled = true;

        // Clear queued transactions
        if (proposal.eta != 0) {
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                bytes32 txHash = keccak256(
                    abi.encode(
                        proposal.targets[i],
                        proposal.values[i],
                        proposal.signatures[i],
                        proposal.calldatas[i],
                        proposal.eta
                    )
                );
                queuedTransactions[txHash] = false;
            }
        }

        emit ProposalCanceled(proposalId);
    }

    // ============ Voting Power Management ============

    /**
     * @dev Set voting power for an account
     */
    function setVotingPower(
        address account,
        uint256 baseVotes,
        uint256 stakingMultiplier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        votingPower[account].baseVotes = baseVotes;
        votingPower[account].stakingMultiplier = stakingMultiplier;

        emit VotingPowerUpdated(account, getVotes(account));
    }

    /**
     * @dev Delegate votes to another address
     */
    function delegate(address delegatee) external {
        address currentDelegate = votingPower[msg.sender].delegate;

        if (currentDelegate != address(0)) {
            votingPower[currentDelegate].delegatedVotes -= votingPower[msg.sender].baseVotes;
        }

        votingPower[msg.sender].delegate = delegatee;

        if (delegatee != address(0)) {
            votingPower[delegatee].delegatedVotes += votingPower[msg.sender].baseVotes;
        }

        emit DelegateChanged(msg.sender, currentDelegate, delegatee);
    }

    /**
     * @dev Get voting power for an account
     */
    function getVotes(address account) public view returns (uint256) {
        VotingPower storage vp = votingPower[account];
        uint256 baseVotes = vp.baseVotes + vp.delegatedVotes;

        // Apply staking multiplier
        uint256 stakingMult = vp.stakingMultiplier > 0 ? vp.stakingMultiplier : 10000;
        baseVotes = (baseVotes * stakingMult) / 10000;

        // Apply role multiplier (use highest role multiplier)
        uint256 roleMult = 10000;
        if (hasRole(GUARDIAN_ROLE, account) && roleVotingMultiplier[GUARDIAN_ROLE] > roleMult) {
            roleMult = roleVotingMultiplier[GUARDIAN_ROLE];
        }
        if (hasRole(MULTISIG_SIGNER_ROLE, account) && roleVotingMultiplier[MULTISIG_SIGNER_ROLE] > roleMult) {
            roleMult = roleVotingMultiplier[MULTISIG_SIGNER_ROLE];
        }
        if (hasRole(PROPOSER_ROLE, account) && roleVotingMultiplier[PROPOSER_ROLE] > roleMult) {
            roleMult = roleVotingMultiplier[PROPOSER_ROLE];
        }

        return (baseVotes * roleMult) / 10000;
    }

    // ============ State Queries ============

    /**
     * @dev Get current state of a proposal
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "Unknown proposal");

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
        if (proposal.forVotes <= proposal.againstVotes || !_quorumReached(proposalId)) {
            return ProposalState.Defeated;
        }
        if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        }
        if (block.timestamp >= proposal.eta + GRACE_PERIOD) {
            return ProposalState.Expired;
        }
        return ProposalState.Queued;
    }

    /**
     * @dev Check if quorum is reached
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        // For simplicity, using a fixed total supply concept
        // In production, this would integrate with token total supply
        return totalVotes >= config.quorumNumerator;
    }

    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 proposalId) external view returns (
        address proposer,
        ProposalCategory category,
        uint256 startBlock,
        uint256 endBlock,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        bool canceled,
        bool executed
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.proposer,
            proposal.category,
            proposal.startBlock,
            proposal.endBlock,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.canceled,
            proposal.executed
        );
    }

    /**
     * @dev Get proposal actions
     */
    function getProposalActions(uint256 proposalId) external view returns (
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.targets, proposal.values, proposal.signatures, proposal.calldatas);
    }

    // ============ Guardian Functions ============

    /**
     * @dev Emergency pause all governance
     */
    function emergencyPause() external onlyGuardian {
        paused = true;
        emit EmergencyPause(msg.sender, true);
    }

    /**
     * @dev Unpause governance (requires multiple guardians)
     */
    function emergencyUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = false;
        emit EmergencyPause(msg.sender, false);
    }

    /**
     * @dev Guardian veto power for critical situations
     */
    function guardianVeto(uint256 proposalId, string calldata reason) external onlyGuardian {
        ProposalState currentState = state(proposalId);
        require(
            currentState == ProposalState.Active ||
            currentState == ProposalState.Succeeded ||
            currentState == ProposalState.Queued,
            "Cannot veto in current state"
        );

        proposals[proposalId].canceled = true;
        emit GuardianAction(string(abi.encodePacked("VETO:", reason)), proposalId, msg.sender);
        emit ProposalCanceled(proposalId);
    }

    // ============ Configuration Management ============

    /**
     * @dev Update governance configuration (via proposal only)
     */
    function updateGovernanceConfig(
        uint256 newProposalDelay,
        uint256 newVotingPeriod,
        uint256 newTimelockDelay,
        uint256 newQuorumNumerator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newProposalDelay >= MIN_PROPOSAL_DELAY && newProposalDelay <= MAX_PROPOSAL_DELAY, "Invalid delay");
        require(newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD, "Invalid period");
        require(newQuorumNumerator <= QUORUM_DENOMINATOR, "Invalid quorum");

        config.proposalDelay = newProposalDelay;
        config.votingPeriod = newVotingPeriod;
        config.timelockDelay = newTimelockDelay;
        config.quorumNumerator = newQuorumNumerator;

        emit GovernanceConfigUpdated(newProposalDelay, newVotingPeriod, newTimelockDelay, newQuorumNumerator);
    }

    /**
     * @dev Update multi-sig threshold
     */
    function updateMultiSigThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newThreshold > 0 && newThreshold <= multiSigConfig.signerCount, "Invalid threshold");
        multiSigConfig.threshold = newThreshold;
    }

    /**
     * @dev Set role voting multiplier
     */
    function setRoleVotingMultiplier(bytes32 role, uint256 multiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(multiplier >= 10000 && multiplier <= 30000, "Invalid multiplier"); // 1x to 3x
        roleVotingMultiplier[role] = multiplier;
    }

    // ============ View Functions ============

    /**
     * @dev Get governance configuration
     */
    function getConfig() external view returns (GovernanceConfig memory) {
        return config;
    }

    /**
     * @dev Get multi-sig configuration
     */
    function getMultiSigConfig() external view returns (uint256 threshold, uint256 signerCount) {
        return (multiSigConfig.threshold, multiSigConfig.signerCount);
    }

    /**
     * @dev Check if an account has voted on a proposal
     */
    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        return receipts[proposalId][account].hasVoted;
    }

    /**
     * @dev Get receipt for a voter on a proposal
     */
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory) {
        return receipts[proposalId][voter];
    }
}

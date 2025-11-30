// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title InsuranceManager
 * @dev Manages insurance policies for carbon credits.
 *
 * This contract allows:
 * - Insurance providers to offer coverage for carbon credits
 * - Credit holders to purchase insurance policies
 * - Claims processing for invalidated or reversed credits
 * - Premium calculations based on project risk ratings
 *
 * Insurance Coverage Types:
 * - Reversal Risk: Coverage if carbon reductions are reversed
 * - Invalidation Risk: Coverage if credits are invalidated
 * - Delivery Risk: Coverage for non-delivery of promised credits
 * - Political Risk: Coverage for regulatory/political changes
 */
contract InsuranceManager is AccessControl, ReentrancyGuard {
    bytes32 public constant INSURER_ROLE = keccak256("INSURER_ROLE");
    bytes32 public constant CLAIMS_ADJUSTER_ROLE = keccak256("CLAIMS_ADJUSTER_ROLE");
    bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");

    // ============ Data Structures ============

    /// @notice Insurance provider registration
    struct InsuranceProvider {
        bytes32 providerId;
        string name;
        address payoutAddress;
        uint256 capitalReserve;
        uint256 totalPoliciesIssued;
        uint256 totalClaimsPaid;
        uint256 registeredAt;
        bool isActive;
        string licenseHash;          // IPFS hash of insurance license
    }

    /// @notice Insurance policy for carbon credits
    struct InsurancePolicy {
        uint256 policyId;
        bytes32 providerId;
        address policyHolder;
        uint256 tokenId;             // ERC1155 token ID being insured
        uint256 creditsInsured;      // Number of credits covered
        uint256 coverageAmount;      // Maximum payout in wei
        uint256 premium;             // Premium paid
        uint256 startDate;
        uint256 endDate;
        CoverageType coverageType;
        PolicyStatus status;
        string termsHash;            // IPFS hash of policy terms
    }

    /// @notice Insurance claim
    struct InsuranceClaim {
        uint256 claimId;
        uint256 policyId;
        address claimant;
        uint256 claimAmount;
        string claimReason;
        string evidenceHash;         // IPFS hash of supporting evidence
        uint256 submittedAt;
        ClaimStatus status;
        uint256 approvedAmount;
        uint256 processedAt;
        address processedBy;
        string resolutionNotes;
    }

    /// @notice Premium calculation parameters
    struct PremiumParams {
        uint256 baseRate;            // Base rate in basis points (1 = 0.01%)
        uint256 riskMultiplier;      // Risk adjustment multiplier (scaled 1e4)
        uint256 durationFactor;      // Factor based on policy duration
        uint256 coverageRatio;       // Coverage amount / credit value ratio
    }

    enum CoverageType {
        REVERSAL,
        INVALIDATION,
        DELIVERY,
        POLITICAL,
        COMPREHENSIVE
    }

    enum PolicyStatus {
        PENDING,
        ACTIVE,
        EXPIRED,
        CLAIMED,
        CANCELLED
    }

    enum ClaimStatus {
        SUBMITTED,
        UNDER_REVIEW,
        APPROVED,
        REJECTED,
        PAID
    }

    // ============ Storage ============

    IERC1155 public carbonCreditToken;

    // Provider management
    mapping(bytes32 => InsuranceProvider) public providers;
    bytes32[] public providerList;
    
    // Policy management
    mapping(uint256 => InsurancePolicy) public policies;
    mapping(address => uint256[]) public holderPolicies;
    mapping(uint256 => uint256[]) public tokenPolicies;  // tokenId => policyIds
    uint256 public nextPolicyId;
    
    // Claims management
    mapping(uint256 => InsuranceClaim) public claims;
    mapping(uint256 => uint256[]) public policyClaims;   // policyId => claimIds
    uint256 public nextClaimId;
    
    // Premium parameters per coverage type
    mapping(CoverageType => PremiumParams) public premiumParams;
    
    // Risk ratings from RatingAgency (tokenId => risk score)
    mapping(uint256 => uint256) public riskScores;

    // === SECURITY FIX: Time-delayed risk score updates to prevent front-running ===
    struct PendingRiskScore {
        uint256 newScore;
        uint256 effectiveTime;
        bool exists;
    }
    mapping(uint256 => PendingRiskScore) public pendingRiskScores;
    uint256 public constant RISK_SCORE_DELAY = 1 hours;  // Delay before new score takes effect

    // === SECURITY FIX: Track committed capital per provider to prevent reserve inflation ===
    mapping(bytes32 => uint256) public committedCapital;  // Capital locked for active policies

    // ============ Events ============

    event ProviderRegistered(
        bytes32 indexed providerId,
        string name,
        address payoutAddress
    );

    event ProviderCapitalUpdated(
        bytes32 indexed providerId,
        uint256 newCapital
    );

    event PolicyIssued(
        uint256 indexed policyId,
        bytes32 indexed providerId,
        address indexed policyHolder,
        uint256 tokenId,
        uint256 coverageAmount
    );

    event PolicyCancelled(
        uint256 indexed policyId,
        string reason
    );

    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed policyId,
        address indexed claimant,
        uint256 claimAmount
    );

    event ClaimProcessed(
        uint256 indexed claimId,
        ClaimStatus status,
        uint256 approvedAmount
    );

    event ClaimPaid(
        uint256 indexed claimId,
        address indexed recipient,
        uint256 amount
    );

    event PremiumParamsUpdated(
        CoverageType coverageType,
        uint256 baseRate,
        uint256 riskMultiplier
    );

    event RiskScoreUpdated(
        uint256 indexed tokenId,
        uint256 newScore
    );

    event RiskScoreUpdateScheduled(
        uint256 indexed tokenId,
        uint256 newScore,
        uint256 effectiveTime
    );

    event RiskScoreUpdateApplied(
        uint256 indexed tokenId,
        uint256 oldScore,
        uint256 newScore
    );

    /// @notice Emitted when ETH is received by the contract
    event EthReceived(address indexed sender, uint256 amount);

    constructor(address _carbonCreditToken) {
        carbonCreditToken = IERC1155(_carbonCreditToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UNDERWRITER_ROLE, msg.sender);

        // Initialize default premium parameters
        _initializeDefaultPremiumParams();
    }

    function _initializeDefaultPremiumParams() internal {
        premiumParams[CoverageType.REVERSAL] = PremiumParams({
            baseRate: 200,          // 2%
            riskMultiplier: 10000,  // 1x base
            durationFactor: 100,    // 1% per year
            coverageRatio: 10000    // 100% coverage
        });

        premiumParams[CoverageType.INVALIDATION] = PremiumParams({
            baseRate: 150,
            riskMultiplier: 10000,
            durationFactor: 75,
            coverageRatio: 10000
        });

        premiumParams[CoverageType.DELIVERY] = PremiumParams({
            baseRate: 100,
            riskMultiplier: 10000,
            durationFactor: 50,
            coverageRatio: 10000
        });

        premiumParams[CoverageType.POLITICAL] = PremiumParams({
            baseRate: 300,
            riskMultiplier: 12000,
            durationFactor: 150,
            coverageRatio: 8000
        });

        premiumParams[CoverageType.COMPREHENSIVE] = PremiumParams({
            baseRate: 500,
            riskMultiplier: 11000,
            durationFactor: 200,
            coverageRatio: 10000
        });
    }

    // ============ Provider Management ============

    /**
     * @dev Register an insurance provider
     */
    function registerProvider(
        bytes32 providerId,
        string calldata name,
        address payoutAddress,
        string calldata licenseHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(providerId != bytes32(0), "Invalid providerId");
        require(!providers[providerId].isActive, "Provider exists");
        require(payoutAddress != address(0), "Invalid payout address");

        providers[providerId] = InsuranceProvider({
            providerId: providerId,
            name: name,
            payoutAddress: payoutAddress,
            capitalReserve: 0,
            totalPoliciesIssued: 0,
            totalClaimsPaid: 0,
            registeredAt: block.timestamp,
            isActive: true,
            licenseHash: licenseHash
        });

        providerList.push(providerId);

        emit ProviderRegistered(providerId, name, payoutAddress);
    }

    /**
     * @dev Add capital to provider reserve
     */
    function addProviderCapital(bytes32 providerId) external payable onlyRole(INSURER_ROLE) {
        require(providers[providerId].isActive, "Provider not active");
        
        providers[providerId].capitalReserve += msg.value;

        emit ProviderCapitalUpdated(providerId, providers[providerId].capitalReserve);
    }

    /**
     * @dev Withdraw provider capital
     */
    function withdrawProviderCapital(
        bytes32 providerId,
        uint256 amount
    ) external onlyRole(INSURER_ROLE) nonReentrant {
        InsuranceProvider storage provider = providers[providerId];
        require(provider.isActive, "Provider not active");
        require(provider.capitalReserve >= amount, "Insufficient capital");

        provider.capitalReserve -= amount;
        
        (bool success, ) = provider.payoutAddress.call{value: amount}("");
        require(success, "Transfer failed");

        emit ProviderCapitalUpdated(providerId, provider.capitalReserve);
    }

    // ============ Policy Management ============

    /**
     * @dev Get effective risk score for a token
     * @notice Uses time-delayed score updates to prevent front-running
     */
    function getEffectiveRiskScore(uint256 tokenId) public view returns (uint256) {
        PendingRiskScore memory pending = pendingRiskScores[tokenId];

        // If there's a pending update and it's now effective, use it
        if (pending.exists && block.timestamp >= pending.effectiveTime) {
            return pending.newScore;
        }

        // Otherwise use current score (default 5000 = neutral)
        uint256 currentScore = riskScores[tokenId];
        return currentScore == 0 ? 5000 : currentScore;
    }

    /**
     * @dev Calculate premium for a policy
     * @notice Uses time-delayed risk scores to prevent front-running arbitrage
     */
    function calculatePremium(
        uint256 tokenId,
        uint256 creditsToInsure,
        uint256 coverageAmount,
        uint256 durationDays,
        CoverageType coverageType
    ) public view returns (uint256 premium) {
        PremiumParams memory params = premiumParams[coverageType];

        // SECURITY FIX: Use effective risk score (with time delay protection)
        uint256 riskScore = getEffectiveRiskScore(tokenId);

        // Base premium calculation
        // premium = coverageAmount * baseRate / 10000
        premium = (coverageAmount * params.baseRate) / 10000;

        // Apply risk multiplier from rating
        // Adjust by risk score (higher score = higher premium)
        premium = (premium * riskScore * params.riskMultiplier) / (5000 * 10000);

        // Apply duration factor
        uint256 durationYears = (durationDays * 10000) / 365;
        premium = premium + (premium * params.durationFactor * durationYears) / (10000 * 10000);

        return premium;
    }

    /**
     * @dev Purchase an insurance policy
     * @notice SECURITY FIX: Properly tracks committed capital for solvency
     */
    function purchasePolicy(
        bytes32 providerId,
        uint256 tokenId,
        uint256 creditsToInsure,
        uint256 coverageAmount,
        uint256 durationDays,
        CoverageType coverageType,
        string calldata termsHash
    ) external payable nonReentrant returns (uint256 policyId) {
        InsuranceProvider storage provider = providers[providerId];
        require(provider.isActive, "Provider not active");
        require(durationDays >= 30 && durationDays <= 3650, "Invalid duration");

        // Verify holder has the credits
        require(
            carbonCreditToken.balanceOf(msg.sender, tokenId) >= creditsToInsure,
            "Insufficient credits"
        );

        // Calculate and verify premium
        uint256 premium = calculatePremium(
            tokenId,
            creditsToInsure,
            coverageAmount,
            durationDays,
            coverageType
        );
        require(msg.value >= premium, "Insufficient premium");

        // SECURITY FIX: Check available capital (reserve - already committed)
        // Require 10% reserve ratio against ALL outstanding coverage
        uint256 availableCapital = provider.capitalReserve > committedCapital[providerId]
            ? provider.capitalReserve - committedCapital[providerId]
            : 0;
        require(
            availableCapital >= coverageAmount / 10,
            "Insufficient provider capital"
        );

        policyId = nextPolicyId++;

        policies[policyId] = InsurancePolicy({
            policyId: policyId,
            providerId: providerId,
            policyHolder: msg.sender,
            tokenId: tokenId,
            creditsInsured: creditsToInsure,
            coverageAmount: coverageAmount,
            premium: premium,
            startDate: block.timestamp,
            endDate: block.timestamp + (durationDays * 1 days),
            coverageType: coverageType,
            status: PolicyStatus.ACTIVE,
            termsHash: termsHash
        });

        holderPolicies[msg.sender].push(policyId);
        tokenPolicies[tokenId].push(policyId);
        provider.totalPoliciesIssued++;
        provider.capitalReserve += premium;

        // SECURITY FIX: Track committed capital for this policy
        committedCapital[providerId] += coverageAmount;

        // Refund excess payment
        if (msg.value > premium) {
            (bool success, ) = msg.sender.call{value: msg.value - premium}("");
            require(success, "Refund failed");
        }

        emit PolicyIssued(policyId, providerId, msg.sender, tokenId, coverageAmount);
    }

    /**
     * @dev Check if policy is active
     */
    function isPolicyActive(uint256 policyId) public view returns (bool) {
        InsurancePolicy memory policy = policies[policyId];
        return policy.status == PolicyStatus.ACTIVE && 
               block.timestamp <= policy.endDate;
    }

    /**
     * @dev Cancel a policy (by holder before claims)
     * @notice SECURITY FIX: Properly decrements provider capital reserve to prevent inflation attack
     */
    function cancelPolicy(uint256 policyId) external nonReentrant {
        InsurancePolicy storage policy = policies[policyId];
        require(policy.policyHolder == msg.sender, "Not policy holder");
        require(policy.status == PolicyStatus.ACTIVE, "Not active");
        require(policyClaims[policyId].length == 0, "Has claims");

        policy.status = PolicyStatus.CANCELLED;

        InsuranceProvider storage provider = providers[policy.providerId];

        // Calculate prorated refund
        uint256 remainingDays = (policy.endDate - block.timestamp) / 1 days;
        uint256 totalDays = (policy.endDate - policy.startDate) / 1 days;
        uint256 refund = (policy.premium * remainingDays * 80) / (totalDays * 100); // 80% prorated refund

        // SECURITY FIX: Decrement provider capital reserve by the refund amount
        // This ensures the accounting stays in sync with actual ETH balance
        if (refund > 0) {
            require(provider.capitalReserve >= refund, "Insufficient reserve for refund");
            provider.capitalReserve -= refund;

            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Refund failed");
        }

        // SECURITY FIX: Release committed capital since policy is no longer active
        if (committedCapital[policy.providerId] >= policy.coverageAmount) {
            committedCapital[policy.providerId] -= policy.coverageAmount;
        } else {
            committedCapital[policy.providerId] = 0;
        }

        emit PolicyCancelled(policyId, "Holder cancelled");
    }

    // ============ Claims Management ============

    /**
     * @dev Submit an insurance claim
     */
    function submitClaim(
        uint256 policyId,
        uint256 claimAmount,
        string calldata claimReason,
        string calldata evidenceHash
    ) external returns (uint256 claimId) {
        InsurancePolicy storage policy = policies[policyId];
        require(policy.policyHolder == msg.sender, "Not policy holder");
        require(isPolicyActive(policyId), "Policy not active");
        require(claimAmount <= policy.coverageAmount, "Exceeds coverage");
        require(bytes(evidenceHash).length > 0, "Evidence required");

        claimId = nextClaimId++;

        claims[claimId] = InsuranceClaim({
            claimId: claimId,
            policyId: policyId,
            claimant: msg.sender,
            claimAmount: claimAmount,
            claimReason: claimReason,
            evidenceHash: evidenceHash,
            submittedAt: block.timestamp,
            status: ClaimStatus.SUBMITTED,
            approvedAmount: 0,
            processedAt: 0,
            processedBy: address(0),
            resolutionNotes: ""
        });

        policyClaims[policyId].push(claimId);

        emit ClaimSubmitted(claimId, policyId, msg.sender, claimAmount);
    }

    /**
     * @dev Process a claim (approve/reject)
     */
    function processClaim(
        uint256 claimId,
        bool approved,
        uint256 approvedAmount,
        string calldata resolutionNotes
    ) external onlyRole(CLAIMS_ADJUSTER_ROLE) {
        InsuranceClaim storage claim = claims[claimId];
        require(claim.status == ClaimStatus.SUBMITTED || 
                claim.status == ClaimStatus.UNDER_REVIEW, "Invalid status");

        if (approved) {
            require(approvedAmount <= claim.claimAmount, "Exceeds claim amount");
            claim.status = ClaimStatus.APPROVED;
            claim.approvedAmount = approvedAmount;
            policies[claim.policyId].status = PolicyStatus.CLAIMED;
        } else {
            claim.status = ClaimStatus.REJECTED;
            claim.approvedAmount = 0;
        }

        claim.processedAt = block.timestamp;
        claim.processedBy = msg.sender;
        claim.resolutionNotes = resolutionNotes;

        emit ClaimProcessed(claimId, claim.status, approvedAmount);
    }

    /**
     * @dev Pay out an approved claim
     * @notice SECURITY FIX: Releases committed capital when claim is paid
     */
    function payClaim(uint256 claimId) external onlyRole(CLAIMS_ADJUSTER_ROLE) nonReentrant {
        InsuranceClaim storage claim = claims[claimId];
        require(claim.status == ClaimStatus.APPROVED, "Not approved");

        InsurancePolicy storage policy = policies[claim.policyId];
        InsuranceProvider storage provider = providers[policy.providerId];

        require(provider.capitalReserve >= claim.approvedAmount, "Insufficient reserve");

        provider.capitalReserve -= claim.approvedAmount;
        provider.totalClaimsPaid += claim.approvedAmount;
        claim.status = ClaimStatus.PAID;

        // SECURITY FIX: Release committed capital since policy is now claimed
        if (committedCapital[policy.providerId] >= policy.coverageAmount) {
            committedCapital[policy.providerId] -= policy.coverageAmount;
        } else {
            committedCapital[policy.providerId] = 0;
        }

        (bool success, ) = claim.claimant.call{value: claim.approvedAmount}("");
        require(success, "Payment failed");

        emit ClaimPaid(claimId, claim.claimant, claim.approvedAmount);
    }

    // ============ Risk Score Integration ============

    /**
     * @dev Schedule a risk score update with time delay
     * @notice SECURITY FIX: Time-delayed updates prevent front-running premium arbitrage
     *
     * The delay ensures that:
     * 1. Users cannot front-run score increases to lock in lower premiums
     * 2. Users cannot back-run score decreases to wait for lower premiums
     * 3. All users see the same effective score at any given time
     */
    function scheduleRiskScoreUpdate(uint256 tokenId, uint256 newScore) external onlyRole(UNDERWRITER_ROLE) {
        require(newScore <= 10000, "Score must be <= 10000");

        // First, apply any pending update that's now effective
        _applyPendingRiskScore(tokenId);

        // Schedule the new update
        pendingRiskScores[tokenId] = PendingRiskScore({
            newScore: newScore,
            effectiveTime: block.timestamp + RISK_SCORE_DELAY,
            exists: true
        });

        emit RiskScoreUpdateScheduled(tokenId, newScore, block.timestamp + RISK_SCORE_DELAY);
    }

    /**
     * @dev Apply a pending risk score update if it's now effective
     */
    function applyPendingRiskScore(uint256 tokenId) external {
        _applyPendingRiskScore(tokenId);
    }

    /**
     * @dev Internal function to apply pending risk score
     */
    function _applyPendingRiskScore(uint256 tokenId) internal {
        PendingRiskScore storage pending = pendingRiskScores[tokenId];

        if (pending.exists && block.timestamp >= pending.effectiveTime) {
            uint256 oldScore = riskScores[tokenId];
            riskScores[tokenId] = pending.newScore;
            pending.exists = false;

            emit RiskScoreUpdateApplied(tokenId, oldScore, pending.newScore);
        }
    }

    /**
     * @dev Legacy immediate update - only for emergency use by admin
     * @notice Should only be used in emergencies; prefer scheduleRiskScoreUpdate
     */
    function updateRiskScoreEmergency(uint256 tokenId, uint256 score) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(score <= 10000, "Score must be <= 10000");

        // Clear any pending update
        pendingRiskScores[tokenId].exists = false;

        uint256 oldScore = riskScores[tokenId];
        riskScores[tokenId] = score;

        emit RiskScoreUpdated(tokenId, score);
        emit RiskScoreUpdateApplied(tokenId, oldScore, score);
    }

    /**
     * @dev Check if there's a pending risk score update
     */
    function hasPendingRiskScoreUpdate(uint256 tokenId) external view returns (bool, uint256, uint256) {
        PendingRiskScore memory pending = pendingRiskScores[tokenId];
        return (pending.exists, pending.newScore, pending.effectiveTime);
    }

    // ============ Premium Parameter Management ============

    /**
     * @dev Update premium parameters
     */
    function updatePremiumParams(
        CoverageType coverageType,
        uint256 baseRate,
        uint256 riskMultiplier,
        uint256 durationFactor,
        uint256 coverageRatio
    ) external onlyRole(UNDERWRITER_ROLE) {
        premiumParams[coverageType] = PremiumParams({
            baseRate: baseRate,
            riskMultiplier: riskMultiplier,
            durationFactor: durationFactor,
            coverageRatio: coverageRatio
        });

        emit PremiumParamsUpdated(coverageType, baseRate, riskMultiplier);
    }

    // ============ Query Functions ============

    /**
     * @dev Get available capital for a provider (total reserve minus committed)
     */
    function getAvailableCapital(bytes32 providerId) external view returns (uint256) {
        InsuranceProvider storage provider = providers[providerId];
        if (provider.capitalReserve > committedCapital[providerId]) {
            return provider.capitalReserve - committedCapital[providerId];
        }
        return 0;
    }

    /**
     * @dev Release committed capital for expired policies
     * @notice Call this periodically to clean up expired policies and free capital
     */
    function releaseExpiredPolicyCapital(uint256[] calldata policyIds) external {
        for (uint256 i = 0; i < policyIds.length; i++) {
            InsurancePolicy storage policy = policies[policyIds[i]];

            // Only process if policy expired naturally (not claimed/cancelled)
            if (policy.status == PolicyStatus.ACTIVE && block.timestamp > policy.endDate) {
                policy.status = PolicyStatus.EXPIRED;

                // Release committed capital
                if (committedCapital[policy.providerId] >= policy.coverageAmount) {
                    committedCapital[policy.providerId] -= policy.coverageAmount;
                } else {
                    committedCapital[policy.providerId] = 0;
                }
            }
        }
    }

    /**
     * @dev Get all policies for a holder
     */
    function getHolderPolicies(address holder) external view returns (uint256[] memory) {
        return holderPolicies[holder];
    }

    /**
     * @dev Get all policies for a token
     */
    function getTokenPolicies(uint256 tokenId) external view returns (uint256[] memory) {
        return tokenPolicies[tokenId];
    }

    /**
     * @dev Get claims for a policy
     */
    function getPolicyClaims(uint256 policyId) external view returns (uint256[] memory) {
        return policyClaims[policyId];
    }

    /**
     * @dev Get total insured value for a holder
     */
    function getTotalInsuredValue(address holder) external view returns (uint256 total) {
        uint256[] memory policyIds = holderPolicies[holder];
        for (uint256 i = 0; i < policyIds.length; i++) {
            if (isPolicyActive(policyIds[i])) {
                total += policies[policyIds[i]].coverageAmount;
            }
        }
    }

    /**
     * @dev Check if credits are insured
     */
    function areCreditsInsured(uint256 tokenId, address holder) external view returns (bool) {
        uint256[] memory policyIds = tokenPolicies[tokenId];
        for (uint256 i = 0; i < policyIds.length; i++) {
            InsurancePolicy memory policy = policies[policyIds[i]];
            if (policy.policyHolder == holder && isPolicyActive(policyIds[i])) {
                return true;
            }
        }
        return false;
    }

    // ============ Receive Function ============

    /// @notice Receive ETH deposits for insurance capital
    /// @dev Emits EthReceived event for tracking all incoming ETH
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }
}

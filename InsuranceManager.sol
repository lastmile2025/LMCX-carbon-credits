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
     * @dev Calculate premium for a policy
     */
    function calculatePremium(
        uint256 tokenId,
        uint256 creditsToInsure,
        uint256 coverageAmount,
        uint256 durationDays,
        CoverageType coverageType
    ) public view returns (uint256 premium) {
        PremiumParams memory params = premiumParams[coverageType];
        
        // Get risk score (default 5000 = neutral)
        uint256 riskScore = riskScores[tokenId];
        if (riskScore == 0) riskScore = 5000;

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

        // Check provider has adequate capital (require 10% reserve)
        require(
            provider.capitalReserve >= coverageAmount / 10,
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
     */
    function cancelPolicy(uint256 policyId) external {
        InsurancePolicy storage policy = policies[policyId];
        require(policy.policyHolder == msg.sender, "Not policy holder");
        require(policy.status == PolicyStatus.ACTIVE, "Not active");
        require(policyClaims[policyId].length == 0, "Has claims");

        policy.status = PolicyStatus.CANCELLED;

        // Calculate prorated refund
        uint256 remainingDays = (policy.endDate - block.timestamp) / 1 days;
        uint256 totalDays = (policy.endDate - policy.startDate) / 1 days;
        uint256 refund = (policy.premium * remainingDays * 80) / (totalDays * 100); // 80% prorated refund

        if (refund > 0) {
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Refund failed");
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
     */
    function payClaim(uint256 claimId) external onlyRole(CLAIMS_ADJUSTER_ROLE) nonReentrant {
        InsuranceClaim storage claim = claims[claimId];
        require(claim.status == ClaimStatus.APPROVED, "Not approved");

        InsurancePolicy memory policy = policies[claim.policyId];
        InsuranceProvider storage provider = providers[policy.providerId];

        require(provider.capitalReserve >= claim.approvedAmount, "Insufficient reserve");

        provider.capitalReserve -= claim.approvedAmount;
        provider.totalClaimsPaid += claim.approvedAmount;
        claim.status = ClaimStatus.PAID;

        (bool success, ) = claim.claimant.call{value: claim.approvedAmount}("");
        require(success, "Payment failed");

        emit ClaimPaid(claimId, claim.claimant, claim.approvedAmount);
    }

    // ============ Risk Score Integration ============

    /**
     * @dev Update risk score for a token (called by RatingAgency)
     */
    function updateRiskScore(uint256 tokenId, uint256 score) external onlyRole(UNDERWRITER_ROLE) {
        require(score <= 10000, "Score must be <= 10000");
        riskScores[tokenId] = score;
        emit RiskScoreUpdated(tokenId, score);
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

    receive() external payable {}
}

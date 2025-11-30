// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @notice Interface for the ERC1155 token contract
interface ILMCXCarbonCredit {
    function mintCredits(
        address to,
        bytes32 projectId,
        uint256 vintageYear,
        uint256 amount,
        string memory methodology,
        string memory verificationHash
    ) external returns (uint256 mintId, uint256 tokenId);

    function mintCreditsBatch(
        address to,
        bytes32[] memory projectIds,
        uint256[] memory vintageYears,
        uint256[] memory amounts,
        string[] memory methodologies,
        string[] memory verificationHashes
    ) external returns (uint256[] memory mintIds, uint256[] memory tokenIds);
}

/// @notice Interface for ISO 14064-2/3 validator (NEW - replaces ISO 14065)
interface IISO14064Validator {
    function isProjectVerified(bytes32 projectId) external view returns (bool);
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
    function getComplianceScore(bytes32 projectId) external view returns (uint256);
}

/// @notice Interface for OGMP 2.0 validator (enhanced)
interface IOGMP2Validator {
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
    function meetsGoldStandard(bytes32 projectId) external view returns (bool);
    function getComplianceScore(bytes32 projectId) external view returns (uint256);
}

/// @notice Interface for ISO 14065 verifier (legacy support)
interface IISO14065Verifier {
    function isProjectVerified(bytes32 projectId) external view returns (bool);
}

/// @notice Interface for CORSIA compliance
interface ICORSIACompliance {
    function isProjectEligible(bytes32 projectId) external view returns (bool);
    function isVintageYearEligible(bytes32 projectId, uint256 compliancePeriod) external view returns (bool);
}

/// @notice Interface for EPA Subpart W validator (enhanced)
interface IEPASubpartWValidator {
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
    function getComplianceScore(bytes32 projectId) external view returns (uint256);
    function hasCurrentReport(bytes32 projectId) external view returns (bool);
}

/// @notice Interface for CDM AM0023 validator (enhanced)
interface ICDMAM0023Validator {
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
    function isVintageEligible(bytes32 projectId, uint256 year) external view returns (bool);
    function getComplianceScore(bytes32 projectId) external view returns (uint256);
}

/**
 * @title ComplianceManager
 * @dev Orchestrates all regulatory checks and controls access to ERC1155 token minting.
 *
 * Supports multiple international compliance standards:
 * - ISO 14064-2/3: GHG project quantification and verification
 * - OGMP 2.0: Oil and Gas Methane Partnership (5-level framework)
 * - EPA Subpart W: US petroleum and natural gas systems reporting
 * - UNFCCC CDM AM0023: Clean Development Mechanism methodology
 * - CORSIA: Carbon Offsetting and Reduction Scheme for International Aviation
 *
 * Flow:
 *  1. ISSUER_ROLE submits a minting request with projectId, vintage, amount, etc.
 *  2. ADMIN_ROLE (or the same account, depending on your governance) runs compliance checks.
 *  3. If all validators return true, ADMIN_ROLE can approve and execute minting.
 *  4. Only this contract is granted COMPLIANCE_MANAGER_ROLE on the token.
 */
contract ComplianceManager is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    ILMCXCarbonCredit public immutable tokenContract;
    IISO14064Validator public immutable iso14064Validator;  // ISO 14064-2/3 (primary)
    IOGMP2Validator public immutable ogmpValidator;
    IISO14065Verifier public immutable isoVerifier;  // Legacy ISO 14065
    ICORSIACompliance public immutable corsiaCompliance;
    IEPASubpartWValidator public immutable epaSubpartWValidator;
    ICDMAM0023Validator public immutable cdmAM0023Validator;

    // Minimum compliance scores for high-integrity credits (0-10000 scale)
    uint256 public constant MIN_ISO14064_SCORE = 9000;    // 90% for ISO 14064
    uint256 public constant MIN_OGMP_SCORE = 8000;        // 80% for OGMP Gold Standard
    uint256 public constant MIN_EPA_SCORE = 6000;         // 60% for EPA compliance
    uint256 public constant MIN_CDM_SCORE = 7000;         // 70% for CDM compliance

    struct MintingRequest {
        uint256 requestId;
        address requester;
        address beneficiary;
        uint256 amount;
        bytes32 projectId;
        uint256 vintageYear;
        string methodology;
        string verificationHash;
        uint256 createdAt;

        // Compliance flags (enhanced for multi-standard support)
        bool iso14064Compliant;         // ISO 14064-2/3 full compliance
        bool ogmpCompliant;             // OGMP 2.0 compliant
        bool ogmpGoldStandard;          // OGMP 2.0 Gold Standard (highest tier)
        bool isoVerified;               // Legacy ISO 14065 verification
        bool corsiaEligible;            // CORSIA eligible
        bool epaSubpartWCompliant;      // EPA Subpart W compliant
        bool cdmAM0023Compliant;        // CDM AM0023 compliant
        bool vintageEligible;           // Vintage within crediting period

        // Aggregated compliance score
        uint256 aggregateComplianceScore;

        bool approved;
        bool minted;

        // Results after minting (ERC1155 specific)
        uint256 mintId;
        uint256 tokenId;
    }

    uint256 public nextRequestId;
    mapping(uint256 => MintingRequest) private _requests;

    event MintingRequested(
        uint256 indexed requestId,
        address indexed requester,
        address indexed beneficiary,
        uint256 amount,
        bytes32 projectId,
        uint256 vintageYear,
        string methodology,
        string verificationHash
    );

    event ComplianceChecked(
        uint256 indexed requestId,
        bool iso14064Compliant,
        bool ogmpCompliant,
        bool isoVerified,
        bool corsiaEligible,
        bool epaSubpartWCompliant,
        bool cdmAM0023Compliant,
        bool vintageEligible,
        uint256 aggregateScore
    );

    event MintApproved(uint256 indexed requestId, address indexed admin);
    event MintExecuted(uint256 indexed requestId, uint256 mintId, uint256 tokenId);
    event MintRejected(uint256 indexed requestId, string reason);

    constructor(
        address _tokenContract,
        address _iso14064Validator,
        address _ogmpValidator,
        address _isoVerifier,
        address _corsiaCompliance,
        address _epaSubpartWValidator,
        address _cdmAM0023Validator
    ) {
        require(_tokenContract != address(0), "Invalid token contract");
        require(_iso14064Validator != address(0), "Invalid ISO 14064 validator");
        require(_ogmpValidator != address(0), "Invalid OGMP validator");
        require(_isoVerifier != address(0), "Invalid ISO verifier");
        require(_corsiaCompliance != address(0), "Invalid CORSIA contract");
        require(_epaSubpartWValidator != address(0), "Invalid EPA validator");
        require(_cdmAM0023Validator != address(0), "Invalid CDM validator");

        tokenContract = ILMCXCarbonCredit(_tokenContract);
        iso14064Validator = IISO14064Validator(_iso14064Validator);
        ogmpValidator = IOGMP2Validator(_ogmpValidator);
        isoVerifier = IISO14065Verifier(_isoVerifier);
        corsiaCompliance = ICORSIACompliance(_corsiaCompliance);
        epaSubpartWValidator = IEPASubpartWValidator(_epaSubpartWValidator);
        cdmAM0023Validator = ICDMAM0023Validator(_cdmAM0023Validator);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ISSUER_ROLE, msg.sender);
    }

    /**
     * @dev Submit a new minting request.
     */
    function requestMinting(
        address beneficiary,
        uint256 amount,
        bytes32 projectId,
        uint256 vintageYear,
        string calldata methodology,
        string calldata verificationHash
    ) external onlyRole(ISSUER_ROLE) returns (uint256 requestId) {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(projectId != bytes32(0), "Invalid projectId");
        require(vintageYear >= 2000 && vintageYear <= 2100, "Invalid vintage year");
        require(bytes(methodology).length > 0, "Methodology required");
        require(bytes(verificationHash).length > 0, "Verification hash required");

        requestId = nextRequestId;
        nextRequestId += 1;

        _requests[requestId] = MintingRequest({
            requestId: requestId,
            requester: msg.sender,
            beneficiary: beneficiary,
            amount: amount,
            projectId: projectId,
            vintageYear: vintageYear,
            methodology: methodology,
            verificationHash: verificationHash,
            createdAt: block.timestamp,
            iso14064Compliant: false,
            ogmpCompliant: false,
            ogmpGoldStandard: false,
            isoVerified: false,
            corsiaEligible: false,
            epaSubpartWCompliant: false,
            cdmAM0023Compliant: false,
            vintageEligible: false,
            aggregateComplianceScore: 0,
            approved: false,
            minted: false,
            mintId: 0,
            tokenId: 0
        });

        emit MintingRequested(
            requestId,
            msg.sender,
            beneficiary,
            amount,
            projectId,
            vintageYear,
            methodology,
            verificationHash
        );
    }

    /**
     * @dev Run all compliance checks for a given request.
     * Can be called by ADMIN_ROLE (e.g. compliance officer).
     *
     * Enhanced to support:
     * - ISO 14064-2/3 comprehensive validation
     * - OGMP 2.0 with Gold Standard tracking
     * - Aggregate compliance scoring
     */
    function performComplianceChecks(uint256 requestId) public onlyRole(ADMIN_ROLE) {
        MintingRequest storage r = _getExistingRequest(requestId);

        // ISO 14064-2/3 check (primary standard for project-level GHG)
        bool iso14064Ok = iso14064Validator.isProjectCompliant(r.projectId);
        uint256 iso14064Score = iso14064Validator.getComplianceScore(r.projectId);

        // OGMP 2.0 checks (for oil & gas methane projects)
        bool ogmpOk = ogmpValidator.isProjectCompliant(r.projectId);
        bool ogmpGold = ogmpValidator.meetsGoldStandard(r.projectId);
        uint256 ogmpScore = ogmpValidator.getComplianceScore(r.projectId);

        // Legacy ISO 14065 verification body check
        bool isoOk = isoVerifier.isProjectVerified(r.projectId);

        // CORSIA eligibility
        bool corsiaOk = corsiaCompliance.isProjectEligible(r.projectId);

        // EPA Subpart W check (for US facilities)
        bool epaOk = epaSubpartWValidator.isProjectCompliant(r.projectId);
        uint256 epaScore = epaSubpartWValidator.getComplianceScore(r.projectId);

        // CDM AM0023 check (for waste management methane projects)
        bool cdmOk = cdmAM0023Validator.isProjectCompliant(r.projectId);
        uint256 cdmScore = cdmAM0023Validator.getComplianceScore(r.projectId);

        // Vintage eligibility: require CORSIA & CDM agreement
        bool corsiaVintageOk = corsiaCompliance.isVintageYearEligible(r.projectId, r.vintageYear);
        bool cdmVintageOk = cdmAM0023Validator.isVintageEligible(r.projectId, r.vintageYear);
        bool vintageOk = corsiaVintageOk && cdmVintageOk;

        // Calculate aggregate compliance score (weighted average)
        // ISO 14064: 30%, OGMP: 25%, EPA: 20%, CDM: 25%
        uint256 aggregateScore = (
            (iso14064Score * 3000) +
            (ogmpScore * 2500) +
            (epaScore * 2000) +
            (cdmScore * 2500)
        ) / 10000;

        // Store results
        r.iso14064Compliant = iso14064Ok;
        r.ogmpCompliant = ogmpOk;
        r.ogmpGoldStandard = ogmpGold;
        r.isoVerified = isoOk;
        r.corsiaEligible = corsiaOk;
        r.epaSubpartWCompliant = epaOk;
        r.cdmAM0023Compliant = cdmOk;
        r.vintageEligible = vintageOk;
        r.aggregateComplianceScore = aggregateScore;

        emit ComplianceChecked(
            requestId,
            iso14064Ok,
            ogmpOk,
            isoOk,
            corsiaOk,
            epaOk,
            cdmOk,
            vintageOk,
            aggregateScore
        );
    }

    /**
     * @dev Approve and execute minting if all checks pass.
     *
     * For highest-integrity credits, requires:
     * - ISO 14064-2/3 compliance (primary standard)
     * - OGMP 2.0 compliance (for oil & gas projects)
     * - ISO 14065 verification (accredited body)
     * - CORSIA eligibility
     * - EPA Subpart W compliance (for US facilities)
     * - CDM AM0023 compliance (for waste methane projects)
     * - Valid vintage year
     */
    function approveMinting(uint256 requestId) external onlyRole(ADMIN_ROLE) nonReentrant {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(!r.minted, "Already minted");

        // If no checks have been run yet, run them now
        if (
            !r.iso14064Compliant &&
            !r.ogmpCompliant &&
            !r.isoVerified &&
            !r.corsiaEligible &&
            !r.epaSubpartWCompliant &&
            !r.cdmAM0023Compliant &&
            !r.vintageEligible
        ) {
            performComplianceChecks(requestId);
        }

        // Primary requirement: ISO 14064-2/3 compliance
        require(r.iso14064Compliant, "ISO 14064-2/3 non-compliant");

        // Secondary requirements for highest integrity
        require(r.ogmpCompliant, "OGMP2 non-compliant");
        require(r.isoVerified, "ISO14065 not verified");
        require(r.corsiaEligible, "Not CORSIA-eligible");
        require(r.epaSubpartWCompliant, "EPA Subpart W non-compliant");
        require(r.cdmAM0023Compliant, "CDM AM0023 non-compliant");
        require(r.vintageEligible, "Vintage not eligible");

        r.approved = true;
        emit MintApproved(requestId, msg.sender);

        // Mint credits (ERC1155 version)
        (uint256 mintId, uint256 tokenId) = tokenContract.mintCredits(
            r.beneficiary,
            r.projectId,
            r.vintageYear,
            r.amount,
            r.methodology,
            r.verificationHash
        );

        r.minted = true;
        r.mintId = mintId;
        r.tokenId = tokenId;

        emit MintExecuted(requestId, mintId, tokenId);
    }

    /**
     * @dev Reject a request off-chain / governance reasons, without minting.
     * Does NOT delete the request; it simply marks it as not minted and emits an event.
     */
    function rejectMinting(uint256 requestId, string calldata reason)
        external
        onlyRole(ADMIN_ROLE)
    {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(!r.minted, "Already minted");
        // no state change besides the event; off-chain systems can treat this as final
        emit MintRejected(requestId, reason);
    }

    /**
     * @dev View helper: returns full details of a minting request.
     */
    function getMintingRequest(uint256 requestId)
        external
        view
        returns (MintingRequest memory)
    {
        return _getExistingRequest(requestId);
    }

    /**
     * @dev Returns true if all compliance flags are set to true for this request.
     */
    function isFullyCompliant(uint256 requestId) external view returns (bool) {
        MintingRequest storage r = _getExistingRequest(requestId);
        return (
            r.iso14064Compliant &&
            r.ogmpCompliant &&
            r.isoVerified &&
            r.corsiaEligible &&
            r.epaSubpartWCompliant &&
            r.cdmAM0023Compliant &&
            r.vintageEligible
        );
    }

    /**
     * @dev Returns true if project meets Gold Standard (highest integrity tier).
     * Requires OGMP 2.0 Gold Standard + all other compliance checks.
     */
    function meetsGoldStandard(uint256 requestId) external view returns (bool) {
        MintingRequest storage r = _getExistingRequest(requestId);
        return (
            r.iso14064Compliant &&
            r.ogmpGoldStandard &&  // Gold Standard specifically
            r.isoVerified &&
            r.corsiaEligible &&
            r.epaSubpartWCompliant &&
            r.cdmAM0023Compliant &&
            r.vintageEligible
        );
    }

    /**
     * @dev Get the aggregate compliance score for a request.
     */
    function getAggregateComplianceScore(uint256 requestId) external view returns (uint256) {
        return _getExistingRequest(requestId).aggregateComplianceScore;
    }

    /**
     * @dev Get the ERC1155 token ID for a minted request.
     */
    function getTokenId(uint256 requestId) external view returns (uint256) {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(r.minted, "Not yet minted");
        return r.tokenId;
    }

    /**
     * @dev Get the mint record ID for a minted request.
     */
    function getMintId(uint256 requestId) external view returns (uint256) {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(r.minted, "Not yet minted");
        return r.mintId;
    }

    function _getExistingRequest(uint256 requestId) internal view returns (MintingRequest storage) {
        require(requestId < nextRequestId, "Invalid requestId");
        return _requests[requestId];
    }
}

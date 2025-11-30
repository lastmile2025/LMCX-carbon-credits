// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Interfaces for integrated contracts
interface IGovernanceController {
    function hasRequiredSignatures(uint256 proposalId) external view returns (bool);
    function state(uint256 proposalId) external view returns (uint8);
}

interface IVerificationRegistry {
    function isCreditVerified(bytes32 creditTokenId) external view returns (bool);
    function getCreditVerificationStatus(bytes32 creditTokenId) external view returns (
        uint8 status,
        uint256 verifiedAt,
        uint256 expiresAt,
        int256 verifiedReductions,
        uint256 signatureCount
    );
    function recordCustodyTransfer(
        bytes32 creditTokenId,
        address from,
        address to,
        bytes32 transactionHash,
        string calldata custodyType
    ) external returns (bytes32);
}

interface IOracleAggregator {
    function getLatestValue(bytes32 feedId) external view returns (int256 value, uint256 timestamp, uint256 quality);
    function circuitBreakerActive() external view returns (bool);
}

interface IVintageTracker {
    function createVintageRecord(
        bytes32 creditId,
        uint256 tokenId,
        bytes32 projectId,
        uint256 vintageYear,
        address minter,
        bytes32 jurisdictionCode
    ) external returns (bytes32);
    function recordTransfer(
        bytes32 creditId,
        address from,
        address to,
        bytes32 transactionHash
    ) external;
    function isTransferable(bytes32 creditId) external view returns (bool);
    function getEffectiveValue(bytes32 creditId, uint256 baseValue) external view returns (uint256);
    function getVintageRecord(bytes32 creditId) external view returns (
        bytes32 creditIdRet,
        uint256 tokenId,
        bytes32 projectId,
        uint256 vintageYear,
        uint256 mintedAt,
        uint256 coolingOffEndsAt,
        uint8 state,
        uint8 grade,
        uint256 qualityScore,
        uint256 discountFactor,
        address originalMinter,
        address currentHolder,
        uint256 transferCount,
        uint256 lastTransferAt,
        bool isGeofenced,
        bytes32 jurisdictionCode
    );
    function retireCredit(
        bytes32 creditId,
        uint256 amount,
        string calldata beneficiary,
        string calldata purpose,
        string calldata certificateHash
    ) external returns (bytes32);
}

/**
 * @title LMCXCarbonCredit
 * @dev ERC1155 multi-token representing verified carbon credits with comprehensive
 * compliance controls, insurance integration, rating agency access, and dMRV support.
 *
 * Each token ID represents a unique combination of project + vintage year.
 * Each token unit represents 1 tonne of CO2e avoided or removed.
 *
 * Integrations:
 * - Insurance: Credits can be insured through InsuranceManager
 * - Ratings: Rating agencies can assess credit quality
 * - dMRV: Real-time monitoring data from Enovate.ai
 * - SMART Protocol: Data governance and integrity compliance
 * - Governance: DAO-based governance with time-locks and multi-sig
 * - Verification: Cryptographic proof chains for verification integrity
 * - Oracle Aggregator: Multi-oracle redundancy for data integrity
 * - Vintage Tracker: Credit lifecycle and vintage tracking
 */
contract LMCXCarbonCredit is ERC1155Burnable, ERC1155Supply, AccessControl, Pausable {
    using Strings for uint256;

    // ============ Roles ============
    bytes32 public constant COMPLIANCE_MANAGER_ROLE = keccak256("COMPLIANCE_MANAGER_ROLE");
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 public constant RATING_AGENCY_ROLE = keccak256("RATING_AGENCY_ROLE");
    bytes32 public constant DMRV_ORACLE_ROLE = keccak256("DMRV_ORACLE_ROLE");
    bytes32 public constant INSURANCE_MANAGER_ROLE = keccak256("INSURANCE_MANAGER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant VINTAGE_TRACKER_ROLE = keccak256("VINTAGE_TRACKER_ROLE");

    string public name = "LMCX Carbon Credit";
    string public symbol = "LMCXCC";
    string private _baseURI;

    // ============ Core Data Structures ============
    
    struct CreditMetadata {
        bytes32 projectId;
        uint256 vintageYear;
        string methodology;
        string verificationHash;
        uint256 createdAt;
        bool exists;
        // SMART Protocol compliance
        bool hasSMARTCompliance;
        bytes32 smartDataId;
    }

    struct MintRecord {
        uint256 tokenId;
        address beneficiary;
        uint256 amount;
        uint256 mintedAt;
        string verificationHash;
        bytes32 dmrvReportId;        // Associated dMRV report
    }

    // ============ Insurance Integration ============
    
    struct InsuranceStatus {
        bool isInsurable;
        uint256 maxCoverage;
        uint256 riskScore;           // From rating agencies
        uint256 lastRiskUpdate;
    }

    // ============ Rating Integration ============
    
    struct RatingInfo {
        uint256 aggregatedScore;     // 0-10000 scale
        string grade;                // Letter grade
        uint256 lastRatingUpdate;
        uint256 ratingCount;         // Number of agencies that have rated
    }

    // ============ dMRV Integration ============
    
    struct DMRVStatus {
        bool isMonitored;
        bytes32 latestReportId;
        uint256 lastMeasurement;
        int256 cumulativeReductions;  // Scaled by 1e6
        uint256 measurementCount;
        bool hasActiveAlerts;
    }

    // ============ SMART Protocol Compliance ============
    
    struct SMARTCompliance {
        bool locationVerified;
        bool temporallyBound;
        bool verificationComplete;
        bool custodyAssigned;
        bool lineageTracked;
        bytes32 complianceDataId;
    }

    // ============ Storage ============

    mapping(uint256 => CreditMetadata) private _creditMetadata;
    mapping(uint256 => InsuranceStatus) public insuranceStatus;
    mapping(uint256 => RatingInfo) public ratingInfo;
    mapping(uint256 => DMRVStatus) public dmrvStatus;
    mapping(uint256 => SMARTCompliance) public smartCompliance;
    
    uint256 public nextMintId;
    mapping(uint256 => MintRecord) private _mintRecords;
    
    uint256[] private _allTokenIds;
    mapping(uint256 => bool) private _tokenIdExists;

    // External contract references
    address public insuranceManager;
    address public ratingAgencyRegistry;
    address public dmrvOracle;
    address public smartDataRegistry;

    // New integrated contract references
    address public governanceController;
    address public verificationRegistry;
    address public oracleAggregator;
    address public vintageTracker;

    // Jurisdiction tracking for geofencing
    mapping(uint256 => bytes32) public tokenJurisdiction;

    // Credit ID mapping (for verification and vintage tracking)
    mapping(uint256 => bytes32) public tokenToCreditId;

    // Verification requirements
    bool public requireVerificationForMint = true;
    bool public requireVerificationForTransfer = false;
    uint256 public minOracleQuality = 7000; // 70% minimum quality score

    // Optional feature flags
    bool public insuranceEnabled = false;      // Insurance is optional
    bool public ratingsEnabled = false;        // Ratings are optional
    bool public vintageTrackingEnabled = true; // Vintage tracking enabled by default

    // ============ Events ============

    event ComplianceManagerSet(address indexed complianceManager);
    
    event CreditTypeCreated(
        uint256 indexed tokenId,
        bytes32 indexed projectId,
        uint256 vintageYear,
        string methodology
    );

    event CreditsMinted(
        uint256 indexed mintId,
        uint256 indexed tokenId,
        address indexed beneficiary,
        uint256 amount,
        bytes32 projectId,
        uint256 vintageYear,
        string verificationHash
    );

    event CreditsBatchMinted(
        uint256[] mintIds,
        uint256[] tokenIds,
        address indexed beneficiary,
        uint256[] amounts
    );

    event CreditRetired(
        uint256 indexed tokenId,
        address indexed holder,
        uint256 amount,
        string retirementReason,
        string beneficiaryName
    );

    event InsuranceStatusUpdated(
        uint256 indexed tokenId,
        bool isInsurable,
        uint256 maxCoverage,
        uint256 riskScore
    );

    event RatingUpdated(
        uint256 indexed tokenId,
        uint256 aggregatedScore,
        string grade,
        uint256 ratingCount
    );

    event DMRVStatusUpdated(
        uint256 indexed tokenId,
        bytes32 reportId,
        int256 cumulativeReductions,
        bool hasActiveAlerts
    );

    event SMARTComplianceUpdated(
        uint256 indexed tokenId,
        bool isCompliant,
        bytes32 complianceDataId
    );

    event ExternalContractSet(
        string contractType,
        address indexed contractAddress
    );

    event GovernanceActionExecuted(
        uint256 indexed proposalId,
        string action
    );

    event VerificationRequired(
        uint256 indexed tokenId,
        bytes32 creditId,
        bool isVerified
    );

    event VintageRecordLinked(
        uint256 indexed tokenId,
        bytes32 indexed creditId,
        uint256 vintageYear
    );

    event OracleDataUsed(
        bytes32 indexed feedId,
        int256 value,
        uint256 quality
    );

    event TransferRestricted(
        uint256 indexed tokenId,
        address from,
        address to,
        string reason
    );

    event FeatureFlagUpdated(
        string feature,
        bool enabled
    );

    constructor(string memory baseURI_) ERC1155(baseURI_) {
        _baseURI = baseURI_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(URI_SETTER_ROLE, msg.sender);
    }

    // ============ Token ID Generation ============

    function generateTokenId(bytes32 projectId, uint256 vintageYear) 
        public 
        pure 
        returns (uint256) 
    {
        return uint256(keccak256(abi.encodePacked(projectId, vintageYear)));
    }

    // ============ Minting Functions ============

    function mintCredits(
        address to,
        bytes32 projectId,
        uint256 vintageYear,
        uint256 amount,
        string memory methodology,
        string memory verificationHash
    ) external onlyRole(COMPLIANCE_MANAGER_ROLE) whenNotPaused returns (uint256 mintId, uint256 tokenId) {
        return mintCreditsWithJurisdiction(to, projectId, vintageYear, amount, methodology, verificationHash, bytes32(0));
    }

    /**
     * @dev Mint credits with jurisdiction for geofencing
     */
    function mintCreditsWithJurisdiction(
        address to,
        bytes32 projectId,
        uint256 vintageYear,
        uint256 amount,
        string memory methodology,
        string memory verificationHash,
        bytes32 jurisdictionCode
    ) public onlyRole(COMPLIANCE_MANAGER_ROLE) whenNotPaused returns (uint256 mintId, uint256 tokenId) {
        require(to != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(bytes(verificationHash).length > 0, "Verification hash required");

        // Check oracle circuit breaker
        if (oracleAggregator != address(0)) {
            require(!IOracleAggregator(oracleAggregator).circuitBreakerActive(), "Oracle circuit breaker active");
        }

        tokenId = generateTokenId(projectId, vintageYear);
        bytes32 creditId = bytes32(tokenId);

        // Check verification if required
        if (requireVerificationForMint && verificationRegistry != address(0)) {
            bool isVerified = IVerificationRegistry(verificationRegistry).isCreditVerified(creditId);
            emit VerificationRequired(tokenId, creditId, isVerified);
            require(isVerified, "Credit verification required");
        }

        if (!_creditMetadata[tokenId].exists) {
            _creditMetadata[tokenId] = CreditMetadata({
                projectId: projectId,
                vintageYear: vintageYear,
                methodology: methodology,
                verificationHash: verificationHash,
                createdAt: block.timestamp,
                exists: true,
                hasSMARTCompliance: false,
                smartDataId: bytes32(0)
            });

            _allTokenIds.push(tokenId);
            _tokenIdExists[tokenId] = true;

            // Initialize insurance status
            insuranceStatus[tokenId] = InsuranceStatus({
                isInsurable: true,
                maxCoverage: 0,
                riskScore: 5000,  // Neutral default
                lastRiskUpdate: block.timestamp
            });

            // Set jurisdiction for geofencing
            tokenJurisdiction[tokenId] = jurisdictionCode;

            emit CreditTypeCreated(tokenId, projectId, vintageYear, methodology);
        }

        mintId = nextMintId++;
        tokenToCreditId[tokenId] = creditId;

        _mintRecords[mintId] = MintRecord({
            tokenId: tokenId,
            beneficiary: to,
            amount: amount,
            mintedAt: block.timestamp,
            verificationHash: verificationHash,
            dmrvReportId: bytes32(0)
        });

        _mint(to, tokenId, amount, "");

        // Create vintage record if tracker is set and enabled
        if (vintageTrackingEnabled && vintageTracker != address(0)) {
            IVintageTracker(vintageTracker).createVintageRecord(
                creditId,
                tokenId,
                projectId,
                vintageYear,
                to,
                jurisdictionCode
            );
            emit VintageRecordLinked(tokenId, creditId, vintageYear);
        }

        // Record custody in verification registry
        if (verificationRegistry != address(0)) {
            IVerificationRegistry(verificationRegistry).recordCustodyTransfer(
                creditId,
                address(0),
                to,
                bytes32(uint256(uint160(address(this)))),
                "mint"
            );
        }

        emit CreditsMinted(mintId, tokenId, to, amount, projectId, vintageYear, verificationHash);
    }

    function mintCreditsWithDMRV(
        address to,
        bytes32 projectId,
        uint256 vintageYear,
        uint256 amount,
        string memory methodology,
        string memory verificationHash,
        bytes32 dmrvReportId
    ) external onlyRole(COMPLIANCE_MANAGER_ROLE) whenNotPaused returns (uint256 mintId, uint256 tokenId) {
        (mintId, tokenId) = this.mintCredits(to, projectId, vintageYear, amount, methodology, verificationHash);
        
        _mintRecords[mintId].dmrvReportId = dmrvReportId;
        
        // Update dMRV status
        dmrvStatus[tokenId].isMonitored = true;
        dmrvStatus[tokenId].latestReportId = dmrvReportId;
    }

    // ============ Retirement Function ============

    function retireCredits(
        uint256 tokenId,
        uint256 amount,
        string memory retirementReason,
        string memory beneficiaryName
    ) external whenNotPaused {
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");
        require(bytes(retirementReason).length > 0, "Retirement reason required");

        bytes32 creditId = tokenToCreditId[tokenId];

        // Record retirement in vintage tracker if enabled
        if (vintageTrackingEnabled && vintageTracker != address(0) && creditId != bytes32(0)) {
            IVintageTracker(vintageTracker).retireCredit(
                creditId,
                amount,
                beneficiaryName,
                retirementReason,
                "" // Certificate hash can be set externally
            );
        }

        // Record custody transfer for retirement
        if (verificationRegistry != address(0) && creditId != bytes32(0)) {
            IVerificationRegistry(verificationRegistry).recordCustodyTransfer(
                creditId,
                msg.sender,
                address(0),
                bytes32(uint256(uint160(address(this)))),
                "retire"
            );
        }

        _burn(msg.sender, tokenId, amount);

        emit CreditRetired(tokenId, msg.sender, amount, retirementReason, beneficiaryName);
    }

    /**
     * @dev Enhanced retirement with certificate hash
     */
    function retireCreditsWithCertificate(
        uint256 tokenId,
        uint256 amount,
        string memory retirementReason,
        string memory beneficiaryName,
        string memory certificateHash
    ) external whenNotPaused {
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");
        require(bytes(retirementReason).length > 0, "Retirement reason required");

        bytes32 creditId = tokenToCreditId[tokenId];

        // Record retirement in vintage tracker with certificate if enabled
        if (vintageTrackingEnabled && vintageTracker != address(0) && creditId != bytes32(0)) {
            IVintageTracker(vintageTracker).retireCredit(
                creditId,
                amount,
                beneficiaryName,
                retirementReason,
                certificateHash
            );
        }

        // Record custody transfer for retirement
        if (verificationRegistry != address(0) && creditId != bytes32(0)) {
            IVerificationRegistry(verificationRegistry).recordCustodyTransfer(
                creditId,
                msg.sender,
                address(0),
                bytes32(uint256(uint160(address(this)))),
                "retire"
            );
        }

        _burn(msg.sender, tokenId, amount);

        emit CreditRetired(tokenId, msg.sender, amount, retirementReason, beneficiaryName);
    }

    // ============ Insurance Integration ============

    /**
     * @dev Update insurance status for a token (called by InsuranceManager)
     * @notice Insurance is an optional feature - must be enabled first
     */
    function updateInsuranceStatus(
        uint256 tokenId,
        bool _isInsurable,
        uint256 maxCoverage,
        uint256 riskScore
    ) external onlyRole(INSURANCE_MANAGER_ROLE) {
        require(insuranceEnabled, "Insurance feature not enabled");
        require(_tokenIdExists[tokenId], "Token does not exist");

        insuranceStatus[tokenId] = InsuranceStatus({
            isInsurable: _isInsurable,
            maxCoverage: maxCoverage,
            riskScore: riskScore,
            lastRiskUpdate: block.timestamp
        });

        emit InsuranceStatusUpdated(tokenId, _isInsurable, maxCoverage, riskScore);
    }

    /**
     * @dev Check if credits are insurable
     */
    function isInsurable(uint256 tokenId) external view returns (bool) {
        return insuranceStatus[tokenId].isInsurable;
    }

    /**
     * @dev Get insurance details for a token
     */
    function getInsuranceStatus(uint256 tokenId) 
        external 
        view 
        returns (InsuranceStatus memory) 
    {
        return insuranceStatus[tokenId];
    }

    // ============ Rating Agency Integration ============

    /**
     * @dev Update rating information (called by RatingAgencyRegistry)
     * @notice Ratings are an optional feature - must be enabled first
     */
    function updateRating(
        uint256 tokenId,
        uint256 aggregatedScore,
        string memory grade,
        uint256 ratingCount
    ) external onlyRole(RATING_AGENCY_ROLE) {
        require(ratingsEnabled, "Ratings feature not enabled");
        require(_tokenIdExists[tokenId], "Token does not exist");

        ratingInfo[tokenId] = RatingInfo({
            aggregatedScore: aggregatedScore,
            grade: grade,
            lastRatingUpdate: block.timestamp,
            ratingCount: ratingCount
        });

        // Also update insurance risk score if insurance is enabled (inverse relationship)
        if (insuranceEnabled) {
            insuranceStatus[tokenId].riskScore = 10000 - aggregatedScore;
            insuranceStatus[tokenId].lastRiskUpdate = block.timestamp;
        }

        emit RatingUpdated(tokenId, aggregatedScore, grade, ratingCount);
    }

    /**
     * @dev Get rating for a token
     */
    function getRating(uint256 tokenId) 
        external 
        view 
        returns (uint256 score, string memory grade, uint256 count) 
    {
        RatingInfo memory info = ratingInfo[tokenId];
        return (info.aggregatedScore, info.grade, info.ratingCount);
    }

    /**
     * @dev Check if token is investment grade (BBB or above = 6000+)
     */
    function isInvestmentGrade(uint256 tokenId) external view returns (bool) {
        return ratingInfo[tokenId].aggregatedScore >= 6000;
    }

    // ============ dMRV Integration ============

    /**
     * @dev Update dMRV status (called by DMRVOracle)
     */
    function updateDMRVStatus(
        uint256 tokenId,
        bytes32 reportId,
        int256 cumulativeReductions,
        uint256 measurementCount,
        bool hasActiveAlerts
    ) external onlyRole(DMRV_ORACLE_ROLE) {
        require(_tokenIdExists[tokenId], "Token does not exist");
        
        dmrvStatus[tokenId] = DMRVStatus({
            isMonitored: true,
            latestReportId: reportId,
            lastMeasurement: block.timestamp,
            cumulativeReductions: cumulativeReductions,
            measurementCount: measurementCount,
            hasActiveAlerts: hasActiveAlerts
        });

        emit DMRVStatusUpdated(tokenId, reportId, cumulativeReductions, hasActiveAlerts);
    }

    /**
     * @dev Get dMRV status for a token
     */
    function getDMRVStatus(uint256 tokenId) 
        external 
        view 
        returns (DMRVStatus memory) 
    {
        return dmrvStatus[tokenId];
    }

    /**
     * @dev Check if token has active monitoring
     */
    function isActivelyMonitored(uint256 tokenId) external view returns (bool) {
        DMRVStatus memory status = dmrvStatus[tokenId];
        // Consider monitored if measurement within last 30 days
        return status.isMonitored && 
               (block.timestamp - status.lastMeasurement) < 30 days;
    }

    // ============ SMART Protocol Integration ============

    /**
     * @dev Update SMART Protocol compliance status
     */
    function updateSMARTCompliance(
        uint256 tokenId,
        bool locationVerified,
        bool temporallyBound,
        bool verificationComplete,
        bool custodyAssigned,
        bool lineageTracked,
        bytes32 complianceDataId
    ) external onlyRole(COMPLIANCE_MANAGER_ROLE) {
        require(_tokenIdExists[tokenId], "Token does not exist");
        
        smartCompliance[tokenId] = SMARTCompliance({
            locationVerified: locationVerified,
            temporallyBound: temporallyBound,
            verificationComplete: verificationComplete,
            custodyAssigned: custodyAssigned,
            lineageTracked: lineageTracked,
            complianceDataId: complianceDataId
        });

        bool isCompliant = locationVerified && temporallyBound && 
                          verificationComplete && custodyAssigned && lineageTracked;
        
        _creditMetadata[tokenId].hasSMARTCompliance = isCompliant;
        _creditMetadata[tokenId].smartDataId = complianceDataId;

        emit SMARTComplianceUpdated(tokenId, isCompliant, complianceDataId);
    }

    /**
     * @dev Check if token is SMART Protocol compliant
     */
    function isSMARTCompliant(uint256 tokenId) external view returns (bool) {
        SMARTCompliance memory compliance = smartCompliance[tokenId];
        return compliance.locationVerified && 
               compliance.temporallyBound && 
               compliance.verificationComplete && 
               compliance.custodyAssigned && 
               compliance.lineageTracked;
    }

    /**
     * @dev Get full SMART compliance status
     */
    function getSMARTCompliance(uint256 tokenId) 
        external 
        view 
        returns (SMARTCompliance memory) 
    {
        return smartCompliance[tokenId];
    }

    // ============ Comprehensive Token Info ============

    /**
     * @dev Get comprehensive token information including all integrations
     */
    function getComprehensiveTokenInfo(uint256 tokenId)
        external
        view
        returns (
            CreditMetadata memory metadata,
            InsuranceStatus memory insurance,
            RatingInfo memory rating,
            DMRVStatus memory dmrv,
            SMARTCompliance memory smart,
            uint256 tokenTotalSupply
        )
    {
        require(_tokenIdExists[tokenId], "Token does not exist");

        metadata = _creditMetadata[tokenId];
        insurance = insuranceStatus[tokenId];
        rating = ratingInfo[tokenId];
        dmrv = dmrvStatus[tokenId];
        smart = smartCompliance[tokenId];
        tokenTotalSupply = totalSupply(tokenId);
    }

    // ============ Metadata Functions ============

    function getCreditMetadata(uint256 tokenId) 
        external 
        view 
        returns (CreditMetadata memory) 
    {
        require(_creditMetadata[tokenId].exists, "Token ID does not exist");
        return _creditMetadata[tokenId];
    }

    function getMintRecord(uint256 mintId) 
        external 
        view 
        returns (MintRecord memory) 
    {
        require(mintId < nextMintId, "Invalid mintId");
        return _mintRecords[mintId];
    }

    /// @notice Returns all token IDs. Warning: May fail for large arrays due to gas limits.
    /// @dev For large collections, use getTokenIdsPaginated instead.
    function getAllTokenIds() external view returns (uint256[] memory) {
        return _allTokenIds;
    }

    /// @notice Gas-optimized paginated token ID retrieval
    /// @param offset Starting index
    /// @param limit Maximum number of token IDs to return
    /// @return tokenIds Array of token IDs for the requested page
    /// @return total Total number of token IDs available
    function getTokenIdsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokenIds, uint256 total)
    {
        total = _allTokenIds.length;

        if (offset >= total || limit == 0) {
            return (new uint256[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 resultLength = end - offset;
        tokenIds = new uint256[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            tokenIds[i] = _allTokenIds[offset + i];
        }

        return (tokenIds, total);
    }

    function getTotalCreditTypes() external view returns (uint256) {
        return _allTokenIds.length;
    }

    function tokenExists(uint256 tokenId) external view returns (bool) {
        return _tokenIdExists[tokenId];
    }

    function balanceOfByProject(
        address account,
        bytes32 projectId,
        uint256 vintageYear
    ) external view returns (uint256) {
        uint256 tokenId = generateTokenId(projectId, vintageYear);
        return balanceOf(account, tokenId);
    }

    // ============ External Contract Management ============

    function setInsuranceManager(address _insuranceManager) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        insuranceManager = _insuranceManager;
        _grantRole(INSURANCE_MANAGER_ROLE, _insuranceManager);
        emit ExternalContractSet("InsuranceManager", _insuranceManager);
    }

    function setRatingAgencyRegistry(address _ratingAgencyRegistry) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        ratingAgencyRegistry = _ratingAgencyRegistry;
        _grantRole(RATING_AGENCY_ROLE, _ratingAgencyRegistry);
        emit ExternalContractSet("RatingAgencyRegistry", _ratingAgencyRegistry);
    }

    function setDMRVOracle(address _dmrvOracle) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        dmrvOracle = _dmrvOracle;
        _grantRole(DMRV_ORACLE_ROLE, _dmrvOracle);
        emit ExternalContractSet("DMRVOracle", _dmrvOracle);
    }

    function setSMARTDataRegistry(address _smartDataRegistry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        smartDataRegistry = _smartDataRegistry;
        emit ExternalContractSet("SMARTDataRegistry", _smartDataRegistry);
    }

    function setComplianceManager(address complianceManager)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(complianceManager != address(0), "Invalid address");
        _grantRole(COMPLIANCE_MANAGER_ROLE, complianceManager);
        emit ComplianceManagerSet(complianceManager);
    }

    // ============ New Integrated Contract Setters ============

    /**
     * @dev Set the governance controller address
     */
    function setGovernanceController(address _governanceController)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        governanceController = _governanceController;
        if (_governanceController != address(0)) {
            _grantRole(GOVERNANCE_ROLE, _governanceController);
        }
        emit ExternalContractSet("GovernanceController", _governanceController);
    }

    /**
     * @dev Set the verification registry address
     */
    function setVerificationRegistry(address _verificationRegistry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        verificationRegistry = _verificationRegistry;
        emit ExternalContractSet("VerificationRegistry", _verificationRegistry);
    }

    /**
     * @dev Set the oracle aggregator address
     */
    function setOracleAggregator(address _oracleAggregator)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        oracleAggregator = _oracleAggregator;
        emit ExternalContractSet("OracleAggregator", _oracleAggregator);
    }

    /**
     * @dev Set the vintage tracker address
     */
    function setVintageTracker(address _vintageTracker)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        vintageTracker = _vintageTracker;
        if (_vintageTracker != address(0)) {
            _grantRole(VINTAGE_TRACKER_ROLE, _vintageTracker);
        }
        emit ExternalContractSet("VintageTracker", _vintageTracker);
    }

    /**
     * @dev Set verification requirements
     */
    function setVerificationRequirements(
        bool _requireForMint,
        bool _requireForTransfer,
        uint256 _minOracleQuality
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        requireVerificationForMint = _requireForMint;
        requireVerificationForTransfer = _requireForTransfer;
        minOracleQuality = _minOracleQuality;
    }

    /**
     * @dev Enable or disable optional features
     * @param _insuranceEnabled Enable insurance integration
     * @param _ratingsEnabled Enable rating agency integration
     * @param _vintageTrackingEnabled Enable vintage lifecycle tracking
     */
    function setFeatureFlags(
        bool _insuranceEnabled,
        bool _ratingsEnabled,
        bool _vintageTrackingEnabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (insuranceEnabled != _insuranceEnabled) {
            insuranceEnabled = _insuranceEnabled;
            emit FeatureFlagUpdated("insurance", _insuranceEnabled);
        }
        if (ratingsEnabled != _ratingsEnabled) {
            ratingsEnabled = _ratingsEnabled;
            emit FeatureFlagUpdated("ratings", _ratingsEnabled);
        }
        if (vintageTrackingEnabled != _vintageTrackingEnabled) {
            vintageTrackingEnabled = _vintageTrackingEnabled;
            emit FeatureFlagUpdated("vintageTracking", _vintageTrackingEnabled);
        }
    }

    /**
     * @dev Enable insurance feature
     */
    function enableInsurance() external onlyRole(DEFAULT_ADMIN_ROLE) {
        insuranceEnabled = true;
        emit FeatureFlagUpdated("insurance", true);
    }

    /**
     * @dev Disable insurance feature
     */
    function disableInsurance() external onlyRole(DEFAULT_ADMIN_ROLE) {
        insuranceEnabled = false;
        emit FeatureFlagUpdated("insurance", false);
    }

    /**
     * @dev Enable ratings feature
     */
    function enableRatings() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ratingsEnabled = true;
        emit FeatureFlagUpdated("ratings", true);
    }

    /**
     * @dev Disable ratings feature
     */
    function disableRatings() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ratingsEnabled = false;
        emit FeatureFlagUpdated("ratings", false);
    }

    // ============ Vintage and Verification Query Functions ============

    /**
     * @dev Get effective value of credits after vintage discount
     */
    function getEffectiveValue(uint256 tokenId, uint256 baseValue)
        external
        view
        returns (uint256)
    {
        if (vintageTracker == address(0)) return baseValue;

        bytes32 creditId = tokenToCreditId[tokenId];
        if (creditId == bytes32(0)) return baseValue;

        return IVintageTracker(vintageTracker).getEffectiveValue(creditId, baseValue);
    }

    /**
     * @dev Check if a credit is verified
     */
    function isCreditVerified(uint256 tokenId) external view returns (bool) {
        if (verificationRegistry == address(0)) return true;

        bytes32 creditId = tokenToCreditId[tokenId];
        if (creditId == bytes32(0)) return false;

        return IVerificationRegistry(verificationRegistry).isCreditVerified(creditId);
    }

    /**
     * @dev Check if a credit is transferable (considering vintage cooling-off)
     */
    function isCreditTransferable(uint256 tokenId) external view returns (bool) {
        if (vintageTracker == address(0)) return true;

        bytes32 creditId = tokenToCreditId[tokenId];
        if (creditId == bytes32(0)) return true;

        return IVintageTracker(vintageTracker).isTransferable(creditId);
    }

    /**
     * @dev Get oracle data for a feed
     */
    function getOracleData(bytes32 feedId)
        external
        view
        returns (int256 value, uint256 timestamp, uint256 quality)
    {
        require(oracleAggregator != address(0), "Oracle aggregator not set");
        return IOracleAggregator(oracleAggregator).getLatestValue(feedId);
    }

    // ============ URI Functions ============

    function setURI(string memory newuri) external onlyRole(URI_SETTER_ROLE) {
        _baseURI = newuri;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        require(_creditMetadata[tokenId].exists, "URI query for nonexistent token");
        return string(abi.encodePacked(_baseURI, tokenId.toString()));
    }

    // ============ Pause Functions ============

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============ Required Overrides ============

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Supply) whenNotPaused {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        // Check transfer restrictions for each token
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            bytes32 creditId = tokenToCreditId[tokenId];

            // Skip checks for mints (from == 0) and burns (to == 0)
            if (from != address(0) && to != address(0)) {
                // Check vintage tracker transferability if enabled
                if (vintageTrackingEnabled && vintageTracker != address(0) && creditId != bytes32(0)) {
                    bool isTransferable = IVintageTracker(vintageTracker).isTransferable(creditId);
                    if (!isTransferable) {
                        emit TransferRestricted(tokenId, from, to, "Lifecycle restriction");
                        revert("Transfer restricted by vintage tracker");
                    }
                }

                // Check verification requirement for transfer
                if (requireVerificationForTransfer && verificationRegistry != address(0) && creditId != bytes32(0)) {
                    bool isVerified = IVerificationRegistry(verificationRegistry).isCreditVerified(creditId);
                    if (!isVerified) {
                        emit TransferRestricted(tokenId, from, to, "Credit not verified");
                        revert("Transfer requires verified credit");
                    }
                }
            }
        }
    }

    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);

        // Record transfers in integrated systems
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            bytes32 creditId = tokenToCreditId[tokenId];

            // Skip for mints and burns
            if (from != address(0) && to != address(0) && creditId != bytes32(0)) {
                // Record transfer in vintage tracker if enabled
                if (vintageTrackingEnabled && vintageTracker != address(0)) {
                    try IVintageTracker(vintageTracker).recordTransfer(
                        creditId,
                        from,
                        to,
                        bytes32(uint256(uint160(address(this))))
                    ) {} catch {}
                }

                // Record custody transfer in verification registry
                if (verificationRegistry != address(0)) {
                    try IVerificationRegistry(verificationRegistry).recordCustodyTransfer(
                        creditId,
                        from,
                        to,
                        bytes32(uint256(uint160(address(this)))),
                        "transfer"
                    ) {} catch {}
                }
            }
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Supply, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

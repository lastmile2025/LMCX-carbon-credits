// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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
 */
contract LMCXCarbonCredit is ERC1155, ERC1155Burnable, ERC1155Supply, AccessControl, Pausable {
    using Strings for uint256;

    // ============ Roles ============
    bytes32 public constant COMPLIANCE_MANAGER_ROLE = keccak256("COMPLIANCE_MANAGER_ROLE");
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 public constant RATING_AGENCY_ROLE = keccak256("RATING_AGENCY_ROLE");
    bytes32 public constant DMRV_ORACLE_ROLE = keccak256("DMRV_ORACLE_ROLE");
    bytes32 public constant INSURANCE_MANAGER_ROLE = keccak256("INSURANCE_MANAGER_ROLE");

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
        require(to != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(bytes(verificationHash).length > 0, "Verification hash required");

        tokenId = generateTokenId(projectId, vintageYear);
        
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

            emit CreditTypeCreated(tokenId, projectId, vintageYear, methodology);
        }

        mintId = nextMintId++;

        _mintRecords[mintId] = MintRecord({
            tokenId: tokenId,
            beneficiary: to,
            amount: amount,
            mintedAt: block.timestamp,
            verificationHash: verificationHash,
            dmrvReportId: bytes32(0)
        });

        _mint(to, tokenId, amount, "");

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

        _burn(msg.sender, tokenId, amount);

        emit CreditRetired(tokenId, msg.sender, amount, retirementReason, beneficiaryName);
    }

    // ============ Insurance Integration ============

    /**
     * @dev Update insurance status for a token (called by InsuranceManager)
     */
    function updateInsuranceStatus(
        uint256 tokenId,
        bool isInsurable,
        uint256 maxCoverage,
        uint256 riskScore
    ) external onlyRole(INSURANCE_MANAGER_ROLE) {
        require(_tokenIdExists[tokenId], "Token does not exist");
        
        insuranceStatus[tokenId] = InsuranceStatus({
            isInsurable: isInsurable,
            maxCoverage: maxCoverage,
            riskScore: riskScore,
            lastRiskUpdate: block.timestamp
        });

        emit InsuranceStatusUpdated(tokenId, isInsurable, maxCoverage, riskScore);
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
     */
    function updateRating(
        uint256 tokenId,
        uint256 aggregatedScore,
        string memory grade,
        uint256 ratingCount
    ) external onlyRole(RATING_AGENCY_ROLE) {
        require(_tokenIdExists[tokenId], "Token does not exist");
        
        ratingInfo[tokenId] = RatingInfo({
            aggregatedScore: aggregatedScore,
            grade: grade,
            lastRatingUpdate: block.timestamp,
            ratingCount: ratingCount
        });

        // Also update insurance risk score (inverse relationship)
        insuranceStatus[tokenId].riskScore = 10000 - aggregatedScore;
        insuranceStatus[tokenId].lastRiskUpdate = block.timestamp;

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
            uint256 totalSupply
        ) 
    {
        require(_tokenIdExists[tokenId], "Token does not exist");
        
        metadata = _creditMetadata[tokenId];
        insurance = insuranceStatus[tokenId];
        rating = ratingInfo[tokenId];
        dmrv = dmrvStatus[tokenId];
        smart = smartCompliance[tokenId];
        totalSupply = totalSupply(tokenId);
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

    function getAllTokenIds() external view returns (uint256[] memory) {
        return _allTokenIds;
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

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

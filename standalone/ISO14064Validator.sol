// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ISO14064Validator
 * @dev Comprehensive validator for ISO 14064-2 and ISO 14064-3 compliance.
 *
 * ISO 14064-2: Specification for quantification, monitoring and reporting of
 *              GHG emission reductions or removal enhancements at the project level.
 *
 * ISO 14064-3: Specification for the verification and validation of GHG statements.
 *
 * This contract ensures projects meet rigorous international standards for:
 * - Baseline scenario establishment
 * - Additionality demonstration
 * - Quantification of emission reductions/removals
 * - Leakage assessment
 * - Uncertainty analysis
 * - Monitoring plan requirements
 * - Verification body accreditation
 */
contract ISO14064Validator is AccessControl, ReentrancyGuard {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // ============ ISO 14064-2 Project Categories ============
    enum ProjectCategory {
        AGRICULTURE,                    // Agricultural practices
        FORESTRY_LAND_USE,             // AFOLU projects
        WASTE_HANDLING,                // Landfill, composting, etc.
        ENERGY_EFFICIENCY,             // Industrial/building efficiency
        RENEWABLE_ENERGY,              // Solar, wind, hydro, etc.
        INDUSTRIAL_PROCESSES,          // Process emissions reduction
        FUGITIVE_EMISSIONS,            // Oil & gas methane capture
        CARBON_CAPTURE_STORAGE         // CCS/CCUS projects
    }

    // ============ Additionality Test Types ============
    enum AdditionalityTest {
        REGULATORY_SURPLUS,            // Beyond regulatory requirements
        INVESTMENT_BARRIER,            // Not economically viable without credits
        TECHNOLOGY_BARRIER,            // First-of-kind technology
        INSTITUTIONAL_BARRIER,         // Organizational/cultural barriers
        COMMON_PRACTICE               // Not common practice in region
    }

    // ============ Verification Levels per ISO 14064-3 ============
    enum AssuranceLevel {
        LIMITED,                       // Limited assurance engagement
        REASONABLE                     // Reasonable assurance (higher rigor)
    }

    // ============ Materiality Thresholds ============
    struct MaterialityThreshold {
        uint256 percentageThreshold;   // Basis points (e.g., 500 = 5%)
        uint256 absoluteThreshold;     // Tonnes CO2e (scaled by 1e6)
        bool usePercentage;
        bool useAbsolute;
    }

    // ============ Baseline Scenario (ISO 14064-2 Section 5.4) ============
    struct BaselineScenario {
        bytes32 scenarioId;
        string description;
        uint256 baselineEmissions;     // tCO2e/year (scaled by 1e6)
        uint256 baselineStartDate;
        uint256 baselineEndDate;
        string methodologyReference;   // e.g., "CDM ACM0001 v18"
        string dataSourcesHash;        // IPFS hash of supporting data
        bool isApproved;
        address approvedBy;
        uint256 approvedAt;
    }

    // ============ Additionality Assessment (ISO 14064-2 Section 5.3) ============
    struct AdditionalityAssessment {
        AdditionalityTest[] testsApplied;
        bool regulatorySurplusDemo;
        bool investmentAnalysisDemo;
        bool barrierAnalysisDemo;
        bool commonPracticeDemo;
        string evidenceHash;           // IPFS hash of additionality documentation
        bool isPassed;
        address assessedBy;
        uint256 assessedAt;
    }

    // ============ Emission Quantification (ISO 14064-2 Section 5.5) ============
    struct EmissionQuantification {
        uint256 grossReductions;       // Total reductions (scaled by 1e6)
        uint256 projectEmissions;      // Direct project emissions (scaled by 1e6)
        uint256 leakageEmissions;      // Leakage emissions (scaled by 1e6)
        uint256 netReductions;         // Net = Gross - Project - Leakage (scaled by 1e6)
        uint256 uncertaintyPercent;    // Uncertainty as basis points (e.g., 1000 = 10%)
        string calculationMethodHash;  // IPFS hash of calculation methodology
        bool isQuantified;
    }

    // ============ Leakage Assessment (ISO 14064-2 Section 5.6) ============
    struct LeakageAssessment {
        bool hasUpstreamLeakage;
        bool hasDownstreamLeakage;
        bool hasMarketLeakage;
        uint256 estimatedLeakage;      // tCO2e (scaled by 1e6)
        string leakageSourcesHash;     // IPFS documentation
        bool isMitigated;
        string mitigationMeasures;
    }

    // ============ Monitoring Plan (ISO 14064-2 Section 5.7) ============
    struct MonitoringPlan {
        bytes32 planId;
        string[] monitoringParameters;
        uint256 monitoringFrequency;   // Days between measurements
        string qaqcProceduresHash;     // Quality assurance procedures
        string dataManagementHash;     // Data management plan
        bool isImplemented;
        uint256 lastMonitoringDate;
        uint256 nextMonitoringDue;
    }

    // ============ Verification Record (ISO 14064-3) ============
    struct VerificationRecord {
        bytes32 verificationId;
        address verificationBody;
        string verificationBodyName;
        string accreditationId;        // e.g., ANAB, UKAS accreditation number
        string accreditationBody;      // e.g., "ANAB", "UKAS", "JAS-ANZ"
        AssuranceLevel assuranceLevel;
        uint256 verificationDate;
        uint256 validUntil;
        string scopeOfVerification;
        string verificationStatementHash; // IPFS hash of verification statement
        string findingsHash;           // IPFS hash of verification findings
        bool hasMaterialFindings;
        bool isValid;
    }

    // ============ Complete ISO 14064 Project Status ============
    struct ISO14064Status {
        bytes32 projectId;
        ProjectCategory category;

        // ISO 14064-2 Components
        bool hasApprovedBaseline;
        bool passedAdditionality;
        bool isQuantified;
        bool hasMonitoringPlan;
        bool leakageAssessed;

        // ISO 14064-3 Verification
        bool isVerified;
        bytes32 currentVerificationId;
        AssuranceLevel assuranceLevel;

        // Overall Status
        bool isFullyCompliant;
        uint256 lastUpdated;
        uint256 complianceScore;       // 0-10000 scale
    }

    // ============ Storage ============
    mapping(bytes32 => ISO14064Status) private _projectStatus;
    mapping(bytes32 => BaselineScenario) private _baselines;
    mapping(bytes32 => AdditionalityAssessment) private _additionality;
    mapping(bytes32 => EmissionQuantification) private _quantification;
    mapping(bytes32 => LeakageAssessment) private _leakage;
    mapping(bytes32 => MonitoringPlan) private _monitoring;
    mapping(bytes32 => VerificationRecord) private _verifications;
    mapping(bytes32 => bytes32[]) private _projectVerificationHistory;

    // Accredited verification bodies
    mapping(address => bool) public accreditedVerifiers;
    mapping(address => string) public verifierAccreditationIds;

    MaterialityThreshold public materialityThreshold;

    // ============ Events ============
    event ProjectRegistered(
        bytes32 indexed projectId,
        ProjectCategory category,
        address indexed registeredBy
    );

    event BaselineApproved(
        bytes32 indexed projectId,
        bytes32 indexed scenarioId,
        uint256 baselineEmissions,
        address indexed approvedBy
    );

    event AdditionalityAssessed(
        bytes32 indexed projectId,
        bool passed,
        address indexed assessedBy
    );

    event EmissionsQuantified(
        bytes32 indexed projectId,
        uint256 grossReductions,
        uint256 netReductions,
        uint256 uncertaintyPercent
    );

    event LeakageAssessed(
        bytes32 indexed projectId,
        uint256 estimatedLeakage,
        bool isMitigated
    );

    event MonitoringPlanApproved(
        bytes32 indexed projectId,
        bytes32 indexed planId,
        uint256 frequency
    );

    event ProjectVerified(
        bytes32 indexed projectId,
        bytes32 indexed verificationId,
        address indexed verificationBody,
        AssuranceLevel assuranceLevel
    );

    event VerificationRevoked(
        bytes32 indexed projectId,
        bytes32 indexed verificationId,
        string reason
    );

    event VerifierAccredited(
        address indexed verifier,
        string accreditationId
    );

    event ComplianceScoreUpdated(
        bytes32 indexed projectId,
        uint256 newScore,
        bool isFullyCompliant
    );

    // ============ Constructor ============
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
        _grantRole(AUDITOR_ROLE, msg.sender);

        // Default materiality threshold: 5% or 10,000 tCO2e
        materialityThreshold = MaterialityThreshold({
            percentageThreshold: 500,      // 5%
            absoluteThreshold: 10000 * 1e6, // 10,000 tonnes
            usePercentage: true,
            useAbsolute: true
        });
    }

    // ============ Verification Body Management ============

    /**
     * @dev Register an accredited verification body (ISO 14065 accredited)
     */
    function accreditVerifier(
        address verifier,
        string calldata accreditationId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(verifier != address(0), "Invalid verifier address");
        require(bytes(accreditationId).length > 0, "Accreditation ID required");

        accreditedVerifiers[verifier] = true;
        verifierAccreditationIds[verifier] = accreditationId;
        _grantRole(VERIFIER_ROLE, verifier);

        emit VerifierAccredited(verifier, accreditationId);
    }

    /**
     * @dev Revoke verification body accreditation
     */
    function revokeVerifierAccreditation(address verifier)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        accreditedVerifiers[verifier] = false;
        _revokeRole(VERIFIER_ROLE, verifier);
    }

    // ============ Project Registration ============

    /**
     * @dev Register a new project for ISO 14064 compliance tracking
     */
    function registerProject(
        bytes32 projectId,
        ProjectCategory category
    ) external onlyRole(VALIDATOR_ROLE) {
        require(projectId != bytes32(0), "Invalid projectId");
        require(!_projectStatus[projectId].isFullyCompliant, "Project exists");

        _projectStatus[projectId] = ISO14064Status({
            projectId: projectId,
            category: category,
            hasApprovedBaseline: false,
            passedAdditionality: false,
            isQuantified: false,
            hasMonitoringPlan: false,
            leakageAssessed: false,
            isVerified: false,
            currentVerificationId: bytes32(0),
            assuranceLevel: AssuranceLevel.LIMITED,
            isFullyCompliant: false,
            lastUpdated: block.timestamp,
            complianceScore: 0
        });

        emit ProjectRegistered(projectId, category, msg.sender);
    }

    // ============ ISO 14064-2 Section 5.4: Baseline Scenario ============

    /**
     * @dev Approve baseline scenario for a project
     */
    function approveBaseline(
        bytes32 projectId,
        bytes32 scenarioId,
        string calldata description,
        uint256 baselineEmissions,
        uint256 baselineStartDate,
        uint256 baselineEndDate,
        string calldata methodologyReference,
        string calldata dataSourcesHash
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].projectId != bytes32(0), "Project not registered");
        require(baselineEmissions > 0, "Baseline emissions required");
        require(baselineEndDate > baselineStartDate, "Invalid date range");
        require(bytes(methodologyReference).length > 0, "Methodology required");

        _baselines[projectId] = BaselineScenario({
            scenarioId: scenarioId,
            description: description,
            baselineEmissions: baselineEmissions,
            baselineStartDate: baselineStartDate,
            baselineEndDate: baselineEndDate,
            methodologyReference: methodologyReference,
            dataSourcesHash: dataSourcesHash,
            isApproved: true,
            approvedBy: msg.sender,
            approvedAt: block.timestamp
        });

        _projectStatus[projectId].hasApprovedBaseline = true;
        _updateComplianceScore(projectId);

        emit BaselineApproved(projectId, scenarioId, baselineEmissions, msg.sender);
    }

    // ============ ISO 14064-2 Section 5.3: Additionality ============

    /**
     * @dev Record additionality assessment results
     */
    function recordAdditionalityAssessment(
        bytes32 projectId,
        bool regulatorySurplus,
        bool investmentAnalysis,
        bool barrierAnalysis,
        bool commonPractice,
        string calldata evidenceHash
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].projectId != bytes32(0), "Project not registered");

        // Additionality requires at least regulatory surplus + one other test
        bool passed = regulatorySurplus && (investmentAnalysis || barrierAnalysis || commonPractice);

        AdditionalityTest[] memory tests = new AdditionalityTest[](4);
        uint256 testCount = 0;

        if (regulatorySurplus) tests[testCount++] = AdditionalityTest.REGULATORY_SURPLUS;
        if (investmentAnalysis) tests[testCount++] = AdditionalityTest.INVESTMENT_BARRIER;
        if (barrierAnalysis) tests[testCount++] = AdditionalityTest.TECHNOLOGY_BARRIER;
        if (commonPractice) tests[testCount++] = AdditionalityTest.COMMON_PRACTICE;

        _additionality[projectId] = AdditionalityAssessment({
            testsApplied: tests,
            regulatorySurplusDemo: regulatorySurplus,
            investmentAnalysisDemo: investmentAnalysis,
            barrierAnalysisDemo: barrierAnalysis,
            commonPracticeDemo: commonPractice,
            evidenceHash: evidenceHash,
            isPassed: passed,
            assessedBy: msg.sender,
            assessedAt: block.timestamp
        });

        _projectStatus[projectId].passedAdditionality = passed;
        _updateComplianceScore(projectId);

        emit AdditionalityAssessed(projectId, passed, msg.sender);
    }

    // ============ ISO 14064-2 Section 5.5: Quantification ============

    /**
     * @dev Record emission reduction quantification
     */
    function recordQuantification(
        bytes32 projectId,
        uint256 grossReductions,
        uint256 projectEmissions,
        uint256 leakageEmissions,
        uint256 uncertaintyPercent,
        string calldata calculationMethodHash
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].projectId != bytes32(0), "Project not registered");
        require(grossReductions >= projectEmissions + leakageEmissions, "Invalid reduction calc");
        require(uncertaintyPercent <= 5000, "Uncertainty too high (>50%)");

        uint256 netReductions = grossReductions - projectEmissions - leakageEmissions;

        _quantification[projectId] = EmissionQuantification({
            grossReductions: grossReductions,
            projectEmissions: projectEmissions,
            leakageEmissions: leakageEmissions,
            netReductions: netReductions,
            uncertaintyPercent: uncertaintyPercent,
            calculationMethodHash: calculationMethodHash,
            isQuantified: true
        });

        _projectStatus[projectId].isQuantified = true;
        _updateComplianceScore(projectId);

        emit EmissionsQuantified(projectId, grossReductions, netReductions, uncertaintyPercent);
    }

    // ============ ISO 14064-2 Section 5.6: Leakage ============

    /**
     * @dev Record leakage assessment
     */
    function recordLeakageAssessment(
        bytes32 projectId,
        bool hasUpstreamLeakage,
        bool hasDownstreamLeakage,
        bool hasMarketLeakage,
        uint256 estimatedLeakage,
        string calldata leakageSourcesHash,
        bool isMitigated,
        string calldata mitigationMeasures
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].projectId != bytes32(0), "Project not registered");

        _leakage[projectId] = LeakageAssessment({
            hasUpstreamLeakage: hasUpstreamLeakage,
            hasDownstreamLeakage: hasDownstreamLeakage,
            hasMarketLeakage: hasMarketLeakage,
            estimatedLeakage: estimatedLeakage,
            leakageSourcesHash: leakageSourcesHash,
            isMitigated: isMitigated,
            mitigationMeasures: mitigationMeasures
        });

        _projectStatus[projectId].leakageAssessed = true;
        _updateComplianceScore(projectId);

        emit LeakageAssessed(projectId, estimatedLeakage, isMitigated);
    }

    // ============ ISO 14064-2 Section 5.7: Monitoring Plan ============

    /**
     * @dev Approve monitoring plan
     */
    function approveMonitoringPlan(
        bytes32 projectId,
        bytes32 planId,
        string[] calldata monitoringParameters,
        uint256 monitoringFrequencyDays,
        string calldata qaqcProceduresHash,
        string calldata dataManagementHash
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].projectId != bytes32(0), "Project not registered");
        require(monitoringParameters.length > 0, "Parameters required");
        require(monitoringFrequencyDays > 0 && monitoringFrequencyDays <= 365, "Invalid frequency");

        _monitoring[projectId] = MonitoringPlan({
            planId: planId,
            monitoringParameters: monitoringParameters,
            monitoringFrequency: monitoringFrequencyDays,
            qaqcProceduresHash: qaqcProceduresHash,
            dataManagementHash: dataManagementHash,
            isImplemented: true,
            lastMonitoringDate: block.timestamp,
            nextMonitoringDue: block.timestamp + (monitoringFrequencyDays * 1 days)
        });

        _projectStatus[projectId].hasMonitoringPlan = true;
        _updateComplianceScore(projectId);

        emit MonitoringPlanApproved(projectId, planId, monitoringFrequencyDays);
    }

    /**
     * @dev Update monitoring timestamp
     */
    function recordMonitoringEvent(bytes32 projectId) external onlyRole(VALIDATOR_ROLE) {
        require(_monitoring[projectId].isImplemented, "No monitoring plan");

        _monitoring[projectId].lastMonitoringDate = block.timestamp;
        _monitoring[projectId].nextMonitoringDue =
            block.timestamp + (_monitoring[projectId].monitoringFrequency * 1 days);
    }

    // ============ ISO 14064-3: Verification ============

    /**
     * @dev Record project verification by accredited body
     */
    function verifyProject(
        bytes32 projectId,
        bytes32 verificationId,
        string calldata verificationBodyName,
        AssuranceLevel assuranceLevel,
        uint256 validityDays,
        string calldata scopeOfVerification,
        string calldata verificationStatementHash,
        string calldata findingsHash,
        bool hasMaterialFindings
    ) external onlyRole(VERIFIER_ROLE) {
        require(_projectStatus[projectId].projectId != bytes32(0), "Project not registered");
        require(accreditedVerifiers[msg.sender], "Not accredited verifier");
        require(!hasMaterialFindings, "Cannot verify with material findings");
        require(validityDays > 0 && validityDays <= 1095, "Invalid validity (max 3 years)");

        // All ISO 14064-2 components must be complete before verification
        ISO14064Status storage status = _projectStatus[projectId];
        require(status.hasApprovedBaseline, "Baseline not approved");
        require(status.passedAdditionality, "Additionality not passed");
        require(status.isQuantified, "Not quantified");
        require(status.hasMonitoringPlan, "No monitoring plan");
        require(status.leakageAssessed, "Leakage not assessed");

        _verifications[verificationId] = VerificationRecord({
            verificationId: verificationId,
            verificationBody: msg.sender,
            verificationBodyName: verificationBodyName,
            accreditationId: verifierAccreditationIds[msg.sender],
            accreditationBody: "",
            assuranceLevel: assuranceLevel,
            verificationDate: block.timestamp,
            validUntil: block.timestamp + (validityDays * 1 days),
            scopeOfVerification: scopeOfVerification,
            verificationStatementHash: verificationStatementHash,
            findingsHash: findingsHash,
            hasMaterialFindings: hasMaterialFindings,
            isValid: true
        });

        _projectVerificationHistory[projectId].push(verificationId);

        status.isVerified = true;
        status.currentVerificationId = verificationId;
        status.assuranceLevel = assuranceLevel;
        _updateComplianceScore(projectId);

        emit ProjectVerified(projectId, verificationId, msg.sender, assuranceLevel);
    }

    /**
     * @dev Revoke verification
     */
    function revokeVerification(
        bytes32 projectId,
        bytes32 verificationId,
        string calldata reason
    ) external onlyRole(AUDITOR_ROLE) {
        require(_verifications[verificationId].isValid, "Not valid verification");

        _verifications[verificationId].isValid = false;

        if (_projectStatus[projectId].currentVerificationId == verificationId) {
            _projectStatus[projectId].isVerified = false;
            _projectStatus[projectId].currentVerificationId = bytes32(0);
            _updateComplianceScore(projectId);
        }

        emit VerificationRevoked(projectId, verificationId, reason);
    }

    // ============ Compliance Score Calculation ============

    function _updateComplianceScore(bytes32 projectId) internal {
        ISO14064Status storage status = _projectStatus[projectId];
        uint256 score = 0;

        // ISO 14064-2 components (60% of score)
        if (status.hasApprovedBaseline) score += 1200;      // 12%
        if (status.passedAdditionality) score += 1200;      // 12%
        if (status.isQuantified) score += 1200;             // 12%
        if (status.hasMonitoringPlan) score += 1200;        // 12%
        if (status.leakageAssessed) score += 1200;          // 12%

        // ISO 14064-3 verification (40% of score)
        if (status.isVerified) {
            VerificationRecord storage v = _verifications[status.currentVerificationId];
            if (v.isValid && block.timestamp <= v.validUntil) {
                if (v.assuranceLevel == AssuranceLevel.REASONABLE) {
                    score += 4000;  // 40% for reasonable assurance
                } else {
                    score += 2500;  // 25% for limited assurance
                }
            }
        }

        status.complianceScore = score;
        status.isFullyCompliant = (score >= 9000);  // 90% threshold
        status.lastUpdated = block.timestamp;

        emit ComplianceScoreUpdated(projectId, score, status.isFullyCompliant);
    }

    // ============ View Functions ============

    /**
     * @dev Check if project is verified (main interface for ComplianceManager)
     */
    function isProjectVerified(bytes32 projectId) external view returns (bool) {
        ISO14064Status storage status = _projectStatus[projectId];
        if (!status.isVerified) return false;

        VerificationRecord storage v = _verifications[status.currentVerificationId];
        return v.isValid && block.timestamp <= v.validUntil;
    }

    /**
     * @dev Check if project is fully ISO 14064-2/3 compliant
     */
    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return _projectStatus[projectId].isFullyCompliant;
    }

    /**
     * @dev Get full project status
     */
    function getProjectStatus(bytes32 projectId)
        external
        view
        returns (ISO14064Status memory)
    {
        return _projectStatus[projectId];
    }

    /**
     * @dev Get baseline scenario
     */
    function getBaseline(bytes32 projectId)
        external
        view
        returns (BaselineScenario memory)
    {
        return _baselines[projectId];
    }

    /**
     * @dev Get additionality assessment
     */
    function getAdditionality(bytes32 projectId)
        external
        view
        returns (
            bool regulatorySurplus,
            bool investmentAnalysis,
            bool barrierAnalysis,
            bool commonPractice,
            bool passed
        )
    {
        AdditionalityAssessment storage a = _additionality[projectId];
        return (
            a.regulatorySurplusDemo,
            a.investmentAnalysisDemo,
            a.barrierAnalysisDemo,
            a.commonPracticeDemo,
            a.isPassed
        );
    }

    /**
     * @dev Get emission quantification
     */
    function getQuantification(bytes32 projectId)
        external
        view
        returns (EmissionQuantification memory)
    {
        return _quantification[projectId];
    }

    /**
     * @dev Get leakage assessment
     */
    function getLeakage(bytes32 projectId)
        external
        view
        returns (LeakageAssessment memory)
    {
        return _leakage[projectId];
    }

    /**
     * @dev Get monitoring plan
     */
    function getMonitoringPlan(bytes32 projectId)
        external
        view
        returns (MonitoringPlan memory)
    {
        return _monitoring[projectId];
    }

    /**
     * @dev Get current verification record
     */
    function getCurrentVerification(bytes32 projectId)
        external
        view
        returns (VerificationRecord memory)
    {
        bytes32 vId = _projectStatus[projectId].currentVerificationId;
        return _verifications[vId];
    }

    /**
     * @dev Get verification history
     */
    function getVerificationHistory(bytes32 projectId)
        external
        view
        returns (bytes32[] memory)
    {
        return _projectVerificationHistory[projectId];
    }

    /**
     * @dev Get net emission reductions with uncertainty bounds
     */
    function getNetReductionsWithUncertainty(bytes32 projectId)
        external
        view
        returns (
            uint256 netReductions,
            uint256 lowerBound,
            uint256 upperBound,
            uint256 uncertaintyPercent
        )
    {
        EmissionQuantification storage q = _quantification[projectId];
        if (!q.isQuantified) return (0, 0, 0, 0);

        netReductions = q.netReductions;
        uncertaintyPercent = q.uncertaintyPercent;

        // Calculate confidence interval
        uint256 uncertainty = (netReductions * uncertaintyPercent) / 10000;
        lowerBound = netReductions > uncertainty ? netReductions - uncertainty : 0;
        upperBound = netReductions + uncertainty;
    }

    /**
     * @dev Check if monitoring is current
     */
    function isMonitoringCurrent(bytes32 projectId) external view returns (bool) {
        MonitoringPlan storage m = _monitoring[projectId];
        if (!m.isImplemented) return false;
        return block.timestamp <= m.nextMonitoringDue;
    }

    /**
     * @dev Get compliance score (0-10000)
     */
    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return _projectStatus[projectId].complianceScore;
    }

    // ============ Admin Functions ============

    /**
     * @dev Update materiality threshold
     */
    function setMaterialityThreshold(
        uint256 percentageThreshold,
        uint256 absoluteThreshold,
        bool usePercentage,
        bool useAbsolute
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(percentageThreshold <= 1000, "Max 10%");
        require(usePercentage || useAbsolute, "At least one threshold required");

        materialityThreshold = MaterialityThreshold({
            percentageThreshold: percentageThreshold,
            absoluteThreshold: absoluteThreshold,
            usePercentage: usePercentage,
            useAbsolute: useAbsolute
        });
    }
}

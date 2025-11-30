// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title OGMP2Validator
 * @dev Comprehensive OGMP 2.0 (Oil and Gas Methane Partnership) compliance validator.
 *
 * OGMP 2.0 Framework Levels:
 * - Level 1: Company-wide emission factors (lowest accuracy)
 * - Level 2: Asset-type emission factors
 * - Level 3: Generic equipment-level emission factors
 * - Level 4: Site-specific measurements + reconciliation
 * - Level 5: Continuous measurement + full reconciliation (highest accuracy)
 *
 * The framework requires:
 * - Annual reporting of methane emissions
 * - Progressive improvement toward Level 4/5
 * - Reconciliation between bottom-up and top-down measurements
 * - Specific coverage of operated and non-operated assets
 *
 * Reference: https://ogmpartnership.com/
 */
contract OGMP2Validator is AccessControl, ReentrancyGuard {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // ============ OGMP 2.0 Reporting Levels ============
    enum ReportingLevel {
        LEVEL_1,    // Company-wide emission factors
        LEVEL_2,    // Asset-type emission factors
        LEVEL_3,    // Generic equipment-level factors
        LEVEL_4,    // Site-specific measurements
        LEVEL_5     // Continuous measurement + reconciliation
    }

    // ============ Asset Segment Types (per OGMP 2.0) ============
    enum AssetSegment {
        UPSTREAM_ONSHORE,           // Onshore oil & gas production
        UPSTREAM_OFFSHORE,          // Offshore platforms
        MIDSTREAM,                  // Processing & fractionation
        LNG,                        // LNG liquefaction/regasification
        TRANSMISSION,               // Gas transmission pipelines
        STORAGE,                    // Underground storage
        DISTRIBUTION                // Gas distribution networks
    }

    // ============ Emission Source Categories ============
    enum SourceCategory {
        FUGITIVE_LEAKS,             // Equipment leaks (valves, flanges, etc.)
        VENTING,                    // Intentional venting
        FLARING,                    // Flare incomplete combustion
        COMBUSTION,                 // Engine/turbine methane slip
        PROCESS,                    // Process emissions
        OTHER                       // Other sources
    }

    // ============ Measurement Method ============
    enum MeasurementMethod {
        EMISSION_FACTOR,            // Using emission factors
        ENGINEERING_CALCULATION,    // Engineering estimates
        DIRECT_MEASUREMENT,         // OGI, Hi-Flow, etc.
        CONTINUOUS_MONITORING,      // CEMS, satellite, etc.
        TOP_DOWN_RECONCILED         // Reconciled with aerial/satellite
    }

    // ============ OGMP 2.0 Gold Standard Requirements ============
    struct GoldStandardCriteria {
        bool hasLevel4ByDeadline;           // Level 4 by 2025 for operated
        bool hasLevel5Target;               // Targeting Level 5 by 2025
        bool implementsReconciliation;      // Bottom-up vs top-down
        bool reportsNonOperated;            // Reports non-operated JV assets
        bool annualPublicReporting;         // Public emissions disclosure
        bool hasReductionTarget;            // Committed reduction target
        uint256 targetReductionPercent;     // e.g., 4500 = 45% reduction
        uint256 targetYear;
    }

    // ============ Asset-Level Compliance ============
    struct AssetCompliance {
        bytes32 assetId;
        bytes32 projectId;
        AssetSegment segment;
        ReportingLevel currentLevel;
        ReportingLevel targetLevel;
        uint256 targetLevelDeadline;
        bool isOperated;
        uint256 operatedShare;              // Basis points (10000 = 100%)
        uint256 lastReportDate;
        bool isActive;
    }

    // ============ Emission Report Structure ============
    struct EmissionReport {
        bytes32 reportId;
        bytes32 projectId;
        uint256 reportingYear;
        uint256 totalMethaneEmissions;      // Tonnes CH4 (scaled by 1e6)
        uint256 totalCO2eEmissions;         // Tonnes CO2e (scaled by 1e6, GWP=28)
        uint256 methaneIntensity;           // kg CH4 / BOE (scaled by 1e6)
        ReportingLevel reportingLevel;
        MeasurementMethod primaryMethod;
        uint256 submittedAt;
        bool isVerified;
        address verifiedBy;
        string reportHash;                  // IPFS hash of full report
    }

    // ============ Source-Level Breakdown ============
    struct SourceBreakdown {
        uint256 fugitiveEmissions;          // Tonnes CH4 (scaled by 1e6)
        uint256 ventingEmissions;
        uint256 flaringEmissions;
        uint256 combustionEmissions;
        uint256 processEmissions;
        uint256 otherEmissions;
    }

    // ============ Reconciliation Record ============
    struct ReconciliationRecord {
        bytes32 recordId;
        bytes32 projectId;
        uint256 reportingYear;
        uint256 bottomUpEstimate;           // Tonnes CH4 (scaled by 1e6)
        uint256 topDownMeasurement;         // From satellite/aerial
        int256 difference;                  // Top-down minus bottom-up
        uint256 differencePercent;          // Basis points
        bool isReconciled;
        string reconciliationNotes;
        string evidenceHash;
    }

    // ============ Complete OGMP 2.0 Status ============
    struct OGMP2Status {
        bytes32 projectId;
        bool isRegistered;
        bool isCompliant;
        ReportingLevel operatedLevel;
        ReportingLevel nonOperatedLevel;
        bool meetsGoldStandard;
        uint256 lastReportYear;
        uint256 lastReconciliationYear;
        uint256 complianceScore;            // 0-10000
        uint256 lastUpdated;
        string evidenceHash;
    }

    // ============ Storage ============
    mapping(bytes32 => OGMP2Status) private _projectStatus;
    mapping(bytes32 => GoldStandardCriteria) private _goldStandard;
    mapping(bytes32 => AssetCompliance[]) private _assets;
    mapping(bytes32 => mapping(uint256 => EmissionReport)) private _reports; // projectId => year => report
    mapping(bytes32 => mapping(uint256 => SourceBreakdown)) private _sourceBreakdowns;
    mapping(bytes32 => mapping(uint256 => ReconciliationRecord)) private _reconciliations;

    // Methane-specific constants
    uint256 public constant METHANE_GWP_100 = 28;  // IPCC AR5 100-year GWP
    uint256 public constant METHANE_GWP_20 = 84;   // IPCC AR5 20-year GWP
    uint256 public constant GOLD_STANDARD_THRESHOLD = 8000; // 80% score required

    // ============ Events ============
    event ProjectRegistered(
        bytes32 indexed projectId,
        address indexed registeredBy
    );

    event AssetAdded(
        bytes32 indexed projectId,
        bytes32 indexed assetId,
        AssetSegment segment,
        ReportingLevel currentLevel
    );

    event EmissionReportSubmitted(
        bytes32 indexed projectId,
        bytes32 indexed reportId,
        uint256 indexed year,
        uint256 totalMethaneEmissions,
        ReportingLevel level
    );

    event ReportVerified(
        bytes32 indexed projectId,
        uint256 indexed year,
        address indexed verifier
    );

    event ReconciliationCompleted(
        bytes32 indexed projectId,
        uint256 indexed year,
        uint256 bottomUp,
        uint256 topDown,
        int256 difference
    );

    event LevelUpgraded(
        bytes32 indexed projectId,
        bytes32 indexed assetId,
        ReportingLevel oldLevel,
        ReportingLevel newLevel
    );

    event GoldStandardAchieved(
        bytes32 indexed projectId,
        uint256 timestamp
    );

    event ComplianceUpdated(
        bytes32 indexed projectId,
        bool isCompliant,
        uint256 score
    );

    // ============ Constructor ============
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
        _grantRole(REPORTER_ROLE, msg.sender);
        _grantRole(AUDITOR_ROLE, msg.sender);
    }

    // ============ Project Registration ============

    /**
     * @dev Register a project for OGMP 2.0 compliance tracking
     */
    function registerProject(
        bytes32 projectId,
        bool hasReductionTarget,
        uint256 targetReductionPercent,
        uint256 targetYear
    ) external onlyRole(VALIDATOR_ROLE) {
        require(projectId != bytes32(0), "Invalid projectId");
        require(!_projectStatus[projectId].isRegistered, "Already registered");

        _projectStatus[projectId] = OGMP2Status({
            projectId: projectId,
            isRegistered: true,
            isCompliant: false,
            operatedLevel: ReportingLevel.LEVEL_1,
            nonOperatedLevel: ReportingLevel.LEVEL_1,
            meetsGoldStandard: false,
            lastReportYear: 0,
            lastReconciliationYear: 0,
            complianceScore: 0,
            lastUpdated: block.timestamp,
            evidenceHash: ""
        });

        _goldStandard[projectId] = GoldStandardCriteria({
            hasLevel4ByDeadline: false,
            hasLevel5Target: false,
            implementsReconciliation: false,
            reportsNonOperated: false,
            annualPublicReporting: false,
            hasReductionTarget: hasReductionTarget,
            targetReductionPercent: targetReductionPercent,
            targetYear: targetYear
        });

        emit ProjectRegistered(projectId, msg.sender);
    }

    // ============ Asset Management ============

    /**
     * @dev Add an asset to a project
     */
    function addAsset(
        bytes32 projectId,
        bytes32 assetId,
        AssetSegment segment,
        ReportingLevel currentLevel,
        ReportingLevel targetLevel,
        uint256 targetLevelDeadline,
        bool isOperated,
        uint256 operatedShare
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Project not registered");
        require(assetId != bytes32(0), "Invalid assetId");
        require(operatedShare <= 10000, "Invalid share (max 100%)");

        _assets[projectId].push(AssetCompliance({
            assetId: assetId,
            projectId: projectId,
            segment: segment,
            currentLevel: currentLevel,
            targetLevel: targetLevel,
            targetLevelDeadline: targetLevelDeadline,
            isOperated: isOperated,
            operatedShare: operatedShare,
            lastReportDate: 0,
            isActive: true
        }));

        emit AssetAdded(projectId, assetId, segment, currentLevel);
    }

    /**
     * @dev Upgrade asset reporting level
     */
    function upgradeAssetLevel(
        bytes32 projectId,
        bytes32 assetId,
        ReportingLevel newLevel,
        string calldata evidenceHash
    ) external onlyRole(VALIDATOR_ROLE) {
        AssetCompliance[] storage assets = _assets[projectId];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].assetId == assetId && assets[i].isActive) {
                ReportingLevel oldLevel = assets[i].currentLevel;
                require(uint8(newLevel) > uint8(oldLevel), "Must upgrade level");
                assets[i].currentLevel = newLevel;
                emit LevelUpgraded(projectId, assetId, oldLevel, newLevel);
                _updateProjectLevel(projectId);
                return;
            }
        }
        revert("Asset not found");
    }

    // ============ Emission Reporting ============

    /**
     * @dev Submit annual emission report
     */
    function submitEmissionReport(
        bytes32 projectId,
        bytes32 reportId,
        uint256 reportingYear,
        uint256 totalMethaneEmissions,
        ReportingLevel reportingLevel,
        MeasurementMethod primaryMethod,
        string calldata reportHash,
        SourceBreakdown calldata breakdown
    ) external onlyRole(REPORTER_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Project not registered");
        require(reportingYear >= 2020 && reportingYear <= 2100, "Invalid year");
        require(totalMethaneEmissions > 0, "Emissions required");

        // Validate source breakdown matches total
        uint256 breakdownTotal = breakdown.fugitiveEmissions +
            breakdown.ventingEmissions +
            breakdown.flaringEmissions +
            breakdown.combustionEmissions +
            breakdown.processEmissions +
            breakdown.otherEmissions;
        require(breakdownTotal == totalMethaneEmissions, "Breakdown mismatch");

        // Calculate CO2e using GWP-100
        uint256 co2eEmissions = totalMethaneEmissions * METHANE_GWP_100;

        _reports[projectId][reportingYear] = EmissionReport({
            reportId: reportId,
            projectId: projectId,
            reportingYear: reportingYear,
            totalMethaneEmissions: totalMethaneEmissions,
            totalCO2eEmissions: co2eEmissions,
            methaneIntensity: 0,  // Set separately with production data
            reportingLevel: reportingLevel,
            primaryMethod: primaryMethod,
            submittedAt: block.timestamp,
            isVerified: false,
            verifiedBy: address(0),
            reportHash: reportHash
        });

        _sourceBreakdowns[projectId][reportingYear] = breakdown;

        _projectStatus[projectId].lastReportYear = reportingYear;
        _goldStandard[projectId].annualPublicReporting = true;

        emit EmissionReportSubmitted(
            projectId,
            reportId,
            reportingYear,
            totalMethaneEmissions,
            reportingLevel
        );

        _updateComplianceScore(projectId);
    }

    /**
     * @dev Set methane intensity (requires production data)
     */
    function setMethaneIntensity(
        bytes32 projectId,
        uint256 year,
        uint256 methaneIntensity
    ) external onlyRole(REPORTER_ROLE) {
        require(_reports[projectId][year].reportId != bytes32(0), "Report not found");
        _reports[projectId][year].methaneIntensity = methaneIntensity;
    }

    /**
     * @dev Verify emission report
     */
    function verifyReport(
        bytes32 projectId,
        uint256 year
    ) external onlyRole(AUDITOR_ROLE) {
        require(_reports[projectId][year].reportId != bytes32(0), "Report not found");
        require(!_reports[projectId][year].isVerified, "Already verified");

        _reports[projectId][year].isVerified = true;
        _reports[projectId][year].verifiedBy = msg.sender;

        emit ReportVerified(projectId, year, msg.sender);
        _updateComplianceScore(projectId);
    }

    // ============ Reconciliation (Key OGMP 2.0 Feature) ============

    /**
     * @dev Submit reconciliation between bottom-up and top-down measurements
     */
    function submitReconciliation(
        bytes32 projectId,
        bytes32 recordId,
        uint256 reportingYear,
        uint256 bottomUpEstimate,
        uint256 topDownMeasurement,
        string calldata reconciliationNotes,
        string calldata evidenceHash
    ) external onlyRole(REPORTER_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Project not registered");
        require(_reports[projectId][reportingYear].reportId != bytes32(0), "No report for year");

        int256 difference = int256(topDownMeasurement) - int256(bottomUpEstimate);
        uint256 absDiff = difference >= 0 ? uint256(difference) : uint256(-difference);
        uint256 diffPercent = bottomUpEstimate > 0
            ? (absDiff * 10000) / bottomUpEstimate
            : 0;

        // Reconciliation considered successful if difference < 20%
        bool isReconciled = diffPercent < 2000;

        _reconciliations[projectId][reportingYear] = ReconciliationRecord({
            recordId: recordId,
            projectId: projectId,
            reportingYear: reportingYear,
            bottomUpEstimate: bottomUpEstimate,
            topDownMeasurement: topDownMeasurement,
            difference: difference,
            differencePercent: diffPercent,
            isReconciled: isReconciled,
            reconciliationNotes: reconciliationNotes,
            evidenceHash: evidenceHash
        });

        _projectStatus[projectId].lastReconciliationYear = reportingYear;
        _goldStandard[projectId].implementsReconciliation = true;

        emit ReconciliationCompleted(
            projectId,
            reportingYear,
            bottomUpEstimate,
            topDownMeasurement,
            difference
        );

        _updateComplianceScore(projectId);
    }

    // ============ Gold Standard Criteria ============

    /**
     * @dev Update Gold Standard criteria status
     */
    function updateGoldStandardCriteria(
        bytes32 projectId,
        bool hasLevel4ByDeadline,
        bool hasLevel5Target,
        bool reportsNonOperated
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Project not registered");

        GoldStandardCriteria storage g = _goldStandard[projectId];
        g.hasLevel4ByDeadline = hasLevel4ByDeadline;
        g.hasLevel5Target = hasLevel5Target;
        g.reportsNonOperated = reportsNonOperated;

        _updateComplianceScore(projectId);
    }

    // ============ Internal Functions ============

    function _updateProjectLevel(bytes32 projectId) internal {
        AssetCompliance[] storage assets = _assets[projectId];
        if (assets.length == 0) return;

        // Find minimum level for operated and non-operated assets
        uint8 minOperatedLevel = 5;
        uint8 minNonOperatedLevel = 5;
        bool hasOperated = false;
        bool hasNonOperated = false;

        for (uint256 i = 0; i < assets.length; i++) {
            if (!assets[i].isActive) continue;

            if (assets[i].isOperated) {
                hasOperated = true;
                if (uint8(assets[i].currentLevel) < minOperatedLevel) {
                    minOperatedLevel = uint8(assets[i].currentLevel);
                }
            } else {
                hasNonOperated = true;
                if (uint8(assets[i].currentLevel) < minNonOperatedLevel) {
                    minNonOperatedLevel = uint8(assets[i].currentLevel);
                }
            }
        }

        OGMP2Status storage status = _projectStatus[projectId];
        if (hasOperated) {
            status.operatedLevel = ReportingLevel(minOperatedLevel);
        }
        if (hasNonOperated) {
            status.nonOperatedLevel = ReportingLevel(minNonOperatedLevel);
            _goldStandard[projectId].reportsNonOperated = true;
        }

        _updateComplianceScore(projectId);
    }

    function _updateComplianceScore(bytes32 projectId) internal {
        OGMP2Status storage status = _projectStatus[projectId];
        GoldStandardCriteria storage g = _goldStandard[projectId];
        uint256 score = 0;

        // Reporting Level Score (40% max)
        // Level 4/5 for operated assets is key requirement
        uint8 opLevel = uint8(status.operatedLevel);
        if (opLevel >= 4) {
            score += 4000;  // Level 4 or 5
            g.hasLevel4ByDeadline = true;
        } else if (opLevel == 3) {
            score += 2500;
        } else if (opLevel == 2) {
            score += 1500;
        } else {
            score += 500;
        }

        // Level 5 targeting (10% max)
        if (opLevel == 5 || g.hasLevel5Target) {
            score += 1000;
        }

        // Reconciliation (20% max)
        if (g.implementsReconciliation) {
            score += 2000;
        }

        // Non-operated asset reporting (10% max)
        if (g.reportsNonOperated) {
            score += 1000;
        }

        // Annual public reporting (10% max)
        if (g.annualPublicReporting) {
            score += 1000;
        }

        // Reduction target (10% max)
        if (g.hasReductionTarget && g.targetReductionPercent >= 4500) {
            score += 1000;  // At least 45% reduction target
        } else if (g.hasReductionTarget) {
            score += 500;
        }

        status.complianceScore = score;
        status.isCompliant = score >= 6000;  // 60% minimum for compliance
        status.meetsGoldStandard = score >= GOLD_STANDARD_THRESHOLD;
        status.lastUpdated = block.timestamp;

        if (status.meetsGoldStandard) {
            emit GoldStandardAchieved(projectId, block.timestamp);
        }

        emit ComplianceUpdated(projectId, status.isCompliant, score);
    }

    // ============ View Functions ============

    /**
     * @dev Primary interface for ComplianceManager
     */
    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return _projectStatus[projectId].isCompliant;
    }

    /**
     * @dev Check if project meets OGMP 2.0 Gold Standard
     */
    function meetsGoldStandard(bytes32 projectId) external view returns (bool) {
        return _projectStatus[projectId].meetsGoldStandard;
    }

    /**
     * @dev Get project reporting level
     */
    function getReportingLevel(bytes32 projectId)
        external
        view
        returns (ReportingLevel operated, ReportingLevel nonOperated)
    {
        OGMP2Status storage s = _projectStatus[projectId];
        return (s.operatedLevel, s.nonOperatedLevel);
    }

    /**
     * @dev Get full project status
     */
    function getStatus(bytes32 projectId) external view returns (OGMP2Status memory) {
        return _projectStatus[projectId];
    }

    /**
     * @dev Get Gold Standard criteria
     */
    function getGoldStandardCriteria(bytes32 projectId)
        external
        view
        returns (GoldStandardCriteria memory)
    {
        return _goldStandard[projectId];
    }

    /**
     * @dev Get emission report for a year
     */
    function getEmissionReport(bytes32 projectId, uint256 year)
        external
        view
        returns (EmissionReport memory)
    {
        return _reports[projectId][year];
    }

    /**
     * @dev Get source breakdown for a year
     */
    function getSourceBreakdown(bytes32 projectId, uint256 year)
        external
        view
        returns (SourceBreakdown memory)
    {
        return _sourceBreakdowns[projectId][year];
    }

    /**
     * @dev Get reconciliation record for a year
     */
    function getReconciliation(bytes32 projectId, uint256 year)
        external
        view
        returns (ReconciliationRecord memory)
    {
        return _reconciliations[projectId][year];
    }

    /**
     * @dev Get all assets for a project
     */
    function getAssets(bytes32 projectId)
        external
        view
        returns (AssetCompliance[] memory)
    {
        return _assets[projectId];
    }

    /**
     * @dev Get compliance score
     */
    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return _projectStatus[projectId].complianceScore;
    }

    /**
     * @dev Check if reconciliation is current (within 2 years)
     */
    function hasRecentReconciliation(bytes32 projectId) external view returns (bool) {
        uint256 currentYear = (block.timestamp / 365 days) + 1970;
        uint256 lastReconYear = _projectStatus[projectId].lastReconciliationYear;
        return lastReconYear >= currentYear - 1;
    }

    /**
     * @dev Calculate year-over-year emission change
     */
    function getEmissionTrend(bytes32 projectId, uint256 year)
        external
        view
        returns (int256 changePercent, bool isReduction)
    {
        EmissionReport storage current = _reports[projectId][year];
        EmissionReport storage previous = _reports[projectId][year - 1];

        if (current.reportId == bytes32(0) || previous.reportId == bytes32(0)) {
            return (0, false);
        }

        int256 change = int256(current.totalMethaneEmissions) - int256(previous.totalMethaneEmissions);
        if (previous.totalMethaneEmissions > 0) {
            changePercent = (change * 10000) / int256(previous.totalMethaneEmissions);
        }
        isReduction = change < 0;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title EPASubpartWValidator
 * @dev Comprehensive EPA 40 CFR Part 98 Subpart W compliance validator.
 *
 * Subpart W covers GHG emissions from Petroleum and Natural Gas Systems.
 * This includes:
 * - Onshore petroleum and natural gas production
 * - Offshore petroleum and natural gas production
 * - Natural gas processing
 * - Natural gas transmission/compression
 * - Underground natural gas storage
 * - LNG import/export equipment
 * - Natural gas distribution
 *
 * Key requirements:
 * - Annual reporting to EPA via e-GGRT
 * - Facility-specific emission calculations
 * - Equipment counts and leak detection (LDAR)
 * - Well count and basin information
 * - Specific calculation methodologies per source type
 *
 * Reference: 40 CFR Part 98, Subpart W
 */
contract EPASubpartWValidator is AccessControl, ReentrancyGuard {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // ============ Industry Segment Types (per 98.230) ============
    enum IndustrySegment {
        ONSHORE_PRODUCTION,             // Onshore petroleum and gas production
        OFFSHORE_PRODUCTION,            // Offshore petroleum and gas production
        PROCESSING,                     // Natural gas processing plants
        TRANSMISSION_COMPRESSION,       // Transmission compressor stations
        UNDERGROUND_STORAGE,            // Underground storage facilities
        LNG_STORAGE,                    // LNG storage facilities
        LNG_IMPORT_EXPORT,             // LNG import/export equipment
        DISTRIBUTION,                   // Natural gas distribution
        GATHERING_BOOSTING             // Gathering and boosting systems
    }

    // ============ Emission Source Categories (per 98.232) ============
    enum SourceCategory {
        // Equipment Leaks (W-1 through W-5)
        FUGITIVE_EQUIPMENT_LEAKS,       // Valves, connectors, pumps, etc.

        // Venting Sources (W-6 through W-17)
        NATURAL_GAS_PNEUMATIC_DEVICES,  // High-bleed, low-bleed, intermittent
        NATURAL_GAS_DRIVEN_PNEUMATIC_PUMPS,
        ACID_GAS_REMOVAL_VENTS,
        DEHYDRATOR_VENTS,
        WELL_VENTING_COMPLETIONS,       // Well completions with hydraulic fracturing
        WELL_VENTING_WORKOVERS,
        BLOWDOWN_VENTING,
        COMPRESSOR_VENTING,             // Centrifugal compressor wet/dry seals
        STORAGE_TANKS,                  // Atmospheric storage tanks

        // Flaring (W-18)
        FLARE_STACKS,

        // Combustion (W-19 through W-21)
        STATIONARY_COMBUSTION,          // Engines, turbines, heaters
        PORTABLE_COMBUSTION,
        FLARE_COMBUSTION,

        // Other Sources (W-22 through W-36)
        CENTRIFUGAL_COMPRESSOR_SEALS,
        RECIPROCATING_COMPRESSOR_SEALS,
        WELL_TESTING_VENTING,
        ASSOCIATED_GAS_VENTING_FLARING,
        OFFSHORE_EQUIPMENT,
        LNG_EQUIPMENT,
        OTHER_SOURCES
    }

    // ============ Calculation Methodology (per 98.233) ============
    enum CalculationMethod {
        DIRECT_MEASUREMENT,             // Method 21 or equivalent
        EMISSION_FACTOR,               // EPA emission factors
        ENGINEERING_CALCULATION,        // Engineering estimates
        MASS_BALANCE,                  // Mass balance approach
        MANUFACTURER_DATA,             // Equipment manufacturer data
        BEST_AVAILABLE_MONITORING     // BAM methods
    }

    // ============ Global Warming Potentials (per 98.2) ============
    uint256 public constant GWP_CO2 = 1;
    uint256 public constant GWP_CH4 = 25;      // Subpart W uses AR4 values
    uint256 public constant GWP_N2O = 298;

    // ============ Facility Information ============
    struct FacilityInfo {
        bytes32 facilityId;
        bytes32 projectId;
        string ghgrpId;                 // EPA GHGRP facility ID
        string facilityName;
        IndustrySegment segment;
        string naicsCode;               // NAICS code (e.g., "211111")
        int256 latitude;                // Scaled by 1e6
        int256 longitude;               // Scaled by 1e6
        string state;
        string county;
        string basin;                   // For production facilities
        uint256 registeredAt;
        bool isActive;
    }

    // ============ Equipment Counts (per 98.236) ============
    struct EquipmentCounts {
        // Well counts
        uint256 oilWellsWithGas;
        uint256 oilWellsWithoutGas;
        uint256 gasWellsWithOil;
        uint256 gasWellsWithoutOil;
        uint256 injectionWells;

        // Equipment counts
        uint256 separators;
        uint256 meters;
        uint256 tanks;
        uint256 compressors;
        uint256 dehydrators;
        uint256 pneumaticDevicesHighBleed;
        uint256 pneumaticDevicesLowBleed;
        uint256 pneumaticDevicesIntermittent;
        uint256 pneumaticPumps;

        // LDAR component counts
        uint256 valves;
        uint256 pumpSeals;
        uint256 connectors;
        uint256 flanges;
        uint256 openEndedLines;
        uint256 pressureReliefValves;
    }

    // ============ Annual Emission Report ============
    struct AnnualReport {
        bytes32 reportId;
        bytes32 facilityId;
        uint256 reportingYear;

        // Total emissions (metric tonnes, scaled by 1e6)
        uint256 totalCO2;
        uint256 totalCH4;
        uint256 totalN2O;
        uint256 totalCO2e;

        // Submission tracking
        uint256 submittedAt;
        string ghgrpSubmissionId;       // EPA e-GGRT submission ID
        bool isVerified;
        bool isAccepted;                // Accepted by EPA
        string reportHash;              // IPFS hash of full report
    }

    // ============ Source-Level Emissions ============
    struct SourceEmissions {
        SourceCategory category;
        uint256 co2Emissions;           // Metric tonnes (scaled by 1e6)
        uint256 ch4Emissions;
        uint256 n2oEmissions;
        CalculationMethod method;
        string calculationDetails;      // IPFS hash
        bool isComplete;
    }

    // ============ LDAR Program Compliance ============
    struct LDARCompliance {
        bytes32 facilityId;
        uint256 reportingYear;
        bool hasLDARProgram;
        uint256 surveyFrequencyDays;    // e.g., 90 for quarterly
        uint256 lastSurveyDate;
        uint256 leaksDetected;
        uint256 leaksRepaired;
        uint256 leaksAwaitingRepair;
        uint256 averageRepairDays;
        string surveyMethodology;       // e.g., "OGI", "Method 21"
        string evidenceHash;
    }

    // ============ Complete Subpart W Status ============
    struct SubpartWStatus {
        bytes32 projectId;
        bool isRegistered;
        bool isCompliant;
        bool hasCurrentReport;
        bool hasLDARProgram;
        uint256 lastReportYear;
        string ghgrpReportId;
        uint256 complianceScore;        // 0-10000
        uint256 lastUpdated;
        string evidenceHash;
    }

    // ============ Storage ============
    mapping(bytes32 => SubpartWStatus) private _projectStatus;
    mapping(bytes32 => FacilityInfo[]) private _facilities;
    mapping(bytes32 => EquipmentCounts) private _equipmentCounts; // facilityId => counts
    mapping(bytes32 => mapping(uint256 => AnnualReport)) private _reports;
    mapping(bytes32 => mapping(uint256 => SourceEmissions[])) private _sourceEmissions;
    mapping(bytes32 => mapping(uint256 => LDARCompliance)) private _ldarCompliance;

    // Reporting threshold (25,000 MT CO2e per 98.2)
    uint256 public constant REPORTING_THRESHOLD = 25000 * 1e6;

    // ============ Events ============
    event ProjectRegistered(
        bytes32 indexed projectId,
        address indexed registeredBy
    );

    event FacilityAdded(
        bytes32 indexed projectId,
        bytes32 indexed facilityId,
        string ghgrpId,
        IndustrySegment segment
    );

    event EquipmentCountsUpdated(
        bytes32 indexed facilityId,
        uint256 totalWells,
        uint256 totalEquipment
    );

    event AnnualReportSubmitted(
        bytes32 indexed projectId,
        bytes32 indexed reportId,
        uint256 indexed year,
        uint256 totalCO2e
    );

    event ReportVerified(
        bytes32 indexed projectId,
        uint256 indexed year,
        address indexed verifier
    );

    event EPAAcceptanceRecorded(
        bytes32 indexed projectId,
        uint256 indexed year,
        string ghgrpSubmissionId
    );

    event LDARComplianceUpdated(
        bytes32 indexed facilityId,
        uint256 indexed year,
        uint256 leaksDetected,
        uint256 leaksRepaired
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
     * @dev Register a project for Subpart W compliance
     */
    function registerProject(bytes32 projectId) external onlyRole(VALIDATOR_ROLE) {
        require(projectId != bytes32(0), "Invalid projectId");
        require(!_projectStatus[projectId].isRegistered, "Already registered");

        _projectStatus[projectId] = SubpartWStatus({
            projectId: projectId,
            isRegistered: true,
            isCompliant: false,
            hasCurrentReport: false,
            hasLDARProgram: false,
            lastReportYear: 0,
            ghgrpReportId: "",
            complianceScore: 0,
            lastUpdated: block.timestamp,
            evidenceHash: ""
        });

        emit ProjectRegistered(projectId, msg.sender);
    }

    // ============ Facility Management ============

    /**
     * @dev Add a facility to a project
     */
    function addFacility(
        bytes32 projectId,
        bytes32 facilityId,
        string calldata ghgrpId,
        string calldata facilityName,
        IndustrySegment segment,
        string calldata naicsCode,
        int256 latitude,
        int256 longitude,
        string calldata state,
        string calldata county,
        string calldata basin
    ) external onlyRole(VALIDATOR_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Project not registered");
        require(facilityId != bytes32(0), "Invalid facilityId");
        require(bytes(ghgrpId).length > 0, "GHGRP ID required");

        _facilities[projectId].push(FacilityInfo({
            facilityId: facilityId,
            projectId: projectId,
            ghgrpId: ghgrpId,
            facilityName: facilityName,
            segment: segment,
            naicsCode: naicsCode,
            latitude: latitude,
            longitude: longitude,
            state: state,
            county: county,
            basin: basin,
            registeredAt: block.timestamp,
            isActive: true
        }));

        emit FacilityAdded(projectId, facilityId, ghgrpId, segment);
    }

    /**
     * @dev Update equipment counts for a facility
     */
    function updateEquipmentCounts(
        bytes32 facilityId,
        EquipmentCounts calldata counts
    ) external onlyRole(REPORTER_ROLE) {
        _equipmentCounts[facilityId] = counts;

        uint256 totalWells = counts.oilWellsWithGas +
            counts.oilWellsWithoutGas +
            counts.gasWellsWithOil +
            counts.gasWellsWithoutOil +
            counts.injectionWells;

        uint256 totalEquipment = counts.separators +
            counts.meters +
            counts.tanks +
            counts.compressors +
            counts.dehydrators +
            counts.pneumaticDevicesHighBleed +
            counts.pneumaticDevicesLowBleed +
            counts.pneumaticDevicesIntermittent +
            counts.pneumaticPumps;

        emit EquipmentCountsUpdated(facilityId, totalWells, totalEquipment);
    }

    // ============ Annual Reporting ============

    /**
     * @dev Submit annual emissions report
     */
    function submitAnnualReport(
        bytes32 projectId,
        bytes32 reportId,
        uint256 reportingYear,
        uint256 totalCO2,
        uint256 totalCH4,
        uint256 totalN2O,
        string calldata reportHash
    ) external onlyRole(REPORTER_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Project not registered");
        require(reportingYear >= 2010 && reportingYear <= 2100, "Invalid year");

        // Calculate CO2e
        uint256 totalCO2e = totalCO2 + (totalCH4 * GWP_CH4) + (totalN2O * GWP_N2O);

        _reports[projectId][reportingYear] = AnnualReport({
            reportId: reportId,
            facilityId: projectId,
            reportingYear: reportingYear,
            totalCO2: totalCO2,
            totalCH4: totalCH4,
            totalN2O: totalN2O,
            totalCO2e: totalCO2e,
            submittedAt: block.timestamp,
            ghgrpSubmissionId: "",
            isVerified: false,
            isAccepted: false,
            reportHash: reportHash
        });

        _projectStatus[projectId].lastReportYear = reportingYear;
        _projectStatus[projectId].hasCurrentReport = true;

        emit AnnualReportSubmitted(projectId, reportId, reportingYear, totalCO2e);
        _updateComplianceScore(projectId);
    }

    /**
     * @dev Add source-level emissions detail
     */
    function addSourceEmissions(
        bytes32 projectId,
        uint256 reportingYear,
        SourceCategory category,
        uint256 co2Emissions,
        uint256 ch4Emissions,
        uint256 n2oEmissions,
        CalculationMethod method,
        string calldata calculationDetails
    ) external onlyRole(REPORTER_ROLE) {
        require(_reports[projectId][reportingYear].reportId != bytes32(0), "No report");

        _sourceEmissions[projectId][reportingYear].push(SourceEmissions({
            category: category,
            co2Emissions: co2Emissions,
            ch4Emissions: ch4Emissions,
            n2oEmissions: n2oEmissions,
            method: method,
            calculationDetails: calculationDetails,
            isComplete: true
        }));
    }

    /**
     * @dev Record EPA e-GGRT submission acceptance
     */
    function recordEPAAcceptance(
        bytes32 projectId,
        uint256 reportingYear,
        string calldata ghgrpSubmissionId
    ) external onlyRole(AUDITOR_ROLE) {
        require(_reports[projectId][reportingYear].reportId != bytes32(0), "No report");

        _reports[projectId][reportingYear].isAccepted = true;
        _reports[projectId][reportingYear].ghgrpSubmissionId = ghgrpSubmissionId;
        _projectStatus[projectId].ghgrpReportId = ghgrpSubmissionId;

        emit EPAAcceptanceRecorded(projectId, reportingYear, ghgrpSubmissionId);
        _updateComplianceScore(projectId);
    }

    /**
     * @dev Verify report (third-party verification)
     */
    function verifyReport(bytes32 projectId, uint256 year) external onlyRole(AUDITOR_ROLE) {
        require(_reports[projectId][year].reportId != bytes32(0), "No report");
        _reports[projectId][year].isVerified = true;
        emit ReportVerified(projectId, year, msg.sender);
        _updateComplianceScore(projectId);
    }

    // ============ LDAR Compliance ============

    /**
     * @dev Update LDAR compliance status
     */
    function updateLDARCompliance(
        bytes32 facilityId,
        uint256 reportingYear,
        bool hasLDARProgram,
        uint256 surveyFrequencyDays,
        uint256 lastSurveyDate,
        uint256 leaksDetected,
        uint256 leaksRepaired,
        uint256 leaksAwaitingRepair,
        uint256 averageRepairDays,
        string calldata surveyMethodology,
        string calldata evidenceHash
    ) external onlyRole(REPORTER_ROLE) {
        _ldarCompliance[facilityId][reportingYear] = LDARCompliance({
            facilityId: facilityId,
            reportingYear: reportingYear,
            hasLDARProgram: hasLDARProgram,
            surveyFrequencyDays: surveyFrequencyDays,
            lastSurveyDate: lastSurveyDate,
            leaksDetected: leaksDetected,
            leaksRepaired: leaksRepaired,
            leaksAwaitingRepair: leaksAwaitingRepair,
            averageRepairDays: averageRepairDays,
            surveyMethodology: surveyMethodology,
            evidenceHash: evidenceHash
        });

        emit LDARComplianceUpdated(facilityId, reportingYear, leaksDetected, leaksRepaired);
    }

    /**
     * @dev Set project-level LDAR status
     */
    function setProjectLDARStatus(bytes32 projectId, bool hasProgram)
        external
        onlyRole(VALIDATOR_ROLE)
    {
        require(_projectStatus[projectId].isRegistered, "Not registered");
        _projectStatus[projectId].hasLDARProgram = hasProgram;
        _updateComplianceScore(projectId);
    }

    // ============ Internal Functions ============

    function _updateComplianceScore(bytes32 projectId) internal {
        SubpartWStatus storage status = _projectStatus[projectId];
        uint256 score = 0;

        // Check if project has current year report
        uint256 currentYear = (block.timestamp / 365 days) + 1970;
        AnnualReport storage latestReport = _reports[projectId][status.lastReportYear];

        // Timely reporting (30% max)
        if (status.lastReportYear >= currentYear - 1) {
            score += 3000;
            status.hasCurrentReport = true;
        } else {
            status.hasCurrentReport = false;
        }

        // EPA acceptance (30% max)
        if (latestReport.isAccepted) {
            score += 3000;
        }

        // Third-party verification (20% max)
        if (latestReport.isVerified) {
            score += 2000;
        }

        // LDAR program (20% max)
        if (status.hasLDARProgram) {
            score += 2000;
        }

        status.complianceScore = score;
        status.isCompliant = score >= 6000;  // 60% threshold
        status.lastUpdated = block.timestamp;

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
     * @dev Get full project status
     */
    function getStatus(bytes32 projectId) external view returns (SubpartWStatus memory) {
        return _projectStatus[projectId];
    }

    /**
     * @dev Get all facilities for a project
     */
    function getFacilities(bytes32 projectId)
        external
        view
        returns (FacilityInfo[] memory)
    {
        return _facilities[projectId];
    }

    /**
     * @dev Get equipment counts for a facility
     */
    function getEquipmentCounts(bytes32 facilityId)
        external
        view
        returns (EquipmentCounts memory)
    {
        return _equipmentCounts[facilityId];
    }

    /**
     * @dev Get annual report
     */
    function getAnnualReport(bytes32 projectId, uint256 year)
        external
        view
        returns (AnnualReport memory)
    {
        return _reports[projectId][year];
    }

    /**
     * @dev Get source-level emissions
     */
    function getSourceEmissions(bytes32 projectId, uint256 year)
        external
        view
        returns (SourceEmissions[] memory)
    {
        return _sourceEmissions[projectId][year];
    }

    /**
     * @dev Get LDAR compliance status
     */
    function getLDARCompliance(bytes32 facilityId, uint256 year)
        external
        view
        returns (LDARCompliance memory)
    {
        return _ldarCompliance[facilityId][year];
    }

    /**
     * @dev Get compliance score
     */
    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return _projectStatus[projectId].complianceScore;
    }

    /**
     * @dev Check if facility exceeds reporting threshold
     */
    function exceedsReportingThreshold(bytes32 projectId, uint256 year)
        external
        view
        returns (bool)
    {
        return _reports[projectId][year].totalCO2e >= REPORTING_THRESHOLD;
    }

    /**
     * @dev Get total methane emissions (CH4 in tonnes)
     */
    function getTotalMethaneEmissions(bytes32 projectId, uint256 year)
        external
        view
        returns (uint256)
    {
        return _reports[projectId][year].totalCH4;
    }

    /**
     * @dev Calculate leak repair rate
     */
    function getLeakRepairRate(bytes32 facilityId, uint256 year)
        external
        view
        returns (uint256 repairRateBps)
    {
        LDARCompliance storage ldar = _ldarCompliance[facilityId][year];
        if (ldar.leaksDetected == 0) return 10000;  // 100% if no leaks
        return (ldar.leaksRepaired * 10000) / ldar.leaksDetected;
    }

    /**
     * @dev Check if report is current
     */
    function hasCurrentReport(bytes32 projectId) external view returns (bool) {
        uint256 currentYear = (block.timestamp / 365 days) + 1970;
        return _projectStatus[projectId].lastReportYear >= currentYear - 1;
    }

    /**
     * @dev Get emission breakdown by source category
     */
    function getEmissionsBySource(bytes32 projectId, uint256 year)
        external
        view
        returns (
            uint256[] memory categories,
            uint256[] memory ch4Emissions
        )
    {
        SourceEmissions[] storage sources = _sourceEmissions[projectId][year];
        uint256 len = sources.length;

        categories = new uint256[](len);
        ch4Emissions = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            categories[i] = uint256(sources[i].category);
            ch4Emissions[i] = sources[i].ch4Emissions;
        }
    }

    // ============ Admin Functions ============

    /**
     * @dev Set compliance status directly (for migration/correction)
     */
    function setComplianceStatus(
        bytes32 projectId,
        bool isCompliant,
        string calldata ghgrpReportId,
        string calldata evidenceHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_projectStatus[projectId].isRegistered, "Not registered");

        SubpartWStatus storage status = _projectStatus[projectId];
        status.isCompliant = isCompliant;
        status.ghgrpReportId = ghgrpReportId;
        status.evidenceHash = evidenceHash;
        status.lastUpdated = block.timestamp;

        emit ComplianceUpdated(projectId, isCompliant, status.complianceScore);
    }
}

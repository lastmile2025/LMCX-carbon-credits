// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CDMAM0023Validator
 * @dev Comprehensive UNFCCC CDM AM0023 methodology validator.
 *
 * AM0023: "Avoidance of methane production from decay of biomass through
 *          controlled combustion, gasification or mechanical/thermal treatment"
 *
 * This methodology applies to:
 * - Landfill gas capture and destruction/utilization
 * - Composting of organic waste
 * - Mechanical biological treatment (MBT)
 * - Anaerobic digestion with biogas utilization
 *
 * Key requirements:
 * - Baseline scenario: Uncontrolled decay in solid waste disposal site (SWDS)
 * - Project scenario: Controlled treatment preventing methane generation
 * - Monitoring: Waste quantities, composition, treatment efficiency
 * - Leakage: Transportation, energy consumption
 *
 * Reference: UNFCCC CDM Methodology AM0023 Version 05.0
 *
 * @notice Uses custom errors for gas efficiency.
 */
contract CDMAM0023Validator is AccessControl, ReentrancyGuard {
    // ============ Custom Errors ============
    error InvalidDOEAddress();
    error AccreditationRequired();
    error InvalidProjectId();
    error AlreadyRegistered();
    error InvalidStartYear();
    error InvalidCreditingPeriod();
    error MaxCreditingPeriodExceeded();
    error NotRegisteredDOE();
    error ProjectNotFound();
    error AlreadyValidated();
    error ProjectNotRegistered();
    error InvalidMCF();
    error InvalidDOC();
    error InvalidDOCf();
    error InvalidF();
    error BaselineNotApproved();
    error KValueTooHigh();
    error InvalidPeriod();
    error InvalidEfficiency();
    error InvalidIndex();
    error InvalidCalculation();
    error MaxUncertaintyExceeded();
    error NotCalculated();
    error AlreadyVerified();
    error NotVerified();
    error ExceedsNetReductions();

    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant DOE_ROLE = keccak256("DOE_ROLE");  // Designated Operational Entity
    bytes32 public constant PP_ROLE = keccak256("PP_ROLE");     // Project Participant

    // ============ Project Activity Types ============
    enum ProjectActivityType {
        LANDFILL_GAS_FLARING,           // LFG capture and flaring
        LANDFILL_GAS_ELECTRICITY,       // LFG to electricity
        LANDFILL_GAS_DIRECT_USE,        // LFG direct thermal use
        COMPOSTING,                     // Aerobic composting
        ANAEROBIC_DIGESTION,            // AD with biogas use
        MECHANICAL_BIOLOGICAL_TREATMENT, // MBT facilities
        REFUSE_DERIVED_FUEL,            // RDF production
        INCINERATION                    // Waste-to-energy incineration
    }

    // ============ Waste Categories (per IPCC) ============
    enum WasteCategory {
        FOOD_WASTE,                     // Food and kitchen waste
        GARDEN_WASTE,                   // Garden and park waste
        PAPER_CARDBOARD,                // Paper and cardboard
        WOOD,                           // Wood and wood products
        TEXTILES,                       // Textiles and rubber
        NAPPIES,                        // Disposable nappies
        SEWAGE_SLUDGE,                  // Sewage sludge
        INDUSTRIAL_ORGANIC,             // Industrial organic waste
        OTHER_ORGANIC                   // Other organic fractions
    }

    // ============ IPCC Methane Correction Factors ============
    // MCF values scaled by 100 (e.g., 100 = 1.0)
    struct MethaneCorrection {
        uint8 managedAnaerobic;         // 100 (1.0) - Managed, anaerobic
        uint8 managedSemiAerobic;       // 50 (0.5) - Managed, semi-aerobic
        uint8 unmanagedDeep;            // 80 (0.8) - Unmanaged, deep
        uint8 unmanagedShallow;         // 40 (0.4) - Unmanaged, shallow
        uint8 uncategorized;            // 60 (0.6) - Uncategorized
    }

    // ============ Project Design Document (PDD) ============
    struct ProjectDesignDocument {
        bytes32 projectId;
        string cdmProjectNumber;         // UNFCCC project reference
        ProjectActivityType activityType;
        string projectTitle;
        string hostCountry;
        string hostParty;                // Annex I Party (if any)

        // Crediting Period
        uint256 creditingStartDate;
        uint256 creditingEndDate;
        bool isRenewable;                // Fixed or renewable crediting period

        // Documentation
        string pddHash;                  // IPFS hash of PDD
        string validationReportHash;     // DOE validation report
        string registrationNumber;       // UNFCCC registration number

        // Status
        bool isValidated;
        bool isRegistered;
        uint256 registrationDate;
        address validatingDOE;
    }

    // ============ Baseline Scenario (Section 5.1 AM0023) ============
    struct BaselineScenario {
        bytes32 projectId;

        // Baseline waste disposal site characteristics
        string swdsType;                 // Type of SWDS in baseline
        uint8 mcf;                       // Methane Correction Factor (scaled by 100)
        uint256 doc;                     // Degradable Organic Carbon (kg C/kg waste, scaled 1e4)
        uint256 docf;                    // Fraction DOC dissimilated (scaled 1e4)
        uint256 f;                       // Fraction of CH4 in LFG (scaled 1e4, typically 5000 = 0.5)

        // Model parameters
        uint256 oxidationFactor;         // OX (scaled 1e4)
        uint256 gwpMethane;              // GWP of CH4 (default 25 or 28)

        // Decay rates by waste type (k values, scaled 1e4)
        mapping(WasteCategory => uint256) decayRates;

        // Baseline documentation
        string baselineStudyHash;
        bool isApproved;
    }

    // ============ Project Emissions (Section 5.2 AM0023) ============
    struct ProjectEmissions {
        bytes32 monitoringId;
        bytes32 projectId;
        uint256 monitoringPeriodStart;
        uint256 monitoringPeriodEnd;

        // Emission sources
        uint256 electricityEmissions;    // Grid electricity (tCO2e, scaled 1e6)
        uint256 fossilFuelEmissions;     // Fossil fuel consumption (tCO2e, scaled 1e6)
        uint256 flareInefficiency;       // Unburned methane (tCO2e, scaled 1e6)
        uint256 residualEmissions;       // Residual waste emissions (tCO2e, scaled 1e6)

        uint256 totalProjectEmissions;   // Total PE (tCO2e, scaled 1e6)
        string calculationHash;          // IPFS hash of calculations
    }

    // ============ Leakage Assessment (Section 5.3 AM0023) ============
    struct LeakageEmissions {
        bytes32 monitoringId;

        // Transportation leakage
        uint256 wasteTransportEmissions; // Waste transport (tCO2e, scaled 1e6)
        uint256 productTransportEmissions;

        // Upstream/downstream leakage
        uint256 displacedActivities;     // Emissions from displaced activities
        uint256 materialsProduction;     // Emissions from materials/chemicals

        uint256 totalLeakage;            // Total LE (tCO2e, scaled 1e6)
        string evidenceHash;
    }

    // ============ Monitoring Data (Section 6 AM0023) ============
    struct MonitoringData {
        bytes32 monitoringId;
        bytes32 projectId;
        uint256 periodStart;
        uint256 periodEnd;

        // Waste quantities (tonnes)
        uint256 totalWasteReceived;
        uint256 organicFraction;         // Organic content (scaled 1e4)
        uint256 moistureContent;         // Moisture % (scaled 1e4)

        // Gas measurements (for LFG projects)
        uint256 methaneCapured;          // m³ CH4 captured
        uint256 methaneFlared;           // m³ CH4 destroyed by flaring
        uint256 methaneUtilized;         // m³ CH4 utilized for energy
        uint256 flareEfficiency;         // Destruction efficiency % (scaled 1e4)

        // Composting/MBT specific
        uint256 compostProduced;         // tonnes compost/digestate
        uint256 residualsToLandfill;     // tonnes sent to SWDS

        // Energy
        uint256 electricityConsumed;     // MWh
        uint256 electricityGenerated;    // MWh (if applicable)
        uint256 fossilFuelConsumed;      // GJ

        // QA/QC
        bool isVerified;
        address verifiedBy;
        string dataHash;
    }

    // ============ Emission Reduction Calculation ============
    struct EmissionReduction {
        bytes32 monitoringId;
        bytes32 projectId;
        uint256 vintageYear;

        // Components (all in tCO2e, scaled 1e6)
        uint256 baselineEmissions;       // BE
        uint256 projectEmissions;        // PE
        uint256 leakageEmissions;        // LE

        // Final calculation: ER = BE - PE - LE
        uint256 grossReductions;
        uint256 netReductions;           // After any adjustments

        // Uncertainty & conservativeness
        uint256 uncertaintyDeduction;    // % deduction (scaled 1e4)
        uint256 conservativeAdjustment;

        // Status
        bool isCalculated;
        bool isVerified;
        bool isCertified;                // CERs issued

        // Issuance
        uint256 cersRequested;
        uint256 cersIssued;
        string issuanceRequestHash;
    }

    // ============ Complete CDM Status ============
    struct CDMStatus {
        bytes32 projectId;
        bool isCompliant;
        bool isRegistered;
        bool hasValidPDD;
        bool hasMonitoringPlan;
        uint256 creditingStartYear;
        uint256 creditingEndYear;
        string cdmProjectNumber;
        string pddHash;
        uint256 totalCERsIssued;
        uint256 complianceScore;         // 0-10000
        uint256 lastUpdated;
    }

    // ============ Storage ============
    mapping(bytes32 => CDMStatus) private _projectStatus;
    mapping(bytes32 => ProjectDesignDocument) private _pdds;
    mapping(bytes32 => BaselineScenario) private _baselines;
    mapping(bytes32 => MonitoringData[]) private _monitoringData;
    mapping(bytes32 => ProjectEmissions[]) private _projectEmissions;
    mapping(bytes32 => LeakageEmissions[]) private _leakageEmissions;
    mapping(bytes32 => EmissionReduction[]) private _emissionReductions;
    mapping(bytes32 => mapping(uint256 => EmissionReduction)) private _vintageReductions;

    // Registered DOEs (Designated Operational Entities)
    mapping(address => bool) public registeredDOEs;
    mapping(address => string) public doeAccreditation;

    // IPCC default values
    uint256 public constant DEFAULT_DOC = 1500;      // 0.15 kg C/kg waste (scaled 1e4)
    uint256 public constant DEFAULT_DOCF = 5000;     // 0.5 (scaled 1e4)
    uint256 public constant DEFAULT_F = 5000;        // 0.5 CH4 fraction (scaled 1e4)
    uint256 public constant DEFAULT_OX = 0;          // 0 oxidation (conservative)
    uint256 public constant DEFAULT_GWP = 25;        // AR4 GWP for CH4

    // ============ Events ============
    event ProjectRegistered(
        bytes32 indexed projectId,
        string cdmProjectNumber,
        ProjectActivityType activityType
    );

    event PDDValidated(
        bytes32 indexed projectId,
        address indexed doe,
        string validationReportHash
    );

    event BaselineApproved(
        bytes32 indexed projectId,
        uint8 mcf,
        uint256 doc
    );

    event MonitoringDataSubmitted(
        bytes32 indexed projectId,
        bytes32 indexed monitoringId,
        uint256 periodStart,
        uint256 periodEnd
    );

    event EmissionReductionCalculated(
        bytes32 indexed projectId,
        bytes32 indexed monitoringId,
        uint256 vintageYear,
        uint256 netReductions
    );

    event CERsIssued(
        bytes32 indexed projectId,
        uint256 indexed vintageYear,
        uint256 amount
    );

    event DOERegistered(
        address indexed doe,
        string accreditationId
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
        _grantRole(DOE_ROLE, msg.sender);
        _grantRole(PP_ROLE, msg.sender);
    }

    // ============ DOE Management ============

    /**
     * @dev Register a Designated Operational Entity
     */
    function registerDOE(
        address doe,
        string calldata accreditationId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (doe == address(0)) revert InvalidDOEAddress();
        if (bytes(accreditationId).length == 0) revert AccreditationRequired();

        registeredDOEs[doe] = true;
        doeAccreditation[doe] = accreditationId;
        _grantRole(DOE_ROLE, doe);

        emit DOERegistered(doe, accreditationId);
    }

    // ============ Project Registration ============

    /**
     * @dev Register a new CDM project
     */
    function registerProject(
        bytes32 projectId,
        string calldata cdmProjectNumber,
        ProjectActivityType activityType,
        string calldata projectTitle,
        string calldata hostCountry,
        uint256 creditingStartYear,
        uint256 creditingEndYear,
        string calldata pddHash
    ) external onlyRole(PP_ROLE) {
        if (projectId == bytes32(0)) revert InvalidProjectId();
        if (_projectStatus[projectId].isRegistered) revert AlreadyRegistered();
        if (creditingStartYear < 2000) revert InvalidStartYear();
        if (creditingEndYear <= creditingStartYear) revert InvalidCreditingPeriod();
        if (creditingEndYear - creditingStartYear > 21) revert MaxCreditingPeriodExceeded();

        _pdds[projectId] = ProjectDesignDocument({
            projectId: projectId,
            cdmProjectNumber: cdmProjectNumber,
            activityType: activityType,
            projectTitle: projectTitle,
            hostCountry: hostCountry,
            hostParty: "",
            creditingStartDate: 0,
            creditingEndDate: 0,
            isRenewable: true,
            pddHash: pddHash,
            validationReportHash: "",
            registrationNumber: "",
            isValidated: false,
            isRegistered: false,
            registrationDate: 0,
            validatingDOE: address(0)
        });

        _projectStatus[projectId] = CDMStatus({
            projectId: projectId,
            isCompliant: false,
            isRegistered: false,
            hasValidPDD: true,
            hasMonitoringPlan: false,
            creditingStartYear: creditingStartYear,
            creditingEndYear: creditingEndYear,
            cdmProjectNumber: cdmProjectNumber,
            pddHash: pddHash,
            totalCERsIssued: 0,
            complianceScore: 0,
            lastUpdated: block.timestamp
        });

        emit ProjectRegistered(projectId, cdmProjectNumber, activityType);
    }

    // ============ PDD Validation ============

    /**
     * @dev DOE validates the PDD
     */
    function validatePDD(
        bytes32 projectId,
        string calldata validationReportHash,
        string calldata registrationNumber
    ) external onlyRole(DOE_ROLE) {
        if (!registeredDOEs[msg.sender]) revert NotRegisteredDOE();
        if (_pdds[projectId].projectId == bytes32(0)) revert ProjectNotFound();
        if (_pdds[projectId].isValidated) revert AlreadyValidated();

        ProjectDesignDocument storage pdd = _pdds[projectId];
        pdd.isValidated = true;
        pdd.validationReportHash = validationReportHash;
        pdd.registrationNumber = registrationNumber;
        pdd.validatingDOE = msg.sender;
        pdd.isRegistered = true;
        pdd.registrationDate = block.timestamp;

        _projectStatus[projectId].isRegistered = true;

        emit PDDValidated(projectId, msg.sender, validationReportHash);
        _updateComplianceScore(projectId);
    }

    // ============ Baseline Establishment ============

    /**
     * @dev Set baseline scenario parameters
     */
    function setBaseline(
        bytes32 projectId,
        string calldata swdsType,
        uint8 mcf,
        uint256 doc,
        uint256 docf,
        uint256 f,
        uint256 oxidationFactor,
        string calldata baselineStudyHash
    ) external onlyRole(VALIDATOR_ROLE) {
        if (!_projectStatus[projectId].isRegistered) revert ProjectNotRegistered();
        if (mcf > 100) revert InvalidMCF();
        if (doc > 10000) revert InvalidDOC();
        if (docf > 10000) revert InvalidDOCf();
        if (f > 10000) revert InvalidF();

        BaselineScenario storage baseline = _baselines[projectId];
        baseline.projectId = projectId;
        baseline.swdsType = swdsType;
        baseline.mcf = mcf;
        baseline.doc = doc;
        baseline.docf = docf;
        baseline.f = f;
        baseline.oxidationFactor = oxidationFactor;
        baseline.gwpMethane = DEFAULT_GWP;
        baseline.baselineStudyHash = baselineStudyHash;
        baseline.isApproved = true;

        emit BaselineApproved(projectId, mcf, doc);
        _updateComplianceScore(projectId);
    }

    /**
     * @dev Set decay rate for a waste category
     */
    function setDecayRate(
        bytes32 projectId,
        WasteCategory category,
        uint256 kValue
    ) external onlyRole(VALIDATOR_ROLE) {
        if (!_baselines[projectId].isApproved) revert BaselineNotApproved();
        if (kValue > 5000) revert KValueTooHigh(); // scaled 1e4

        _baselines[projectId].decayRates[category] = kValue;
    }

    // ============ Monitoring ============

    /**
     * @dev Submit monitoring data
     */
    function submitMonitoringData(
        bytes32 projectId,
        bytes32 monitoringId,
        uint256 periodStart,
        uint256 periodEnd,
        uint256 totalWasteReceived,
        uint256 organicFraction,
        uint256 methaneCapured,
        uint256 methaneFlared,
        uint256 flareEfficiency,
        uint256 electricityConsumed,
        string calldata dataHash
    ) external onlyRole(PP_ROLE) {
        if (!_projectStatus[projectId].isRegistered) revert ProjectNotRegistered();
        if (periodEnd <= periodStart) revert InvalidPeriod();
        if (flareEfficiency > 10000) revert InvalidEfficiency();

        _monitoringData[projectId].push(MonitoringData({
            monitoringId: monitoringId,
            projectId: projectId,
            periodStart: periodStart,
            periodEnd: periodEnd,
            totalWasteReceived: totalWasteReceived,
            organicFraction: organicFraction,
            moistureContent: 0,
            methaneCapured: methaneCapured,
            methaneFlared: methaneFlared,
            methaneUtilized: 0,
            flareEfficiency: flareEfficiency,
            compostProduced: 0,
            residualsToLandfill: 0,
            electricityConsumed: electricityConsumed,
            electricityGenerated: 0,
            fossilFuelConsumed: 0,
            isVerified: false,
            verifiedBy: address(0),
            dataHash: dataHash
        }));

        _projectStatus[projectId].hasMonitoringPlan = true;

        emit MonitoringDataSubmitted(projectId, monitoringId, periodStart, periodEnd);
        _updateComplianceScore(projectId);
    }

    /**
     * @dev DOE verifies monitoring data
     */
    function verifyMonitoringData(
        bytes32 projectId,
        uint256 monitoringIndex
    ) external onlyRole(DOE_ROLE) {
        if (!registeredDOEs[msg.sender]) revert NotRegisteredDOE();
        if (monitoringIndex >= _monitoringData[projectId].length) revert InvalidIndex();

        _monitoringData[projectId][monitoringIndex].isVerified = true;
        _monitoringData[projectId][monitoringIndex].verifiedBy = msg.sender;
    }

    // ============ Emission Reduction Calculation ============

    /**
     * @dev Calculate emission reductions for a monitoring period
     */
    function calculateEmissionReduction(
        bytes32 projectId,
        bytes32 monitoringId,
        uint256 vintageYear,
        uint256 baselineEmissions,
        uint256 projectEmissions,
        uint256 leakageEmissions,
        uint256 uncertaintyDeduction,
        string calldata calculationHash
    ) external onlyRole(VALIDATOR_ROLE) nonReentrant {
        if (!_projectStatus[projectId].isRegistered) revert ProjectNotRegistered();
        if (baselineEmissions < projectEmissions + leakageEmissions) revert InvalidCalculation();
        if (uncertaintyDeduction > 2000) revert MaxUncertaintyExceeded();

        // Write directly to storage to avoid stack too deep
        EmissionReduction storage er = _vintageReductions[projectId][vintageYear];
        er.monitoringId = monitoringId;
        er.projectId = projectId;
        er.vintageYear = vintageYear;
        er.baselineEmissions = baselineEmissions;
        er.projectEmissions = projectEmissions;
        er.leakageEmissions = leakageEmissions;
        er.grossReductions = baselineEmissions - projectEmissions - leakageEmissions;
        er.netReductions = er.grossReductions - (er.grossReductions * uncertaintyDeduction) / 10000;
        er.uncertaintyDeduction = uncertaintyDeduction;
        er.conservativeAdjustment = (er.grossReductions * uncertaintyDeduction) / 10000;
        er.isCalculated = true;
        er.isVerified = false;
        er.isCertified = false;
        er.cersRequested = 0;
        er.cersIssued = 0;
        er.issuanceRequestHash = calculationHash;

        _emissionReductions[projectId].push(er);

        emit EmissionReductionCalculated(projectId, monitoringId, vintageYear, er.netReductions);
        _updateComplianceScore(projectId);
    }

    /**
     * @dev DOE verifies emission reductions
     */
    function verifyEmissionReduction(
        bytes32 projectId,
        uint256 vintageYear
    ) external onlyRole(DOE_ROLE) {
        if (!registeredDOEs[msg.sender]) revert NotRegisteredDOE();

        EmissionReduction storage er = _vintageReductions[projectId][vintageYear];
        if (!er.isCalculated) revert NotCalculated();
        if (er.isVerified) revert AlreadyVerified();

        er.isVerified = true;
    }

    /**
     * @dev Record CER issuance
     */
    function recordCERIssuance(
        bytes32 projectId,
        uint256 vintageYear,
        uint256 cersIssued
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        EmissionReduction storage er = _vintageReductions[projectId][vintageYear];
        if (!er.isVerified) revert NotVerified();
        if (cersIssued > er.netReductions) revert ExceedsNetReductions();

        er.isCertified = true;
        er.cersIssued = cersIssued;
        _projectStatus[projectId].totalCERsIssued += cersIssued;

        emit CERsIssued(projectId, vintageYear, cersIssued);
    }

    // ============ Internal Functions ============

    function _updateComplianceScore(bytes32 projectId) internal {
        CDMStatus storage status = _projectStatus[projectId];
        uint256 score = 0;

        // PDD validation (20%)
        if (_pdds[projectId].isValidated) {
            score += 2000;
        }

        // Registration (20%)
        if (status.isRegistered) {
            score += 2000;
        }

        // Baseline approved (15%)
        if (_baselines[projectId].isApproved) {
            score += 1500;
        }

        // Monitoring plan (15%)
        if (status.hasMonitoringPlan) {
            score += 1500;
        }

        // Has verified reductions (15%)
        bool hasVerifiedReductions = false;
        for (uint256 i = 0; i < _emissionReductions[projectId].length; i++) {
            if (_emissionReductions[projectId][i].isVerified) {
                hasVerifiedReductions = true;
                break;
            }
        }
        if (hasVerifiedReductions) {
            score += 1500;
        }

        // Has issued CERs (15%)
        if (status.totalCERsIssued > 0) {
            score += 1500;
        }

        status.complianceScore = score;
        status.isCompliant = score >= 7000;  // 70% threshold
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
     * @dev Check if vintage year is within crediting period
     */
    function isVintageEligible(bytes32 projectId, uint256 year)
        external
        view
        returns (bool)
    {
        CDMStatus memory s = _projectStatus[projectId];
        if (!s.isCompliant) return false;
        return year >= s.creditingStartYear && year <= s.creditingEndYear;
    }

    /**
     * @dev Get full CDM status
     */
    function getStatus(bytes32 projectId)
        external
        view
        returns (CDMStatus memory)
    {
        return _projectStatus[projectId];
    }

    /**
     * @dev Get PDD details
     */
    function getPDD(bytes32 projectId)
        external
        view
        returns (ProjectDesignDocument memory)
    {
        return _pdds[projectId];
    }

    /**
     * @dev Get baseline parameters
     */
    function getBaseline(bytes32 projectId)
        external
        view
        returns (
            string memory swdsType,
            uint8 mcf,
            uint256 doc,
            uint256 docf,
            uint256 f,
            bool isApproved
        )
    {
        BaselineScenario storage b = _baselines[projectId];
        return (b.swdsType, b.mcf, b.doc, b.docf, b.f, b.isApproved);
    }

    /**
     * @dev Get monitoring data count
     */
    function getMonitoringDataCount(bytes32 projectId)
        external
        view
        returns (uint256)
    {
        return _monitoringData[projectId].length;
    }

    /**
     * @dev Get specific monitoring data
     */
    function getMonitoringData(bytes32 projectId, uint256 index)
        external
        view
        returns (MonitoringData memory)
    {
        if (index >= _monitoringData[projectId].length) revert InvalidIndex();
        return _monitoringData[projectId][index];
    }

    /**
     * @dev Get emission reduction for a vintage
     */
    function getEmissionReduction(bytes32 projectId, uint256 vintageYear)
        external
        view
        returns (EmissionReduction memory)
    {
        return _vintageReductions[projectId][vintageYear];
    }

    /**
     * @dev Get all emission reductions
     */
    function getAllEmissionReductions(bytes32 projectId)
        external
        view
        returns (EmissionReduction[] memory)
    {
        return _emissionReductions[projectId];
    }

    /**
     * @dev Get total CERs issued
     */
    function getTotalCERsIssued(bytes32 projectId)
        external
        view
        returns (uint256)
    {
        return _projectStatus[projectId].totalCERsIssued;
    }

    /**
     * @dev Get compliance score
     */
    function getComplianceScore(bytes32 projectId)
        external
        view
        returns (uint256)
    {
        return _projectStatus[projectId].complianceScore;
    }

    /**
     * @dev Check if crediting period is active
     */
    function isCreditingPeriodActive(bytes32 projectId)
        external
        view
        returns (bool)
    {
        CDMStatus memory s = _projectStatus[projectId];
        uint256 currentYear = (block.timestamp / 365 days) + 1970;
        return currentYear >= s.creditingStartYear && currentYear <= s.creditingEndYear;
    }

    /**
     * @dev Get remaining crediting years
     */
    function getRemainingCreditingYears(bytes32 projectId)
        external
        view
        returns (uint256)
    {
        CDMStatus memory s = _projectStatus[projectId];
        uint256 currentYear = (block.timestamp / 365 days) + 1970;
        if (currentYear >= s.creditingEndYear) return 0;
        return s.creditingEndYear - currentYear;
    }

    // ============ Admin Functions ============

    /**
     * @dev Set compliance directly (for migration)
     */
    function setCompliance(
        bytes32 projectId,
        bool isCompliant,
        uint256 creditingStartYear,
        uint256 creditingEndYear,
        string calldata cdmProjectNumber,
        string calldata pddHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (projectId == bytes32(0)) revert InvalidProjectId();

        CDMStatus storage status = _projectStatus[projectId];
        status.projectId = projectId;
        status.isCompliant = isCompliant;
        status.creditingStartYear = creditingStartYear;
        status.creditingEndYear = creditingEndYear;
        status.cdmProjectNumber = cdmProjectNumber;
        status.pddHash = pddHash;
        status.lastUpdated = block.timestamp;
    }
}

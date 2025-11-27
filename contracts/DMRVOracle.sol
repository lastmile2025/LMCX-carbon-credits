// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DMRVOracle
 * @dev Digital Measurement, Reporting, and Verification (dMRV) Oracle for Enovate.ai integration.
 *
 * This contract serves as the on-chain interface for real-time monitoring data from the
 * Enovate.ai system. It receives, validates, and stores continuous monitoring reports
 * that feed into the carbon credit verification process.
 *
 * Features:
 * - Real-time data ingestion from authorized Enovate.ai nodes
 * - Measurement validation and anomaly detection
 * - Historical data tracking for audit trails
 * - Integration with SMART Protocol data governance
 * - Automatic alert generation for threshold violations
 */
contract DMRVOracle is AccessControl, Pausable {
    bytes32 public constant ORACLE_OPERATOR_ROLE = keccak256("ORACLE_OPERATOR_ROLE");
    bytes32 public constant DATA_VALIDATOR_ROLE = keccak256("DATA_VALIDATOR_ROLE");
    bytes32 public constant ENOVATE_NODE_ROLE = keccak256("ENOVATE_NODE_ROLE");

    // ============ Data Structures ============

    /// @notice Measurement data from Enovate.ai sensors
    struct MeasurementData {
        bytes32 measurementId;
        bytes32 projectId;
        bytes32 sensorId;
        uint256 timestamp;
        int256 value;              // Scaled by 1e6 for precision
        string unit;               // e.g., "tCO2e", "kg/hr", "ppm"
        string measurementType;    // e.g., "methane_emission", "co2_capture", "flare_efficiency"
        bytes32 dataHash;          // Hash of raw measurement data
        bool isValidated;
        bool hasAnomaly;
    }

    /// @notice Sensor configuration
    struct SensorConfig {
        bytes32 sensorId;
        bytes32 projectId;
        string sensorType;
        string manufacturer;
        string model;
        int256 calibrationFactor;  // Scaled by 1e6
        uint256 lastCalibration;
        uint256 calibrationExpiry;
        bool isActive;
    }

    /// @notice Monitoring report aggregating multiple measurements
    struct MonitoringReport {
        bytes32 reportId;
        bytes32 projectId;
        uint256 periodStart;
        uint256 periodEnd;
        uint256 measurementCount;
        int256 totalEmissions;     // Scaled by 1e6
        int256 totalReductions;    // Scaled by 1e6
        int256 netReduction;       // Scaled by 1e6
        string reportHash;         // IPFS hash of full report
        uint256 submittedAt;
        bool isVerified;
        address verifiedBy;
    }

    /// @notice Threshold configuration for alerts
    struct ThresholdConfig {
        int256 minValue;
        int256 maxValue;
        int256 anomalyDeviation;   // Percentage deviation that triggers anomaly (scaled 1e4)
        bool isActive;
    }

    /// @notice Alert record
    struct Alert {
        uint256 alertId;
        bytes32 projectId;
        bytes32 measurementId;
        string alertType;          // "threshold_exceeded", "anomaly_detected", "sensor_offline"
        string severity;           // "low", "medium", "high", "critical"
        string message;
        uint256 timestamp;
        bool isResolved;
        address resolvedBy;
        uint256 resolvedAt;
    }

    // ============ Storage ============

    // Measurement storage
    mapping(bytes32 => MeasurementData) public measurements;
    mapping(bytes32 => bytes32[]) public projectMeasurements;
    mapping(bytes32 => bytes32) public latestMeasurement; // projectId => latest measurementId
    
    // Sensor management
    mapping(bytes32 => SensorConfig) public sensors;
    mapping(bytes32 => bytes32[]) public projectSensors;
    
    // Monitoring reports
    mapping(bytes32 => MonitoringReport) public reports;
    mapping(bytes32 => bytes32[]) public projectReports;
    
    // Thresholds
    mapping(bytes32 => mapping(string => ThresholdConfig)) public thresholds; // projectId => measurementType => config
    
    // Alerts
    mapping(uint256 => Alert) public alerts;
    mapping(bytes32 => uint256[]) public projectAlerts;
    uint256 public nextAlertId;
    
    // Statistics
    mapping(bytes32 => uint256) public measurementCounts;
    mapping(bytes32 => int256) public cumulativeReductions;

    // ============ Events ============

    event MeasurementReceived(
        bytes32 indexed measurementId,
        bytes32 indexed projectId,
        bytes32 indexed sensorId,
        int256 value,
        string measurementType,
        uint256 timestamp
    );

    event MeasurementValidated(
        bytes32 indexed measurementId,
        bool isValid,
        bool hasAnomaly
    );

    event SensorRegistered(
        bytes32 indexed sensorId,
        bytes32 indexed projectId,
        string sensorType
    );

    event SensorCalibrated(
        bytes32 indexed sensorId,
        int256 calibrationFactor,
        uint256 expiryDate
    );

    event MonitoringReportSubmitted(
        bytes32 indexed reportId,
        bytes32 indexed projectId,
        uint256 periodStart,
        uint256 periodEnd,
        int256 netReduction
    );

    event MonitoringReportVerified(
        bytes32 indexed reportId,
        address indexed verifier
    );

    event AlertCreated(
        uint256 indexed alertId,
        bytes32 indexed projectId,
        string alertType,
        string severity
    );

    event AlertResolved(
        uint256 indexed alertId,
        address indexed resolver
    );

    event ThresholdUpdated(
        bytes32 indexed projectId,
        string measurementType,
        int256 minValue,
        int256 maxValue
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_OPERATOR_ROLE, msg.sender);
    }

    // ============ Sensor Management ============

    /**
     * @dev Register a new sensor for a project
     */
    function registerSensor(
        bytes32 sensorId,
        bytes32 projectId,
        string calldata sensorType,
        string calldata manufacturer,
        string calldata model,
        int256 calibrationFactor,
        uint256 calibrationExpiry
    ) external onlyRole(ORACLE_OPERATOR_ROLE) {
        require(sensorId != bytes32(0), "Invalid sensorId");
        require(projectId != bytes32(0), "Invalid projectId");
        require(!sensors[sensorId].isActive, "Sensor already registered");

        sensors[sensorId] = SensorConfig({
            sensorId: sensorId,
            projectId: projectId,
            sensorType: sensorType,
            manufacturer: manufacturer,
            model: model,
            calibrationFactor: calibrationFactor,
            lastCalibration: block.timestamp,
            calibrationExpiry: calibrationExpiry,
            isActive: true
        });

        projectSensors[projectId].push(sensorId);

        emit SensorRegistered(sensorId, projectId, sensorType);
    }

    /**
     * @dev Update sensor calibration
     */
    function calibrateSensor(
        bytes32 sensorId,
        int256 newCalibrationFactor,
        uint256 newExpiry
    ) external onlyRole(ORACLE_OPERATOR_ROLE) {
        require(sensors[sensorId].isActive, "Sensor not found");
        require(newExpiry > block.timestamp, "Expiry must be future");

        sensors[sensorId].calibrationFactor = newCalibrationFactor;
        sensors[sensorId].lastCalibration = block.timestamp;
        sensors[sensorId].calibrationExpiry = newExpiry;

        emit SensorCalibrated(sensorId, newCalibrationFactor, newExpiry);
    }

    /**
     * @dev Check if sensor is valid and calibrated
     */
    function isSensorValid(bytes32 sensorId) public view returns (bool) {
        SensorConfig memory sensor = sensors[sensorId];
        return sensor.isActive && block.timestamp <= sensor.calibrationExpiry;
    }

    // ============ Measurement Data Ingestion ============

    /**
     * @dev Submit measurement from Enovate.ai node
     */
    function submitMeasurement(
        bytes32 measurementId,
        bytes32 projectId,
        bytes32 sensorId,
        int256 value,
        string calldata unit,
        string calldata measurementType,
        bytes32 dataHash
    ) external onlyRole(ENOVATE_NODE_ROLE) whenNotPaused {
        require(measurementId != bytes32(0), "Invalid measurementId");
        require(projectId != bytes32(0), "Invalid projectId");
        require(isSensorValid(sensorId), "Invalid or uncalibrated sensor");
        require(measurements[measurementId].measurementId == bytes32(0), "Measurement exists");

        // Apply calibration factor
        int256 calibratedValue = (value * sensors[sensorId].calibrationFactor) / 1e6;

        measurements[measurementId] = MeasurementData({
            measurementId: measurementId,
            projectId: projectId,
            sensorId: sensorId,
            timestamp: block.timestamp,
            value: calibratedValue,
            unit: unit,
            measurementType: measurementType,
            dataHash: dataHash,
            isValidated: false,
            hasAnomaly: false
        });

        projectMeasurements[projectId].push(measurementId);
        latestMeasurement[projectId] = measurementId;
        measurementCounts[projectId]++;

        emit MeasurementReceived(measurementId, projectId, sensorId, calibratedValue, measurementType, block.timestamp);

        // Check thresholds and create alerts if needed
        _checkThresholds(measurementId, projectId, calibratedValue, measurementType);
    }

    /**
     * @dev Batch submit measurements for efficiency
     */
    function submitMeasurementBatch(
        bytes32[] calldata measurementIds,
        bytes32 projectId,
        bytes32[] calldata sensorIds,
        int256[] calldata values,
        string[] calldata units,
        string[] calldata measurementTypes,
        bytes32[] calldata dataHashes
    ) external onlyRole(ENOVATE_NODE_ROLE) whenNotPaused {
        require(measurementIds.length == sensorIds.length, "Array mismatch");
        require(measurementIds.length == values.length, "Array mismatch");

        for (uint256 i = 0; i < measurementIds.length; i++) {
            if (isSensorValid(sensorIds[i])) {
                int256 calibratedValue = (values[i] * sensors[sensorIds[i]].calibrationFactor) / 1e6;

                measurements[measurementIds[i]] = MeasurementData({
                    measurementId: measurementIds[i],
                    projectId: projectId,
                    sensorId: sensorIds[i],
                    timestamp: block.timestamp,
                    value: calibratedValue,
                    unit: units[i],
                    measurementType: measurementTypes[i],
                    dataHash: dataHashes[i],
                    isValidated: false,
                    hasAnomaly: false
                });

                projectMeasurements[projectId].push(measurementIds[i]);
                measurementCounts[projectId]++;

                emit MeasurementReceived(
                    measurementIds[i], 
                    projectId, 
                    sensorIds[i], 
                    calibratedValue, 
                    measurementTypes[i], 
                    block.timestamp
                );
            }
        }

        latestMeasurement[projectId] = measurementIds[measurementIds.length - 1];
    }

    /**
     * @dev Validate a measurement
     */
    function validateMeasurement(
        bytes32 measurementId,
        bool isValid,
        bool hasAnomaly
    ) external onlyRole(DATA_VALIDATOR_ROLE) {
        require(measurements[measurementId].measurementId != bytes32(0), "Measurement not found");

        measurements[measurementId].isValidated = true;
        measurements[measurementId].hasAnomaly = hasAnomaly;

        if (hasAnomaly) {
            _createAlert(
                measurements[measurementId].projectId,
                measurementId,
                "anomaly_detected",
                "medium",
                "Anomaly detected in measurement data"
            );
        }

        emit MeasurementValidated(measurementId, isValid, hasAnomaly);
    }

    // ============ Threshold Management ============

    /**
     * @dev Set thresholds for a measurement type
     */
    function setThresholds(
        bytes32 projectId,
        string calldata measurementType,
        int256 minValue,
        int256 maxValue,
        int256 anomalyDeviation
    ) external onlyRole(ORACLE_OPERATOR_ROLE) {
        thresholds[projectId][measurementType] = ThresholdConfig({
            minValue: minValue,
            maxValue: maxValue,
            anomalyDeviation: anomalyDeviation,
            isActive: true
        });

        emit ThresholdUpdated(projectId, measurementType, minValue, maxValue);
    }

    /**
     * @dev Check if value exceeds thresholds
     */
    function _checkThresholds(
        bytes32 measurementId,
        bytes32 projectId,
        int256 value,
        string memory measurementType
    ) internal {
        ThresholdConfig memory config = thresholds[projectId][measurementType];
        
        if (!config.isActive) return;

        if (value < config.minValue || value > config.maxValue) {
            _createAlert(
                projectId,
                measurementId,
                "threshold_exceeded",
                value > config.maxValue ? "high" : "medium",
                "Measurement value outside acceptable range"
            );
        }
    }

    // ============ Alert Management ============

    /**
     * @dev Create an alert
     */
    function _createAlert(
        bytes32 projectId,
        bytes32 measurementId,
        string memory alertType,
        string memory severity,
        string memory message
    ) internal {
        uint256 alertId = nextAlertId++;

        alerts[alertId] = Alert({
            alertId: alertId,
            projectId: projectId,
            measurementId: measurementId,
            alertType: alertType,
            severity: severity,
            message: message,
            timestamp: block.timestamp,
            isResolved: false,
            resolvedBy: address(0),
            resolvedAt: 0
        });

        projectAlerts[projectId].push(alertId);

        emit AlertCreated(alertId, projectId, alertType, severity);
    }

    /**
     * @dev Resolve an alert
     */
    function resolveAlert(uint256 alertId) external onlyRole(ORACLE_OPERATOR_ROLE) {
        require(!alerts[alertId].isResolved, "Already resolved");

        alerts[alertId].isResolved = true;
        alerts[alertId].resolvedBy = msg.sender;
        alerts[alertId].resolvedAt = block.timestamp;

        emit AlertResolved(alertId, msg.sender);
    }

    /**
     * @dev Get active alerts for a project
     */
    function getActiveAlerts(bytes32 projectId) external view returns (uint256[] memory) {
        uint256[] memory projectAlertIds = projectAlerts[projectId];
        uint256 activeCount = 0;

        // Count active alerts
        for (uint256 i = 0; i < projectAlertIds.length; i++) {
            if (!alerts[projectAlertIds[i]].isResolved) {
                activeCount++;
            }
        }

        // Build active alerts array
        uint256[] memory activeAlerts = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < projectAlertIds.length; i++) {
            if (!alerts[projectAlertIds[i]].isResolved) {
                activeAlerts[index++] = projectAlertIds[i];
            }
        }

        return activeAlerts;
    }

    // ============ Monitoring Reports ============

    /**
     * @dev Submit a monitoring report
     */
    function submitMonitoringReport(
        bytes32 reportId,
        bytes32 projectId,
        uint256 periodStart,
        uint256 periodEnd,
        uint256 measurementCount,
        int256 totalEmissions,
        int256 totalReductions,
        string calldata reportHash
    ) external onlyRole(ORACLE_OPERATOR_ROLE) {
        require(reportId != bytes32(0), "Invalid reportId");
        require(periodEnd > periodStart, "Invalid period");
        require(reports[reportId].reportId == bytes32(0), "Report exists");

        int256 netReduction = totalReductions - totalEmissions;

        reports[reportId] = MonitoringReport({
            reportId: reportId,
            projectId: projectId,
            periodStart: periodStart,
            periodEnd: periodEnd,
            measurementCount: measurementCount,
            totalEmissions: totalEmissions,
            totalReductions: totalReductions,
            netReduction: netReduction,
            reportHash: reportHash,
            submittedAt: block.timestamp,
            isVerified: false,
            verifiedBy: address(0)
        });

        projectReports[projectId].push(reportId);
        cumulativeReductions[projectId] += netReduction;

        emit MonitoringReportSubmitted(reportId, projectId, periodStart, periodEnd, netReduction);
    }

    /**
     * @dev Verify a monitoring report
     */
    function verifyMonitoringReport(bytes32 reportId) external onlyRole(DATA_VALIDATOR_ROLE) {
        require(reports[reportId].reportId != bytes32(0), "Report not found");
        require(!reports[reportId].isVerified, "Already verified");

        reports[reportId].isVerified = true;
        reports[reportId].verifiedBy = msg.sender;

        emit MonitoringReportVerified(reportId, msg.sender);
    }

    // ============ Query Functions ============

    /**
     * @dev Get latest measurement value for a project
     */
    function getLatestMeasurement(bytes32 projectId) 
        external 
        view 
        returns (MeasurementData memory) 
    {
        bytes32 measurementId = latestMeasurement[projectId];
        return measurements[measurementId];
    }

    /**
     * @dev Get measurement count for a project
     */
    function getMeasurementCount(bytes32 projectId) external view returns (uint256) {
        return measurementCounts[projectId];
    }

    /**
     * @dev Get cumulative reductions for a project
     */
    function getCumulativeReductions(bytes32 projectId) external view returns (int256) {
        return cumulativeReductions[projectId];
    }

    /**
     * @dev Get project report IDs
     */
    function getProjectReports(bytes32 projectId) external view returns (bytes32[] memory) {
        return projectReports[projectId];
    }

    /**
     * @dev Check if project has verified reports
     */
    function hasVerifiedReports(bytes32 projectId) external view returns (bool) {
        bytes32[] memory reportIds = projectReports[projectId];
        for (uint256 i = 0; i < reportIds.length; i++) {
            if (reports[reportIds[i]].isVerified) {
                return true;
            }
        }
        return false;
    }

    // ============ Admin Functions ============

    /**
     * @dev Pause oracle operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause oracle operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Grant Enovate node role
     */
    function addEnovateNode(address node) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(ENOVATE_NODE_ROLE, node);
    }

    /**
     * @dev Revoke Enovate node role
     */
    function removeEnovateNode(address node) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ENOVATE_NODE_ROLE, node);
    }
}

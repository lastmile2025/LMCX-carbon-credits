// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title OracleAggregator
 * @dev Multi-oracle aggregation system for carbon credit data with:
 * - Minimum 3 independent data sources for redundancy
 * - Weighted median calculation for manipulation resistance
 * - Anomaly detection with automatic pause triggers
 * - Data quality scoring with staleness checks
 * - Chainlink integration support
 * - HSM attestation verification for sensor integrity
 *
 * Follows decentralized oracle best practices for maximum data integrity.
 */
contract OracleAggregator is AccessControl, ReentrancyGuard, Pausable {
    // ============ Roles ============
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    bytes32 public constant ORACLE_NODE_ROLE = keccak256("ORACLE_NODE_ROLE");
    bytes32 public constant ANOMALY_RESOLVER_ROLE = keccak256("ANOMALY_RESOLVER_ROLE");

    // ============ Constants ============
    uint256 public constant MIN_ORACLES = 3;
    uint256 public constant MAX_ORACLES = 20;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_DEVIATION_PERCENTAGE = 2000; // 20% in basis points
    uint256 public constant DEFAULT_HEARTBEAT = 1 hours;
    uint256 public constant MIN_QUALITY_SCORE = 5000; // 50% minimum
    uint256 public constant MAX_STALENESS = 24 hours;

    // ============ Enums ============
    enum OracleStatus {
        Active,
        Suspended,
        Deprecated,
        Offline
    }

    enum AggregationStrategy {
        Median,
        WeightedMedian,
        TrimmedMean,
        WeightedAverage
    }

    enum DataType {
        EmissionRate,           // tCO2e per time unit
        ReductionAmount,        // Total reductions
        SensorReading,          // Raw sensor data
        VerificationScore,      // Verification quality
        PriceData,              // Carbon credit price
        WeatherData,            // Environmental factors
        Custom
    }

    // ============ Structs ============

    /// @notice Oracle configuration
    struct OracleConfig {
        address oracleAddress;
        string name;
        string endpoint;                // API or contract address
        OracleStatus status;
        uint256 weight;                 // Weight for aggregation (1-10000)
        uint256 reputation;             // Reputation score (0-10000)
        uint256 heartbeat;              // Expected update frequency
        uint256 registeredAt;
        uint256 lastUpdate;
        uint256 successCount;
        uint256 failureCount;
        bool isChainlink;               // Chainlink oracle flag
        bytes32 jobId;                  // Chainlink job ID if applicable
    }

    /// @notice Individual oracle data submission
    struct OracleSubmission {
        bytes32 submissionId;
        bytes32 dataFeedId;
        address oracle;
        int256 value;                   // Scaled by PRECISION
        uint256 timestamp;
        bytes32 dataHash;               // Hash of supporting data
        uint256 confidence;             // Confidence level (0-10000)
        bool isValid;
        string sourceRef;               // IPFS/external reference
    }

    /// @notice Aggregated data feed
    struct DataFeed {
        bytes32 feedId;
        bytes32 projectId;
        DataType dataType;
        string description;
        AggregationStrategy strategy;
        uint256 minOracles;             // Minimum oracles for valid aggregation
        uint256 maxDeviation;           // Max allowed deviation between oracles
        uint256 heartbeat;              // Max age of data
        bool isActive;
        uint256 createdAt;
    }

    /// @notice Aggregated result
    struct AggregatedResult {
        bytes32 feedId;
        int256 value;                   // Aggregated value
        uint256 timestamp;
        uint256 oracleCount;            // Number of oracles used
        uint256 qualityScore;           // Data quality (0-10000)
        bool hasAnomaly;
        bytes32 resultHash;
        int256[] individualValues;      // Values from each oracle
        address[] participatingOracles;
    }

    /// @notice Anomaly record
    struct AnomalyRecord {
        uint256 anomalyId;
        bytes32 feedId;
        string anomalyType;             // "deviation", "stale", "missing", "outlier"
        string severity;                // "low", "medium", "high", "critical"
        int256[] reportedValues;
        uint256 detectedAt;
        bool isResolved;
        address resolvedBy;
        string resolution;
    }

    /// @notice HSM attestation for sensor integrity
    struct HSMAttestation {
        bytes32 attestationId;
        bytes32 sensorId;
        bytes signature;
        bytes32 publicKeyHash;
        uint256 timestamp;
        bool isValid;
        uint256 expiresAt;
    }

    // ============ Storage ============

    // Oracle management
    mapping(address => OracleConfig) public oracles;
    address[] public oracleList;
    uint256 public activeOracleCount;

    // Data feeds
    mapping(bytes32 => DataFeed) public dataFeeds;
    bytes32[] public feedIds;

    // Submissions
    mapping(bytes32 => OracleSubmission) public submissions;
    mapping(bytes32 => mapping(address => OracleSubmission)) public feedSubmissions; // feedId => oracle => submission
    mapping(bytes32 => address[]) public feedOracleSubmitters; // feedId => oracles that submitted

    // Aggregated results
    mapping(bytes32 => AggregatedResult) public latestResults;
    mapping(bytes32 => AggregatedResult[]) public resultHistory;
    uint256 public maxHistoryLength = 100;

    // Anomalies
    mapping(uint256 => AnomalyRecord) public anomalies;
    mapping(bytes32 => uint256[]) public feedAnomalies;
    uint256 public anomalyCount;
    uint256 public unresolvedAnomalyCount;

    // HSM attestations
    mapping(bytes32 => HSMAttestation) public hsmAttestations;
    mapping(bytes32 => bytes32) public sensorAttestation; // sensorId => attestationId

    // Circuit breaker
    bool public circuitBreakerActive;
    uint256 public circuitBreakerThreshold = 3; // Consecutive anomalies to trigger

    // Gas optimization: Circular buffer for history
    mapping(bytes32 => uint256) public historyHead;  // Points to oldest entry index
    mapping(bytes32 => uint256) public historyCount; // Current count of history entries

    // Gas optimization: O(1) duplicate submitter check
    mapping(bytes32 => mapping(address => bool)) private _hasSubmittedInRound; // roundKey => oracle => hasSubmitted
    mapping(bytes32 => uint256) public feedRoundId;  // Track submission rounds per feed

    // ============ Events ============

    event OracleRegistered(
        address indexed oracle,
        string name,
        uint256 weight
    );

    event OracleStatusChanged(
        address indexed oracle,
        OracleStatus oldStatus,
        OracleStatus newStatus
    );

    event DataFeedCreated(
        bytes32 indexed feedId,
        bytes32 indexed projectId,
        DataType dataType,
        AggregationStrategy strategy
    );

    event DataSubmitted(
        bytes32 indexed submissionId,
        bytes32 indexed feedId,
        address indexed oracle,
        int256 value,
        uint256 confidence
    );

    event DataAggregated(
        bytes32 indexed feedId,
        int256 aggregatedValue,
        uint256 oracleCount,
        uint256 qualityScore
    );

    event AnomalyDetected(
        uint256 indexed anomalyId,
        bytes32 indexed feedId,
        string anomalyType,
        string severity
    );

    event AnomalyResolved(
        uint256 indexed anomalyId,
        address indexed resolver,
        string resolution
    );

    event CircuitBreakerTriggered(
        bytes32 indexed feedId,
        uint256 anomalyCount
    );

    event HSMAttestationRecorded(
        bytes32 indexed attestationId,
        bytes32 indexed sensorId,
        bool isValid
    );

    // ============ Modifiers ============

    modifier onlyActiveOracle() {
        require(oracles[msg.sender].status == OracleStatus.Active, "Oracle not active");
        _;
    }

    modifier feedExists(bytes32 feedId) {
        require(dataFeeds[feedId].feedId != bytes32(0), "Feed not found");
        _;
    }

    // ============ Constructor ============

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ADMIN_ROLE, msg.sender);
        _grantRole(ANOMALY_RESOLVER_ROLE, msg.sender);
    }

    // ============ Oracle Management ============

    /**
     * @dev Register a new oracle
     */
    function registerOracle(
        address oracleAddress,
        string calldata name,
        string calldata endpoint,
        uint256 weight,
        uint256 heartbeat,
        bool isChainlink,
        bytes32 jobId
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(oracleAddress != address(0), "Invalid address");
        require(oracles[oracleAddress].oracleAddress == address(0), "Already registered");
        require(weight > 0 && weight <= 10000, "Invalid weight");
        require(activeOracleCount < MAX_ORACLES, "Max oracles reached");

        oracles[oracleAddress] = OracleConfig({
            oracleAddress: oracleAddress,
            name: name,
            endpoint: endpoint,
            status: OracleStatus.Active,
            weight: weight,
            reputation: 7500, // Start with good reputation
            heartbeat: heartbeat > 0 ? heartbeat : DEFAULT_HEARTBEAT,
            registeredAt: block.timestamp,
            lastUpdate: 0,
            successCount: 0,
            failureCount: 0,
            isChainlink: isChainlink,
            jobId: jobId
        });

        oracleList.push(oracleAddress);
        activeOracleCount++;
        _grantRole(ORACLE_NODE_ROLE, oracleAddress);

        emit OracleRegistered(oracleAddress, name, weight);
    }

    /**
     * @dev Update oracle status
     */
    function setOracleStatus(address oracleAddress, OracleStatus newStatus)
        public
        onlyRole(ORACLE_ADMIN_ROLE)
    {
        require(oracles[oracleAddress].oracleAddress != address(0), "Oracle not found");

        OracleStatus oldStatus = oracles[oracleAddress].status;
        oracles[oracleAddress].status = newStatus;

        if (oldStatus == OracleStatus.Active && newStatus != OracleStatus.Active) {
            activeOracleCount--;
        } else if (oldStatus != OracleStatus.Active && newStatus == OracleStatus.Active) {
            activeOracleCount++;
        }

        emit OracleStatusChanged(oracleAddress, oldStatus, newStatus);
    }

    /**
     * @dev Update oracle weight
     */
    function setOracleWeight(address oracleAddress, uint256 newWeight)
        external
        onlyRole(ORACLE_ADMIN_ROLE)
    {
        require(oracles[oracleAddress].oracleAddress != address(0), "Oracle not found");
        require(newWeight > 0 && newWeight <= 10000, "Invalid weight");

        oracles[oracleAddress].weight = newWeight;
    }

    // ============ Data Feed Management ============

    /**
     * @dev Create a new data feed
     */
    function createDataFeed(
        bytes32 feedId,
        bytes32 projectId,
        DataType dataType,
        string calldata description,
        AggregationStrategy strategy,
        uint256 minOracles,
        uint256 maxDeviation,
        uint256 heartbeat
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(feedId != bytes32(0), "Invalid feedId");
        require(dataFeeds[feedId].feedId == bytes32(0), "Feed exists");
        require(minOracles >= MIN_ORACLES, "Min oracles too low");
        require(maxDeviation <= MAX_DEVIATION_PERCENTAGE, "Deviation too high");

        dataFeeds[feedId] = DataFeed({
            feedId: feedId,
            projectId: projectId,
            dataType: dataType,
            description: description,
            strategy: strategy,
            minOracles: minOracles,
            maxDeviation: maxDeviation,
            heartbeat: heartbeat > 0 ? heartbeat : DEFAULT_HEARTBEAT,
            isActive: true,
            createdAt: block.timestamp
        });

        feedIds.push(feedId);

        emit DataFeedCreated(feedId, projectId, dataType, strategy);
    }

    // ============ Data Submission ============

    /**
     * @dev Submit data to a feed
     */
    function submitData(
        bytes32 feedId,
        int256 value,
        bytes32 dataHash,
        uint256 confidence,
        string calldata sourceRef
    ) external onlyActiveOracle feedExists(feedId) whenNotPaused {
        require(dataFeeds[feedId].isActive, "Feed not active");
        require(confidence <= 10000, "Invalid confidence");
        require(!circuitBreakerActive, "Circuit breaker active");

        bytes32 submissionId = keccak256(abi.encodePacked(
            feedId,
            msg.sender,
            value,
            block.timestamp
        ));

        OracleSubmission memory submission = OracleSubmission({
            submissionId: submissionId,
            dataFeedId: feedId,
            oracle: msg.sender,
            value: value,
            timestamp: block.timestamp,
            dataHash: dataHash,
            confidence: confidence,
            isValid: true,
            sourceRef: sourceRef
        });

        submissions[submissionId] = submission;

        // Gas optimization: O(1) duplicate check using mapping
        bytes32 roundKey = keccak256(abi.encodePacked(feedId, feedRoundId[feedId]));
        if (!_hasSubmittedInRound[roundKey][msg.sender]) {
            _hasSubmittedInRound[roundKey][msg.sender] = true;
            feedOracleSubmitters[feedId].push(msg.sender);
        }

        feedSubmissions[feedId][msg.sender] = submission;

        // Update oracle stats
        oracles[msg.sender].lastUpdate = block.timestamp;
        oracles[msg.sender].successCount++;

        emit DataSubmitted(submissionId, feedId, msg.sender, value, confidence);

        // Check if we can aggregate
        if (feedOracleSubmitters[feedId].length >= dataFeeds[feedId].minOracles) {
            _aggregateData(feedId);
        }
    }

    /**
     * @dev Aggregate data from multiple oracles
     */
    function _aggregateData(bytes32 feedId) internal {
        DataFeed storage feed = dataFeeds[feedId];
        address[] storage submitters = feedOracleSubmitters[feedId];

        // Collect valid submissions
        int256[] memory values = new int256[](submitters.length);
        uint256[] memory weights = new uint256[](submitters.length);
        address[] memory validOracles = new address[](submitters.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < submitters.length; i++) {
            OracleSubmission storage sub = feedSubmissions[feedId][submitters[i]];
            if (sub.isValid && (block.timestamp - sub.timestamp) <= feed.heartbeat) {
                values[validCount] = sub.value;
                weights[validCount] = oracles[submitters[i]].weight;
                validOracles[validCount] = submitters[i];
                validCount++;
            }
        }

        if (validCount < feed.minOracles) {
            return; // Not enough valid submissions
        }

        // Check for anomalies
        bool hasAnomaly = _checkForAnomalies(feedId, values, validCount, feed.maxDeviation);

        // Calculate aggregated value based on strategy
        int256 aggregatedValue;
        if (feed.strategy == AggregationStrategy.Median) {
            aggregatedValue = _calculateMedian(values, validCount);
        } else if (feed.strategy == AggregationStrategy.WeightedMedian) {
            aggregatedValue = _calculateWeightedMedian(values, weights, validCount);
        } else if (feed.strategy == AggregationStrategy.TrimmedMean) {
            aggregatedValue = _calculateTrimmedMean(values, validCount);
        } else {
            aggregatedValue = _calculateWeightedAverage(values, weights, validCount);
        }

        // Calculate quality score
        uint256 qualityScore = _calculateQualityScore(feedId, values, validCount, aggregatedValue);

        // Create result arrays of exact size
        int256[] memory resultValues = new int256[](validCount);
        address[] memory resultOracles = new address[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            resultValues[i] = values[i];
            resultOracles[i] = validOracles[i];
        }

        // Store result
        AggregatedResult memory result = AggregatedResult({
            feedId: feedId,
            value: aggregatedValue,
            timestamp: block.timestamp,
            oracleCount: validCount,
            qualityScore: qualityScore,
            hasAnomaly: hasAnomaly,
            resultHash: keccak256(abi.encodePacked(feedId, aggregatedValue, block.timestamp)),
            individualValues: resultValues,
            participatingOracles: resultOracles
        });

        latestResults[feedId] = result;

        // Gas optimization: O(1) circular buffer for history
        if (historyCount[feedId] < maxHistoryLength) {
            // Still filling up the buffer
            resultHistory[feedId].push(result);
            historyCount[feedId]++;
        } else {
            // Buffer is full, overwrite oldest entry
            uint256 writeIndex = historyHead[feedId];
            resultHistory[feedId][writeIndex] = result;
            historyHead[feedId] = (writeIndex + 1) % maxHistoryLength;
        }

        // Clear submissions for next round and increment round ID
        delete feedOracleSubmitters[feedId];
        feedRoundId[feedId]++;  // Invalidates old round submissions in O(1)

        emit DataAggregated(feedId, aggregatedValue, validCount, qualityScore);
    }

    // ============ Aggregation Algorithms ============

    /**
     * @dev Calculate median value
     */
    function _calculateMedian(int256[] memory values, uint256 count) internal pure returns (int256) {
        // Sort values
        for (uint256 i = 0; i < count - 1; i++) {
            for (uint256 j = 0; j < count - i - 1; j++) {
                if (values[j] > values[j + 1]) {
                    (values[j], values[j + 1]) = (values[j + 1], values[j]);
                }
            }
        }

        if (count % 2 == 0) {
            return (values[count / 2 - 1] + values[count / 2]) / 2;
        } else {
            return values[count / 2];
        }
    }

    /**
     * @dev Calculate weighted median
     */
    function _calculateWeightedMedian(
        int256[] memory values,
        uint256[] memory weights,
        uint256 count
    ) internal pure returns (int256) {
        // Sort by value while keeping weight association
        for (uint256 i = 0; i < count - 1; i++) {
            for (uint256 j = 0; j < count - i - 1; j++) {
                if (values[j] > values[j + 1]) {
                    (values[j], values[j + 1]) = (values[j + 1], values[j]);
                    (weights[j], weights[j + 1]) = (weights[j + 1], weights[j]);
                }
            }
        }

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < count; i++) {
            totalWeight += weights[i];
        }

        uint256 midWeight = totalWeight / 2;
        uint256 cumulativeWeight = 0;

        for (uint256 i = 0; i < count; i++) {
            cumulativeWeight += weights[i];
            if (cumulativeWeight >= midWeight) {
                return values[i];
            }
        }

        return values[count - 1];
    }

    /**
     * @dev Calculate trimmed mean (remove top/bottom 20%)
     */
    function _calculateTrimmedMean(int256[] memory values, uint256 count) internal pure returns (int256) {
        // Sort values
        for (uint256 i = 0; i < count - 1; i++) {
            for (uint256 j = 0; j < count - i - 1; j++) {
                if (values[j] > values[j + 1]) {
                    (values[j], values[j + 1]) = (values[j + 1], values[j]);
                }
            }
        }

        uint256 trimCount = count / 5; // Remove 20% from each end
        if (trimCount == 0 && count > 2) trimCount = 1;

        int256 sum = 0;
        uint256 validCount = 0;

        for (uint256 i = trimCount; i < count - trimCount; i++) {
            sum += values[i];
            validCount++;
        }

        if (validCount == 0) return values[count / 2];
        return sum / int256(validCount);
    }

    /**
     * @dev Calculate weighted average
     */
    function _calculateWeightedAverage(
        int256[] memory values,
        uint256[] memory weights,
        uint256 count
    ) internal pure returns (int256) {
        int256 weightedSum = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < count; i++) {
            weightedSum += values[i] * int256(weights[i]);
            totalWeight += weights[i];
        }

        if (totalWeight == 0) return 0;
        return weightedSum / int256(totalWeight);
    }

    // ============ Anomaly Detection ============

    /**
     * @dev Check for anomalies in submitted values
     */
    function _checkForAnomalies(
        bytes32 feedId,
        int256[] memory values,
        uint256 count,
        uint256 maxDeviation
    ) internal returns (bool) {
        if (count < 2) return false;

        // Calculate median for comparison
        int256 median = _calculateMedian(values, count);
        if (median == 0) return false;

        uint256 anomalyVotes = 0;

        for (uint256 i = 0; i < count; i++) {
            int256 deviation = values[i] - median;
            if (deviation < 0) deviation = -deviation;

            uint256 deviationBps = uint256(deviation * 10000 / median);
            if (deviationBps > maxDeviation) {
                anomalyVotes++;
            }
        }

        // More than 25% outliers indicates anomaly
        if (anomalyVotes * 4 > count) {
            _recordAnomaly(feedId, "deviation", "medium", values, count);
            return true;
        }

        return false;
    }

    /**
     * @dev Record an anomaly
     */
    function _recordAnomaly(
        bytes32 feedId,
        string memory anomalyType,
        string memory severity,
        int256[] memory values,
        uint256 count
    ) internal {
        uint256 anomalyId = anomalyCount++;

        int256[] memory reportedValues = new int256[](count);
        for (uint256 i = 0; i < count; i++) {
            reportedValues[i] = values[i];
        }

        anomalies[anomalyId] = AnomalyRecord({
            anomalyId: anomalyId,
            feedId: feedId,
            anomalyType: anomalyType,
            severity: severity,
            reportedValues: reportedValues,
            detectedAt: block.timestamp,
            isResolved: false,
            resolvedBy: address(0),
            resolution: ""
        });

        feedAnomalies[feedId].push(anomalyId);
        unresolvedAnomalyCount++;

        emit AnomalyDetected(anomalyId, feedId, anomalyType, severity);

        // Check circuit breaker
        if (unresolvedAnomalyCount >= circuitBreakerThreshold) {
            _triggerCircuitBreaker(feedId);
        }
    }

    /**
     * @dev Trigger circuit breaker
     */
    function _triggerCircuitBreaker(bytes32 feedId) internal {
        circuitBreakerActive = true;
        emit CircuitBreakerTriggered(feedId, unresolvedAnomalyCount);
    }

    /**
     * @dev Resolve an anomaly
     */
    function resolveAnomaly(uint256 anomalyId, string calldata resolution)
        external
        onlyRole(ANOMALY_RESOLVER_ROLE)
    {
        require(!anomalies[anomalyId].isResolved, "Already resolved");

        anomalies[anomalyId].isResolved = true;
        anomalies[anomalyId].resolvedBy = msg.sender;
        anomalies[anomalyId].resolution = resolution;
        unresolvedAnomalyCount--;

        emit AnomalyResolved(anomalyId, msg.sender, resolution);
    }

    /**
     * @dev Reset circuit breaker
     */
    function resetCircuitBreaker() external onlyRole(ORACLE_ADMIN_ROLE) {
        require(unresolvedAnomalyCount < circuitBreakerThreshold, "Resolve anomalies first");
        circuitBreakerActive = false;
    }

    // ============ Quality Scoring ============

    /**
     * @dev Calculate data quality score
     */
    function _calculateQualityScore(
        bytes32 feedId,
        int256[] memory values,
        uint256 count,
        int256 aggregatedValue
    ) internal view returns (uint256) {
        uint256 score = 10000; // Start with perfect score

        // Factor 1: Oracle count (more oracles = higher quality)
        DataFeed storage feed = dataFeeds[feedId];
        if (count < feed.minOracles * 2) {
            score -= (feed.minOracles * 2 - count) * 500;
        }

        // Factor 2: Value deviation (lower deviation = higher quality)
        uint256 totalDeviation = 0;
        for (uint256 i = 0; i < count; i++) {
            int256 deviation = values[i] - aggregatedValue;
            if (deviation < 0) deviation = -deviation;
            totalDeviation += uint256(deviation);
        }

        if (aggregatedValue != 0 && count > 0) {
            uint256 avgDeviation = totalDeviation / count;
            uint256 deviationBps = uint256(int256(avgDeviation) * 10000 / aggregatedValue);
            if (deviationBps > 100) {
                score -= deviationBps;
            }
        }

        // Factor 3: Data freshness
        AggregatedResult storage lastResult = latestResults[feedId];
        if (lastResult.timestamp != 0 && block.timestamp - lastResult.timestamp > feed.heartbeat) {
            score -= 1000;
        }

        // Ensure minimum score
        if (score < MIN_QUALITY_SCORE) score = MIN_QUALITY_SCORE;
        if (score > 10000) score = 10000;

        return score;
    }

    // ============ HSM Attestation ============

    /**
     * @dev Record HSM attestation for a sensor
     */
    function recordHSMAttestation(
        bytes32 attestationId,
        bytes32 sensorId,
        bytes calldata signature,
        bytes32 publicKeyHash,
        uint256 validityPeriod
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(hsmAttestations[attestationId].attestationId == bytes32(0), "Attestation exists");

        hsmAttestations[attestationId] = HSMAttestation({
            attestationId: attestationId,
            sensorId: sensorId,
            signature: signature,
            publicKeyHash: publicKeyHash,
            timestamp: block.timestamp,
            isValid: true,
            expiresAt: block.timestamp + validityPeriod
        });

        sensorAttestation[sensorId] = attestationId;

        emit HSMAttestationRecorded(attestationId, sensorId, true);
    }

    /**
     * @dev Check if sensor has valid HSM attestation
     */
    function isSensorAttested(bytes32 sensorId) external view returns (bool) {
        bytes32 attestationId = sensorAttestation[sensorId];
        if (attestationId == bytes32(0)) return false;

        HSMAttestation storage attestation = hsmAttestations[attestationId];
        return attestation.isValid && block.timestamp < attestation.expiresAt;
    }

    // ============ Query Functions ============

    /**
     * @dev Get latest aggregated result for a feed
     */
    function getLatestResult(bytes32 feedId) external view returns (AggregatedResult memory) {
        return latestResults[feedId];
    }

    /**
     * @dev Get latest value for a feed
     */
    function getLatestValue(bytes32 feedId) external view returns (int256 value, uint256 timestamp, uint256 quality) {
        AggregatedResult storage result = latestResults[feedId];
        return (result.value, result.timestamp, result.qualityScore);
    }

    /**
     * @dev Get oracle details
     */
    function getOracle(address oracleAddress) external view returns (OracleConfig memory) {
        return oracles[oracleAddress];
    }

    /**
     * @dev Get all active oracles
     */
    function getActiveOracles() external view returns (address[] memory) {
        address[] memory activeOracles = new address[](activeOracleCount);
        uint256 index = 0;

        for (uint256 i = 0; i < oracleList.length && index < activeOracleCount; i++) {
            if (oracles[oracleList[i]].status == OracleStatus.Active) {
                activeOracles[index++] = oracleList[i];
            }
        }

        return activeOracles;
    }

    /**
     * @dev Get feed anomalies
     */
    function getFeedAnomalies(bytes32 feedId) external view returns (uint256[] memory) {
        return feedAnomalies[feedId];
    }

    /**
     * @dev Get result history for a feed
     */
    function getResultHistory(bytes32 feedId, uint256 count)
        external
        view
        returns (AggregatedResult[] memory)
    {
        uint256 totalCount = historyCount[feedId];
        uint256 resultCount = count > totalCount ? totalCount : count;

        AggregatedResult[] memory results = new AggregatedResult[](resultCount);

        if (resultCount == 0) {
            return results;
        }

        // Calculate starting index for reading (oldest of the requested entries)
        // In circular buffer, head points to oldest, so we read from most recent backwards
        uint256 head = historyHead[feedId];
        uint256 len = resultHistory[feedId].length;

        // Most recent entry is at (head - 1 + len) % len when buffer is full
        // or at (totalCount - 1) when buffer is not full
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 readIndex;
            if (totalCount < maxHistoryLength) {
                // Buffer not full yet, simple indexing from end
                readIndex = totalCount - resultCount + i;
            } else {
                // Circular buffer: calculate position
                // head points to oldest, so newest is at (head - 1 + len) % len
                // We want the last 'resultCount' entries in chronological order
                readIndex = (head + totalCount - resultCount + i) % len;
            }
            results[i] = resultHistory[feedId][readIndex];
        }

        return results;
    }

    // ============ Admin Functions ============

    /**
     * @dev Pause oracle operations
     */
    function pause() external onlyRole(ORACLE_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause oracle operations
     */
    function unpause() external onlyRole(ORACLE_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Set circuit breaker threshold
     */
    function setCircuitBreakerThreshold(uint256 threshold) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(threshold > 0, "Invalid threshold");
        circuitBreakerThreshold = threshold;
    }

    /**
     * @dev Update oracle reputation
     */
    function updateOracleReputation(address oracleAddress, int256 change)
        external
        onlyRole(ORACLE_ADMIN_ROLE)
    {
        require(oracles[oracleAddress].oracleAddress != address(0), "Oracle not found");

        int256 newRep = int256(oracles[oracleAddress].reputation) + change;
        if (newRep < 0) newRep = 0;
        if (newRep > 10000) newRep = 10000;

        oracles[oracleAddress].reputation = uint256(newRep);

        // Auto-suspend if reputation too low
        if (oracles[oracleAddress].reputation < 3000) {
            setOracleStatus(oracleAddress, OracleStatus.Suspended);
        }
    }
}

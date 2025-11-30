// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title SMARTDataRegistry
 * @dev Implements SMART Protocol data governance requirements for carbon credit data.
 *
 * SMART Protocol Requirements Implemented:
 * 1. Physical Location Governance - All data tied to geographic coordinates
 * 2. Temporal Binding - Production/measurement period tracking
 * 3. Corroboration/Verification - Multi-party verification without conflict of interest
 * 4. Event Sequencing - Enforced governance workflow
 * 5. Restatement Processes - Traceable corrections with justification
 * 6. Aggregation Processes - Persisted assumptions and constants
 * 7. Data Custody - Clear entity responsibility for data quality
 * 8. Digital Lineage - Integrity of data relationships
 */
contract SMARTDataRegistry is AccessControl {
    using ECDSA for bytes32;

    bytes32 public constant DATA_CUSTODIAN_ROLE = keccak256("DATA_CUSTODIAN_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant AGGREGATOR_ROLE = keccak256("AGGREGATOR_ROLE");

    // ============ SMART Protocol Data Structures ============

    /// @notice Physical location governance (Requirement 1)
    struct GeoLocation {
        int256 latitude;      // Latitude * 1e6 (6 decimal precision)
        int256 longitude;     // Longitude * 1e6
        string country;
        string region;
        string siteIdentifier;
        bool isValid;
    }

    /// @notice Temporal binding for data (Requirement 2)
    struct TemporalPeriod {
        uint256 startTimestamp;
        uint256 endTimestamp;
        string periodType;    // "production", "measurement", "verification", "reporting"
        bool isBound;
    }

    /// @notice Verification record with conflict of interest check (Requirement 3)
    struct VerificationRecord {
        address verifier;
        bytes32 verifierOrgId;
        uint256 timestamp;
        string verificationHash;
        bool hasConflictOfInterest;
        string conflictDeclaration;
        bool isValid;
    }

    /// @notice Event sequence for governance workflow (Requirement 4)
    struct GovernanceEvent {
        uint256 eventId;
        uint256 timestamp;
        string eventType;
        address actor;
        bytes32 previousEventHash;
        bytes32 eventDataHash;
        string description;
    }

    /// @notice Restatement record for data corrections (Requirement 5)
    struct Restatement {
        uint256 restatementId;
        uint256 timestamp;
        bytes32 originalDataHash;
        bytes32 correctedDataHash;
        string justification;
        address authorizedBy;
        bool isApproved;
    }

    /// @notice Aggregation parameters (Requirement 6)
    struct AggregationParams {
        bytes32 aggregationId;
        string methodology;
        string[] assumptions;
        mapping(string => string) constants;
        string[] constantKeys;
        uint256 createdAt;
        uint256 lastUpdated;
        bool isActive;
    }

    /// @notice Data custody agreement (Requirement 7)
    struct DataCustody {
        address custodian;
        bytes32 organizationId;
        string organizationName;
        string responsibilityScope;
        uint256 effectiveDate;
        uint256 expirationDate;
        string agreementHash;    // IPFS hash of full agreement
        bool isActive;
    }

    /// @notice Data lineage record (Requirement 8)
    struct DataLineage {
        bytes32 dataId;
        bytes32 parentDataId;
        bytes32[] childDataIds;
        bytes32 sourceHash;
        uint256 createdAt;
        address creator;
        string transformationType;
        bool isRoot;
    }

    // ============ Storage ============

    // Project ID => GeoLocation
    mapping(bytes32 => GeoLocation) public projectLocations;
    
    // Data ID => Temporal Period
    mapping(bytes32 => TemporalPeriod) public temporalBindings;
    
    // Data ID => Verification Records
    mapping(bytes32 => VerificationRecord[]) public verifications;
    
    // Project ID => Governance Events
    mapping(bytes32 => GovernanceEvent[]) public governanceEvents;
    mapping(bytes32 => uint256) public eventSequenceNumber;
    
    // Data ID => Restatements
    mapping(bytes32 => Restatement[]) public restatements;
    uint256 public nextRestatementId;
    
    // Aggregation ID => Parameters (using separate mappings due to nested mapping)
    mapping(bytes32 => bytes32) public aggregationIds;
    mapping(bytes32 => string) public aggregationMethodology;
    mapping(bytes32 => string[]) public aggregationAssumptions;
    mapping(bytes32 => mapping(string => string)) public aggregationConstants;
    mapping(bytes32 => string[]) public aggregationConstantKeys;
    mapping(bytes32 => bool) public aggregationActive;
    
    // Project ID => Data Custody
    mapping(bytes32 => DataCustody) public dataCustody;
    
    // Data ID => Lineage
    mapping(bytes32 => DataLineage) public dataLineage;
    
    // Conflict of interest registry: verifierOrg => projectOrg => hasConflict
    mapping(bytes32 => mapping(bytes32 => bool)) public conflictRegistry;

    // ============ Events ============

    event LocationRegistered(bytes32 indexed projectId, int256 latitude, int256 longitude, string country);
    event TemporalPeriodBound(bytes32 indexed dataId, uint256 startTime, uint256 endTime, string periodType);
    event DataVerified(bytes32 indexed dataId, address indexed verifier, string verificationHash);
    event GovernanceEventRecorded(bytes32 indexed projectId, uint256 eventId, string eventType);
    event DataRestated(bytes32 indexed dataId, uint256 restatementId, string justification);
    event AggregationParamsSet(bytes32 indexed aggregationId, string methodology);
    event CustodyAssigned(bytes32 indexed projectId, address indexed custodian, string organizationName);
    event LineageRecorded(bytes32 indexed dataId, bytes32 indexed parentDataId, string transformationType);
    event ConflictOfInterestDeclared(bytes32 indexed verifierOrg, bytes32 indexed projectOrg);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DATA_CUSTODIAN_ROLE, msg.sender);
    }

    // ============ Requirement 1: Physical Location Governance ============

    /**
     * @dev Register physical location for a project
     */
    function registerLocation(
        bytes32 projectId,
        int256 latitude,
        int256 longitude,
        string calldata country,
        string calldata region,
        string calldata siteIdentifier
    ) external onlyRole(DATA_CUSTODIAN_ROLE) {
        require(projectId != bytes32(0), "Invalid projectId");
        require(latitude >= -90000000 && latitude <= 90000000, "Invalid latitude");
        require(longitude >= -180000000 && longitude <= 180000000, "Invalid longitude");
        require(bytes(country).length > 0, "Country required");

        projectLocations[projectId] = GeoLocation({
            latitude: latitude,
            longitude: longitude,
            country: country,
            region: region,
            siteIdentifier: siteIdentifier,
            isValid: true
        });

        emit LocationRegistered(projectId, latitude, longitude, country);
    }

    /**
     * @dev Verify data has valid location governance
     */
    function hasValidLocation(bytes32 projectId) external view returns (bool) {
        return projectLocations[projectId].isValid;
    }

    // ============ Requirement 2: Temporal Binding ============

    /**
     * @dev Bind data to a temporal period
     */
    function bindTemporalPeriod(
        bytes32 dataId,
        uint256 startTimestamp,
        uint256 endTimestamp,
        string calldata periodType
    ) external onlyRole(DATA_CUSTODIAN_ROLE) {
        require(dataId != bytes32(0), "Invalid dataId");
        require(endTimestamp >= startTimestamp, "Invalid time range");
        require(bytes(periodType).length > 0, "Period type required");

        temporalBindings[dataId] = TemporalPeriod({
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            periodType: periodType,
            isBound: true
        });

        emit TemporalPeriodBound(dataId, startTimestamp, endTimestamp, periodType);
    }

    /**
     * @dev Check if data is temporally bound
     */
    function isTemporallyBound(bytes32 dataId) external view returns (bool) {
        return temporalBindings[dataId].isBound;
    }

    // ============ Requirement 3: Corroboration/Verification ============

    /**
     * @dev Declare conflict of interest between organizations
     */
    function declareConflictOfInterest(
        bytes32 verifierOrgId,
        bytes32 projectOrgId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        conflictRegistry[verifierOrgId][projectOrgId] = true;
        emit ConflictOfInterestDeclared(verifierOrgId, projectOrgId);
    }

    /**
     * @dev Record verification with conflict of interest check
     */
    function recordVerification(
        bytes32 dataId,
        bytes32 verifierOrgId,
        bytes32 projectOrgId,
        string calldata verificationHash,
        string calldata conflictDeclaration
    ) external onlyRole(VERIFIER_ROLE) {
        require(dataId != bytes32(0), "Invalid dataId");
        require(bytes(verificationHash).length > 0, "Verification hash required");

        bool hasConflict = conflictRegistry[verifierOrgId][projectOrgId];
        
        // If there's a conflict, a declaration must be provided
        if (hasConflict) {
            require(bytes(conflictDeclaration).length > 0, "Conflict declaration required");
        }

        verifications[dataId].push(VerificationRecord({
            verifier: msg.sender,
            verifierOrgId: verifierOrgId,
            timestamp: block.timestamp,
            verificationHash: verificationHash,
            hasConflictOfInterest: hasConflict,
            conflictDeclaration: conflictDeclaration,
            isValid: true
        }));

        emit DataVerified(dataId, msg.sender, verificationHash);
    }

    /**
     * @dev Get verification count for data
     */
    function getVerificationCount(bytes32 dataId) external view returns (uint256) {
        return verifications[dataId].length;
    }

    /**
     * @dev Check if data has been verified without conflict
     */
    function hasConflictFreeVerification(bytes32 dataId) external view returns (bool) {
        VerificationRecord[] memory records = verifications[dataId];
        for (uint256 i = 0; i < records.length; i++) {
            if (records[i].isValid && !records[i].hasConflictOfInterest) {
                return true;
            }
        }
        return false;
    }

    // ============ Requirement 4: Event Sequencing ============

    /**
     * @dev Record governance event with proper sequencing
     */
    function recordGovernanceEvent(
        bytes32 projectId,
        string calldata eventType,
        bytes32 eventDataHash,
        string calldata description
    ) external onlyRole(DATA_CUSTODIAN_ROLE) returns (uint256 eventId) {
        require(projectId != bytes32(0), "Invalid projectId");

        eventId = eventSequenceNumber[projectId];
        
        bytes32 previousHash = bytes32(0);
        if (eventId > 0) {
            GovernanceEvent memory prevEvent = governanceEvents[projectId][eventId - 1];
            previousHash = keccak256(abi.encodePacked(
                prevEvent.eventId,
                prevEvent.timestamp,
                prevEvent.eventDataHash
            ));
        }

        governanceEvents[projectId].push(GovernanceEvent({
            eventId: eventId,
            timestamp: block.timestamp,
            eventType: eventType,
            actor: msg.sender,
            previousEventHash: previousHash,
            eventDataHash: eventDataHash,
            description: description
        }));

        eventSequenceNumber[projectId] = eventId + 1;

        emit GovernanceEventRecorded(projectId, eventId, eventType);
    }

    /**
     * @dev Verify event chain integrity
     */
    function verifyEventChain(bytes32 projectId) external view returns (bool) {
        GovernanceEvent[] memory events = governanceEvents[projectId];
        if (events.length == 0) return true;

        for (uint256 i = 1; i < events.length; i++) {
            bytes32 expectedPrevHash = keccak256(abi.encodePacked(
                events[i-1].eventId,
                events[i-1].timestamp,
                events[i-1].eventDataHash
            ));
            if (events[i].previousEventHash != expectedPrevHash) {
                return false;
            }
        }
        return true;
    }

    // ============ Requirement 5: Restatement Processes ============

    /**
     * @dev Submit a data restatement with justification
     */
    function submitRestatement(
        bytes32 dataId,
        bytes32 originalDataHash,
        bytes32 correctedDataHash,
        string calldata justification
    ) external onlyRole(DATA_CUSTODIAN_ROLE) returns (uint256 restatementId) {
        require(dataId != bytes32(0), "Invalid dataId");
        require(bytes(justification).length > 0, "Justification required");
        require(originalDataHash != correctedDataHash, "Data must be different");

        restatementId = nextRestatementId;
        nextRestatementId++;

        restatements[dataId].push(Restatement({
            restatementId: restatementId,
            timestamp: block.timestamp,
            originalDataHash: originalDataHash,
            correctedDataHash: correctedDataHash,
            justification: justification,
            authorizedBy: msg.sender,
            isApproved: false
        }));

        emit DataRestated(dataId, restatementId, justification);
    }

    /**
     * @dev Approve a restatement (requires different authority)
     */
    function approveRestatement(
        bytes32 dataId,
        uint256 restatementId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Restatement[] storage dataRestatements = restatements[dataId];
        for (uint256 i = 0; i < dataRestatements.length; i++) {
            if (dataRestatements[i].restatementId == restatementId) {
                require(dataRestatements[i].authorizedBy != msg.sender, "Cannot self-approve");
                dataRestatements[i].isApproved = true;
                return;
            }
        }
        revert("Restatement not found");
    }

    // ============ Requirement 6: Aggregation Processes ============

    /**
     * @dev Set aggregation parameters with assumptions and constants
     */
    function setAggregationParams(
        bytes32 aggregationId,
        string calldata methodology,
        string[] calldata assumptions,
        string[] calldata constantKeys,
        string[] calldata constantValues
    ) external onlyRole(AGGREGATOR_ROLE) {
        require(aggregationId != bytes32(0), "Invalid aggregationId");
        require(constantKeys.length == constantValues.length, "Keys/values mismatch");

        aggregationIds[aggregationId] = aggregationId;
        aggregationMethodology[aggregationId] = methodology;
        aggregationAssumptions[aggregationId] = assumptions;
        aggregationConstantKeys[aggregationId] = constantKeys;
        
        for (uint256 i = 0; i < constantKeys.length; i++) {
            aggregationConstants[aggregationId][constantKeys[i]] = constantValues[i];
        }
        
        aggregationActive[aggregationId] = true;

        emit AggregationParamsSet(aggregationId, methodology);
    }

    /**
     * @dev Get aggregation constant value
     */
    function getAggregationConstant(
        bytes32 aggregationId,
        string calldata key
    ) external view returns (string memory) {
        return aggregationConstants[aggregationId][key];
    }

    // ============ Requirement 7: Data Custody ============

    /**
     * @dev Assign data custody responsibility
     */
    function assignCustody(
        bytes32 projectId,
        address custodian,
        bytes32 organizationId,
        string calldata organizationName,
        string calldata responsibilityScope,
        uint256 expirationDate,
        string calldata agreementHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(projectId != bytes32(0), "Invalid projectId");
        require(custodian != address(0), "Invalid custodian");
        require(expirationDate > block.timestamp, "Expiration must be future");

        dataCustody[projectId] = DataCustody({
            custodian: custodian,
            organizationId: organizationId,
            organizationName: organizationName,
            responsibilityScope: responsibilityScope,
            effectiveDate: block.timestamp,
            expirationDate: expirationDate,
            agreementHash: agreementHash,
            isActive: true
        });

        // Grant custodian role
        _grantRole(DATA_CUSTODIAN_ROLE, custodian);

        emit CustodyAssigned(projectId, custodian, organizationName);
    }

    /**
     * @dev Check if custody is active and valid
     */
    function isCustodyValid(bytes32 projectId) external view returns (bool) {
        DataCustody memory custody = dataCustody[projectId];
        return custody.isActive && 
               block.timestamp >= custody.effectiveDate && 
               block.timestamp <= custody.expirationDate;
    }

    // ============ Requirement 8: Data Lineage ============

    /**
     * @dev Record data lineage
     */
    function recordLineage(
        bytes32 dataId,
        bytes32 parentDataId,
        bytes32 sourceHash,
        string calldata transformationType
    ) external onlyRole(DATA_CUSTODIAN_ROLE) {
        require(dataId != bytes32(0), "Invalid dataId");

        bool isRoot = (parentDataId == bytes32(0));

        dataLineage[dataId] = DataLineage({
            dataId: dataId,
            parentDataId: parentDataId,
            childDataIds: new bytes32[](0),
            sourceHash: sourceHash,
            createdAt: block.timestamp,
            creator: msg.sender,
            transformationType: transformationType,
            isRoot: isRoot
        });

        // Update parent's children if not root
        if (!isRoot) {
            dataLineage[parentDataId].childDataIds.push(dataId);
        }

        emit LineageRecorded(dataId, parentDataId, transformationType);
    }

    /**
     * @dev Verify complete lineage chain to root
     */
    function verifyLineageToRoot(bytes32 dataId) external view returns (bool, bytes32[] memory) {
        bytes32[] memory chain = new bytes32[](100); // Max depth
        uint256 depth = 0;
        bytes32 current = dataId;

        while (current != bytes32(0) && depth < 100) {
            chain[depth] = current;
            DataLineage memory lineage = dataLineage[current];
            
            if (lineage.dataId == bytes32(0)) {
                return (false, chain); // Broken chain
            }
            
            if (lineage.isRoot) {
                // Resize array to actual length
                bytes32[] memory result = new bytes32[](depth + 1);
                for (uint256 i = 0; i <= depth; i++) {
                    result[i] = chain[i];
                }
                return (true, result);
            }
            
            current = lineage.parentDataId;
            depth++;
        }

        return (false, chain);
    }

    // ============ Comprehensive Compliance Check ============

    /**
     * @dev Check if all SMART Protocol requirements are met for a project
     */
    function checkSMARTCompliance(bytes32 projectId, bytes32 dataId) 
        external 
        view 
        returns (
            bool locationValid,
            bool temporallyBound,
            bool hasVerification,
            bool custodyValid,
            bool hasLineage,
            bool isCompliant
        ) 
    {
        locationValid = projectLocations[projectId].isValid;
        temporallyBound = temporalBindings[dataId].isBound;
        hasVerification = verifications[dataId].length > 0;
        
        DataCustody memory custody = dataCustody[projectId];
        custodyValid = custody.isActive && 
                       block.timestamp >= custody.effectiveDate && 
                       block.timestamp <= custody.expirationDate;
        
        hasLineage = dataLineage[dataId].dataId != bytes32(0);
        
        isCompliant = locationValid && temporallyBound && hasVerification && custodyValid && hasLineage;
    }
}

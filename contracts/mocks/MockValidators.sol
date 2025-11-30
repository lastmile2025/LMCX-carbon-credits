// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockISO14064Validator
 * @dev Mock implementation for testing
 */
contract MockISO14064Validator {
    mapping(bytes32 => bool) public projectCompliance;
    mapping(bytes32 => bool) public projectVerification;
    mapping(bytes32 => uint256) public complianceScores;

    function setProjectCompliant(bytes32 projectId, bool compliant) external {
        projectCompliance[projectId] = compliant;
    }

    function setProjectVerified(bytes32 projectId, bool verified) external {
        projectVerification[projectId] = verified;
    }

    function setComplianceScore(bytes32 projectId, uint256 score) external {
        complianceScores[projectId] = score;
    }

    function isProjectVerified(bytes32 projectId) external view returns (bool) {
        return projectVerification[projectId];
    }

    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return projectCompliance[projectId];
    }

    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return complianceScores[projectId];
    }
}

/**
 * @title MockOGMP2Validator
 * @dev Mock implementation for testing
 */
contract MockOGMP2Validator {
    mapping(bytes32 => bool) public projectCompliance;
    mapping(bytes32 => bool) public goldStandard;
    mapping(bytes32 => uint256) public complianceScores;

    function setProjectCompliant(bytes32 projectId, bool compliant) external {
        projectCompliance[projectId] = compliant;
    }

    function setGoldStandard(bytes32 projectId, bool isGold) external {
        goldStandard[projectId] = isGold;
    }

    function setComplianceScore(bytes32 projectId, uint256 score) external {
        complianceScores[projectId] = score;
    }

    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return projectCompliance[projectId];
    }

    function meetsGoldStandard(bytes32 projectId) external view returns (bool) {
        return goldStandard[projectId];
    }

    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return complianceScores[projectId];
    }
}

/**
 * @title MockISO14065Verifier
 * @dev Mock implementation for testing
 */
contract MockISO14065Verifier {
    mapping(bytes32 => bool) public projectVerification;

    function setProjectVerified(bytes32 projectId, bool verified) external {
        projectVerification[projectId] = verified;
    }

    function isProjectVerified(bytes32 projectId) external view returns (bool) {
        return projectVerification[projectId];
    }
}

/**
 * @title MockCORSIACompliance
 * @dev Mock implementation for testing
 */
contract MockCORSIACompliance {
    mapping(bytes32 => bool) public projectEligibility;
    mapping(bytes32 => mapping(uint256 => bool)) public vintageEligibility;

    function setProjectEligible(bytes32 projectId, bool eligible) external {
        projectEligibility[projectId] = eligible;
    }

    function setVintageEligible(bytes32 projectId, uint256 year, bool eligible) external {
        vintageEligibility[projectId][year] = eligible;
    }

    function isProjectEligible(bytes32 projectId) external view returns (bool) {
        return projectEligibility[projectId];
    }

    function isVintageYearEligible(bytes32 projectId, uint256 compliancePeriod) external view returns (bool) {
        return vintageEligibility[projectId][compliancePeriod];
    }
}

/**
 * @title MockEPASubpartWValidator
 * @dev Mock implementation for testing
 */
contract MockEPASubpartWValidator {
    mapping(bytes32 => bool) public projectCompliance;
    mapping(bytes32 => uint256) public complianceScores;
    mapping(bytes32 => bool) public currentReports;

    function setProjectCompliant(bytes32 projectId, bool compliant) external {
        projectCompliance[projectId] = compliant;
    }

    function setComplianceScore(bytes32 projectId, uint256 score) external {
        complianceScores[projectId] = score;
    }

    function setHasCurrentReport(bytes32 projectId, bool hasReport) external {
        currentReports[projectId] = hasReport;
    }

    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return projectCompliance[projectId];
    }

    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return complianceScores[projectId];
    }

    function hasCurrentReport(bytes32 projectId) external view returns (bool) {
        return currentReports[projectId];
    }
}

/**
 * @title MockCDMAM0023Validator
 * @dev Mock implementation for testing
 */
contract MockCDMAM0023Validator {
    mapping(bytes32 => bool) public projectCompliance;
    mapping(bytes32 => mapping(uint256 => bool)) public vintageEligibility;
    mapping(bytes32 => uint256) public complianceScores;

    function setProjectCompliant(bytes32 projectId, bool compliant) external {
        projectCompliance[projectId] = compliant;
    }

    function setVintageEligible(bytes32 projectId, uint256 year, bool eligible) external {
        vintageEligibility[projectId][year] = eligible;
    }

    function setComplianceScore(bytes32 projectId, uint256 score) external {
        complianceScores[projectId] = score;
    }

    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return projectCompliance[projectId];
    }

    function isVintageEligible(bytes32 projectId, uint256 year) external view returns (bool) {
        return vintageEligibility[projectId][year];
    }

    function getComplianceScore(bytes32 projectId) external view returns (uint256) {
        return complianceScores[projectId];
    }
}

/**
 * @title MockOracleAggregator
 * @dev Mock implementation for testing circuit breaker
 */
contract MockOracleAggregator {
    bool public circuitBreakerActive;
    mapping(bytes32 => int256) public values;
    mapping(bytes32 => uint256) public timestamps;
    mapping(bytes32 => uint256) public qualities;

    function setCircuitBreaker(bool active) external {
        circuitBreakerActive = active;
    }

    function setLatestValue(bytes32 feedId, int256 value, uint256 timestamp, uint256 quality) external {
        values[feedId] = value;
        timestamps[feedId] = timestamp;
        qualities[feedId] = quality;
    }

    function getLatestValue(bytes32 feedId) external view returns (int256 value, uint256 timestamp, uint256 quality) {
        return (values[feedId], timestamps[feedId], qualities[feedId]);
    }
}

/**
 * @title MockVerificationRegistry
 * @dev Mock implementation for testing verification checks
 */
contract MockVerificationRegistry {
    mapping(bytes32 => bool) public creditVerified;
    mapping(bytes32 => uint8) public verificationStatus;
    mapping(bytes32 => uint256) public verifiedAt;
    mapping(bytes32 => uint256) public expiresAt;
    mapping(bytes32 => int256) public verifiedReductions;
    mapping(bytes32 => uint256) public signatureCount;

    function setCreditVerified(bytes32 creditTokenId, bool verified) external {
        creditVerified[creditTokenId] = verified;
    }

    function setVerificationStatus(
        bytes32 creditTokenId,
        uint8 _status,
        uint256 _verifiedAt,
        uint256 _expiresAt,
        int256 _verifiedReductions,
        uint256 _signatureCount
    ) external {
        verificationStatus[creditTokenId] = _status;
        verifiedAt[creditTokenId] = _verifiedAt;
        expiresAt[creditTokenId] = _expiresAt;
        verifiedReductions[creditTokenId] = _verifiedReductions;
        signatureCount[creditTokenId] = _signatureCount;
    }

    function isCreditVerified(bytes32 creditTokenId) external view returns (bool) {
        return creditVerified[creditTokenId];
    }

    function getCreditVerificationStatus(bytes32 creditTokenId) external view returns (
        uint8 status,
        uint256 _verifiedAt,
        uint256 _expiresAt,
        int256 _verifiedReductions,
        uint256 _signatureCount
    ) {
        return (
            verificationStatus[creditTokenId],
            verifiedAt[creditTokenId],
            expiresAt[creditTokenId],
            verifiedReductions[creditTokenId],
            signatureCount[creditTokenId]
        );
    }

    function recordCustodyTransfer(
        bytes32 creditTokenId,
        address from,
        address to,
        bytes32 transactionHash,
        string calldata custodyType
    ) external returns (bytes32) {
        // Mock implementation - just return a hash
        return keccak256(abi.encodePacked(creditTokenId, from, to, transactionHash, custodyType));
    }
}

/**
 * @title MockVintageTracker
 * @dev Mock implementation for testing vintage tracking
 */
contract MockVintageTracker {
    mapping(bytes32 => bool) public transferable;
    mapping(bytes32 => uint256) public effectiveValues;
    mapping(bytes32 => bool) public vintageRecordExists;

    function setTransferable(bytes32 creditId, bool _transferable) external {
        transferable[creditId] = _transferable;
    }

    function setEffectiveValue(bytes32 creditId, uint256 value) external {
        effectiveValues[creditId] = value;
    }

    function createVintageRecord(
        bytes32 creditId,
        uint256 tokenId,
        bytes32 projectId,
        uint256 vintageYear,
        address minter,
        bytes32 jurisdictionCode
    ) external returns (bytes32) {
        vintageRecordExists[creditId] = true;
        transferable[creditId] = true; // Default to transferable
        return creditId;
    }

    function recordTransfer(
        bytes32 creditId,
        address from,
        address to,
        bytes32 transactionHash
    ) external {
        // Mock implementation
    }

    function isTransferable(bytes32 creditId) external view returns (bool) {
        if (!vintageRecordExists[creditId]) return true;
        return transferable[creditId];
    }

    function getEffectiveValue(bytes32 creditId, uint256 baseValue) external view returns (uint256) {
        if (effectiveValues[creditId] > 0) {
            return effectiveValues[creditId];
        }
        return baseValue;
    }

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
    ) {
        return (creditId, 0, bytes32(0), 2023, 0, 0, 0, 0, 10000, 0, address(0), address(0), 0, 0, false, bytes32(0));
    }

    function retireCredit(
        bytes32 creditId,
        uint256 amount,
        string calldata beneficiary,
        string calldata purpose,
        string calldata certificateHash
    ) external returns (bytes32) {
        return keccak256(abi.encodePacked(creditId, amount, beneficiary, purpose, certificateHash));
    }
}

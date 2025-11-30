// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ISO14065Verifier
 * @dev Registry for ISO 14065 verification status.
 *
 * ISO 14065 specifies requirements for greenhouse gas validation and
 * verification bodies. This contract tracks which projects have been
 * verified by accredited ISO 14065 bodies.
 *
 * @notice Security Considerations:
 * - block.timestamp is used for verification dates and expiration checks.
 *   Miners can manipulate timestamps by ~15 seconds, which is negligible
 *   for verification periods spanning months or years.
 * - All input validation uses require() for proper error handling.
 */
contract ISO14065Verifier is Ownable {
    constructor() Ownable() {}

    struct VerificationStatus {
        bool isVerified;
        address verificationBody;
        uint256 verificationDate;
        uint256 expirationDate;
        string certificateHash;  // IPFS hash of verification certificate
        string accreditationId;  // Verification body's accreditation ID
    }

    mapping(bytes32 => VerificationStatus) private _verifications;

    event ProjectVerified(
        bytes32 indexed projectId,
        address indexed verificationBody,
        uint256 expirationDate,
        string certificateHash,
        string accreditationId
    );

    event VerificationRevoked(
        bytes32 indexed projectId,
        string reason
    );

    /**
     * @dev Record ISO 14065 verification for a project.
     * Can only be called by contract owner (registry administrator).
     * @param projectId Unique identifier for the project
     * @param verificationBody Address of the accredited verification body
     * @param expirationDate Unix timestamp when verification expires
     * @param certificateHash IPFS hash of the verification certificate
     * @param accreditationId Verification body's accreditation identifier
     *
     * @notice Uses block.timestamp for recording verification date.
     * Miner manipulation (~15s) is negligible for this use case.
     */
    function setVerification(
        bytes32 projectId,
        address verificationBody,
        uint256 expirationDate,
        string calldata certificateHash,
        string calldata accreditationId
    ) external onlyOwner {
        require(projectId != bytes32(0), "Invalid projectId");
        require(verificationBody != address(0), "Invalid verification body");
        // solhint-disable-next-line not-rely-on-time
        require(expirationDate > block.timestamp, "Expiration must be future");
        require(bytes(certificateHash).length > 0, "Certificate hash required");
        require(bytes(accreditationId).length > 0, "Accreditation ID required");

        // solhint-disable-next-line not-rely-on-time
        _verifications[projectId] = VerificationStatus({
            isVerified: true,
            verificationBody: verificationBody,
            verificationDate: block.timestamp,
            expirationDate: expirationDate,
            certificateHash: certificateHash,
            accreditationId: accreditationId
        });

        emit ProjectVerified(
            projectId,
            verificationBody,
            expirationDate,
            certificateHash,
            accreditationId
        );
    }

    /**
     * @dev Revoke verification for a project.
     * @param projectId Project to revoke verification for
     * @param reason Reason for revocation (stored in event log)
     */
    function revokeVerification(bytes32 projectId, string calldata reason)
        external
        onlyOwner
    {
        require(_verifications[projectId].isVerified, "Not verified");
        _verifications[projectId].isVerified = false;
        emit VerificationRevoked(projectId, reason);
    }

    /**
     * @dev Check if project is currently verified under ISO 14065.
     * @param projectId Project to check
     * @return True if verified AND not expired
     *
     * @notice Uses block.timestamp for expiration check.
     * Miner manipulation (~15s) is negligible for verification periods.
     */
    function isProjectVerified(bytes32 projectId) external view returns (bool) {
        VerificationStatus storage status = _verifications[projectId];
        // solhint-disable-next-line not-rely-on-time
        return status.isVerified && block.timestamp <= status.expirationDate;
    }

    /**
     * @dev Get full verification status for a project.
     * @param projectId Project to query
     * @return Full VerificationStatus struct
     */
    function getVerificationStatus(bytes32 projectId)
        external
        view
        returns (VerificationStatus memory)
    {
        return _verifications[projectId];
    }
}

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
 */
contract ISO14065Verifier is Ownable {
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
        require(expirationDate > block.timestamp, "Expiration must be future");
        require(bytes(certificateHash).length > 0, "Certificate hash required");
        require(bytes(accreditationId).length > 0, "Accreditation ID required");

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
     * Returns true only if verified AND not expired.
     */
    function isProjectVerified(bytes32 projectId) external view returns (bool) {
        VerificationStatus memory status = _verifications[projectId];
        return status.isVerified && block.timestamp <= status.expirationDate;
    }

    /**
     * @dev Get full verification status for a project.
     */
    function getVerificationStatus(bytes32 projectId) 
        external 
        view 
        returns (VerificationStatus memory) 
    {
        return _verifications[projectId];
    }
}

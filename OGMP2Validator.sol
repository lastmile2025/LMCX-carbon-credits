// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OGMP2Validator
 * @dev Minimal OGMP 2.0 compliance registry.
 *
 * This contract is intentionally simplified: it lets the owner mark a project
 * as compliant or not. You can later extend it with detailed survey, frequency,
 * and monitoring-technology logic without changing the external
 * `isProjectCompliant` interface used by ComplianceManager.
 */
contract OGMP2Validator is Ownable {
    struct OGMPStatus {
        bool isCompliant;
        uint256 lastUpdated;
        string evidenceHash; // e.g. IPFS CID of OGMP2 report / Enovate.AI analysis
    }

    mapping(bytes32 => OGMPStatus) private _status;

    event OGMPComplianceSet(
        bytes32 indexed projectId,
        bool isCompliant,
        string evidenceHash
    );

    /**
     * @dev Set OGMP2 compliance status for a project.
     * Can only be called by contract owner (e.g. registry or verifier).
     */
    function setCompliance(
        bytes32 projectId,
        bool isCompliant,
        string calldata evidenceHash
    ) external onlyOwner {
        require(projectId != bytes32(0), "Invalid projectId");
        require(bytes(evidenceHash).length > 0, "Evidence hash required");

        _status[projectId] = OGMPStatus({
            isCompliant: isCompliant,
            lastUpdated: block.timestamp,
            evidenceHash: evidenceHash
        });

        emit OGMPComplianceSet(projectId, isCompliant, evidenceHash);
    }

    /**
     * @dev Check if project is currently compliant with OGMP2.
     */
    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return _status[projectId].isCompliant;
    }

    /**
     * @dev Get full OGMP2 status record for a project.
     */
    function getStatus(bytes32 projectId) external view returns (OGMPStatus memory) {
        return _status[projectId];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EPASubpartWValidator
 * @dev Minimal EPA 40 CFR Part 98 Subpart W compliance registry.
 */
contract EPASubpartWValidator is Ownable {
    struct SubpartWStatus {
        bool isCompliant;
        uint256 lastReportDate;
        string ghgrpReportId;
        string evidenceHash;
    }

    mapping(bytes32 => SubpartWStatus) private _status;

    event SubpartWComplianceSet(
        bytes32 indexed projectId,
        bool isCompliant,
        string ghgrpReportId,
        string evidenceHash
    );

    /**
     * @dev Set EPA Subpart W compliance status.
     */
    function setCompliance(
        bytes32 projectId,
        bool isCompliant,
        string calldata ghgrpReportId,
        string calldata evidenceHash
    ) external onlyOwner {
        require(projectId != bytes32(0), "Invalid projectId");
        require(bytes(ghgrpReportId).length > 0, "GHGRP ID required");
        require(bytes(evidenceHash).length > 0, "Evidence hash required");

        _status[projectId] = SubpartWStatus({
            isCompliant: isCompliant,
            lastReportDate: block.timestamp,
            ghgrpReportId: ghgrpReportId,
            evidenceHash: evidenceHash
        });

        emit SubpartWComplianceSet(projectId, isCompliant, ghgrpReportId, evidenceHash);
    }

    /**
     * @dev Check if project is compliant with Subpart W.
     */
    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return _status[projectId].isCompliant;
    }

    function getStatus(bytes32 projectId)
        external
        view
        returns (SubpartWStatus memory)
    {
        return _status[projectId];
    }
}

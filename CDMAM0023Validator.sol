// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CDMAM0023Validator
 * @dev Minimal CDM AM0023 compliance & vintage eligibility registry.
 *
 * NOTE: This is deliberately simplified: you can extend it later with
 * detailed baseline, leakage, monitoring, etc. while keeping the
 * `isProjectCompliant` and `isVintageEligible` function signatures intact.
 */
contract CDMAM0023Validator is Ownable {
    struct CDMStatus {
        bool isCompliant;
        uint256 creditingStartYear;
        uint256 creditingEndYear;
        string cdmProjectNumber;
        string pddHash;
        uint256 lastUpdated;
    }

    mapping(bytes32 => CDMStatus) private _status;

    event CDMComplianceSet(
        bytes32 indexed projectId,
        bool isCompliant,
        uint256 creditingStartYear,
        uint256 creditingEndYear,
        string cdmProjectNumber,
        string pddHash
    );

    /**
     * @dev Set CDM AM0023 compliance & crediting period.
     */
    function setCompliance(
        bytes32 projectId,
        bool isCompliant,
        uint256 creditingStartYear,
        uint256 creditingEndYear,
        string calldata cdmProjectNumber,
        string calldata pddHash
    ) external onlyOwner {
        require(projectId != bytes32(0), "Invalid projectId");
        require(creditingStartYear >= 2000, "Start year too early");
        require(creditingEndYear >= creditingStartYear, "Invalid crediting range");
        require(bytes(cdmProjectNumber).length > 0, "CDM project number required");
        require(bytes(pddHash).length > 0, "PDD hash required");

        _status[projectId] = CDMStatus({
            isCompliant: isCompliant,
            creditingStartYear: creditingStartYear,
            creditingEndYear: creditingEndYear,
            cdmProjectNumber: cdmProjectNumber,
            pddHash: pddHash,
            lastUpdated: block.timestamp
        });

        emit CDMComplianceSet(
            projectId,
            isCompliant,
            creditingStartYear,
            creditingEndYear,
            cdmProjectNumber,
            pddHash
        );
    }

    /**
     * @dev Check if project is currently compliant with CDM AM0023.
     */
    function isProjectCompliant(bytes32 projectId) external view returns (bool) {
        return _status[projectId].isCompliant;
    }

    /**
     * @dev Check if a specific vintage year is eligible for credit issuance.
     */
    function isVintageEligible(bytes32 projectId, uint256 year)
        external
        view
        returns (bool)
    {
        CDMStatus memory s = _status[projectId];
        if (!s.isCompliant) return false;
        return year >= s.creditingStartYear && year <= s.creditingEndYear;
    }

    function getStatus(bytes32 projectId)
        external
        view
        returns (CDMStatus memory)
    {
        return _status[projectId];
    }
}

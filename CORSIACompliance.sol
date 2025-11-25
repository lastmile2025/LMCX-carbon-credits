// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CORSIACompliance
 * @dev Registry for CORSIA (Carbon Offsetting and Reduction Scheme for 
 * International Aviation) eligibility.
 *
 * CORSIA has specific requirements for eligible emissions units (EUCs)
 * including vintage year restrictions and program eligibility.
 */
contract CORSIACompliance is Ownable {
    struct CORSIAStatus {
        bool isEligible;
        uint256 registrationDate;
        uint256 firstEligibleVintage;
        uint256 lastEligibleVintage;
        string programId;           // CORSIA-eligible program identifier
        string evidenceHash;        // IPFS hash of eligibility documentation
    }

    // Compliance periods for CORSIA (pilot phase, first phase, etc.)
    struct CompliancePeriod {
        uint256 startYear;
        uint256 endYear;
        uint256 vintageFloor;       // Earliest acceptable vintage
        bool isActive;
    }

    mapping(bytes32 => CORSIAStatus) private _projectStatus;
    mapping(uint256 => CompliancePeriod) private _compliancePeriods;
    uint256 public currentPeriodId;

    event CORSIAEligibilitySet(
        bytes32 indexed projectId,
        bool isEligible,
        uint256 firstEligibleVintage,
        uint256 lastEligibleVintage,
        string programId
    );

    event CompliancePeriodSet(
        uint256 indexed periodId,
        uint256 startYear,
        uint256 endYear,
        uint256 vintageFloor
    );

    constructor() {
        // Initialize with CORSIA pilot phase (2021-2023)
        _compliancePeriods[1] = CompliancePeriod({
            startYear: 2021,
            endYear: 2023,
            vintageFloor: 2016,
            isActive: false
        });

        // First phase (2024-2026)
        _compliancePeriods[2] = CompliancePeriod({
            startYear: 2024,
            endYear: 2026,
            vintageFloor: 2021,
            isActive: true
        });

        currentPeriodId = 2;
    }

    /**
     * @dev Set CORSIA eligibility status for a project.
     */
    function setEligibility(
        bytes32 projectId,
        bool isEligible,
        uint256 firstEligibleVintage,
        uint256 lastEligibleVintage,
        string calldata programId,
        string calldata evidenceHash
    ) external onlyOwner {
        require(projectId != bytes32(0), "Invalid projectId");
        require(lastEligibleVintage >= firstEligibleVintage, "Invalid vintage range");
        require(bytes(programId).length > 0, "Program ID required");
        require(bytes(evidenceHash).length > 0, "Evidence hash required");

        _projectStatus[projectId] = CORSIAStatus({
            isEligible: isEligible,
            registrationDate: block.timestamp,
            firstEligibleVintage: firstEligibleVintage,
            lastEligibleVintage: lastEligibleVintage,
            programId: programId,
            evidenceHash: evidenceHash
        });

        emit CORSIAEligibilitySet(
            projectId,
            isEligible,
            firstEligibleVintage,
            lastEligibleVintage,
            programId
        );
    }

    /**
     * @dev Update compliance period parameters.
     */
    function setCompliancePeriod(
        uint256 periodId,
        uint256 startYear,
        uint256 endYear,
        uint256 vintageFloor,
        bool isActive
    ) external onlyOwner {
        require(endYear >= startYear, "Invalid year range");
        
        _compliancePeriods[periodId] = CompliancePeriod({
            startYear: startYear,
            endYear: endYear,
            vintageFloor: vintageFloor,
            isActive: isActive
        });

        if (isActive) {
            currentPeriodId = periodId;
        }

        emit CompliancePeriodSet(periodId, startYear, endYear, vintageFloor);
    }

    /**
     * @dev Check if project is eligible for CORSIA.
     */
    function isProjectEligible(bytes32 projectId) external view returns (bool) {
        return _projectStatus[projectId].isEligible;
    }

    /**
     * @dev Check if a specific vintage year is eligible for a compliance period.
     * @param projectId The project identifier
     * @param compliancePeriod The compliance period ID to check against
     */
    function isVintageYearEligible(bytes32 projectId, uint256 compliancePeriod) 
        external 
        view 
        returns (bool) 
    {
        CORSIAStatus memory status = _projectStatus[projectId];
        CompliancePeriod memory period = _compliancePeriods[compliancePeriod];
        
        if (!status.isEligible || !period.isActive) {
            return false;
        }

        // Check if project's vintage range overlaps with period requirements
        return status.firstEligibleVintage <= period.endYear &&
               status.lastEligibleVintage >= period.vintageFloor;
    }

    /**
     * @dev Get full CORSIA status for a project.
     */
    function getProjectStatus(bytes32 projectId) 
        external 
        view 
        returns (CORSIAStatus memory) 
    {
        return _projectStatus[projectId];
    }

    /**
     * @dev Get compliance period details.
     */
    function getCompliancePeriod(uint256 periodId) 
        external 
        view 
        returns (CompliancePeriod memory) 
    {
        return _compliancePeriods[periodId];
    }
}

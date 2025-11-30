// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CORSIACompliance
 * @dev Registry for CORSIA (Carbon Offsetting and Reduction Scheme for
 * International Aviation) eligibility.
 *
 * CORSIA has specific requirements for eligible emissions units (EUCs)
 * including vintage year restrictions and program eligibility.
 *
 * @notice Security Considerations:
 * - block.timestamp is used for registration dates. Miner manipulation (~15s)
 *   is negligible for eligibility periods spanning years.
 * - All input validation uses custom errors for gas efficiency.
 */
contract CORSIACompliance is Ownable {
    // ============ Custom Errors ============
    error InvalidProjectId();
    error InvalidVintageRange();
    error ProgramIdRequired();
    error EvidenceHashRequired();
    error InvalidYearRange();

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
    mapping(uint256 => CompliancePeriod) private _periods;
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

    constructor() Ownable() {
        // Initialize with CORSIA pilot phase (2021-2023)
        _periods[1] = CompliancePeriod({
            startYear: 2021,
            endYear: 2023,
            vintageFloor: 2016,
            isActive: false
        });

        // First phase (2024-2026)
        _periods[2] = CompliancePeriod({
            startYear: 2024,
            endYear: 2026,
            vintageFloor: 2021,
            isActive: true
        });

        currentPeriodId = 2;
    }

    /**
     * @dev Set CORSIA eligibility status for a project.
     * @param projectId Unique identifier for the project
     * @param isEligible Whether the project is CORSIA eligible
     * @param firstEligibleVintage First eligible vintage year
     * @param lastEligibleVintage Last eligible vintage year
     * @param programId CORSIA-eligible program identifier
     * @param evidenceHash IPFS hash of eligibility documentation
     *
     * @notice Uses block.timestamp for registration date.
     */
    function setEligibility(
        bytes32 projectId,
        bool isEligible,
        uint256 firstEligibleVintage,
        uint256 lastEligibleVintage,
        string calldata programId,
        string calldata evidenceHash
    ) external onlyOwner {
        if (projectId == bytes32(0)) revert InvalidProjectId();
        if (lastEligibleVintage < firstEligibleVintage) revert InvalidVintageRange();
        if (bytes(programId).length == 0) revert ProgramIdRequired();
        if (bytes(evidenceHash).length == 0) revert EvidenceHashRequired();

        // solhint-disable-next-line not-rely-on-time
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
     * @param periodId The period identifier
     * @param startYear Start year of the compliance period
     * @param endYear End year of the compliance period
     * @param vintageFloor Earliest acceptable vintage year
     * @param isActive Whether this period is currently active
     */
    function setCompliancePeriod(
        uint256 periodId,
        uint256 startYear,
        uint256 endYear,
        uint256 vintageFloor,
        bool isActive
    ) external onlyOwner {
        if (endYear < startYear) revert InvalidYearRange();

        _periods[periodId] = CompliancePeriod({
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
     * @param projectId The project to check
     * @return True if project is CORSIA eligible
     */
    function isProjectEligible(bytes32 projectId) external view returns (bool) {
        return _projectStatus[projectId].isEligible;
    }

    /**
     * @dev Check if a specific vintage year is eligible for a compliance period.
     * @param projectId The project identifier
     * @param periodId The compliance period ID to check against
     * @return True if vintage is eligible for the specified period
     */
    function isVintageYearEligible(bytes32 projectId, uint256 periodId)
        external
        view
        returns (bool)
    {
        CORSIAStatus storage status = _projectStatus[projectId];
        CompliancePeriod storage period = _periods[periodId];

        if (!status.isEligible || !period.isActive) {
            return false;
        }

        // Check if project's vintage range overlaps with period requirements
        return status.firstEligibleVintage <= period.endYear &&
               status.lastEligibleVintage >= period.vintageFloor;
    }

    /**
     * @dev Get full CORSIA status for a project.
     * @param projectId The project to query
     * @return Full CORSIAStatus struct
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
     * @param periodId The period to query
     * @return Full CompliancePeriod struct
     */
    function getCompliancePeriod(uint256 periodId)
        external
        view
        returns (CompliancePeriod memory)
    {
        return _periods[periodId];
    }
}

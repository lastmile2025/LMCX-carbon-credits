// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @notice Interface for the ERC1155 token contract
interface ILMCXCarbonCredit {
    function mintCredits(
        address to,
        bytes32 projectId,
        uint256 vintageYear,
        uint256 amount,
        string memory methodology,
        string memory verificationHash
    ) external returns (uint256 mintId, uint256 tokenId);

    function mintCreditsBatch(
        address to,
        bytes32[] memory projectIds,
        uint256[] memory vintageYears,
        uint256[] memory amounts,
        string[] memory methodologies,
        string[] memory verificationHashes
    ) external returns (uint256[] memory mintIds, uint256[] memory tokenIds);
}

/// @notice Interface for OGMP 2.0 validator
interface IOGMP2Validator {
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
}

/// @notice Interface for ISO 14065 verifier
interface IISO14065Verifier {
    function isProjectVerified(bytes32 projectId) external view returns (bool);
}

/// @notice Interface for CORSIA compliance
interface ICORSIACompliance {
    function isProjectEligible(bytes32 projectId) external view returns (bool);
    function isVintageYearEligible(bytes32 projectId, uint256 compliancePeriod) external view returns (bool);
}

/// @notice Interface for EPA Subpart W validator
interface IEPASubpartWValidator {
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
}

/// @notice Interface for CDM AM0023 validator
interface ICDMAM0023Validator {
    function isProjectCompliant(bytes32 projectId) external view returns (bool);
    function isVintageEligible(bytes32 projectId, uint256 year) external view returns (bool);
}

/**
 * @title ComplianceManager
 * @dev Orchestrates all regulatory checks and controls access to ERC1155 token minting.
 *
 * Flow:
 *  1. ISSUER_ROLE submits a minting request with projectId, vintage, amount, etc.
 *  2. ADMIN_ROLE (or the same account, depending on your governance) runs compliance checks.
 *  3. If all validators return true, ADMIN_ROLE can approve and execute minting.
 *  4. Only this contract is granted COMPLIANCE_MANAGER_ROLE on the token.
 */
contract ComplianceManager is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    ILMCXCarbonCredit public immutable tokenContract;
    IOGMP2Validator public immutable ogmpValidator;
    IISO14065Verifier public immutable isoVerifier;
    ICORSIACompliance public immutable corsiaCompliance;
    IEPASubpartWValidator public immutable epaSubpartWValidator;
    ICDMAM0023Validator public immutable cdmAM0023Validator;

    struct MintingRequest {
        uint256 requestId;
        address requester;
        address beneficiary;
        uint256 amount;
        bytes32 projectId;
        uint256 vintageYear;
        string methodology;
        string verificationHash;
        uint256 createdAt;

        // Compliance flags
        bool ogmpCompliant;
        bool isoVerified;
        bool corsiaEligible;
        bool epaSubpartWCompliant;
        bool cdmAM0023Compliant;
        bool vintageEligible;

        bool approved;
        bool minted;
        
        // Results after minting (ERC1155 specific)
        uint256 mintId;
        uint256 tokenId;
    }

    uint256 public nextRequestId;
    mapping(uint256 => MintingRequest) private _requests;

    event MintingRequested(
        uint256 indexed requestId,
        address indexed requester,
        address indexed beneficiary,
        uint256 amount,
        bytes32 projectId,
        uint256 vintageYear,
        string methodology,
        string verificationHash
    );

    event ComplianceChecked(
        uint256 indexed requestId,
        bool ogmpCompliant,
        bool isoVerified,
        bool corsiaEligible,
        bool epaSubpartWCompliant,
        bool cdmAM0023Compliant,
        bool vintageEligible
    );

    event MintApproved(uint256 indexed requestId, address indexed admin);
    event MintExecuted(uint256 indexed requestId, uint256 mintId, uint256 tokenId);
    event MintRejected(uint256 indexed requestId, string reason);

    constructor(
        address _tokenContract,
        address _ogmpValidator,
        address _isoVerifier,
        address _corsiaCompliance,
        address _epaSubpartWValidator,
        address _cdmAM0023Validator
    ) {
        require(_tokenContract != address(0), "Invalid token contract");
        require(_ogmpValidator != address(0), "Invalid OGMP validator");
        require(_isoVerifier != address(0), "Invalid ISO verifier");
        require(_corsiaCompliance != address(0), "Invalid CORSIA contract");
        require(_epaSubpartWValidator != address(0), "Invalid EPA validator");
        require(_cdmAM0023Validator != address(0), "Invalid CDM validator");

        tokenContract = ILMCXCarbonCredit(_tokenContract);
        ogmpValidator = IOGMP2Validator(_ogmpValidator);
        isoVerifier = IISO14065Verifier(_isoVerifier);
        corsiaCompliance = ICORSIACompliance(_corsiaCompliance);
        epaSubpartWValidator = IEPASubpartWValidator(_epaSubpartWValidator);
        cdmAM0023Validator = ICDMAM0023Validator(_cdmAM0023Validator);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ISSUER_ROLE, msg.sender);
    }

    /**
     * @dev Submit a new minting request.
     */
    function requestMinting(
        address beneficiary,
        uint256 amount,
        bytes32 projectId,
        uint256 vintageYear,
        string calldata methodology,
        string calldata verificationHash
    ) external onlyRole(ISSUER_ROLE) returns (uint256 requestId) {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(projectId != bytes32(0), "Invalid projectId");
        require(vintageYear >= 2000 && vintageYear <= 2100, "Invalid vintage year");
        require(bytes(methodology).length > 0, "Methodology required");
        require(bytes(verificationHash).length > 0, "Verification hash required");

        requestId = nextRequestId;
        nextRequestId += 1;

        _requests[requestId] = MintingRequest({
            requestId: requestId,
            requester: msg.sender,
            beneficiary: beneficiary,
            amount: amount,
            projectId: projectId,
            vintageYear: vintageYear,
            methodology: methodology,
            verificationHash: verificationHash,
            createdAt: block.timestamp,
            ogmpCompliant: false,
            isoVerified: false,
            corsiaEligible: false,
            epaSubpartWCompliant: false,
            cdmAM0023Compliant: false,
            vintageEligible: false,
            approved: false,
            minted: false,
            mintId: 0,
            tokenId: 0
        });

        emit MintingRequested(
            requestId,
            msg.sender,
            beneficiary,
            amount,
            projectId,
            vintageYear,
            methodology,
            verificationHash
        );
    }

    /**
     * @dev Run all compliance checks for a given request.
     * Can be called by ADMIN_ROLE (e.g. compliance officer).
     */
    function performComplianceChecks(uint256 requestId) public onlyRole(ADMIN_ROLE) {
        MintingRequest storage r = _getExistingRequest(requestId);

        // call external validators
        bool ogmpOk = ogmpValidator.isProjectCompliant(r.projectId);
        bool isoOk = isoVerifier.isProjectVerified(r.projectId);
        bool corsiaOk = corsiaCompliance.isProjectEligible(r.projectId);
        bool epaOk = epaSubpartWValidator.isProjectCompliant(r.projectId);
        bool cdmOk = cdmAM0023Validator.isProjectCompliant(r.projectId);

        // For vintage eligibility, we require both CORSIA & CDM to agree
        bool corsiaVintageOk = corsiaCompliance.isVintageYearEligible(r.projectId, r.vintageYear);
        bool cdmVintageOk = cdmAM0023Validator.isVintageEligible(r.projectId, r.vintageYear);
        bool vintageOk = corsiaVintageOk && cdmVintageOk;

        r.ogmpCompliant = ogmpOk;
        r.isoVerified = isoOk;
        r.corsiaEligible = corsiaOk;
        r.epaSubpartWCompliant = epaOk;
        r.cdmAM0023Compliant = cdmOk;
        r.vintageEligible = vintageOk;

        emit ComplianceChecked(
            requestId,
            ogmpOk,
            isoOk,
            corsiaOk,
            epaOk,
            cdmOk,
            vintageOk
        );
    }

    /**
     * @dev Approve and execute minting if all checks pass.
     */
    function approveMinting(uint256 requestId) external onlyRole(ADMIN_ROLE) nonReentrant {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(!r.minted, "Already minted");

        // If no checks have been run yet, run them now
        if (
            !r.ogmpCompliant &&
            !r.isoVerified &&
            !r.corsiaEligible &&
            !r.epaSubpartWCompliant &&
            !r.cdmAM0023Compliant &&
            !r.vintageEligible
        ) {
            performComplianceChecks(requestId);
        }

        require(r.ogmpCompliant, "OGMP2 non-compliant");
        require(r.isoVerified, "ISO14065 not verified");
        require(r.corsiaEligible, "Not CORSIA-eligible");
        require(r.epaSubpartWCompliant, "EPA Subpart W non-compliant");
        require(r.cdmAM0023Compliant, "CDM AM0023 non-compliant");
        require(r.vintageEligible, "Vintage not eligible");

        r.approved = true;
        emit MintApproved(requestId, msg.sender);

        // Mint credits (ERC1155 version)
        (uint256 mintId, uint256 tokenId) = tokenContract.mintCredits(
            r.beneficiary,
            r.projectId,
            r.vintageYear,
            r.amount,
            r.methodology,
            r.verificationHash
        );

        r.minted = true;
        r.mintId = mintId;
        r.tokenId = tokenId;
        
        emit MintExecuted(requestId, mintId, tokenId);
    }

    /**
     * @dev Reject a request off-chain / governance reasons, without minting.
     * Does NOT delete the request; it simply marks it as not minted and emits an event.
     */
    function rejectMinting(uint256 requestId, string calldata reason)
        external
        onlyRole(ADMIN_ROLE)
    {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(!r.minted, "Already minted");
        // no state change besides the event; off-chain systems can treat this as final
        emit MintRejected(requestId, reason);
    }

    /**
     * @dev View helper: returns full details of a minting request.
     */
    function getMintingRequest(uint256 requestId)
        external
        view
        returns (MintingRequest memory)
    {
        return _getExistingRequest(requestId);
    }

    /**
     * @dev Returns true if all compliance flags are set to true for this request.
     */
    function isFullyCompliant(uint256 requestId) external view returns (bool) {
        MintingRequest storage r = _getExistingRequest(requestId);
        return (
            r.ogmpCompliant &&
            r.isoVerified &&
            r.corsiaEligible &&
            r.epaSubpartWCompliant &&
            r.cdmAM0023Compliant &&
            r.vintageEligible
        );
    }

    /**
     * @dev Get the ERC1155 token ID for a minted request.
     */
    function getTokenId(uint256 requestId) external view returns (uint256) {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(r.minted, "Not yet minted");
        return r.tokenId;
    }

    /**
     * @dev Get the mint record ID for a minted request.
     */
    function getMintId(uint256 requestId) external view returns (uint256) {
        MintingRequest storage r = _getExistingRequest(requestId);
        require(r.minted, "Not yet minted");
        return r.mintId;
    }

    function _getExistingRequest(uint256 requestId) internal view returns (MintingRequest storage) {
        require(requestId < nextRequestId, "Invalid requestId");
        return _requests[requestId];
    }
}

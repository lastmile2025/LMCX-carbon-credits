// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title VintageTracker
 * @dev Comprehensive credit lifecycle and vintage tracking system with:
 * - Vintage year classification and automatic discount factors
 * - Mandatory cooling-off period between minting and first transfer
 * - Credit provenance tracking with full history
 * - Geofencing for jurisdiction-specific compliance
 * - Lifecycle state machine (mint -> active -> transferred -> retired/invalidated)
 * - Vintage quality scoring based on age and verification status
 *
 * This contract ensures credits maintain integrity throughout their lifecycle
 * and provides transparent provenance for regulatory compliance.
 */
contract VintageTracker is AccessControl, ReentrancyGuard, Pausable {
    // ============ Roles ============
    bytes32 public constant LIFECYCLE_MANAGER_ROLE = keccak256("LIFECYCLE_MANAGER_ROLE");
    bytes32 public constant GEOFENCE_ADMIN_ROLE = keccak256("GEOFENCE_ADMIN_ROLE");
    bytes32 public constant VINTAGE_ADMIN_ROLE = keccak256("VINTAGE_ADMIN_ROLE");

    // ============ Constants ============
    uint256 public constant COOLING_OFF_PERIOD = 7 days;
    uint256 public constant MAX_VINTAGE_AGE = 10 * 365 days; // 10 years
    uint256 public constant PRECISION = 10000;
    uint256 public constant MIN_VINTAGE_QUALITY = 1000; // 10% minimum

    // ============ Enums ============
    enum LifecycleState {
        Minted,             // Just created, in cooling-off period
        Active,             // Available for trading
        Locked,             // Temporarily locked (dispute, verification)
        Transferred,        // Has been transferred at least once
        Retired,            // Permanently retired (offset claimed)
        Invalidated,        // Cancelled due to reversal/fraud
        Expired             // Vintage too old
    }

    enum VintageGrade {
        Premium,            // < 1 year old
        Standard,           // 1-3 years old
        Discount,           // 3-5 years old
        Legacy,             // 5-8 years old
        Archive             // 8-10 years old
    }

    // ============ Structs ============

    /// @notice Core vintage record
    struct VintageRecord {
        bytes32 creditId;               // Unique credit identifier
        uint256 tokenId;                // ERC1155 token ID
        bytes32 projectId;
        uint256 vintageYear;
        uint256 mintedAt;
        uint256 coolingOffEndsAt;
        LifecycleState state;
        VintageGrade grade;
        uint256 qualityScore;           // 0-10000 scale
        uint256 discountFactor;         // Discount percentage (0-10000)
        address originalMinter;
        address currentHolder;
        uint256 transferCount;
        uint256 lastTransferAt;
        bool isGeofenced;
        bytes32 jurisdictionCode;
    }

    /// @notice Provenance entry (immutable history)
    struct ProvenanceEntry {
        bytes32 entryId;
        bytes32 creditId;
        LifecycleState fromState;
        LifecycleState toState;
        address fromAddress;
        address toAddress;
        uint256 timestamp;
        bytes32 transactionHash;
        string action;                  // "mint", "transfer", "retire", etc.
        string metadata;                // Additional info
    }

    /// @notice Retirement record
    struct RetirementRecord {
        bytes32 retirementId;
        bytes32 creditId;
        uint256 tokenId;
        uint256 amount;
        address retiringParty;
        string beneficiary;
        string purpose;
        string certificateHash;         // IPFS hash of retirement certificate
        uint256 retiredAt;
        uint256 vintageYear;
        bool isVerified;
    }

    /// @notice Geofence configuration
    struct Geofence {
        bytes32 jurisdictionCode;
        string jurisdictionName;
        bool isActive;
        bool requiresKYC;
        bool allowsInternationalTransfer;
        uint256 minTransferAmount;
        uint256 maxTransferAmount;
        address[] approvedExchanges;
        bytes32[] compatibleJurisdictions;
    }

    /// @notice Vintage discount schedule
    struct DiscountSchedule {
        uint256 premiumMaxAge;          // Max age for Premium grade
        uint256 standardMaxAge;
        uint256 discountMaxAge;
        uint256 legacyMaxAge;
        uint256 premiumDiscount;        // 0 = no discount
        uint256 standardDiscount;       // e.g., 500 = 5%
        uint256 discountDiscount;       // e.g., 1500 = 15%
        uint256 legacyDiscount;         // e.g., 3000 = 30%
        uint256 archiveDiscount;        // e.g., 5000 = 50%
    }

    /// @notice Lock record
    struct LockRecord {
        bytes32 creditId;
        uint256 lockedAt;
        uint256 unlockAt;
        string reason;
        address lockedBy;
        bool isActive;
    }

    // ============ Storage ============

    // Vintage records
    mapping(bytes32 => VintageRecord) public vintageRecords;
    mapping(uint256 => bytes32) public tokenToCreditId;     // tokenId => creditId
    mapping(bytes32 => bytes32[]) public projectCredits;    // projectId => creditIds

    // Provenance
    mapping(bytes32 => ProvenanceEntry[]) public creditProvenance;  // creditId => entries
    mapping(bytes32 => ProvenanceEntry) public provenanceEntries;   // entryId => entry

    // Retirements
    mapping(bytes32 => RetirementRecord) public retirements;
    mapping(address => bytes32[]) public userRetirements;
    mapping(uint256 => uint256) public yearlyRetirements;   // vintageYear => total retired
    uint256 public totalRetirements;

    // Geofencing
    mapping(bytes32 => Geofence) public geofences;
    bytes32[] public jurisdictionList;
    mapping(address => bytes32) public userJurisdiction;

    // Locks
    mapping(bytes32 => LockRecord) public locks;

    // Discount schedule (configurable)
    DiscountSchedule public discountSchedule;

    // Statistics
    mapping(uint256 => uint256) public creditsByVintageYear;
    mapping(LifecycleState => uint256) public creditsByState;
    uint256 public totalCreditsTracked;

    // ============ Events ============

    event VintageRecordCreated(
        bytes32 indexed creditId,
        uint256 indexed tokenId,
        bytes32 indexed projectId,
        uint256 vintageYear,
        address minter
    );

    event LifecycleStateChanged(
        bytes32 indexed creditId,
        LifecycleState fromState,
        LifecycleState toState,
        string action
    );

    event CreditTransferred(
        bytes32 indexed creditId,
        address indexed from,
        address indexed to,
        uint256 transferCount
    );

    event CreditRetired(
        bytes32 indexed retirementId,
        bytes32 indexed creditId,
        address indexed retiringParty,
        string beneficiary,
        uint256 amount
    );

    event CreditLocked(
        bytes32 indexed creditId,
        string reason,
        uint256 unlockAt
    );

    event CreditUnlocked(
        bytes32 indexed creditId
    );

    event GeofenceConfigured(
        bytes32 indexed jurisdictionCode,
        string jurisdictionName,
        bool isActive
    );

    event VintageGradeUpdated(
        bytes32 indexed creditId,
        VintageGrade newGrade,
        uint256 newDiscount
    );

    event DiscountScheduleUpdated(
        uint256 premiumDiscount,
        uint256 standardDiscount,
        uint256 discountDiscount,
        uint256 legacyDiscount,
        uint256 archiveDiscount
    );

    // ============ Constructor ============

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LIFECYCLE_MANAGER_ROLE, msg.sender);
        _grantRole(GEOFENCE_ADMIN_ROLE, msg.sender);
        _grantRole(VINTAGE_ADMIN_ROLE, msg.sender);

        // Set default discount schedule
        discountSchedule = DiscountSchedule({
            premiumMaxAge: 365 days,        // 1 year
            standardMaxAge: 3 * 365 days,   // 3 years
            discountMaxAge: 5 * 365 days,   // 5 years
            legacyMaxAge: 8 * 365 days,     // 8 years
            premiumDiscount: 0,             // No discount
            standardDiscount: 500,          // 5%
            discountDiscount: 1500,         // 15%
            legacyDiscount: 3000,           // 30%
            archiveDiscount: 5000           // 50%
        });
    }

    // ============ Vintage Record Management ============

    /**
     * @dev Create a new vintage record when credits are minted
     */
    function createVintageRecord(
        bytes32 creditId,
        uint256 tokenId,
        bytes32 projectId,
        uint256 vintageYear,
        address minter,
        bytes32 jurisdictionCode
    ) external onlyRole(LIFECYCLE_MANAGER_ROLE) returns (bytes32) {
        require(vintageRecords[creditId].creditId == bytes32(0), "Record exists");
        require(creditId != bytes32(0), "Invalid creditId");
        require(vintageYear >= 2000 && vintageYear <= block.timestamp / 365 days + 1970 + 1, "Invalid vintage year");

        // Calculate initial vintage grade and discount
        (VintageGrade grade, uint256 discount) = calculateVintageGrade(vintageYear);

        vintageRecords[creditId] = VintageRecord({
            creditId: creditId,
            tokenId: tokenId,
            projectId: projectId,
            vintageYear: vintageYear,
            mintedAt: block.timestamp,
            coolingOffEndsAt: block.timestamp + COOLING_OFF_PERIOD,
            state: LifecycleState.Minted,
            grade: grade,
            qualityScore: 10000 - discount, // Initial quality inversely related to discount
            discountFactor: discount,
            originalMinter: minter,
            currentHolder: minter,
            transferCount: 0,
            lastTransferAt: 0,
            isGeofenced: jurisdictionCode != bytes32(0),
            jurisdictionCode: jurisdictionCode
        });

        tokenToCreditId[tokenId] = creditId;
        projectCredits[projectId].push(creditId);
        creditsByVintageYear[vintageYear]++;
        creditsByState[LifecycleState.Minted]++;
        totalCreditsTracked++;

        // Record provenance
        _recordProvenance(
            creditId,
            LifecycleState.Minted,
            LifecycleState.Minted,
            address(0),
            minter,
            "mint",
            ""
        );

        emit VintageRecordCreated(creditId, tokenId, projectId, vintageYear, minter);
        return creditId;
    }

    /**
     * @dev Calculate vintage grade and discount based on age
     */
    function calculateVintageGrade(uint256 vintageYear) public view returns (VintageGrade grade, uint256 discount) {
        uint256 currentYear = block.timestamp / 365 days + 1970;
        uint256 age = currentYear - vintageYear;
        uint256 ageInDays = age * 365 days;

        if (ageInDays <= discountSchedule.premiumMaxAge) {
            return (VintageGrade.Premium, discountSchedule.premiumDiscount);
        } else if (ageInDays <= discountSchedule.standardMaxAge) {
            return (VintageGrade.Standard, discountSchedule.standardDiscount);
        } else if (ageInDays <= discountSchedule.discountMaxAge) {
            return (VintageGrade.Discount, discountSchedule.discountDiscount);
        } else if (ageInDays <= discountSchedule.legacyMaxAge) {
            return (VintageGrade.Legacy, discountSchedule.legacyDiscount);
        } else {
            return (VintageGrade.Archive, discountSchedule.archiveDiscount);
        }
    }

    /**
     * @dev Update vintage grade based on current age (should be called periodically)
     */
    function updateVintageGrade(bytes32 creditId) external {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");
        require(record.state != LifecycleState.Retired && record.state != LifecycleState.Invalidated, "Credit inactive");

        (VintageGrade newGrade, uint256 newDiscount) = calculateVintageGrade(record.vintageYear);

        if (record.grade != newGrade) {
            record.grade = newGrade;
            record.discountFactor = newDiscount;
            record.qualityScore = 10000 - newDiscount;

            emit VintageGradeUpdated(creditId, newGrade, newDiscount);
        }

        // Check if vintage has expired
        uint256 currentYear = block.timestamp / 365 days + 1970;
        if ((currentYear - record.vintageYear) * 365 days > MAX_VINTAGE_AGE) {
            _transitionState(creditId, LifecycleState.Expired, "expire");
        }
    }

    // ============ Lifecycle State Management ============

    /**
     * @dev Activate credit after cooling-off period
     */
    function activateCredit(bytes32 creditId) external {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");
        require(record.state == LifecycleState.Minted, "Not in Minted state");
        require(block.timestamp >= record.coolingOffEndsAt, "Cooling-off period not ended");

        _transitionState(creditId, LifecycleState.Active, "activate");
    }

    /**
     * @dev Record a credit transfer
     */
    function recordTransfer(
        bytes32 creditId,
        address from,
        address to,
        bytes32 transactionHash
    ) external onlyRole(LIFECYCLE_MANAGER_ROLE) {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");
        require(record.state == LifecycleState.Active || record.state == LifecycleState.Transferred, "Cannot transfer");
        require(!locks[creditId].isActive, "Credit is locked");

        // Check cooling-off period for first transfer
        if (record.transferCount == 0) {
            require(block.timestamp >= record.coolingOffEndsAt, "Cooling-off period active");
        }

        // Check geofencing
        if (record.isGeofenced) {
            _checkGeofenceTransfer(record.jurisdictionCode, from, to);
        }

        LifecycleState previousState = record.state;
        record.currentHolder = to;
        record.transferCount++;
        record.lastTransferAt = block.timestamp;

        if (record.state == LifecycleState.Active) {
            creditsByState[LifecycleState.Active]--;
            creditsByState[LifecycleState.Transferred]++;
            record.state = LifecycleState.Transferred;
        }

        // Record provenance
        _recordProvenance(
            creditId,
            previousState,
            record.state,
            from,
            to,
            "transfer",
            ""
        );

        emit CreditTransferred(creditId, from, to, record.transferCount);
    }

    /**
     * @dev Retire credits (permanent offset)
     */
    function retireCredit(
        bytes32 creditId,
        uint256 amount,
        string calldata beneficiary,
        string calldata purpose,
        string calldata certificateHash
    ) external onlyRole(LIFECYCLE_MANAGER_ROLE) returns (bytes32) {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");
        require(
            record.state == LifecycleState.Active || record.state == LifecycleState.Transferred,
            "Cannot retire"
        );
        require(!locks[creditId].isActive, "Credit is locked");

        bytes32 retirementId = keccak256(abi.encodePacked(
            creditId,
            msg.sender,
            block.timestamp,
            totalRetirements
        ));

        retirements[retirementId] = RetirementRecord({
            retirementId: retirementId,
            creditId: creditId,
            tokenId: record.tokenId,
            amount: amount,
            retiringParty: msg.sender,
            beneficiary: beneficiary,
            purpose: purpose,
            certificateHash: certificateHash,
            retiredAt: block.timestamp,
            vintageYear: record.vintageYear,
            isVerified: false
        });

        userRetirements[msg.sender].push(retirementId);
        yearlyRetirements[record.vintageYear] += amount;
        totalRetirements++;

        LifecycleState previousState = record.state;
        _transitionState(creditId, LifecycleState.Retired, "retire");

        _recordProvenance(
            creditId,
            previousState,
            LifecycleState.Retired,
            record.currentHolder,
            address(0),
            "retire",
            string(abi.encodePacked("beneficiary:", beneficiary, ",purpose:", purpose))
        );

        emit CreditRetired(retirementId, creditId, msg.sender, beneficiary, amount);
        return retirementId;
    }

    /**
     * @dev Invalidate credit (reversal, fraud detection)
     */
    function invalidateCredit(bytes32 creditId, string calldata reason)
        external
        onlyRole(LIFECYCLE_MANAGER_ROLE)
    {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");
        require(record.state != LifecycleState.Retired, "Cannot invalidate retired credit");

        LifecycleState previousState = record.state;
        _transitionState(creditId, LifecycleState.Invalidated, "invalidate");

        _recordProvenance(
            creditId,
            previousState,
            LifecycleState.Invalidated,
            record.currentHolder,
            address(0),
            "invalidate",
            reason
        );
    }

    /**
     * @dev Internal state transition
     */
    function _transitionState(
        bytes32 creditId,
        LifecycleState newState,
        string memory action
    ) internal {
        VintageRecord storage record = vintageRecords[creditId];
        LifecycleState oldState = record.state;

        creditsByState[oldState]--;
        creditsByState[newState]++;
        record.state = newState;

        emit LifecycleStateChanged(creditId, oldState, newState, action);
    }

    // ============ Locking Mechanism ============

    /**
     * @dev Lock a credit (for disputes, verification, etc.)
     */
    function lockCredit(bytes32 creditId, string calldata reason, uint256 duration)
        external
        onlyRole(LIFECYCLE_MANAGER_ROLE)
    {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");
        require(!locks[creditId].isActive, "Already locked");
        require(record.state != LifecycleState.Retired && record.state != LifecycleState.Invalidated, "Cannot lock");

        locks[creditId] = LockRecord({
            creditId: creditId,
            lockedAt: block.timestamp,
            unlockAt: block.timestamp + duration,
            reason: reason,
            lockedBy: msg.sender,
            isActive: true
        });

        LifecycleState previousState = record.state;
        _transitionState(creditId, LifecycleState.Locked, "lock");

        _recordProvenance(
            creditId,
            previousState,
            LifecycleState.Locked,
            record.currentHolder,
            record.currentHolder,
            "lock",
            reason
        );

        emit CreditLocked(creditId, reason, block.timestamp + duration);
    }

    /**
     * @dev Unlock a credit
     */
    function unlockCredit(bytes32 creditId, LifecycleState returnState)
        external
        onlyRole(LIFECYCLE_MANAGER_ROLE)
    {
        require(locks[creditId].isActive, "Not locked");
        require(
            returnState == LifecycleState.Active ||
            returnState == LifecycleState.Transferred ||
            returnState == LifecycleState.Minted,
            "Invalid return state"
        );

        VintageRecord storage record = vintageRecords[creditId];
        locks[creditId].isActive = false;

        _transitionState(creditId, returnState, "unlock");

        _recordProvenance(
            creditId,
            LifecycleState.Locked,
            returnState,
            record.currentHolder,
            record.currentHolder,
            "unlock",
            ""
        );

        emit CreditUnlocked(creditId);
    }

    // ============ Provenance Management ============

    /**
     * @dev Record provenance entry
     */
    function _recordProvenance(
        bytes32 creditId,
        LifecycleState fromState,
        LifecycleState toState,
        address fromAddress,
        address toAddress,
        string memory action,
        string memory metadata
    ) internal {
        bytes32 entryId = keccak256(abi.encodePacked(
            creditId,
            fromState,
            toState,
            block.timestamp,
            creditProvenance[creditId].length
        ));

        ProvenanceEntry memory entry = ProvenanceEntry({
            entryId: entryId,
            creditId: creditId,
            fromState: fromState,
            toState: toState,
            fromAddress: fromAddress,
            toAddress: toAddress,
            timestamp: block.timestamp,
            transactionHash: bytes32(0), // Can be set externally
            action: action,
            metadata: metadata
        });

        creditProvenance[creditId].push(entry);
        provenanceEntries[entryId] = entry;
    }

    /**
     * @dev Get full provenance history for a credit
     */
    function getProvenance(bytes32 creditId)
        external
        view
        returns (ProvenanceEntry[] memory)
    {
        return creditProvenance[creditId];
    }

    // ============ Geofencing ============

    /**
     * @dev Configure a jurisdiction geofence
     */
    function configureGeofence(
        bytes32 jurisdictionCode,
        string calldata jurisdictionName,
        bool requiresKYC,
        bool allowsInternationalTransfer,
        uint256 minTransferAmount,
        uint256 maxTransferAmount
    ) external onlyRole(GEOFENCE_ADMIN_ROLE) {
        bool isNew = geofences[jurisdictionCode].jurisdictionCode == bytes32(0);

        geofences[jurisdictionCode] = Geofence({
            jurisdictionCode: jurisdictionCode,
            jurisdictionName: jurisdictionName,
            isActive: true,
            requiresKYC: requiresKYC,
            allowsInternationalTransfer: allowsInternationalTransfer,
            minTransferAmount: minTransferAmount,
            maxTransferAmount: maxTransferAmount,
            approvedExchanges: new address[](0),
            compatibleJurisdictions: new bytes32[](0)
        });

        if (isNew) {
            jurisdictionList.push(jurisdictionCode);
        }

        emit GeofenceConfigured(jurisdictionCode, jurisdictionName, true);
    }

    /**
     * @dev Add compatible jurisdiction for transfers
     */
    function addCompatibleJurisdiction(bytes32 fromJurisdiction, bytes32 toJurisdiction)
        external
        onlyRole(GEOFENCE_ADMIN_ROLE)
    {
        require(geofences[fromJurisdiction].isActive, "Source jurisdiction not active");
        require(geofences[toJurisdiction].isActive, "Target jurisdiction not active");

        geofences[fromJurisdiction].compatibleJurisdictions.push(toJurisdiction);
    }

    /**
     * @dev Set user jurisdiction (for KYC)
     */
    function setUserJurisdiction(address user, bytes32 jurisdictionCode)
        external
        onlyRole(GEOFENCE_ADMIN_ROLE)
    {
        require(geofences[jurisdictionCode].isActive, "Jurisdiction not active");
        userJurisdiction[user] = jurisdictionCode;
    }

    /**
     * @dev Check if transfer is allowed under geofencing rules
     */
    function _checkGeofenceTransfer(
        bytes32 creditJurisdiction,
        address from,
        address to
    ) internal view {
        Geofence storage geofence = geofences[creditJurisdiction];

        if (!geofence.isActive) return;

        bytes32 toJurisdiction = userJurisdiction[to];

        // Check if international transfer
        if (toJurisdiction != creditJurisdiction) {
            require(geofence.allowsInternationalTransfer, "International transfer not allowed");

            // Check if target jurisdiction is compatible
            bool isCompatible = false;
            for (uint256 i = 0; i < geofence.compatibleJurisdictions.length; i++) {
                if (geofence.compatibleJurisdictions[i] == toJurisdiction) {
                    isCompatible = true;
                    break;
                }
            }
            require(isCompatible, "Incompatible jurisdiction");
        }
    }

    // ============ Discount Schedule Management ============

    /**
     * @dev Update discount schedule
     */
    function updateDiscountSchedule(
        uint256 premiumMaxAge,
        uint256 standardMaxAge,
        uint256 discountMaxAge,
        uint256 legacyMaxAge,
        uint256 premiumDiscount,
        uint256 standardDiscount,
        uint256 discountDiscount,
        uint256 legacyDiscount,
        uint256 archiveDiscount
    ) external onlyRole(VINTAGE_ADMIN_ROLE) {
        require(premiumMaxAge < standardMaxAge, "Invalid age progression");
        require(standardMaxAge < discountMaxAge, "Invalid age progression");
        require(discountMaxAge < legacyMaxAge, "Invalid age progression");
        require(archiveDiscount <= PRECISION, "Discount exceeds 100%");

        discountSchedule = DiscountSchedule({
            premiumMaxAge: premiumMaxAge,
            standardMaxAge: standardMaxAge,
            discountMaxAge: discountMaxAge,
            legacyMaxAge: legacyMaxAge,
            premiumDiscount: premiumDiscount,
            standardDiscount: standardDiscount,
            discountDiscount: discountDiscount,
            legacyDiscount: legacyDiscount,
            archiveDiscount: archiveDiscount
        });

        emit DiscountScheduleUpdated(
            premiumDiscount,
            standardDiscount,
            discountDiscount,
            legacyDiscount,
            archiveDiscount
        );
    }

    // ============ Query Functions ============

    /**
     * @dev Get vintage record
     */
    function getVintageRecord(bytes32 creditId)
        external
        view
        returns (VintageRecord memory)
    {
        return vintageRecords[creditId];
    }

    /**
     * @dev Get vintage record by token ID
     */
    function getVintageRecordByToken(uint256 tokenId)
        external
        view
        returns (VintageRecord memory)
    {
        bytes32 creditId = tokenToCreditId[tokenId];
        require(creditId != bytes32(0), "Token not tracked");
        return vintageRecords[creditId];
    }

    /**
     * @dev Get retirement record
     */
    function getRetirementRecord(bytes32 retirementId)
        external
        view
        returns (RetirementRecord memory)
    {
        return retirements[retirementId];
    }

    /**
     * @dev Get user retirements
     */
    function getUserRetirements(address user)
        external
        view
        returns (bytes32[] memory)
    {
        return userRetirements[user];
    }

    /**
     * @dev Check if credit is transferable
     */
    function isTransferable(bytes32 creditId) external view returns (bool) {
        VintageRecord storage record = vintageRecords[creditId];

        if (record.creditId == bytes32(0)) return false;
        if (locks[creditId].isActive) return false;
        if (record.state == LifecycleState.Retired ||
            record.state == LifecycleState.Invalidated ||
            record.state == LifecycleState.Expired) return false;
        if (record.state == LifecycleState.Minted &&
            block.timestamp < record.coolingOffEndsAt) return false;

        return true;
    }

    /**
     * @dev Get effective value after vintage discount
     */
    function getEffectiveValue(bytes32 creditId, uint256 baseValue)
        external
        view
        returns (uint256)
    {
        VintageRecord storage record = vintageRecords[creditId];
        require(record.creditId != bytes32(0), "Record not found");

        uint256 discount = record.discountFactor;
        return baseValue * (PRECISION - discount) / PRECISION;
    }

    /**
     * @dev Get credits by vintage year
     */
    function getCreditsByVintageYear(uint256 vintageYear)
        external
        view
        returns (uint256)
    {
        return creditsByVintageYear[vintageYear];
    }

    /**
     * @dev Get credits by state
     */
    function getCreditsByState(LifecycleState state)
        external
        view
        returns (uint256)
    {
        return creditsByState[state];
    }

    /**
     * @dev Get project credits
     */
    function getProjectCredits(bytes32 projectId)
        external
        view
        returns (bytes32[] memory)
    {
        return projectCredits[projectId];
    }

    /**
     * @dev Get geofence details
     */
    function getGeofence(bytes32 jurisdictionCode)
        external
        view
        returns (Geofence memory)
    {
        return geofences[jurisdictionCode];
    }

    /**
     * @dev Verify retirement certificate
     */
    function verifyRetirement(bytes32 retirementId)
        external
        onlyRole(LIFECYCLE_MANAGER_ROLE)
    {
        require(retirements[retirementId].retirementId != bytes32(0), "Retirement not found");
        retirements[retirementId].isVerified = true;
    }

    // ============ Admin Functions ============

    /**
     * @dev Pause contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title VintageTracker
 * @dev Comprehensive credit lifecycle and vintage tracking system with:
 * - Vintage year classification and automatic discount factors
 * - No cooling-off period - credits immediately transferable upon minting
 * - Credit provenance tracking with full history
 * - Geofencing for jurisdiction-specific compliance
 * - Lifecycle state machine (mint -> active -> transferred -> retired/invalidated)
 * - Vintage quality scoring based on age and verification status
 * - Slower discount curve reflecting methane's time-sensitive value
 *
 * This contract ensures credits maintain integrity throughout their lifecycle
 * and provides transparent provenance for regulatory compliance.
 */
contract VintageTracker is AccessControl, ReentrancyGuard, Pausable {
    // ============ Roles ============
    bytes32 public constant LIFECYCLE_MANAGER_ROLE = keccak256("LIFECYCLE_MANAGER_ROLE");
    bytes32 public constant GEOFENCE_ADMIN_ROLE = keccak256("GEOFENCE_ADMIN_ROLE");
    bytes32 public constant VINTAGE_ADMIN_ROLE = keccak256("VINTAGE_ADMIN_ROLE");

    // ============ Custom Errors ============
    error RecordExists();
    error InvalidCreditId();
    error InvalidVintageYear();
    error RecordNotFound();
    error CreditInactive();
    error NotInMintedState();
    error CannotTransfer();
    error CreditIsLocked();
    error CannotRetire();
    error CannotInvalidateRetiredCredit();
    error AlreadyLocked();
    error CannotLock();
    error NotLocked();
    error InvalidReturnState();
    error SourceJurisdictionNotActive();
    error TargetJurisdictionNotActive();
    error JurisdictionNotActive();
    error InternationalTransferNotAllowed();
    error IncompatibleJurisdiction();
    error InvalidAgeProgression();
    error DiscountExceedsMax();
    error TokenNotTracked();
    error RetirementNotFound();

    // ============ Constants ============
    uint256 public constant COOLING_OFF_PERIOD = 0;  // No cooling-off period - immediate transferability
    uint256 public constant MAX_VINTAGE_AGE = 10 * 365 days; // 10 years
    uint256 public constant PRECISION = 10000;
    uint256 public constant MIN_VINTAGE_QUALITY = 1000; // 10% minimum

    // ============ Enums ============
    enum LifecycleState {
        Minted,             // Just created, immediately active
        Active,             // Available for trading
        Locked,             // Temporarily locked (dispute, verification)
        Transferred,        // Has been transferred at least once
        Retired,            // Permanently retired (offset claimed)
        Invalidated,        // Cancelled due to reversal/fraud
        Expired             // Vintage too old
    }

    enum VintageGrade {
        Premium,            // < 2 years old (0% discount)
        Standard,           // 2-4 years old (2% discount)
        Discount,           // 4-6 years old (5% discount)
        Legacy,             // 6-8 years old (10% discount)
        Archive             // 8-10 years old (20% discount)
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

    /// @notice Vintage discount schedule - slower decline curve
    /// @dev Methane today is worth more than methane tomorrow, so discounts increase with age
    /// but at a gradual rate to preserve credit value
    struct DiscountSchedule {
        uint256 premiumMaxAge;          // Max age for Premium grade (2 years default)
        uint256 standardMaxAge;         // Max age for Standard grade (4 years default)
        uint256 discountMaxAge;         // Max age for Discount grade (6 years default)
        uint256 legacyMaxAge;           // Max age for Legacy grade (8 years default)
        uint256 premiumDiscount;        // 0 = no discount (newest credits)
        uint256 standardDiscount;       // e.g., 200 = 2% (gradual decline)
        uint256 discountDiscount;       // e.g., 500 = 5% (moderate decline)
        uint256 legacyDiscount;         // e.g., 1000 = 10% (older credits)
        uint256 archiveDiscount;        // e.g., 2000 = 20% (oldest accepted credits)
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

        // Set default discount schedule - slower decline curve
        // Methane today is worth more than methane tomorrow, but decline is gradual
        discountSchedule = DiscountSchedule({
            premiumMaxAge: 2 * 365 days,    // 2 years - Premium (no discount)
            standardMaxAge: 4 * 365 days,   // 4 years - Standard (2% discount)
            discountMaxAge: 6 * 365 days,   // 6 years - Discount (5% discount)
            legacyMaxAge: 8 * 365 days,     // 8 years - Legacy (10% discount)
            premiumDiscount: 0,             // 0% - newest credits retain full value
            standardDiscount: 200,          // 2% - very gradual decline
            discountDiscount: 500,          // 5% - moderate decline
            legacyDiscount: 1000,           // 10% - older credits
            archiveDiscount: 2000           // 20% - maximum discount for oldest credits
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
        if (vintageRecords[creditId].creditId != bytes32(0)) revert RecordExists();
        if (creditId == bytes32(0)) revert InvalidCreditId();
        // solhint-disable-next-line not-rely-on-time
        if (vintageYear < 2000 || vintageYear > block.timestamp / 365 days + 1970 + 1) revert InvalidVintageYear();

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
        if (record.creditId == bytes32(0)) revert RecordNotFound();
        if (record.state == LifecycleState.Retired || record.state == LifecycleState.Invalidated) revert CreditInactive();

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
     * @dev Activate credit - no cooling-off period required
     * @notice Credits are immediately active upon minting but this function
     * can be used to explicitly transition state if needed
     */
    function activateCredit(bytes32 creditId) external {
        VintageRecord storage record = vintageRecords[creditId];
        if (record.creditId == bytes32(0)) revert RecordNotFound();
        if (record.state != LifecycleState.Minted) revert NotInMintedState();
        // No cooling-off period check - credits are immediately transferable

        _transitionState(creditId, LifecycleState.Active, "activate");
    }

    /**
     * @dev Record a credit transfer
     * @notice No cooling-off period - credits are immediately transferable
     */
    function recordTransfer(
        bytes32 creditId,
        address from,
        address to,
        bytes32 transactionHash
    ) external onlyRole(LIFECYCLE_MANAGER_ROLE) {
        VintageRecord storage record = vintageRecords[creditId];
        if (record.creditId == bytes32(0)) revert RecordNotFound();
        // Allow transfer from Minted state as well since no cooling-off period
        if (record.state != LifecycleState.Minted &&
            record.state != LifecycleState.Active &&
            record.state != LifecycleState.Transferred) revert CannotTransfer();
        if (locks[creditId].isActive) revert CreditIsLocked();

        // No cooling-off period check - credits are immediately transferable

        // Check geofencing
        if (record.isGeofenced) {
            _checkGeofenceTransfer(record.jurisdictionCode, from, to);
        }

        LifecycleState previousState = record.state;
        record.currentHolder = to;
        record.transferCount++;
        record.lastTransferAt = block.timestamp;

        // Transition to Transferred state from Minted or Active
        if (record.state == LifecycleState.Minted || record.state == LifecycleState.Active) {
            creditsByState[previousState]--;
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
        if (record.creditId == bytes32(0)) revert RecordNotFound();
        if (record.state != LifecycleState.Active && record.state != LifecycleState.Transferred) revert CannotRetire();
        if (locks[creditId].isActive) revert CreditIsLocked();

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
        if (record.creditId == bytes32(0)) revert RecordNotFound();
        if (record.state == LifecycleState.Retired) revert CannotInvalidateRetiredCredit();

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
        if (record.creditId == bytes32(0)) revert RecordNotFound();
        if (locks[creditId].isActive) revert AlreadyLocked();
        if (record.state == LifecycleState.Retired || record.state == LifecycleState.Invalidated) revert CannotLock();

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
        if (!locks[creditId].isActive) revert NotLocked();
        if (returnState != LifecycleState.Active &&
            returnState != LifecycleState.Transferred &&
            returnState != LifecycleState.Minted) revert InvalidReturnState();

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

        // Write directly to storage to avoid stack too deep
        ProvenanceEntry storage entry = provenanceEntries[entryId];
        entry.entryId = entryId;
        entry.creditId = creditId;
        entry.fromState = fromState;
        entry.toState = toState;
        entry.fromAddress = fromAddress;
        entry.toAddress = toAddress;
        entry.timestamp = block.timestamp;
        entry.transactionHash = bytes32(0);
        entry.action = action;
        entry.metadata = metadata;

        creditProvenance[creditId].push(entry);
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
        if (!geofences[fromJurisdiction].isActive) revert SourceJurisdictionNotActive();
        if (!geofences[toJurisdiction].isActive) revert TargetJurisdictionNotActive();

        geofences[fromJurisdiction].compatibleJurisdictions.push(toJurisdiction);
    }

    /**
     * @dev Set user jurisdiction (for KYC)
     */
    function setUserJurisdiction(address user, bytes32 jurisdictionCode)
        external
        onlyRole(GEOFENCE_ADMIN_ROLE)
    {
        if (!geofences[jurisdictionCode].isActive) revert JurisdictionNotActive();
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
            if (!geofence.allowsInternationalTransfer) revert InternationalTransferNotAllowed();

            // Check if target jurisdiction is compatible
            bool isCompatible = false;
            for (uint256 i = 0; i < geofence.compatibleJurisdictions.length; i++) {
                if (geofence.compatibleJurisdictions[i] == toJurisdiction) {
                    isCompatible = true;
                    break;
                }
            }
            if (!isCompatible) revert IncompatibleJurisdiction();
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
        if (premiumMaxAge >= standardMaxAge) revert InvalidAgeProgression();
        if (standardMaxAge >= discountMaxAge) revert InvalidAgeProgression();
        if (discountMaxAge >= legacyMaxAge) revert InvalidAgeProgression();
        if (archiveDiscount > PRECISION) revert DiscountExceedsMax();

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
        if (creditId == bytes32(0)) revert TokenNotTracked();
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
     * @notice No cooling-off period - Minted credits are immediately transferable
     */
    function isTransferable(bytes32 creditId) external view returns (bool) {
        VintageRecord storage record = vintageRecords[creditId];

        if (record.creditId == bytes32(0)) return false;
        if (locks[creditId].isActive) return false;
        if (record.state == LifecycleState.Retired ||
            record.state == LifecycleState.Invalidated ||
            record.state == LifecycleState.Expired) return false;
        // No cooling-off period check - Minted credits are immediately transferable

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
        if (record.creditId == bytes32(0)) revert RecordNotFound();

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
        if (retirements[retirementId].retirementId == bytes32(0)) revert RetirementNotFound();
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

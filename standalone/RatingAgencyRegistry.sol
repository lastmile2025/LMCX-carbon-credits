// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RatingAgencyRegistry
 * @dev Manages rating agencies and their assessments of carbon credits.
 *
 * This contract allows:
 * - Registration of accredited rating agencies
 * - Rating submission for carbon credit tokens
 * - Rating history tracking and versioning
 * - Integration with InsuranceManager for risk-based pricing
 * - Aggregated ratings from multiple agencies
 *
 * Rating Scale: 0-10000 (basis points)
 * - 9000-10000: AAA (Highest quality)
 * - 8000-8999:  AA
 * - 7000-7999:  A
 * - 6000-6999:  BBB (Investment grade)
 * - 5000-5999:  BB
 * - 4000-4999:  B
 * - 3000-3999:  CCC
 * - 2000-2999:  CC
 * - 1000-1999:  C
 * - 0-999:      D (Default/Highest risk)
 */
contract RatingAgencyRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");
    bytes32 public constant RATING_AGENCY_ROLE = keccak256("RATING_AGENCY_ROLE");

    // ============ Data Structures ============

    /// @notice Rating agency registration
    struct RatingAgency {
        bytes32 agencyId;
        string name;
        string methodology;          // Description of rating methodology
        address ratingAddress;       // Address authorized to submit ratings
        uint256 registeredAt;
        uint256 totalRatingsIssued;
        bool isAccredited;
        string accreditationHash;    // IPFS hash of accreditation documents
        string[] certifications;     // e.g., "ISO 17065", "IOSCO compliant"
    }

    /// @notice Individual rating for a token
    struct Rating {
        bytes32 ratingId;
        bytes32 agencyId;
        uint256 tokenId;
        uint256 score;               // 0-10000 scale
        string grade;                // Letter grade (AAA, AA, A, BBB, etc.)
        uint256 timestamp;
        uint256 validUntil;          // Rating expiration
        string rationale;            // Brief explanation
        string fullReportHash;       // IPFS hash of detailed report
        bool isActive;
    }

    /// @notice Rating category breakdown
    struct RatingBreakdown {
        uint256 projectQuality;      // 0-10000
        uint256 methodology;         // 0-10000
        uint256 permanence;          // 0-10000
        uint256 additionality;       // 0-10000
        uint256 verification;        // 0-10000
        uint256 governance;          // 0-10000
    }

    /// @notice Rating action for audit trail
    struct RatingAction {
        uint256 actionId;
        bytes32 agencyId;
        uint256 tokenId;
        string actionType;           // "INITIAL", "UPGRADE", "DOWNGRADE", "AFFIRM", "WITHDRAW"
        uint256 previousScore;
        uint256 newScore;
        uint256 timestamp;
        string reason;
    }

    /// @notice Watch list entry
    struct WatchListEntry {
        uint256 tokenId;
        bytes32 agencyId;
        string direction;            // "POSITIVE", "NEGATIVE", "DEVELOPING"
        uint256 addedAt;
        string reason;
        bool isActive;
    }

    // ============ Storage ============

    // Agency management
    mapping(bytes32 => RatingAgency) public agencies;
    bytes32[] public agencyList;
    mapping(address => bytes32) public addressToAgency;
    
    // Ratings storage
    mapping(bytes32 => Rating) public ratings;                    // ratingId => Rating
    mapping(uint256 => bytes32[]) public tokenRatings;           // tokenId => ratingIds
    mapping(bytes32 => mapping(uint256 => bytes32)) public agencyTokenRating; // agencyId => tokenId => ratingId
    
    // Rating breakdowns
    mapping(bytes32 => RatingBreakdown) public ratingBreakdowns; // ratingId => breakdown
    
    // Rating actions history
    mapping(uint256 => RatingAction[]) public ratingHistory;      // tokenId => actions
    uint256 public nextActionId;
    
    // Watch list
    mapping(uint256 => WatchListEntry[]) public watchList;        // tokenId => entries
    
    // Aggregated ratings
    mapping(uint256 => uint256) public aggregatedScores;          // tokenId => weighted average
    mapping(uint256 => uint256) public ratingCount;               // tokenId => number of active ratings

    // Insurance manager integration
    address public insuranceManager;

    // ============ Events ============

    event AgencyRegistered(
        bytes32 indexed agencyId,
        string name,
        address ratingAddress
    );

    event AgencyAccreditationUpdated(
        bytes32 indexed agencyId,
        bool isAccredited
    );

    event RatingIssued(
        bytes32 indexed ratingId,
        bytes32 indexed agencyId,
        uint256 indexed tokenId,
        uint256 score,
        string grade
    );

    event RatingUpdated(
        bytes32 indexed ratingId,
        uint256 previousScore,
        uint256 newScore,
        string actionType
    );

    event RatingWithdrawn(
        bytes32 indexed ratingId,
        bytes32 indexed agencyId,
        uint256 indexed tokenId
    );

    event WatchListUpdated(
        uint256 indexed tokenId,
        bytes32 indexed agencyId,
        string direction
    );

    event AggregatedScoreUpdated(
        uint256 indexed tokenId,
        uint256 newScore,
        uint256 ratingCount
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_ADMIN_ROLE, msg.sender);
    }

    // ============ Agency Management ============

    /**
     * @dev Register a new rating agency
     */
    function registerAgency(
        bytes32 agencyId,
        string calldata name,
        string calldata methodology,
        address ratingAddress,
        string calldata accreditationHash,
        string[] calldata certifications
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        require(agencyId != bytes32(0), "Invalid agencyId");
        require(agencies[agencyId].agencyId == bytes32(0), "Agency exists");
        require(ratingAddress != address(0), "Invalid address");

        agencies[agencyId] = RatingAgency({
            agencyId: agencyId,
            name: name,
            methodology: methodology,
            ratingAddress: ratingAddress,
            registeredAt: block.timestamp,
            totalRatingsIssued: 0,
            isAccredited: true,
            accreditationHash: accreditationHash,
            certifications: certifications
        });

        agencyList.push(agencyId);
        addressToAgency[ratingAddress] = agencyId;
        
        _grantRole(RATING_AGENCY_ROLE, ratingAddress);

        emit AgencyRegistered(agencyId, name, ratingAddress);
    }

    /**
     * @dev Update agency accreditation status
     */
    function updateAccreditation(
        bytes32 agencyId,
        bool isAccredited
    ) external onlyRole(REGISTRY_ADMIN_ROLE) {
        require(agencies[agencyId].agencyId != bytes32(0), "Agency not found");
        agencies[agencyId].isAccredited = isAccredited;
        
        if (!isAccredited) {
            _revokeRole(RATING_AGENCY_ROLE, agencies[agencyId].ratingAddress);
        } else {
            _grantRole(RATING_AGENCY_ROLE, agencies[agencyId].ratingAddress);
        }

        emit AgencyAccreditationUpdated(agencyId, isAccredited);
    }

    // ============ Rating Operations ============

    /**
     * @dev Convert score to letter grade
     */
    function scoreToGrade(uint256 score) public pure returns (string memory) {
        if (score >= 9000) return "AAA";
        if (score >= 8500) return "AA+";
        if (score >= 8000) return "AA";
        if (score >= 7500) return "A+";
        if (score >= 7000) return "A";
        if (score >= 6500) return "BBB+";
        if (score >= 6000) return "BBB";
        if (score >= 5500) return "BB+";
        if (score >= 5000) return "BB";
        if (score >= 4500) return "B+";
        if (score >= 4000) return "B";
        if (score >= 3000) return "CCC";
        if (score >= 2000) return "CC";
        if (score >= 1000) return "C";
        return "D";
    }

    /**
     * @dev Issue a new rating
     */
    function issueRating(
        uint256 tokenId,
        uint256 score,
        uint256 validityDays,
        string calldata rationale,
        string calldata fullReportHash,
        RatingBreakdown calldata breakdown
    ) external onlyRole(RATING_AGENCY_ROLE) returns (bytes32 ratingId) {
        bytes32 agencyId = addressToAgency[msg.sender];
        require(agencies[agencyId].isAccredited, "Agency not accredited");
        require(score <= 10000, "Invalid score");
        require(validityDays >= 30 && validityDays <= 365, "Invalid validity");

        ratingId = keccak256(abi.encodePacked(agencyId, tokenId, block.timestamp));
        
        string memory grade = scoreToGrade(score);

        ratings[ratingId] = Rating({
            ratingId: ratingId,
            agencyId: agencyId,
            tokenId: tokenId,
            score: score,
            grade: grade,
            timestamp: block.timestamp,
            validUntil: block.timestamp + (validityDays * 1 days),
            rationale: rationale,
            fullReportHash: fullReportHash,
            isActive: true
        });

        ratingBreakdowns[ratingId] = breakdown;

        // Deactivate previous rating from same agency
        bytes32 previousRatingId = agencyTokenRating[agencyId][tokenId];
        if (previousRatingId != bytes32(0) && ratings[previousRatingId].isActive) {
            ratings[previousRatingId].isActive = false;
        }

        tokenRatings[tokenId].push(ratingId);
        agencyTokenRating[agencyId][tokenId] = ratingId;
        agencies[agencyId].totalRatingsIssued++;

        // Record action
        _recordAction(agencyId, tokenId, "INITIAL", 0, score, "New rating issued");

        // Update aggregated score
        _updateAggregatedScore(tokenId);

        emit RatingIssued(ratingId, agencyId, tokenId, score, grade);
    }

    /**
     * @dev Update an existing rating
     */
    function updateRating(
        uint256 tokenId,
        uint256 newScore,
        string calldata actionType,
        string calldata rationale,
        string calldata fullReportHash
    ) external onlyRole(RATING_AGENCY_ROLE) {
        bytes32 agencyId = addressToAgency[msg.sender];
        bytes32 ratingId = agencyTokenRating[agencyId][tokenId];
        
        require(ratingId != bytes32(0), "No existing rating");
        require(ratings[ratingId].isActive, "Rating not active");
        require(newScore <= 10000, "Invalid score");
        require(
            keccak256(bytes(actionType)) == keccak256(bytes("UPGRADE")) ||
            keccak256(bytes(actionType)) == keccak256(bytes("DOWNGRADE")) ||
            keccak256(bytes(actionType)) == keccak256(bytes("AFFIRM")),
            "Invalid action type"
        );

        Rating storage rating = ratings[ratingId];
        uint256 previousScore = rating.score;

        rating.score = newScore;
        rating.grade = scoreToGrade(newScore);
        rating.timestamp = block.timestamp;
        rating.rationale = rationale;
        rating.fullReportHash = fullReportHash;

        // Record action
        _recordAction(agencyId, tokenId, actionType, previousScore, newScore, rationale);

        // Update aggregated score
        _updateAggregatedScore(tokenId);

        emit RatingUpdated(ratingId, previousScore, newScore, actionType);
    }

    /**
     * @dev Withdraw a rating
     */
    function withdrawRating(
        uint256 tokenId,
        string calldata reason
    ) external onlyRole(RATING_AGENCY_ROLE) {
        bytes32 agencyId = addressToAgency[msg.sender];
        bytes32 ratingId = agencyTokenRating[agencyId][tokenId];
        
        require(ratingId != bytes32(0), "No existing rating");
        require(ratings[ratingId].isActive, "Rating not active");

        Rating storage rating = ratings[ratingId];
        uint256 previousScore = rating.score;
        
        rating.isActive = false;

        // Record action
        _recordAction(agencyId, tokenId, "WITHDRAW", previousScore, 0, reason);

        // Update aggregated score
        _updateAggregatedScore(tokenId);

        emit RatingWithdrawn(ratingId, agencyId, tokenId);
    }

    // ============ Watch List Management ============

    /**
     * @dev Add token to watch list
     */
    function addToWatchList(
        uint256 tokenId,
        string calldata direction,
        string calldata reason
    ) external onlyRole(RATING_AGENCY_ROLE) {
        bytes32 agencyId = addressToAgency[msg.sender];
        
        require(
            keccak256(bytes(direction)) == keccak256(bytes("POSITIVE")) ||
            keccak256(bytes(direction)) == keccak256(bytes("NEGATIVE")) ||
            keccak256(bytes(direction)) == keccak256(bytes("DEVELOPING")),
            "Invalid direction"
        );

        watchList[tokenId].push(WatchListEntry({
            tokenId: tokenId,
            agencyId: agencyId,
            direction: direction,
            addedAt: block.timestamp,
            reason: reason,
            isActive: true
        }));

        emit WatchListUpdated(tokenId, agencyId, direction);
    }

    /**
     * @dev Remove token from watch list
     */
    function removeFromWatchList(uint256 tokenId) external onlyRole(RATING_AGENCY_ROLE) {
        bytes32 agencyId = addressToAgency[msg.sender];
        WatchListEntry[] storage entries = watchList[tokenId];
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].agencyId == agencyId && entries[i].isActive) {
                entries[i].isActive = false;
            }
        }
    }

    // ============ Internal Functions ============

    /**
     * @dev Record rating action for audit trail
     */
    function _recordAction(
        bytes32 agencyId,
        uint256 tokenId,
        string memory actionType,
        uint256 previousScore,
        uint256 newScore,
        string memory reason
    ) internal {
        ratingHistory[tokenId].push(RatingAction({
            actionId: nextActionId++,
            agencyId: agencyId,
            tokenId: tokenId,
            actionType: actionType,
            previousScore: previousScore,
            newScore: newScore,
            timestamp: block.timestamp,
            reason: reason
        }));
    }

    /**
     * @dev Update aggregated score from all active ratings
     */
    function _updateAggregatedScore(uint256 tokenId) internal {
        bytes32[] memory ratingIds = tokenRatings[tokenId];
        uint256 totalScore = 0;
        uint256 activeCount = 0;

        for (uint256 i = 0; i < ratingIds.length; i++) {
            Rating memory rating = ratings[ratingIds[i]];
            if (rating.isActive && block.timestamp <= rating.validUntil) {
                totalScore += rating.score;
                activeCount++;
            }
        }

        if (activeCount > 0) {
            aggregatedScores[tokenId] = totalScore / activeCount;
        } else {
            aggregatedScores[tokenId] = 0;
        }
        
        ratingCount[tokenId] = activeCount;

        // Update insurance manager if set
        if (insuranceManager != address(0) && activeCount > 0) {
            // Convert to risk score (invert: high rating = low risk)
            // Rating 9000 => Risk 1000, Rating 1000 => Risk 9000
            uint256 riskScore = 10000 - aggregatedScores[tokenId];
            IInsuranceManager(insuranceManager).updateRiskScore(tokenId, riskScore);
        }

        emit AggregatedScoreUpdated(tokenId, aggregatedScores[tokenId], activeCount);
    }

    // ============ Query Functions ============

    /**
     * @dev Get all active ratings for a token
     */
    function getActiveRatings(uint256 tokenId) external view returns (Rating[] memory) {
        bytes32[] memory ratingIds = tokenRatings[tokenId];
        uint256 activeCount = 0;

        // Count active ratings
        for (uint256 i = 0; i < ratingIds.length; i++) {
            if (ratings[ratingIds[i]].isActive && 
                block.timestamp <= ratings[ratingIds[i]].validUntil) {
                activeCount++;
            }
        }

        // Build active ratings array
        Rating[] memory activeRatings = new Rating[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < ratingIds.length; i++) {
            if (ratings[ratingIds[i]].isActive && 
                block.timestamp <= ratings[ratingIds[i]].validUntil) {
                activeRatings[index++] = ratings[ratingIds[i]];
            }
        }

        return activeRatings;
    }

    /**
     * @dev Get rating from specific agency for a token
     */
    function getAgencyRating(bytes32 agencyId, uint256 tokenId) 
        external 
        view 
        returns (Rating memory) 
    {
        bytes32 ratingId = agencyTokenRating[agencyId][tokenId];
        return ratings[ratingId];
    }

    /**
     * @dev Get rating breakdown
     */
    function getRatingBreakdown(bytes32 ratingId) 
        external 
        view 
        returns (RatingBreakdown memory) 
    {
        return ratingBreakdowns[ratingId];
    }

    /**
     * @dev Get aggregated score and grade for a token
     */
    function getAggregatedRating(uint256 tokenId) 
        external 
        view 
        returns (uint256 score, string memory grade, uint256 count) 
    {
        score = aggregatedScores[tokenId];
        grade = scoreToGrade(score);
        count = ratingCount[tokenId];
    }

    /**
     * @dev Get rating history for a token
     */
    function getRatingHistory(uint256 tokenId) 
        external 
        view 
        returns (RatingAction[] memory) 
    {
        return ratingHistory[tokenId];
    }

    /**
     * @dev Get active watch list entries for a token
     */
    function getActiveWatchListEntries(uint256 tokenId) 
        external 
        view 
        returns (WatchListEntry[] memory) 
    {
        WatchListEntry[] memory entries = watchList[tokenId];
        uint256 activeCount = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isActive) activeCount++;
        }

        WatchListEntry[] memory activeEntries = new WatchListEntry[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isActive) {
                activeEntries[index++] = entries[i];
            }
        }

        return activeEntries;
    }

    /**
     * @dev Check if token is investment grade (BBB or above)
     */
    function isInvestmentGrade(uint256 tokenId) external view returns (bool) {
        return aggregatedScores[tokenId] >= 6000;
    }

    /**
     * @dev Get all registered agencies
     */
    function getAllAgencies() external view returns (bytes32[] memory) {
        return agencyList;
    }

    // ============ Insurance Integration ============

    /**
     * @dev Set insurance manager for risk score updates
     */
    function setInsuranceManager(address _insuranceManager) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        insuranceManager = _insuranceManager;
    }
}

interface IInsuranceManager {
    function updateRiskScore(uint256 tokenId, uint256 score) external;
}

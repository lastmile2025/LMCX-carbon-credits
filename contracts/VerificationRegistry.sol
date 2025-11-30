// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title VerificationRegistry
 * @dev Cryptographic proof chain system for carbon credit verification with:
 * - Merkle tree proofs for verification data integrity
 * - Multi-verifier signature aggregation
 * - Immutable audit trail with IPFS/Arweave storage references
 * - Chain-of-custody tracking for credits
 * - Zero-knowledge proof support for sensitive data
 *
 * This contract serves as the cryptographic backbone for ensuring
 * the highest integrity verification of carbon credits.
 */
contract VerificationRegistry is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    using MerkleProof for bytes32[];

    // ============ Roles ============
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");
    bytes32 public constant PROOF_SUBMITTER_ROLE = keccak256("PROOF_SUBMITTER_ROLE");

    // ============ Custom Errors ============
    error RecordExists();
    error InvalidProjectId();
    error InvalidMerkleRoot();
    error InsufficientRequiredSignatures();
    error RecordNotFound();
    error ProofExists();
    error InvalidRecordStatus();
    error ArrayMismatch();
    error BatchTooLarge();
    error AlreadyRegistered();
    error InvalidReputation();
    error InvalidStatus();
    error AlreadySigned();
    error InvalidSignature();
    error EmptyBatch();
    error BatchNotFound();
    error AlreadyFinalized();
    error EmptyLeaves();
    error ProofNotFound();
    error NoVerificationRecord();
    error NotVerified();
    error NotAVerifier();

    // ============ Constants ============
    uint256 public constant MIN_VERIFIER_SIGNATURES = 2;
    uint256 public constant PROOF_VALIDITY_PERIOD = 365 days;
    uint256 public constant MAX_BATCH_SIZE = 100;

    // ============ Enums ============
    enum VerificationStatus {
        Pending,
        InProgress,
        Verified,
        Rejected,
        Expired,
        Revoked
    }

    enum ProofType {
        MerkleInclusion,        // Standard Merkle proof
        MultiSigAttestation,    // Multiple verifier signatures
        ZKProof,                // Zero-knowledge proof
        OracleAttestation,      // Oracle-signed data
        DocumentHash,           // Document integrity proof
        ChainOfCustody          // Custody transfer proof
    }

    // ============ Structs ============

    /// @notice Core verification record
    struct VerificationRecord {
        bytes32 recordId;
        bytes32 projectId;
        bytes32 creditTokenId;          // Associated credit token

        // Merkle tree data
        bytes32 merkleRoot;
        uint256 leafCount;

        // Verification status
        VerificationStatus status;
        uint256 verifiedAt;
        uint256 expiresAt;

        // Verifier tracking
        address[] verifiers;
        uint256 requiredSignatures;
        uint256 signatureCount;

        // Storage references
        string ipfsHash;                // IPFS CID for full data
        string arweaveHash;             // Arweave TX for permanent storage

        // Metadata
        bytes32 methodologyHash;
        uint256 vintageYear;
        int256 verifiedReductions;      // Scaled by 1e6 (tonnes CO2e)
    }

    /// @notice Individual proof entry
    struct ProofEntry {
        bytes32 proofId;
        bytes32 recordId;
        ProofType proofType;
        bytes32 dataHash;
        bytes proof;                    // Encoded proof data
        address submitter;
        uint256 submittedAt;
        bool isValid;
        string storageRef;              // IPFS/Arweave reference
    }

    /// @notice Verifier signature for attestation
    struct VerifierSignature {
        address verifier;
        bytes signature;
        uint256 signedAt;
        bytes32 attestationHash;
        string comments;
    }

    /// @notice Chain of custody entry
    struct CustodyEntry {
        bytes32 entryId;
        bytes32 creditTokenId;
        address from;
        address to;
        uint256 timestamp;
        bytes32 transactionHash;
        bytes32 previousEntryId;        // Links to previous custody
        string custodyType;             // "mint", "transfer", "retire", "invalidate"
        bytes32 merkleRoot;             // Root including all prior custody
    }

    /// @notice Merkle tree batch for efficient verification
    struct MerkleBatch {
        bytes32 batchId;
        bytes32[] recordIds;
        bytes32 batchRoot;
        uint256 createdAt;
        bool isFinalized;
        uint256 itemCount;
    }

    /// @notice Zero-knowledge proof metadata
    struct ZKProofRecord {
        bytes32 proofId;
        bytes32 verificationKey;
        bytes32 publicInputHash;
        bytes proof;
        bool isVerified;
        string proofSystem;             // "groth16", "plonk", "stark"
    }

    // ============ Storage ============

    // Verification records
    mapping(bytes32 => VerificationRecord) public records;
    mapping(bytes32 => bytes32[]) public projectRecords;        // projectId => recordIds
    mapping(bytes32 => bytes32) public creditVerification;      // creditTokenId => recordId

    // Proof storage
    mapping(bytes32 => ProofEntry) public proofs;
    mapping(bytes32 => bytes32[]) public recordProofs;          // recordId => proofIds

    // Verifier signatures
    mapping(bytes32 => mapping(address => VerifierSignature)) public verifierSignatures;
    mapping(bytes32 => address[]) public recordVerifiers;

    // Chain of custody
    mapping(bytes32 => CustodyEntry) public custodyEntries;
    mapping(bytes32 => bytes32[]) public creditCustodyChain;    // creditTokenId => entryIds
    mapping(bytes32 => bytes32) public latestCustody;           // creditTokenId => latest entryId

    // Merkle batches
    mapping(bytes32 => MerkleBatch) public batches;
    uint256 public batchCount;

    // ZK proofs
    mapping(bytes32 => ZKProofRecord) public zkProofs;

    // Trusted verifiers registry
    mapping(address => bool) public trustedVerifiers;
    mapping(address => uint256) public verifierReputation;      // Reputation score 0-10000

    // Global Merkle root for all verifications
    bytes32 public globalMerkleRoot;
    uint256 public globalRecordCount;

    // ============ Events ============

    event VerificationRecordCreated(
        bytes32 indexed recordId,
        bytes32 indexed projectId,
        bytes32 indexed creditTokenId,
        bytes32 merkleRoot
    );

    event VerificationCompleted(
        bytes32 indexed recordId,
        VerificationStatus status,
        uint256 signatureCount,
        int256 verifiedReductions
    );

    event ProofSubmitted(
        bytes32 indexed proofId,
        bytes32 indexed recordId,
        ProofType proofType,
        address submitter
    );

    event VerifierSigned(
        bytes32 indexed recordId,
        address indexed verifier,
        bytes32 attestationHash
    );

    event CustodyTransferred(
        bytes32 indexed entryId,
        bytes32 indexed creditTokenId,
        address indexed from,
        address to,
        string custodyType
    );

    event MerkleBatchCreated(
        bytes32 indexed batchId,
        bytes32 batchRoot,
        uint256 itemCount
    );

    event GlobalRootUpdated(
        bytes32 newRoot,
        uint256 totalRecords
    );

    event VerifierRegistered(
        address indexed verifier,
        uint256 reputation
    );

    event ZKProofVerified(
        bytes32 indexed proofId,
        bytes32 indexed recordId,
        bool isValid
    );

    // ============ Constructor ============

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_ADMIN_ROLE, msg.sender);
    }

    // ============ Verification Record Management ============

    /**
     * @dev Create a new verification record
     */
    function createVerificationRecord(
        bytes32 recordId,
        bytes32 projectId,
        bytes32 creditTokenId,
        bytes32 merkleRoot,
        uint256 leafCount,
        uint256 requiredSignatures,
        string calldata ipfsHash,
        bytes32 methodologyHash,
        uint256 vintageYear
    ) external onlyRole(PROOF_SUBMITTER_ROLE) returns (bytes32) {
        if (records[recordId].recordId != bytes32(0)) revert RecordExists();
        if (projectId == bytes32(0)) revert InvalidProjectId();
        if (merkleRoot == bytes32(0)) revert InvalidMerkleRoot();
        if (requiredSignatures < MIN_VERIFIER_SIGNATURES) revert InsufficientRequiredSignatures();

        records[recordId] = VerificationRecord({
            recordId: recordId,
            projectId: projectId,
            creditTokenId: creditTokenId,
            merkleRoot: merkleRoot,
            leafCount: leafCount,
            status: VerificationStatus.Pending,
            verifiedAt: 0,
            expiresAt: 0,
            verifiers: new address[](0),
            requiredSignatures: requiredSignatures,
            signatureCount: 0,
            ipfsHash: ipfsHash,
            arweaveHash: "",
            methodologyHash: methodologyHash,
            vintageYear: vintageYear,
            verifiedReductions: 0
        });

        projectRecords[projectId].push(recordId);

        if (creditTokenId != bytes32(0)) {
            creditVerification[creditTokenId] = recordId;
        }

        globalRecordCount++;

        emit VerificationRecordCreated(recordId, projectId, creditTokenId, merkleRoot);
        return recordId;
    }

    /**
     * @dev Update record with permanent storage reference
     */
    function setArweaveHash(bytes32 recordId, string calldata arweaveHash)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        if (records[recordId].recordId == bytes32(0)) revert RecordNotFound();
        records[recordId].arweaveHash = arweaveHash;
    }

    // ============ Proof Submission ============

    /**
     * @dev Submit a proof for a verification record
     */
    function submitProof(
        bytes32 proofId,
        bytes32 recordId,
        ProofType proofType,
        bytes32 dataHash,
        bytes calldata proof,
        string calldata storageRef
    ) external onlyRole(PROOF_SUBMITTER_ROLE) {
        if (proofs[proofId].proofId != bytes32(0)) revert ProofExists();
        if (records[recordId].recordId == bytes32(0)) revert RecordNotFound();
        if (records[recordId].status != VerificationStatus.Pending &&
            records[recordId].status != VerificationStatus.InProgress) revert InvalidRecordStatus();

        proofs[proofId] = ProofEntry({
            proofId: proofId,
            recordId: recordId,
            proofType: proofType,
            dataHash: dataHash,
            proof: proof,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            isValid: false,
            storageRef: storageRef
        });

        recordProofs[recordId].push(proofId);

        if (records[recordId].status == VerificationStatus.Pending) {
            records[recordId].status = VerificationStatus.InProgress;
        }

        emit ProofSubmitted(proofId, recordId, proofType, msg.sender);
    }

    /**
     * @dev Verify a Merkle inclusion proof
     */
    function verifyMerkleProof(
        bytes32 recordId,
        bytes32 leaf,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        VerificationRecord storage record = records[recordId];
        if (record.recordId == bytes32(0)) revert RecordNotFound();

        return merkleProof.verify(record.merkleRoot, leaf);
    }

    /**
     * @dev Batch verify multiple Merkle proofs
     */
    function batchVerifyMerkleProofs(
        bytes32 recordId,
        bytes32[] calldata leaves,
        bytes32[][] calldata merkleProofs
    ) external view returns (bool[] memory results) {
        if (leaves.length != merkleProofs.length) revert ArrayMismatch();
        if (leaves.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        VerificationRecord storage record = records[recordId];
        if (record.recordId == bytes32(0)) revert RecordNotFound();

        results = new bool[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            results[i] = merkleProofs[i].verify(record.merkleRoot, leaves[i]);
        }

        return results;
    }

    // ============ Verifier Signature Management ============

    /**
     * @dev Register as a trusted verifier
     */
    function registerVerifier(address verifier, uint256 initialReputation)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        if (trustedVerifiers[verifier]) revert AlreadyRegistered();
        if (initialReputation > 10000) revert InvalidReputation();

        trustedVerifiers[verifier] = true;
        verifierReputation[verifier] = initialReputation;
        _grantRole(VERIFIER_ROLE, verifier);

        emit VerifierRegistered(verifier, initialReputation);
    }

    /**
     * @dev Sign and attest to a verification record
     */
    function signVerification(
        bytes32 recordId,
        bytes calldata signature,
        int256 verifiedReductions,
        string calldata comments
    ) external onlyRole(VERIFIER_ROLE) {
        VerificationRecord storage record = records[recordId];
        if (record.recordId == bytes32(0)) revert RecordNotFound();
        if (record.status != VerificationStatus.InProgress) revert InvalidStatus();
        if (verifierSignatures[recordId][msg.sender].verifier != address(0)) revert AlreadySigned();

        // Create attestation hash
        bytes32 attestationHash = keccak256(abi.encodePacked(
            recordId,
            record.merkleRoot,
            verifiedReductions,
            msg.sender,
            block.timestamp
        ));

        // Verify signature
        bytes32 ethSignedHash = attestationHash.toEthSignedMessageHash();
        address recovered = ethSignedHash.recover(signature);
        if (recovered != msg.sender) revert InvalidSignature();

        verifierSignatures[recordId][msg.sender] = VerifierSignature({
            verifier: msg.sender,
            signature: signature,
            signedAt: block.timestamp,
            attestationHash: attestationHash,
            comments: comments
        });

        record.verifiers.push(msg.sender);
        record.signatureCount++;
        recordVerifiers[recordId].push(msg.sender);

        emit VerifierSigned(recordId, msg.sender, attestationHash);

        // Check if we have enough signatures
        if (record.signatureCount >= record.requiredSignatures) {
            _finalizeVerification(recordId, verifiedReductions);
        }
    }

    /**
     * @dev Internal finalization of verification
     */
    function _finalizeVerification(bytes32 recordId, int256 verifiedReductions) internal {
        VerificationRecord storage record = records[recordId];

        record.status = VerificationStatus.Verified;
        record.verifiedAt = block.timestamp;
        record.expiresAt = block.timestamp + PROOF_VALIDITY_PERIOD;
        record.verifiedReductions = verifiedReductions;

        // Update global Merkle root
        _updateGlobalRoot(recordId);

        emit VerificationCompleted(
            recordId,
            VerificationStatus.Verified,
            record.signatureCount,
            verifiedReductions
        );
    }

    /**
     * @dev Update global Merkle root with new record
     */
    function _updateGlobalRoot(bytes32 recordId) internal {
        globalMerkleRoot = keccak256(abi.encodePacked(
            globalMerkleRoot,
            recordId,
            records[recordId].merkleRoot
        ));

        emit GlobalRootUpdated(globalMerkleRoot, globalRecordCount);
    }

    // ============ Chain of Custody ============

    /**
     * @dev Record a custody transfer event
     */
    function recordCustodyTransfer(
        bytes32 creditTokenId,
        address from,
        address to,
        bytes32 transactionHash,
        string calldata custodyType
    ) external onlyRole(PROOF_SUBMITTER_ROLE) returns (bytes32) {
        bytes32 previousEntryId = latestCustody[creditTokenId];
        bytes32 entryId = keccak256(abi.encodePacked(
            creditTokenId,
            from,
            to,
            block.timestamp,
            transactionHash
        ));

        // Calculate new Merkle root including all prior custody
        bytes32 newMerkleRoot;
        if (previousEntryId != bytes32(0)) {
            newMerkleRoot = keccak256(abi.encodePacked(
                custodyEntries[previousEntryId].merkleRoot,
                entryId
            ));
        } else {
            newMerkleRoot = keccak256(abi.encodePacked(entryId));
        }

        custodyEntries[entryId] = CustodyEntry({
            entryId: entryId,
            creditTokenId: creditTokenId,
            from: from,
            to: to,
            timestamp: block.timestamp,
            transactionHash: transactionHash,
            previousEntryId: previousEntryId,
            custodyType: custodyType,
            merkleRoot: newMerkleRoot
        });

        creditCustodyChain[creditTokenId].push(entryId);
        latestCustody[creditTokenId] = entryId;

        emit CustodyTransferred(entryId, creditTokenId, from, to, custodyType);
        return entryId;
    }

    /**
     * @dev Get full custody chain for a credit
     */
    function getCustodyChain(bytes32 creditTokenId)
        external
        view
        returns (CustodyEntry[] memory)
    {
        bytes32[] storage entryIds = creditCustodyChain[creditTokenId];
        CustodyEntry[] memory chain = new CustodyEntry[](entryIds.length);

        for (uint256 i = 0; i < entryIds.length; i++) {
            chain[i] = custodyEntries[entryIds[i]];
        }

        return chain;
    }

    /**
     * @dev Verify custody chain integrity
     */
    function verifyCustodyChainIntegrity(bytes32 creditTokenId) external view returns (bool) {
        bytes32[] storage entryIds = creditCustodyChain[creditTokenId];
        if (entryIds.length == 0) return true;

        bytes32 computedRoot = keccak256(abi.encodePacked(entryIds[0]));

        for (uint256 i = 1; i < entryIds.length; i++) {
            computedRoot = keccak256(abi.encodePacked(computedRoot, entryIds[i]));
        }

        bytes32 latestEntryId = latestCustody[creditTokenId];
        return custodyEntries[latestEntryId].merkleRoot == computedRoot;
    }

    // ============ Merkle Batch Operations ============

    /**
     * @dev Create a batch of verification records with shared Merkle root
     */
    function createMerkleBatch(
        bytes32[] calldata recordIds,
        bytes32[] calldata recordRoots
    ) external onlyRole(REGISTRY_ADMIN_ROLE) returns (bytes32) {
        if (recordIds.length != recordRoots.length) revert ArrayMismatch();
        if (recordIds.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (recordIds.length == 0) revert EmptyBatch();

        bytes32 batchId = keccak256(abi.encodePacked(
            recordIds,
            block.timestamp,
            batchCount++
        ));

        // Calculate batch Merkle root
        bytes32[] memory leaves = new bytes32[](recordIds.length);
        for (uint256 i = 0; i < recordIds.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recordIds[i], recordRoots[i]));
        }

        bytes32 batchRoot = _computeMerkleRoot(leaves);

        batches[batchId] = MerkleBatch({
            batchId: batchId,
            recordIds: recordIds,
            batchRoot: batchRoot,
            createdAt: block.timestamp,
            isFinalized: false,
            itemCount: recordIds.length
        });

        emit MerkleBatchCreated(batchId, batchRoot, recordIds.length);
        return batchId;
    }

    /**
     * @dev Finalize a batch (no more records can be added)
     */
    function finalizeBatch(bytes32 batchId) external onlyRole(REGISTRY_ADMIN_ROLE) {
        if (batches[batchId].batchId == bytes32(0)) revert BatchNotFound();
        if (batches[batchId].isFinalized) revert AlreadyFinalized();

        batches[batchId].isFinalized = true;
    }

    /**
     * @dev Compute Merkle root from leaves
     */
    function _computeMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) revert EmptyLeaves();

        uint256 n = leaves.length;
        while (n > 1) {
            uint256 newN = (n + 1) / 2;
            for (uint256 i = 0; i < newN; i++) {
                if (2 * i + 1 < n) {
                    leaves[i] = keccak256(abi.encodePacked(
                        leaves[2 * i] < leaves[2 * i + 1] ? leaves[2 * i] : leaves[2 * i + 1],
                        leaves[2 * i] < leaves[2 * i + 1] ? leaves[2 * i + 1] : leaves[2 * i]
                    ));
                } else {
                    leaves[i] = leaves[2 * i];
                }
            }
            n = newN;
        }

        return leaves[0];
    }

    // ============ Zero-Knowledge Proof Support ============

    /**
     * @dev Submit a ZK proof for verification
     */
    function submitZKProof(
        bytes32 proofId,
        bytes32 recordId,
        bytes32 verificationKey,
        bytes32 publicInputHash,
        bytes calldata proof,
        string calldata proofSystem
    ) external onlyRole(PROOF_SUBMITTER_ROLE) {
        if (zkProofs[proofId].proofId != bytes32(0)) revert ProofExists();
        if (records[recordId].recordId == bytes32(0)) revert RecordNotFound();

        zkProofs[proofId] = ZKProofRecord({
            proofId: proofId,
            verificationKey: verificationKey,
            publicInputHash: publicInputHash,
            proof: proof,
            isVerified: false,
            proofSystem: proofSystem
        });

        // Submit as proof entry
        bytes32 dataHash = keccak256(abi.encodePacked(verificationKey, publicInputHash, proof));

        proofs[proofId] = ProofEntry({
            proofId: proofId,
            recordId: recordId,
            proofType: ProofType.ZKProof,
            dataHash: dataHash,
            proof: proof,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            isValid: false,
            storageRef: ""
        });

        recordProofs[recordId].push(proofId);
    }

    /**
     * @dev Mark ZK proof as verified (called after off-chain verification)
     */
    function markZKProofVerified(bytes32 proofId, bool isValid)
        external
        onlyRole(VERIFIER_ROLE)
    {
        if (zkProofs[proofId].proofId == bytes32(0)) revert ProofNotFound();

        zkProofs[proofId].isVerified = isValid;
        proofs[proofId].isValid = isValid;

        emit ZKProofVerified(proofId, proofs[proofId].recordId, isValid);
    }

    // ============ Query Functions ============

    /**
     * @dev Get verification record details
     */
    function getVerificationRecord(bytes32 recordId)
        external
        view
        returns (VerificationRecord memory)
    {
        return records[recordId];
    }

    /**
     * @dev Get all proofs for a record
     */
    function getRecordProofs(bytes32 recordId)
        external
        view
        returns (ProofEntry[] memory)
    {
        bytes32[] storage proofIds = recordProofs[recordId];
        ProofEntry[] memory result = new ProofEntry[](proofIds.length);

        for (uint256 i = 0; i < proofIds.length; i++) {
            result[i] = proofs[proofIds[i]];
        }

        return result;
    }

    /**
     * @dev Get verifier signatures for a record
     */
    function getVerifierSignatures(bytes32 recordId)
        external
        view
        returns (VerifierSignature[] memory)
    {
        address[] storage verifiers = recordVerifiers[recordId];
        VerifierSignature[] memory sigs = new VerifierSignature[](verifiers.length);

        for (uint256 i = 0; i < verifiers.length; i++) {
            sigs[i] = verifierSignatures[recordId][verifiers[i]];
        }

        return sigs;
    }

    /**
     * @dev Check if a credit is verified
     */
    function isCreditVerified(bytes32 creditTokenId) external view returns (bool) {
        bytes32 recordId = creditVerification[creditTokenId];
        if (recordId == bytes32(0)) return false;

        VerificationRecord storage record = records[recordId];
        return record.status == VerificationStatus.Verified &&
               block.timestamp < record.expiresAt;
    }

    /**
     * @dev Get verification status for a credit
     */
    function getCreditVerificationStatus(bytes32 creditTokenId)
        external
        view
        returns (
            VerificationStatus status,
            uint256 verifiedAt,
            uint256 expiresAt,
            int256 verifiedReductions,
            uint256 signatureCount
        )
    {
        bytes32 recordId = creditVerification[creditTokenId];
        if (recordId == bytes32(0)) revert NoVerificationRecord();

        VerificationRecord storage record = records[recordId];
        return (
            record.status,
            record.verifiedAt,
            record.expiresAt,
            record.verifiedReductions,
            record.signatureCount
        );
    }

    /**
     * @dev Get records for a project
     */
    function getProjectRecords(bytes32 projectId)
        external
        view
        returns (bytes32[] memory)
    {
        return projectRecords[projectId];
    }

    // ============ Revocation ============

    /**
     * @dev Revoke a verification (in case of discovered issues)
     */
    function revokeVerification(bytes32 recordId, string calldata reason)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        VerificationRecord storage record = records[recordId];
        if (record.recordId == bytes32(0)) revert RecordNotFound();
        if (record.status != VerificationStatus.Verified) revert NotVerified();

        record.status = VerificationStatus.Revoked;

        emit VerificationCompleted(recordId, VerificationStatus.Revoked, record.signatureCount, 0);
    }

    // ============ Verifier Reputation ============

    /**
     * @dev Update verifier reputation
     */
    function updateVerifierReputation(address verifier, int256 change)
        external
        onlyRole(REGISTRY_ADMIN_ROLE)
    {
        if (!trustedVerifiers[verifier]) revert NotAVerifier();

        int256 newRep = int256(verifierReputation[verifier]) + change;
        if (newRep < 0) newRep = 0;
        if (newRep > 10000) newRep = 10000;

        verifierReputation[verifier] = uint256(newRep);
    }

    /**
     * @dev Get verifier reputation
     */
    function getVerifierReputation(address verifier) external view returns (uint256) {
        return verifierReputation[verifier];
    }
}

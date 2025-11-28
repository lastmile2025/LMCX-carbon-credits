// SPDX-License-Identifier: MIT
// Test constants for LMCX Carbon Credit tests

const { ethers } = require("hardhat");

// Role identifiers (matching contract definitions)
const ROLES = {
  DEFAULT_ADMIN_ROLE: ethers.ZeroHash,
  COMPLIANCE_MANAGER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("COMPLIANCE_MANAGER_ROLE")),
  URI_SETTER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("URI_SETTER_ROLE")),
  RATING_AGENCY_ROLE: ethers.keccak256(ethers.toUtf8Bytes("RATING_AGENCY_ROLE")),
  DMRV_ORACLE_ROLE: ethers.keccak256(ethers.toUtf8Bytes("DMRV_ORACLE_ROLE")),
  INSURANCE_MANAGER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("INSURANCE_MANAGER_ROLE")),
  GOVERNANCE_ROLE: ethers.keccak256(ethers.toUtf8Bytes("GOVERNANCE_ROLE")),
  VINTAGE_TRACKER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("VINTAGE_TRACKER_ROLE")),
  // Governance roles
  PROPOSER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("PROPOSER_ROLE")),
  EXECUTOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE")),
  GUARDIAN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE")),
  VOTER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("VOTER_ROLE")),
  MULTISIG_SIGNER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("MULTISIG_SIGNER_ROLE")),
  // Compliance roles
  ADMIN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE")),
  ISSUER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("ISSUER_ROLE")),
  // Oracle roles
  ORACLE_ADMIN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ADMIN_ROLE")),
  ORACLE_NODE_ROLE: ethers.keccak256(ethers.toUtf8Bytes("ORACLE_NODE_ROLE")),
  ANOMALY_RESOLVER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("ANOMALY_RESOLVER_ROLE")),
  // Verification roles
  VERIFIER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("VERIFIER_ROLE")),
  REGISTRY_ADMIN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("REGISTRY_ADMIN_ROLE")),
  PROOF_SUBMITTER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("PROOF_SUBMITTER_ROLE")),
  // Vintage roles
  LIFECYCLE_MANAGER_ROLE: ethers.keccak256(ethers.toUtf8Bytes("LIFECYCLE_MANAGER_ROLE")),
  GEOFENCE_ADMIN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("GEOFENCE_ADMIN_ROLE")),
  VINTAGE_ADMIN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("VINTAGE_ADMIN_ROLE")),
};

// Sample project IDs
const SAMPLE_PROJECTS = {
  PROJECT_1: ethers.keccak256(ethers.toUtf8Bytes("PROJECT_AMAZON_REFORESTATION_001")),
  PROJECT_2: ethers.keccak256(ethers.toUtf8Bytes("PROJECT_WIND_FARM_TEXAS_002")),
  PROJECT_3: ethers.keccak256(ethers.toUtf8Bytes("PROJECT_METHANE_CAPTURE_003")),
  PROJECT_4: ethers.keccak256(ethers.toUtf8Bytes("PROJECT_SOLAR_INDIA_004")),
};

// Sample jurisdictions
const JURISDICTIONS = {
  USA: ethers.keccak256(ethers.toUtf8Bytes("US")),
  EU: ethers.keccak256(ethers.toUtf8Bytes("EU")),
  UK: ethers.keccak256(ethers.toUtf8Bytes("UK")),
  BRAZIL: ethers.keccak256(ethers.toUtf8Bytes("BR")),
  INDIA: ethers.keccak256(ethers.toUtf8Bytes("IN")),
  NONE: ethers.ZeroHash,
};

// Time constants
const TIME = {
  ONE_DAY: 24 * 60 * 60,
  ONE_WEEK: 7 * 24 * 60 * 60,
  ONE_MONTH: 30 * 24 * 60 * 60,
  ONE_YEAR: 365 * 24 * 60 * 60,
  GRACE_PERIOD: 14 * 24 * 60 * 60,
};

// Compliance score thresholds
const COMPLIANCE_THRESHOLDS = {
  MIN_ISO14064_SCORE: 9000,  // 90%
  MIN_OGMP_SCORE: 8000,      // 80%
  MIN_EPA_SCORE: 6000,       // 60%
  MIN_CDM_SCORE: 7000,       // 70%
  INVESTMENT_GRADE: 6000,    // BBB or above
};

// Oracle constants
const ORACLE = {
  MIN_ORACLES: 3,
  MAX_ORACLES: 20,
  PRECISION: ethers.parseEther("1"), // 1e18
  MAX_DEVIATION_PERCENTAGE: 2000,    // 20%
  DEFAULT_HEARTBEAT: 3600,           // 1 hour
  MIN_QUALITY_SCORE: 5000,           // 50%
  MAX_STALENESS: 86400,              // 24 hours
};

// Governance constants
const GOVERNANCE = {
  MIN_PROPOSAL_DELAY: TIME.ONE_DAY,
  MAX_PROPOSAL_DELAY: 30 * TIME.ONE_DAY,
  MIN_VOTING_PERIOD: 3 * TIME.ONE_DAY,
  MAX_VOTING_PERIOD: 30 * TIME.ONE_DAY,
  QUORUM_DENOMINATOR: 10000,
};

// Vintage constants
const VINTAGE = {
  MIN_YEAR: 2000,
  MAX_YEAR: 2100,
  CURRENT_YEAR: new Date().getFullYear(),
  PREMIUM_MAX_AGE: 2,    // years
  STANDARD_MAX_AGE: 4,
  DISCOUNT_MAX_AGE: 6,
  LEGACY_MAX_AGE: 8,
};

// Test amounts
const AMOUNTS = {
  SMALL: 10n,
  MEDIUM: 100n,
  LARGE: 1000n,
  VERY_LARGE: 10000n,
};

// Base URI for token metadata
const BASE_URI = "https://api.lmcx.io/carbon-credits/";

// Error messages
const ERRORS = {
  INVALID_BENEFICIARY: "Invalid beneficiary",
  AMOUNT_MUST_BE_POSITIVE: "Amount must be > 0",
  VERIFICATION_HASH_REQUIRED: "Verification hash required",
  TOKEN_DOES_NOT_EXIST: "Token does not exist",
  INSUFFICIENT_BALANCE: "Insufficient balance",
  RETIREMENT_REASON_REQUIRED: "Retirement reason required",
  ORACLE_CIRCUIT_BREAKER: "Oracle circuit breaker active",
  CREDIT_VERIFICATION_REQUIRED: "Credit verification required",
  TRANSFER_RESTRICTED: "Transfer restricted by vintage tracker",
  ACCESS_CONTROL: "AccessControl:",
  PAUSED: "Pausable: paused",
  INSURANCE_NOT_ENABLED: "Insurance feature not enabled",
  RATINGS_NOT_ENABLED: "Ratings feature not enabled",
};

module.exports = {
  ROLES,
  SAMPLE_PROJECTS,
  JURISDICTIONS,
  TIME,
  COMPLIANCE_THRESHOLDS,
  ORACLE,
  GOVERNANCE,
  VINTAGE,
  AMOUNTS,
  BASE_URI,
  ERRORS,
};

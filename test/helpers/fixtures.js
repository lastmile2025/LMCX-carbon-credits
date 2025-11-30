// SPDX-License-Identifier: MIT
// Test fixtures for LMCX Carbon Credit tests

const { ethers } = require("hardhat");
const { ROLES, SAMPLE_PROJECTS, BASE_URI, TIME, GOVERNANCE } = require("./constants");

/**
 * Deploy the main LMCXCarbonCredit token contract
 */
async function deployLMCXCarbonCredit() {
  const [owner, complianceManager, insuranceManager, ratingAgency, dmrvOracle, user1, user2, user3] = await ethers.getSigners();

  const LMCXCarbonCredit = await ethers.getContractFactory("LMCXCarbonCredit");
  const token = await LMCXCarbonCredit.deploy(BASE_URI);
  await token.waitForDeployment();

  // Grant compliance manager role
  await token.grantRole(ROLES.COMPLIANCE_MANAGER_ROLE, complianceManager.address);

  return {
    token,
    owner,
    complianceManager,
    insuranceManager,
    ratingAgency,
    dmrvOracle,
    user1,
    user2,
    user3,
  };
}

/**
 * Deploy LMCXCarbonCredit with all optional features enabled
 */
async function deployLMCXCarbonCreditWithFeatures() {
  const deployment = await deployLMCXCarbonCredit();
  const { token, owner, insuranceManager, ratingAgency, dmrvOracle } = deployment;

  // Enable optional features
  await token.connect(owner).setFeatureFlags(true, true, true);

  // Grant additional roles
  await token.connect(owner).grantRole(ROLES.INSURANCE_MANAGER_ROLE, insuranceManager.address);
  await token.connect(owner).grantRole(ROLES.RATING_AGENCY_ROLE, ratingAgency.address);
  await token.connect(owner).grantRole(ROLES.DMRV_ORACLE_ROLE, dmrvOracle.address);

  return deployment;
}

/**
 * Deploy mock validator contracts for ComplianceManager testing
 */
async function deployMockValidators() {
  const MockISO14064 = await ethers.getContractFactory("MockISO14064Validator");
  const MockOGMP2 = await ethers.getContractFactory("MockOGMP2Validator");
  const MockISO14065 = await ethers.getContractFactory("MockISO14065Verifier");
  const MockCORSIA = await ethers.getContractFactory("MockCORSIACompliance");
  const MockEPA = await ethers.getContractFactory("MockEPASubpartWValidator");
  const MockCDM = await ethers.getContractFactory("MockCDMAM0023Validator");

  const iso14064 = await MockISO14064.deploy();
  const ogmp2 = await MockOGMP2.deploy();
  const iso14065 = await MockISO14065.deploy();
  const corsia = await MockCORSIA.deploy();
  const epa = await MockEPA.deploy();
  const cdm = await MockCDM.deploy();

  await Promise.all([
    iso14064.waitForDeployment(),
    ogmp2.waitForDeployment(),
    iso14065.waitForDeployment(),
    corsia.waitForDeployment(),
    epa.waitForDeployment(),
    cdm.waitForDeployment(),
  ]);

  return { iso14064, ogmp2, iso14065, corsia, epa, cdm };
}

/**
 * Deploy full ComplianceManager setup with mocks
 */
async function deployComplianceManagerSetup() {
  const [owner, admin, issuer, beneficiary, user1, user2] = await ethers.getSigners();

  // Deploy mock validators
  const mocks = await deployMockValidators();

  // Deploy main token
  const LMCXCarbonCredit = await ethers.getContractFactory("LMCXCarbonCredit");
  const token = await LMCXCarbonCredit.deploy(BASE_URI);
  await token.waitForDeployment();

  // Deploy ComplianceManager
  const ComplianceManager = await ethers.getContractFactory("ComplianceManager");
  const complianceManager = await ComplianceManager.deploy(
    await token.getAddress(),
    await mocks.iso14064.getAddress(),
    await mocks.ogmp2.getAddress(),
    await mocks.iso14065.getAddress(),
    await mocks.corsia.getAddress(),
    await mocks.epa.getAddress(),
    await mocks.cdm.getAddress()
  );
  await complianceManager.waitForDeployment();

  // Grant ComplianceManager the minting role on token
  await token.grantRole(ROLES.COMPLIANCE_MANAGER_ROLE, await complianceManager.getAddress());

  // Disable verification requirement for testing (since we don't have VerificationRegistry)
  await token.setVerificationRequirements(false, false, 7000);

  return {
    token,
    complianceManager,
    mocks,
    owner,
    admin,
    issuer,
    beneficiary,
    user1,
    user2,
  };
}

/**
 * Deploy GovernanceController with test configuration
 */
async function deployGovernanceController() {
  const [owner, proposer, executor, guardian1, guardian2, signer1, signer2, signer3, voter1, voter2] = await ethers.getSigners();

  const guardians = [guardian1.address, guardian2.address];
  const signers = [signer1.address, signer2.address, signer3.address];

  const GovernanceController = await ethers.getContractFactory("GovernanceController");
  const governance = await GovernanceController.deploy(
    TIME.ONE_DAY,           // proposalDelay
    3 * TIME.ONE_DAY,       // votingPeriod
    TIME.ONE_DAY,           // timelockDelay
    1000,                   // quorumNumerator (10%)
    100,                    // proposalThreshold
    2,                      // multiSigThreshold
    guardians,
    signers
  );
  await governance.waitForDeployment();

  // Grant roles
  await governance.grantRole(ROLES.PROPOSER_ROLE, proposer.address);
  await governance.grantRole(ROLES.EXECUTOR_ROLE, executor.address);
  await governance.grantRole(ROLES.VOTER_ROLE, voter1.address);
  await governance.grantRole(ROLES.VOTER_ROLE, voter2.address);

  // Set voting power for voters
  await governance.setVotingPower(voter1.address, 1000, 10000);
  await governance.setVotingPower(voter2.address, 500, 10000);
  await governance.setVotingPower(proposer.address, 200, 10000);

  return {
    governance,
    owner,
    proposer,
    executor,
    guardian1,
    guardian2,
    signer1,
    signer2,
    signer3,
    voter1,
    voter2,
  };
}

/**
 * Deploy OracleAggregator with test configuration
 */
async function deployOracleAggregator() {
  const [owner, admin, oracle1, oracle2, oracle3, oracle4, resolver, user1] = await ethers.getSigners();

  const OracleAggregator = await ethers.getContractFactory("OracleAggregator");
  const aggregator = await OracleAggregator.deploy();
  await aggregator.waitForDeployment();

  // Grant roles
  await aggregator.grantRole(ROLES.ORACLE_ADMIN_ROLE, admin.address);
  await aggregator.grantRole(ROLES.ANOMALY_RESOLVER_ROLE, resolver.address);

  return {
    aggregator,
    owner,
    admin,
    oracle1,
    oracle2,
    oracle3,
    oracle4,
    resolver,
    user1,
  };
}

/**
 * Deploy VintageTracker with test configuration
 */
async function deployVintageTracker() {
  const [owner, lifecycleManager, geofenceAdmin, vintageAdmin, user1, user2] = await ethers.getSigners();

  const VintageTracker = await ethers.getContractFactory("VintageTracker");
  const tracker = await VintageTracker.deploy();
  await tracker.waitForDeployment();

  // Grant roles
  await tracker.grantRole(ROLES.LIFECYCLE_MANAGER_ROLE, lifecycleManager.address);
  await tracker.grantRole(ROLES.GEOFENCE_ADMIN_ROLE, geofenceAdmin.address);
  await tracker.grantRole(ROLES.VINTAGE_ADMIN_ROLE, vintageAdmin.address);

  return {
    tracker,
    owner,
    lifecycleManager,
    geofenceAdmin,
    vintageAdmin,
    user1,
    user2,
  };
}

/**
 * Deploy VerificationRegistry with test configuration
 */
async function deployVerificationRegistry() {
  const [owner, registryAdmin, verifier1, verifier2, verifier3, proofSubmitter, user1] = await ethers.getSigners();

  const VerificationRegistry = await ethers.getContractFactory("VerificationRegistry");
  const registry = await VerificationRegistry.deploy();
  await registry.waitForDeployment();

  // Grant roles
  await registry.grantRole(ROLES.REGISTRY_ADMIN_ROLE, registryAdmin.address);
  await registry.grantRole(ROLES.VERIFIER_ROLE, verifier1.address);
  await registry.grantRole(ROLES.VERIFIER_ROLE, verifier2.address);
  await registry.grantRole(ROLES.VERIFIER_ROLE, verifier3.address);
  await registry.grantRole(ROLES.PROOF_SUBMITTER_ROLE, proofSubmitter.address);

  return {
    registry,
    owner,
    registryAdmin,
    verifier1,
    verifier2,
    verifier3,
    proofSubmitter,
    user1,
  };
}

/**
 * Helper to create sample credit metadata
 */
function createSampleCreditData(overrides = {}) {
  return {
    projectId: SAMPLE_PROJECTS.PROJECT_1,
    vintageYear: 2023,
    amount: 100n,
    methodology: "VCS-VM0015",
    verificationHash: "QmTest123456789",
    jurisdictionCode: ethers.ZeroHash,
    ...overrides,
  };
}

/**
 * Helper to generate token ID from project and vintage
 */
function generateTokenId(projectId, vintageYear) {
  return ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "uint256"],
      [projectId, vintageYear]
    )
  );
}

/**
 * Helper to advance time in tests
 */
async function advanceTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine");
}

/**
 * Helper to advance blocks
 */
async function advanceBlocks(blocks) {
  for (let i = 0; i < blocks; i++) {
    await ethers.provider.send("evm_mine");
  }
}

/**
 * Helper to get current block number
 */
async function getCurrentBlock() {
  return await ethers.provider.getBlockNumber();
}

/**
 * Helper to get current timestamp
 */
async function getCurrentTimestamp() {
  const block = await ethers.provider.getBlock("latest");
  return block.timestamp;
}

module.exports = {
  deployLMCXCarbonCredit,
  deployLMCXCarbonCreditWithFeatures,
  deployMockValidators,
  deployComplianceManagerSetup,
  deployGovernanceController,
  deployOracleAggregator,
  deployVintageTracker,
  deployVerificationRegistry,
  createSampleCreditData,
  generateTokenId,
  advanceTime,
  advanceBlocks,
  getCurrentBlock,
  getCurrentTimestamp,
};

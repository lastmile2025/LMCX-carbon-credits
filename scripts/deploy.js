const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║     LMCX Carbon Credit System - Full Deployment              ║");
  console.log("║     ERC1155 + Insurance + Ratings + dMRV + SMART             ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");
  console.log("");
  console.log("Deployer:", deployer.address);
  console.log("Balance:", (await deployer.provider.getBalance(deployer.address)).toString());
  console.log("");

  const addresses = {};

  // ============ Phase 1: Core Token ============
  console.log("━━━ Phase 1: Core Token Contract ━━━");
  
  const BASE_URI = "https://api.lmcx.io/metadata/";
  
  console.log("Deploying LMCXCarbonCredit (ERC1155)...");
  const LMCXCarbonCredit = await hre.ethers.getContractFactory("LMCXCarbonCredit");
  const token = await LMCXCarbonCredit.deploy(BASE_URI);
  await token.waitForDeployment();
  addresses.token = await token.getAddress();
  console.log("  ✓ LMCXCarbonCredit:", addresses.token);
  console.log("");

  // ============ Phase 2: Governance ============
  console.log("━━━ Phase 2: Governance Contracts ━━━");

  console.log("Deploying SMARTDataRegistry...");
  const SMARTDataRegistry = await hre.ethers.getContractFactory("SMARTDataRegistry");
  const smartRegistry = await SMARTDataRegistry.deploy();
  await smartRegistry.waitForDeployment();
  addresses.smartRegistry = await smartRegistry.getAddress();
  console.log("  ✓ SMARTDataRegistry:", addresses.smartRegistry);
  console.log("");

  // ============ Phase 3: Insurance & Ratings ============
  console.log("━━━ Phase 3: Insurance & Ratings ━━━");

  console.log("Deploying InsuranceManager...");
  const InsuranceManager = await hre.ethers.getContractFactory("InsuranceManager");
  const insurance = await InsuranceManager.deploy(addresses.token);
  await insurance.waitForDeployment();
  addresses.insurance = await insurance.getAddress();
  console.log("  ✓ InsuranceManager:", addresses.insurance);

  console.log("Deploying RatingAgencyRegistry...");
  const RatingAgencyRegistry = await hre.ethers.getContractFactory("RatingAgencyRegistry");
  const ratings = await RatingAgencyRegistry.deploy();
  await ratings.waitForDeployment();
  addresses.ratings = await ratings.getAddress();
  console.log("  ✓ RatingAgencyRegistry:", addresses.ratings);
  console.log("");

  // ============ Phase 4: dMRV Oracle ============
  console.log("━━━ Phase 4: dMRV Oracle ━━━");

  console.log("Deploying DMRVOracle...");
  const DMRVOracle = await hre.ethers.getContractFactory("DMRVOracle");
  const dmrv = await DMRVOracle.deploy();
  await dmrv.waitForDeployment();
  addresses.dmrv = await dmrv.getAddress();
  console.log("  ✓ DMRVOracle:", addresses.dmrv);
  console.log("");

  // ============ Phase 5: Validators ============
  console.log("━━━ Phase 5: Validator Contracts ━━━");

  console.log("Deploying OGMP2Validator...");
  const OGMP2Validator = await hre.ethers.getContractFactory("OGMP2Validator");
  const ogmp = await OGMP2Validator.deploy();
  await ogmp.waitForDeployment();
  addresses.ogmp = await ogmp.getAddress();
  console.log("  ✓ OGMP2Validator:", addresses.ogmp);

  console.log("Deploying ISO14065Verifier...");
  const ISO14065Verifier = await hre.ethers.getContractFactory("ISO14065Verifier");
  const iso = await ISO14065Verifier.deploy();
  await iso.waitForDeployment();
  addresses.iso = await iso.getAddress();
  console.log("  ✓ ISO14065Verifier:", addresses.iso);

  console.log("Deploying CORSIACompliance...");
  const CORSIACompliance = await hre.ethers.getContractFactory("CORSIACompliance");
  const corsia = await CORSIACompliance.deploy();
  await corsia.waitForDeployment();
  addresses.corsia = await corsia.getAddress();
  console.log("  ✓ CORSIACompliance:", addresses.corsia);

  console.log("Deploying EPASubpartWValidator...");
  const EPASubpartWValidator = await hre.ethers.getContractFactory("EPASubpartWValidator");
  const epa = await EPASubpartWValidator.deploy();
  await epa.waitForDeployment();
  addresses.epa = await epa.getAddress();
  console.log("  ✓ EPASubpartWValidator:", addresses.epa);

  console.log("Deploying CDMAM0023Validator...");
  const CDMAM0023Validator = await hre.ethers.getContractFactory("CDMAM0023Validator");
  const cdm = await CDMAM0023Validator.deploy();
  await cdm.waitForDeployment();
  addresses.cdm = await cdm.getAddress();
  console.log("  ✓ CDMAM0023Validator:", addresses.cdm);
  console.log("");

  // ============ Phase 6: Compliance Manager ============
  console.log("━━━ Phase 6: Compliance Manager ━━━");

  console.log("Deploying ComplianceManager...");
  const ComplianceManager = await hre.ethers.getContractFactory("ComplianceManager");
  const complianceManager = await ComplianceManager.deploy(
    addresses.token,
    addresses.ogmp,
    addresses.iso,
    addresses.corsia,
    addresses.epa,
    addresses.cdm
  );
  await complianceManager.waitForDeployment();
  addresses.complianceManager = await complianceManager.getAddress();
  console.log("  ✓ ComplianceManager:", addresses.complianceManager);
  console.log("");

  // ============ Phase 7: Configure Permissions ============
  console.log("━━━ Phase 7: Configuring Permissions ━━━");

  console.log("Setting ComplianceManager on token...");
  let tx = await token.setComplianceManager(addresses.complianceManager);
  await tx.wait();
  console.log("  ✓ ComplianceManager role granted");

  console.log("Setting InsuranceManager on token...");
  tx = await token.setInsuranceManager(addresses.insurance);
  await tx.wait();
  console.log("  ✓ InsuranceManager connected");

  console.log("Setting RatingAgencyRegistry on token...");
  tx = await token.setRatingAgencyRegistry(addresses.ratings);
  await tx.wait();
  console.log("  ✓ RatingAgencyRegistry connected");

  console.log("Setting DMRVOracle on token...");
  tx = await token.setDMRVOracle(addresses.dmrv);
  await tx.wait();
  console.log("  ✓ DMRVOracle connected");

  console.log("Setting SMARTDataRegistry on token...");
  tx = await token.setSMARTDataRegistry(addresses.smartRegistry);
  await tx.wait();
  console.log("  ✓ SMARTDataRegistry connected");

  console.log("Connecting RatingAgency to InsuranceManager...");
  tx = await ratings.setInsuranceManager(addresses.insurance);
  await tx.wait();
  console.log("  ✓ Rating-Insurance integration complete");
  console.log("");

  // ============ Summary ============
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║                    DEPLOYMENT COMPLETE                       ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");
  console.log("");
  console.log("┌─────────────────────────────────────────────────────────────┐");
  console.log("│ CORE CONTRACTS                                              │");
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log(`│ LMCXCarbonCredit:      ${addresses.token}`);
  console.log(`│ ComplianceManager:     ${addresses.complianceManager}`);
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log("│ GOVERNANCE & DATA                                           │");
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log(`│ SMARTDataRegistry:     ${addresses.smartRegistry}`);
  console.log(`│ DMRVOracle:            ${addresses.dmrv}`);
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log("│ INSURANCE & RATINGS                                         │");
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log(`│ InsuranceManager:      ${addresses.insurance}`);
  console.log(`│ RatingAgencyRegistry:  ${addresses.ratings}`);
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log("│ VALIDATORS                                                  │");
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log(`│ OGMP2Validator:        ${addresses.ogmp}`);
  console.log(`│ ISO14065Verifier:      ${addresses.iso}`);
  console.log(`│ CORSIACompliance:      ${addresses.corsia}`);
  console.log(`│ EPASubpartWValidator:  ${addresses.epa}`);
  console.log(`│ CDMAM0023Validator:    ${addresses.cdm}`);
  console.log("└─────────────────────────────────────────────────────────────┘");
  console.log("");
  console.log("Token Details:");
  console.log("  Name:     LMCX Carbon Credit");
  console.log("  Symbol:   LMCXCC");
  console.log("  Standard: ERC1155");
  console.log("  Base URI:", BASE_URI);
  console.log("");
  console.log("⚠️  SAVE THESE ADDRESSES! You'll need them for verification.");
  console.log("");

  return addresses;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

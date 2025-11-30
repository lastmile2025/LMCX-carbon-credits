// SPDX-License-Identifier: MIT
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ROLES, SAMPLE_PROJECTS, JURISDICTIONS, AMOUNTS, BASE_URI, ERRORS } = require("../helpers/constants");

describe("LMCXCarbonCredit", function () {
  // Fixture for basic deployment
  async function deployBasicFixture() {
    const [owner, complianceManager, insuranceManager, ratingAgency, dmrvOracle, user1, user2, user3] = await ethers.getSigners();

    const LMCXCarbonCredit = await ethers.getContractFactory("LMCXCarbonCredit");
    const token = await LMCXCarbonCredit.deploy(BASE_URI);
    await token.waitForDeployment();

    // Grant compliance manager role
    await token.grantRole(ROLES.COMPLIANCE_MANAGER_ROLE, complianceManager.address);

    // Disable verification requirement for basic tests
    await token.setVerificationRequirements(false, false, 7000);

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

  // Fixture with all features enabled
  async function deployWithFeaturesFixture() {
    const deployment = await deployBasicFixture();
    const { token, owner, insuranceManager, ratingAgency, dmrvOracle } = deployment;

    // Enable optional features
    await token.connect(owner).setFeatureFlags(true, true, true);

    // Grant additional roles
    await token.connect(owner).grantRole(ROLES.INSURANCE_MANAGER_ROLE, insuranceManager.address);
    await token.connect(owner).grantRole(ROLES.RATING_AGENCY_ROLE, ratingAgency.address);
    await token.connect(owner).grantRole(ROLES.DMRV_ORACLE_ROLE, dmrvOracle.address);

    return deployment;
  }

  // Fixture with mock external contracts
  async function deployWithMocksFixture() {
    const deployment = await deployBasicFixture();
    const { token, owner } = deployment;

    // Deploy mock contracts
    const MockOracleAggregator = await ethers.getContractFactory("MockOracleAggregator");
    const mockOracle = await MockOracleAggregator.deploy();

    const MockVerificationRegistry = await ethers.getContractFactory("MockVerificationRegistry");
    const mockVerification = await MockVerificationRegistry.deploy();

    const MockVintageTracker = await ethers.getContractFactory("MockVintageTracker");
    const mockVintage = await MockVintageTracker.deploy();

    await Promise.all([
      mockOracle.waitForDeployment(),
      mockVerification.waitForDeployment(),
      mockVintage.waitForDeployment(),
    ]);

    // Set external contracts
    await token.connect(owner).setOracleAggregator(await mockOracle.getAddress());
    await token.connect(owner).setVerificationRegistry(await mockVerification.getAddress());
    await token.connect(owner).setVintageTracker(await mockVintage.getAddress());

    return {
      ...deployment,
      mockOracle,
      mockVerification,
      mockVintage,
    };
  }

  describe("Deployment", function () {
    it("Should deploy with correct name and symbol", async function () {
      const { token } = await loadFixture(deployBasicFixture);

      expect(await token.name()).to.equal("LMCX Carbon Credit");
      expect(await token.symbol()).to.equal("LMCXCC");
    });

    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { token, owner } = await loadFixture(deployBasicFixture);

      expect(await token.hasRole(ROLES.DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should grant URI_SETTER_ROLE to deployer", async function () {
      const { token, owner } = await loadFixture(deployBasicFixture);

      expect(await token.hasRole(ROLES.URI_SETTER_ROLE, owner.address)).to.be.true;
    });

    it("Should set correct base URI", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      // Mint a token first
      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const uri = await token.uri(tokenId);
      expect(uri).to.include(BASE_URI);
    });

    it("Should initialize with correct default feature flags", async function () {
      const { token } = await loadFixture(deployBasicFixture);

      expect(await token.insuranceEnabled()).to.be.false;
      expect(await token.ratingsEnabled()).to.be.false;
      expect(await token.vintageTrackingEnabled()).to.be.true;
    });
  });

  describe("Token ID Generation", function () {
    it("Should generate deterministic token IDs", async function () {
      const { token } = await loadFixture(deployBasicFixture);

      const tokenId1 = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const tokenId2 = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      expect(tokenId1).to.equal(tokenId2);
    });

    it("Should generate different IDs for different projects", async function () {
      const { token } = await loadFixture(deployBasicFixture);

      const tokenId1 = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const tokenId2 = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_2, 2023);

      expect(tokenId1).to.not.equal(tokenId2);
    });

    it("Should generate different IDs for different vintage years", async function () {
      const { token } = await loadFixture(deployBasicFixture);

      const tokenId1 = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const tokenId2 = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2024);

      expect(tokenId1).to.not.equal(tokenId2);
    });
  });

  describe("Minting", function () {
    describe("mintCredits", function () {
      it("Should mint credits successfully with COMPLIANCE_MANAGER_ROLE", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        const tx = await token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        );

        const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
        expect(await token.balanceOf(user1.address, tokenId)).to.equal(AMOUNTS.MEDIUM);
      });

      it("Should emit CreditsMinted event", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.emit(token, "CreditsMinted");
      });

      it("Should emit CreditTypeCreated event for new token type", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.emit(token, "CreditTypeCreated");
      });

      it("Should revert when called without COMPLIANCE_MANAGER_ROLE", async function () {
        const { token, user1, user2 } = await loadFixture(deployBasicFixture);

        await expect(token.connect(user1).mintCredits(
          user2.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.be.reverted;
      });

      it("Should revert with zero address beneficiary", async function () {
        const { token, complianceManager } = await loadFixture(deployBasicFixture);

        await expect(token.connect(complianceManager).mintCredits(
          ethers.ZeroAddress,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.be.revertedWith(ERRORS.INVALID_BENEFICIARY);
      });

      it("Should revert with zero amount", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          0,
          "VCS-VM0015",
          "QmTest123"
        )).to.be.revertedWith(ERRORS.AMOUNT_MUST_BE_POSITIVE);
      });

      it("Should revert with empty verification hash", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          ""
        )).to.be.revertedWith(ERRORS.VERIFICATION_HASH_REQUIRED);
      });

      it("Should increment nextMintId", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        const mintIdBefore = await token.nextMintId();

        await token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        );

        expect(await token.nextMintId()).to.equal(mintIdBefore + 1n);
      });

      it("Should store correct credit metadata", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        await token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        );

        const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
        const metadata = await token.getCreditMetadata(tokenId);

        expect(metadata.projectId).to.equal(SAMPLE_PROJECTS.PROJECT_1);
        expect(metadata.vintageYear).to.equal(2023);
        expect(metadata.methodology).to.equal("VCS-VM0015");
        expect(metadata.exists).to.be.true;
      });
    });

    describe("mintCreditsWithJurisdiction", function () {
      it("Should mint with jurisdiction code", async function () {
        const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

        await token.connect(complianceManager).mintCreditsWithJurisdiction(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123",
          JURISDICTIONS.USA
        );

        const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
        expect(await token.tokenJurisdiction(tokenId)).to.equal(JURISDICTIONS.USA);
      });
    });

    describe("Oracle Circuit Breaker", function () {
      it("Should revert minting when circuit breaker is active", async function () {
        const { token, complianceManager, user1, mockOracle } = await loadFixture(deployWithMocksFixture);

        // Activate circuit breaker
        await mockOracle.setCircuitBreaker(true);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.be.revertedWith(ERRORS.ORACLE_CIRCUIT_BREAKER);
      });

      it("Should allow minting when circuit breaker is inactive", async function () {
        const { token, complianceManager, user1, mockOracle } = await loadFixture(deployWithMocksFixture);

        // Ensure circuit breaker is off
        await mockOracle.setCircuitBreaker(false);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.not.be.reverted;
      });
    });

    describe("Verification Requirements", function () {
      it("Should revert when verification required but credit not verified", async function () {
        const { token, complianceManager, user1, owner, mockVerification } = await loadFixture(deployWithMocksFixture);

        // Enable verification requirement
        await token.connect(owner).setVerificationRequirements(true, false, 7000);

        // Credit is not verified (default)
        const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
        await mockVerification.setCreditVerified(ethers.toBeHex(tokenId, 32), false);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.be.revertedWith(ERRORS.CREDIT_VERIFICATION_REQUIRED);
      });

      it("Should allow minting when credit is verified", async function () {
        const { token, complianceManager, user1, owner, mockVerification } = await loadFixture(deployWithMocksFixture);

        // Enable verification requirement
        await token.connect(owner).setVerificationRequirements(true, false, 7000);

        // Set credit as verified
        const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
        await mockVerification.setCreditVerified(ethers.toBeHex(tokenId, 32), true);

        await expect(token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.MEDIUM,
          "VCS-VM0015",
          "QmTest123"
        )).to.not.be.reverted;
      });
    });
  });

  describe("Retirement", function () {
    async function mintedCreditsFixture() {
      const deployment = await deployBasicFixture();
      const { token, complianceManager, user1 } = deployment;

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.LARGE,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      return { ...deployment, tokenId };
    }

    it("Should retire credits successfully", async function () {
      const { token, user1, tokenId } = await loadFixture(mintedCreditsFixture);

      const balanceBefore = await token.balanceOf(user1.address, tokenId);
      const retireAmount = AMOUNTS.SMALL;

      await token.connect(user1).retireCredits(
        tokenId,
        retireAmount,
        "Climate commitment",
        "ACME Corp"
      );

      expect(await token.balanceOf(user1.address, tokenId)).to.equal(balanceBefore - retireAmount);
    });

    it("Should emit CreditRetired event", async function () {
      const { token, user1, tokenId } = await loadFixture(mintedCreditsFixture);

      await expect(token.connect(user1).retireCredits(
        tokenId,
        AMOUNTS.SMALL,
        "Climate commitment",
        "ACME Corp"
      )).to.emit(token, "CreditRetired")
        .withArgs(tokenId, user1.address, AMOUNTS.SMALL, "Climate commitment", "ACME Corp");
    });

    it("Should revert with insufficient balance", async function () {
      const { token, user1, tokenId } = await loadFixture(mintedCreditsFixture);

      await expect(token.connect(user1).retireCredits(
        tokenId,
        AMOUNTS.VERY_LARGE + 1n,
        "Climate commitment",
        "ACME Corp"
      )).to.be.revertedWith(ERRORS.INSUFFICIENT_BALANCE);
    });

    it("Should revert with empty retirement reason", async function () {
      const { token, user1, tokenId } = await loadFixture(mintedCreditsFixture);

      await expect(token.connect(user1).retireCredits(
        tokenId,
        AMOUNTS.SMALL,
        "",
        "ACME Corp"
      )).to.be.revertedWith(ERRORS.RETIREMENT_REASON_REQUIRED);
    });

    it("Should allow retirement with certificate", async function () {
      const { token, user1, tokenId } = await loadFixture(mintedCreditsFixture);

      await expect(token.connect(user1).retireCreditsWithCertificate(
        tokenId,
        AMOUNTS.SMALL,
        "Climate commitment",
        "ACME Corp",
        "QmCertificateHash123"
      )).to.emit(token, "CreditRetired");
    });
  });

  describe("Transfers", function () {
    async function mintedCreditsFixture() {
      const deployment = await deployBasicFixture();
      const { token, complianceManager, user1 } = deployment;

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.LARGE,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      return { ...deployment, tokenId };
    }

    it("Should transfer credits successfully", async function () {
      const { token, user1, user2, tokenId } = await loadFixture(mintedCreditsFixture);

      await token.connect(user1).safeTransferFrom(
        user1.address,
        user2.address,
        tokenId,
        AMOUNTS.SMALL,
        "0x"
      );

      expect(await token.balanceOf(user2.address, tokenId)).to.equal(AMOUNTS.SMALL);
    });

    it("Should revert transfer when paused", async function () {
      const { token, owner, user1, user2, tokenId } = await loadFixture(mintedCreditsFixture);

      await token.connect(owner).pause();

      await expect(token.connect(user1).safeTransferFrom(
        user1.address,
        user2.address,
        tokenId,
        AMOUNTS.SMALL,
        "0x"
      )).to.be.reverted;
    });

    describe("Transfer Restrictions with VintageTracker", function () {
      it("Should revert transfer when vintage tracker marks as non-transferable", async function () {
        const { token, complianceManager, user1, user2, owner } = await loadFixture(deployWithMocksFixture);

        // Mint credits
        await token.connect(complianceManager).mintCredits(
          user1.address,
          SAMPLE_PROJECTS.PROJECT_1,
          2023,
          AMOUNTS.LARGE,
          "VCS-VM0015",
          "QmTest123"
        );

        const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
        const creditId = ethers.toBeHex(tokenId, 32);

        // Get mock vintage tracker and set non-transferable
        const mockVintageAddress = await token.vintageTracker();
        const MockVintageTracker = await ethers.getContractFactory("MockVintageTracker");
        const mockVintage = MockVintageTracker.attach(mockVintageAddress);

        await mockVintage.setTransferable(creditId, false);

        await expect(token.connect(user1).safeTransferFrom(
          user1.address,
          user2.address,
          tokenId,
          AMOUNTS.SMALL,
          "0x"
        )).to.be.revertedWith(ERRORS.TRANSFER_RESTRICTED);
      });
    });
  });

  describe("Insurance Integration", function () {
    it("Should revert updateInsuranceStatus when insurance not enabled", async function () {
      const { token, complianceManager, user1, owner, insuranceManager } = await loadFixture(deployBasicFixture);

      // Grant role but don't enable feature
      await token.connect(owner).grantRole(ROLES.INSURANCE_MANAGER_ROLE, insuranceManager.address);

      // Mint token first
      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      await expect(token.connect(insuranceManager).updateInsuranceStatus(
        tokenId,
        true,
        1000000,
        5000
      )).to.be.revertedWith(ERRORS.INSURANCE_NOT_ENABLED);
    });

    it("Should allow updateInsuranceStatus when insurance enabled", async function () {
      const { token, complianceManager, user1, insuranceManager } = await loadFixture(deployWithFeaturesFixture);

      // Mint token first
      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      await expect(token.connect(insuranceManager).updateInsuranceStatus(
        tokenId,
        true,
        1000000,
        5000
      )).to.emit(token, "InsuranceStatusUpdated");

      const status = await token.getInsuranceStatus(tokenId);
      expect(status.isInsurable).to.be.true;
      expect(status.maxCoverage).to.equal(1000000);
      expect(status.riskScore).to.equal(5000);
    });
  });

  describe("Rating Integration", function () {
    it("Should revert updateRating when ratings not enabled", async function () {
      const { token, complianceManager, user1, owner, ratingAgency } = await loadFixture(deployBasicFixture);

      await token.connect(owner).grantRole(ROLES.RATING_AGENCY_ROLE, ratingAgency.address);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      await expect(token.connect(ratingAgency).updateRating(
        tokenId,
        8000,
        "A",
        3
      )).to.be.revertedWith(ERRORS.RATINGS_NOT_ENABLED);
    });

    it("Should allow updateRating when ratings enabled", async function () {
      const { token, complianceManager, user1, ratingAgency } = await loadFixture(deployWithFeaturesFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      await expect(token.connect(ratingAgency).updateRating(
        tokenId,
        8000,
        "A",
        3
      )).to.emit(token, "RatingUpdated");

      const [score, grade, count] = await token.getRating(tokenId);
      expect(score).to.equal(8000);
      expect(grade).to.equal("A");
      expect(count).to.equal(3);
    });

    it("Should correctly identify investment grade credits", async function () {
      const { token, complianceManager, user1, ratingAgency } = await loadFixture(deployWithFeaturesFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      // Set BBB rating (investment grade)
      await token.connect(ratingAgency).updateRating(tokenId, 6000, "BBB", 2);
      expect(await token.isInvestmentGrade(tokenId)).to.be.true;

      // Set BB rating (below investment grade)
      await token.connect(ratingAgency).updateRating(tokenId, 5000, "BB", 2);
      expect(await token.isInvestmentGrade(tokenId)).to.be.false;
    });
  });

  describe("dMRV Integration", function () {
    it("Should update dMRV status", async function () {
      const { token, complianceManager, user1, dmrvOracle } = await loadFixture(deployWithFeaturesFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const reportId = ethers.keccak256(ethers.toUtf8Bytes("REPORT_001"));

      await expect(token.connect(dmrvOracle).updateDMRVStatus(
        tokenId,
        reportId,
        1000000,
        10,
        false
      )).to.emit(token, "DMRVStatusUpdated");

      const status = await token.getDMRVStatus(tokenId);
      expect(status.isMonitored).to.be.true;
      expect(status.latestReportId).to.equal(reportId);
      expect(status.cumulativeReductions).to.equal(1000000);
    });
  });

  describe("SMART Protocol Compliance", function () {
    it("Should update SMART compliance status", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const complianceDataId = ethers.keccak256(ethers.toUtf8Bytes("SMART_DATA_001"));

      await token.connect(complianceManager).updateSMARTCompliance(
        tokenId,
        true,  // locationVerified
        true,  // temporallyBound
        true,  // verificationComplete
        true,  // custodyAssigned
        true,  // lineageTracked
        complianceDataId
      );

      expect(await token.isSMARTCompliant(tokenId)).to.be.true;

      const compliance = await token.getSMARTCompliance(tokenId);
      expect(compliance.locationVerified).to.be.true;
      expect(compliance.complianceDataId).to.equal(complianceDataId);
    });

    it("Should return false for incomplete SMART compliance", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      await token.connect(complianceManager).updateSMARTCompliance(
        tokenId,
        true,  // locationVerified
        true,  // temporallyBound
        false, // verificationComplete - not complete
        true,  // custodyAssigned
        true,  // lineageTracked
        ethers.ZeroHash
      );

      expect(await token.isSMARTCompliant(tokenId)).to.be.false;
    });
  });

  describe("Pause Functionality", function () {
    it("Should allow admin to pause", async function () {
      const { token, owner } = await loadFixture(deployBasicFixture);

      await token.connect(owner).pause();
      expect(await token.paused()).to.be.true;
    });

    it("Should allow admin to unpause", async function () {
      const { token, owner } = await loadFixture(deployBasicFixture);

      await token.connect(owner).pause();
      await token.connect(owner).unpause();
      expect(await token.paused()).to.be.false;
    });

    it("Should revert minting when paused", async function () {
      const { token, owner, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(owner).pause();

      await expect(token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      )).to.be.reverted;
    });

    it("Should revert retirement when paused", async function () {
      const { token, owner, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      // Mint first
      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);

      await token.connect(owner).pause();

      await expect(token.connect(user1).retireCredits(
        tokenId,
        AMOUNTS.SMALL,
        "Climate commitment",
        "ACME Corp"
      )).to.be.reverted;
    });
  });

  describe("Feature Flags", function () {
    it("Should update feature flags correctly", async function () {
      const { token, owner } = await loadFixture(deployBasicFixture);

      await token.connect(owner).setFeatureFlags(true, true, false);

      expect(await token.insuranceEnabled()).to.be.true;
      expect(await token.ratingsEnabled()).to.be.true;
      expect(await token.vintageTrackingEnabled()).to.be.false;
    });

    it("Should emit FeatureFlagUpdated events", async function () {
      const { token, owner } = await loadFixture(deployBasicFixture);

      await expect(token.connect(owner).enableInsurance())
        .to.emit(token, "FeatureFlagUpdated")
        .withArgs("insurance", true);

      await expect(token.connect(owner).enableRatings())
        .to.emit(token, "FeatureFlagUpdated")
        .withArgs("ratings", true);
    });
  });

  describe("External Contract Management", function () {
    it("Should set insurance manager correctly", async function () {
      const { token, owner, insuranceManager } = await loadFixture(deployBasicFixture);

      await token.connect(owner).setInsuranceManager(insuranceManager.address);

      expect(await token.insuranceManager()).to.equal(insuranceManager.address);
      expect(await token.hasRole(ROLES.INSURANCE_MANAGER_ROLE, insuranceManager.address)).to.be.true;
    });

    it("Should emit ExternalContractSet event", async function () {
      const { token, owner, insuranceManager } = await loadFixture(deployBasicFixture);

      await expect(token.connect(owner).setInsuranceManager(insuranceManager.address))
        .to.emit(token, "ExternalContractSet")
        .withArgs("InsuranceManager", insuranceManager.address);
    });
  });

  describe("View Functions", function () {
    it("Should return all token IDs", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_2,
        2024,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest456"
      );

      const allTokenIds = await token.getAllTokenIds();
      expect(allTokenIds.length).to.equal(2);
    });

    it("Should return correct total credit types", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      expect(await token.getTotalCreditTypes()).to.equal(1);
    });

    it("Should return balance by project", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const balance = await token.balanceOfByProject(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023
      );

      expect(balance).to.equal(AMOUNTS.MEDIUM);
    });

    it("Should return comprehensive token info", async function () {
      const { token, complianceManager, user1 } = await loadFixture(deployBasicFixture);

      await token.connect(complianceManager).mintCredits(
        user1.address,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        AMOUNTS.MEDIUM,
        "VCS-VM0015",
        "QmTest123"
      );

      const tokenId = await token.generateTokenId(SAMPLE_PROJECTS.PROJECT_1, 2023);
      const info = await token.getComprehensiveTokenInfo(tokenId);

      expect(info.metadata.projectId).to.equal(SAMPLE_PROJECTS.PROJECT_1);
      expect(info.tokenTotalSupply).to.equal(AMOUNTS.MEDIUM);
    });
  });

  describe("ERC1155 Interface", function () {
    it("Should support ERC1155 interface", async function () {
      const { token } = await loadFixture(deployBasicFixture);
      // ERC1155 interface ID
      expect(await token.supportsInterface("0xd9b67a26")).to.be.true;
    });

    it("Should support AccessControl interface", async function () {
      const { token } = await loadFixture(deployBasicFixture);
      // IAccessControl interface ID
      expect(await token.supportsInterface("0x7965db0b")).to.be.true;
    });
  });
});

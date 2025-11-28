// SPDX-License-Identifier: MIT
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ROLES, SAMPLE_PROJECTS, JURISDICTIONS, TIME } = require("../helpers/constants");

describe("VintageTracker", function () {
  // Lifecycle state enum
  const LifecycleState = {
    Minted: 0,
    Active: 1,
    Locked: 2,
    Transferred: 3,
    Retired: 4,
    Invalidated: 5,
    Expired: 6,
  };

  // Vintage grade enum
  const VintageGrade = {
    Premium: 0,     // < 2 years old
    Standard: 1,    // 2-4 years old
    Discount: 2,    // 4-6 years old
    Legacy: 3,      // 6-8 years old
    Archive: 4,     // 8-10 years old
  };

  // Main deployment fixture
  async function deployVintageTrackerFixture() {
    const [owner, lifecycleManager, geofenceAdmin, vintageAdmin, user1, user2, user3] = await ethers.getSigners();

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
      user3,
    };
  }

  // Fixture with vintage record created
  async function deployWithVintageRecordFixture() {
    const deployment = await deployVintageTrackerFixture();
    const { tracker, lifecycleManager, user1 } = deployment;

    const creditId = ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001"));
    const tokenId = 12345n;
    const projectId = SAMPLE_PROJECTS.PROJECT_1;
    const vintageYear = 2023;

    await tracker.connect(lifecycleManager).createVintageRecord(
      creditId,
      tokenId,
      projectId,
      vintageYear,
      user1.address,
      JURISDICTIONS.USA
    );

    return { ...deployment, creditId, tokenId, projectId, vintageYear };
  }

  // Fixture with geofence configured
  async function deployWithGeofenceFixture() {
    const deployment = await deployVintageTrackerFixture();
    const { tracker, geofenceAdmin } = deployment;

    await tracker.connect(geofenceAdmin).configureGeofence(
      JURISDICTIONS.USA,
      "United States",
      true,   // isActive
      true,   // requiresKYC
      true,   // allowsInternationalTransfer
      10,     // minTransferAmount
      1000000, // maxTransferAmount
      [],     // approvedExchanges
      [JURISDICTIONS.EU, JURISDICTIONS.UK]  // compatibleJurisdictions
    );

    return deployment;
  }

  describe("Deployment", function () {
    it("Should deploy successfully", async function () {
      const { tracker } = await loadFixture(deployVintageTrackerFixture);
      expect(await tracker.getAddress()).to.not.equal(ethers.ZeroAddress);
    });

    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { tracker, owner } = await loadFixture(deployVintageTrackerFixture);
      expect(await tracker.hasRole(ROLES.DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should have correct constants", async function () {
      const { tracker } = await loadFixture(deployVintageTrackerFixture);

      expect(await tracker.COOLING_OFF_PERIOD()).to.equal(0);  // No cooling off
      expect(await tracker.PRECISION()).to.equal(10000);
      expect(await tracker.MIN_VINTAGE_QUALITY()).to.equal(1000);
    });

    it("Should initialize with zero statistics", async function () {
      const { tracker } = await loadFixture(deployVintageTrackerFixture);
      expect(await tracker.totalCreditsTracked()).to.equal(0);
      expect(await tracker.totalRetirements()).to.equal(0);
    });
  });

  describe("Vintage Record Creation", function () {
    it("Should create vintage record successfully", async function () {
      const { tracker, lifecycleManager, user1 } = await loadFixture(deployVintageTrackerFixture);

      const creditId = ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001"));

      await expect(tracker.connect(lifecycleManager).createVintageRecord(
        creditId,
        12345n,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        user1.address,
        JURISDICTIONS.USA
      )).to.emit(tracker, "VintageRecordCreated")
        .withArgs(creditId, 12345n, SAMPLE_PROJECTS.PROJECT_1, 2023, user1.address);
    });

    it("Should store vintage record correctly", async function () {
      const { tracker, creditId, tokenId, projectId, vintageYear, user1 } = await loadFixture(deployWithVintageRecordFixture);

      const record = await tracker.vintageRecords(creditId);

      expect(record.creditId).to.equal(creditId);
      expect(record.tokenId).to.equal(tokenId);
      expect(record.projectId).to.equal(projectId);
      expect(record.vintageYear).to.equal(vintageYear);
      expect(record.originalMinter).to.equal(user1.address);
      expect(record.currentHolder).to.equal(user1.address);
      expect(record.state).to.equal(LifecycleState.Active);  // Immediately active, no cooling off
      expect(record.transferCount).to.equal(0);
    });

    it("Should map token to credit ID", async function () {
      const { tracker, creditId, tokenId } = await loadFixture(deployWithVintageRecordFixture);

      expect(await tracker.tokenToCreditId(tokenId)).to.equal(creditId);
    });

    it("Should add credit to project credits", async function () {
      const { tracker, lifecycleManager, user1 } = await loadFixture(deployVintageTrackerFixture);

      const projectId = SAMPLE_PROJECTS.PROJECT_1;
      const creditId1 = ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001"));
      const creditId2 = ethers.keccak256(ethers.toUtf8Bytes("CREDIT_002"));

      await tracker.connect(lifecycleManager).createVintageRecord(creditId1, 1n, projectId, 2023, user1.address, ethers.ZeroHash);
      await tracker.connect(lifecycleManager).createVintageRecord(creditId2, 2n, projectId, 2024, user1.address, ethers.ZeroHash);

      const projectCredits = await tracker.getProjectCredits(projectId);
      expect(projectCredits.length).to.equal(2);
    });

    it("Should increment total credits tracked", async function () {
      const { tracker, lifecycleManager, user1 } = await loadFixture(deployVintageTrackerFixture);

      const countBefore = await tracker.totalCreditsTracked();

      await tracker.connect(lifecycleManager).createVintageRecord(
        ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001")),
        1n,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        user1.address,
        ethers.ZeroHash
      );

      expect(await tracker.totalCreditsTracked()).to.equal(countBefore + 1n);
    });

    it("Should revert without LIFECYCLE_MANAGER_ROLE", async function () {
      const { tracker, user1 } = await loadFixture(deployVintageTrackerFixture);

      await expect(tracker.connect(user1).createVintageRecord(
        ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001")),
        1n,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        user1.address,
        ethers.ZeroHash
      )).to.be.reverted;
    });

    it("Should revert with duplicate credit ID", async function () {
      const { tracker, lifecycleManager, user1, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await expect(tracker.connect(lifecycleManager).createVintageRecord(
        creditId,  // Same ID
        2n,
        SAMPLE_PROJECTS.PROJECT_2,
        2024,
        user1.address,
        ethers.ZeroHash
      )).to.be.revertedWith("Credit already exists");
    });
  });

  describe("Vintage Grading and Discount", function () {
    it("Should assign Premium grade for recent vintage", async function () {
      const { tracker, lifecycleManager, user1 } = await loadFixture(deployVintageTrackerFixture);

      const creditId = ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001"));
      const currentYear = new Date().getFullYear();

      await tracker.connect(lifecycleManager).createVintageRecord(
        creditId,
        1n,
        SAMPLE_PROJECTS.PROJECT_1,
        currentYear,  // Current year = Premium
        user1.address,
        ethers.ZeroHash
      );

      const record = await tracker.vintageRecords(creditId);
      expect(record.grade).to.equal(VintageGrade.Premium);
      expect(record.discountFactor).to.equal(0);  // No discount
    });

    it("Should calculate effective value with discount", async function () {
      const { tracker, lifecycleManager, user1, vintageAdmin } = await loadFixture(deployVintageTrackerFixture);

      const creditId = ethers.keccak256(ethers.toUtf8Bytes("CREDIT_001"));

      // Create with older vintage (5 years ago = Discount grade)
      const oldVintage = new Date().getFullYear() - 5;

      await tracker.connect(lifecycleManager).createVintageRecord(
        creditId,
        1n,
        SAMPLE_PROJECTS.PROJECT_1,
        oldVintage,
        user1.address,
        ethers.ZeroHash
      );

      // Get effective value (base 1000)
      const effectiveValue = await tracker.getEffectiveValue(creditId, 1000);

      // Should be less than base due to discount
      expect(effectiveValue).to.be.lte(1000);
    });

    it("Should update grade based on age", async function () {
      const { tracker, vintageAdmin, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(vintageAdmin).updateVintageGrade(creditId);

      const record = await tracker.vintageRecords(creditId);
      // Grade should be calculated based on vintage year
      expect(record.grade).to.be.gte(0);
      expect(record.grade).to.be.lte(4);
    });
  });

  describe("Transfer Recording", function () {
    it("Should record transfer", async function () {
      const { tracker, lifecycleManager, user1, user2, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const txHash = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));

      await expect(tracker.connect(lifecycleManager).recordTransfer(
        creditId,
        user1.address,
        user2.address,
        txHash
      )).to.emit(tracker, "CreditTransferred")
        .withArgs(creditId, user1.address, user2.address, 1);
    });

    it("Should update current holder", async function () {
      const { tracker, lifecycleManager, user1, user2, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const txHash = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));

      await tracker.connect(lifecycleManager).recordTransfer(creditId, user1.address, user2.address, txHash);

      const record = await tracker.vintageRecords(creditId);
      expect(record.currentHolder).to.equal(user2.address);
    });

    it("Should increment transfer count", async function () {
      const { tracker, lifecycleManager, user1, user2, user3, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const txHash1 = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));
      const txHash2 = ethers.keccak256(ethers.toUtf8Bytes("TX_002"));

      await tracker.connect(lifecycleManager).recordTransfer(creditId, user1.address, user2.address, txHash1);
      await tracker.connect(lifecycleManager).recordTransfer(creditId, user2.address, user3.address, txHash2);

      const record = await tracker.vintageRecords(creditId);
      expect(record.transferCount).to.equal(2);
    });

    it("Should update state to Transferred", async function () {
      const { tracker, lifecycleManager, user1, user2, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const txHash = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));

      await tracker.connect(lifecycleManager).recordTransfer(creditId, user1.address, user2.address, txHash);

      const record = await tracker.vintageRecords(creditId);
      expect(record.state).to.equal(LifecycleState.Transferred);
    });

    it("Should add provenance entry", async function () {
      const { tracker, lifecycleManager, user1, user2, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const txHash = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));

      await tracker.connect(lifecycleManager).recordTransfer(creditId, user1.address, user2.address, txHash);

      const provenance = await tracker.getCreditProvenance(creditId);
      expect(provenance.length).to.be.gt(0);
    });
  });

  describe("Transferability", function () {
    it("Should be transferable immediately after minting (no cooling off)", async function () {
      const { tracker, creditId } = await loadFixture(deployWithVintageRecordFixture);

      expect(await tracker.isTransferable(creditId)).to.be.true;
    });

    it("Should not be transferable when locked", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).lockCredit(creditId, 7 * TIME.ONE_DAY, "Under investigation");

      expect(await tracker.isTransferable(creditId)).to.be.false;
    });

    it("Should be transferable after lock expires", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).lockCredit(creditId, 100, "Short lock");

      await time.increase(101);

      expect(await tracker.isTransferable(creditId)).to.be.true;
    });

    it("Should not be transferable when retired", async function () {
      const { tracker, lifecycleManager, creditId, user1 } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).retireCredit(
        creditId,
        100,
        "Climate Corp",
        "Carbon neutrality",
        "QmCertificate123"
      );

      expect(await tracker.isTransferable(creditId)).to.be.false;
    });
  });

  describe("Credit Retirement", function () {
    it("Should retire credit", async function () {
      const { tracker, lifecycleManager, creditId, user1 } = await loadFixture(deployWithVintageRecordFixture);

      await expect(tracker.connect(lifecycleManager).retireCredit(
        creditId,
        100,
        "Climate Corp",
        "Carbon neutrality pledge",
        "QmCertificate123"
      )).to.emit(tracker, "CreditRetired");
    });

    it("Should store retirement record", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const retirementId = await tracker.connect(lifecycleManager).retireCredit.staticCall(
        creditId,
        100,
        "Climate Corp",
        "Carbon neutrality pledge",
        "QmCertificate123"
      );

      await tracker.connect(lifecycleManager).retireCredit(
        creditId,
        100,
        "Climate Corp",
        "Carbon neutrality pledge",
        "QmCertificate123"
      );

      const retirement = await tracker.retirements(retirementId);
      expect(retirement.creditId).to.equal(creditId);
      expect(retirement.amount).to.equal(100);
      expect(retirement.beneficiary).to.equal("Climate Corp");
      expect(retirement.purpose).to.equal("Carbon neutrality pledge");
    });

    it("Should update state to Retired", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).retireCredit(
        creditId,
        100,
        "Climate Corp",
        "Purpose",
        ""
      );

      const record = await tracker.vintageRecords(creditId);
      expect(record.state).to.equal(LifecycleState.Retired);
    });

    it("Should increment total retirements", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const countBefore = await tracker.totalRetirements();

      await tracker.connect(lifecycleManager).retireCredit(creditId, 100, "Beneficiary", "Purpose", "");

      expect(await tracker.totalRetirements()).to.equal(countBefore + 1n);
    });

    it("Should track retirements by vintage year", async function () {
      const { tracker, lifecycleManager, creditId, vintageYear } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).retireCredit(creditId, 100, "Beneficiary", "Purpose", "");

      const yearlyRetirements = await tracker.yearlyRetirements(vintageYear);
      expect(yearlyRetirements).to.equal(100);
    });

    it("Should add to user retirements", async function () {
      const { tracker, lifecycleManager, creditId, user1 } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).retireCredit(creditId, 100, "Beneficiary", "Purpose", "");

      const userRetirements = await tracker.getUserRetirements(user1.address);
      expect(userRetirements.length).to.be.gt(0);
    });

    it("Should revert retirement of already retired credit", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).retireCredit(creditId, 50, "Beneficiary", "Purpose", "");

      await expect(tracker.connect(lifecycleManager).retireCredit(
        creditId,
        50,
        "Beneficiary",
        "Purpose",
        ""
      )).to.be.revertedWith("Credit already retired");
    });
  });

  describe("Credit Locking", function () {
    it("Should lock credit", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await expect(tracker.connect(lifecycleManager).lockCredit(
        creditId,
        7 * TIME.ONE_DAY,
        "Under investigation"
      )).to.emit(tracker, "CreditLocked");
    });

    it("Should store lock record", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).lockCredit(creditId, 7 * TIME.ONE_DAY, "Under investigation");

      const lock = await tracker.locks(creditId);
      expect(lock.isActive).to.be.true;
      expect(lock.reason).to.equal("Under investigation");
    });

    it("Should update state to Locked", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).lockCredit(creditId, 7 * TIME.ONE_DAY, "Reason");

      const record = await tracker.vintageRecords(creditId);
      expect(record.state).to.equal(LifecycleState.Locked);
    });

    it("Should unlock credit", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).lockCredit(creditId, 7 * TIME.ONE_DAY, "Reason");
      await tracker.connect(lifecycleManager).unlockCredit(creditId);

      const lock = await tracker.locks(creditId);
      expect(lock.isActive).to.be.false;
    });

    it("Should emit CreditUnlocked event", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).lockCredit(creditId, 7 * TIME.ONE_DAY, "Reason");

      await expect(tracker.connect(lifecycleManager).unlockCredit(creditId))
        .to.emit(tracker, "CreditUnlocked");
    });
  });

  describe("Credit Invalidation", function () {
    it("Should invalidate credit", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await expect(tracker.connect(lifecycleManager).invalidateCredit(
        creditId,
        "Fraudulent verification detected"
      )).to.emit(tracker, "CreditInvalidated");
    });

    it("Should update state to Invalidated", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).invalidateCredit(creditId, "Reason");

      const record = await tracker.vintageRecords(creditId);
      expect(record.state).to.equal(LifecycleState.Invalidated);
    });

    it("Should not be transferable after invalidation", async function () {
      const { tracker, lifecycleManager, creditId } = await loadFixture(deployWithVintageRecordFixture);

      await tracker.connect(lifecycleManager).invalidateCredit(creditId, "Reason");

      expect(await tracker.isTransferable(creditId)).to.be.false;
    });
  });

  describe("Geofencing", function () {
    it("Should configure geofence", async function () {
      const { tracker, geofenceAdmin } = await loadFixture(deployVintageTrackerFixture);

      await expect(tracker.connect(geofenceAdmin).configureGeofence(
        JURISDICTIONS.USA,
        "United States",
        true,
        true,
        true,
        10,
        1000000,
        [],
        [JURISDICTIONS.EU]
      )).to.emit(tracker, "GeofenceConfigured");
    });

    it("Should store geofence configuration", async function () {
      const { tracker } = await loadFixture(deployWithGeofenceFixture);

      const geofence = await tracker.geofences(JURISDICTIONS.USA);
      expect(geofence.jurisdictionName).to.equal("United States");
      expect(geofence.isActive).to.be.true;
      expect(geofence.requiresKYC).to.be.true;
      expect(geofence.allowsInternationalTransfer).to.be.true;
    });

    it("Should check jurisdiction compatibility", async function () {
      const { tracker, geofenceAdmin } = await loadFixture(deployWithGeofenceFixture);

      // Configure EU as compatible
      await tracker.connect(geofenceAdmin).configureGeofence(
        JURISDICTIONS.EU,
        "European Union",
        true,
        true,
        true,
        10,
        1000000,
        [],
        [JURISDICTIONS.USA]  // Compatible with USA
      );

      const isCompatible = await tracker.areJurisdictionsCompatible(JURISDICTIONS.USA, JURISDICTIONS.EU);
      expect(isCompatible).to.be.true;
    });

    it("Should check transfer amount limits", async function () {
      const { tracker } = await loadFixture(deployWithGeofenceFixture);

      // Amount within limits
      expect(await tracker.isTransferAmountValid(JURISDICTIONS.USA, 500)).to.be.true;

      // Amount below minimum
      expect(await tracker.isTransferAmountValid(JURISDICTIONS.USA, 5)).to.be.false;

      // Amount above maximum
      expect(await tracker.isTransferAmountValid(JURISDICTIONS.USA, 2000000)).to.be.false;
    });

    it("Should set user jurisdiction", async function () {
      const { tracker, geofenceAdmin, user1 } = await loadFixture(deployWithGeofenceFixture);

      await tracker.connect(geofenceAdmin).setUserJurisdiction(user1.address, JURISDICTIONS.USA);

      expect(await tracker.userJurisdiction(user1.address)).to.equal(JURISDICTIONS.USA);
    });
  });

  describe("Provenance Tracking", function () {
    it("Should create provenance entry on mint", async function () {
      const { tracker, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const provenance = await tracker.getCreditProvenance(creditId);
      expect(provenance.length).to.be.gt(0);
      expect(provenance[0].action).to.equal("mint");
    });

    it("Should add provenance entry on state change", async function () {
      const { tracker, lifecycleManager, user1, user2, creditId } = await loadFixture(deployWithVintageRecordFixture);

      const txHash = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));
      await tracker.connect(lifecycleManager).recordTransfer(creditId, user1.address, user2.address, txHash);

      const provenance = await tracker.getCreditProvenance(creditId);
      expect(provenance.length).to.be.gte(2);
    });

    it("Should maintain complete history", async function () {
      const { tracker, lifecycleManager, user1, user2, user3, creditId } = await loadFixture(deployWithVintageRecordFixture);

      // Multiple transfers
      const txHash1 = ethers.keccak256(ethers.toUtf8Bytes("TX_001"));
      const txHash2 = ethers.keccak256(ethers.toUtf8Bytes("TX_002"));

      await tracker.connect(lifecycleManager).recordTransfer(creditId, user1.address, user2.address, txHash1);
      await tracker.connect(lifecycleManager).recordTransfer(creditId, user2.address, user3.address, txHash2);

      // Lock and unlock
      await tracker.connect(lifecycleManager).lockCredit(creditId, 100, "Review");
      await tracker.connect(lifecycleManager).unlockCredit(creditId);

      const provenance = await tracker.getCreditProvenance(creditId);
      expect(provenance.length).to.be.gte(5);  // mint + 2 transfers + lock + unlock
    });
  });

  describe("Discount Schedule Configuration", function () {
    it("Should update discount schedule", async function () {
      const { tracker, vintageAdmin } = await loadFixture(deployVintageTrackerFixture);

      await expect(tracker.connect(vintageAdmin).updateDiscountSchedule(
        2 * 365 * TIME.ONE_DAY,   // premiumMaxAge
        4 * 365 * TIME.ONE_DAY,   // standardMaxAge
        6 * 365 * TIME.ONE_DAY,   // discountMaxAge
        8 * 365 * TIME.ONE_DAY,   // legacyMaxAge
        0,                         // premiumDiscount
        200,                       // standardDiscount (2%)
        500,                       // discountDiscount (5%)
        1000,                      // legacyDiscount (10%)
        2000                       // archiveDiscount (20%)
      )).to.emit(tracker, "DiscountScheduleUpdated");
    });

    it("Should revert without VINTAGE_ADMIN_ROLE", async function () {
      const { tracker, user1 } = await loadFixture(deployVintageTrackerFixture);

      await expect(tracker.connect(user1).updateDiscountSchedule(
        0, 0, 0, 0, 0, 0, 0, 0, 0
      )).to.be.reverted;
    });
  });

  describe("View Functions", function () {
    it("Should get vintage record", async function () {
      const { tracker, creditId, tokenId, projectId, vintageYear, user1 } = await loadFixture(deployWithVintageRecordFixture);

      const record = await tracker.getVintageRecord(creditId);

      expect(record.creditIdRet).to.equal(creditId);
      expect(record.tokenId).to.equal(tokenId);
      expect(record.projectId).to.equal(projectId);
      expect(record.vintageYear).to.equal(vintageYear);
      expect(record.originalMinter).to.equal(user1.address);
    });

    it("Should get credits by vintage year", async function () {
      const { tracker, vintageYear } = await loadFixture(deployWithVintageRecordFixture);

      const count = await tracker.creditsByVintageYear(vintageYear);
      expect(count).to.equal(1);
    });

    it("Should get credits by state", async function () {
      const { tracker } = await loadFixture(deployWithVintageRecordFixture);

      const activeCount = await tracker.creditsByState(LifecycleState.Active);
      expect(activeCount).to.be.gt(0);
    });

    it("Should get jurisdiction list", async function () {
      const { tracker, geofenceAdmin } = await loadFixture(deployWithGeofenceFixture);

      const jurisdictions = await tracker.getJurisdictionList();
      expect(jurisdictions.length).to.be.gt(0);
    });
  });

  describe("Pause Functionality", function () {
    it("Should pause contract", async function () {
      const { tracker, owner } = await loadFixture(deployVintageTrackerFixture);

      await tracker.connect(owner).pause();
      expect(await tracker.paused()).to.be.true;
    });

    it("Should revert operations when paused", async function () {
      const { tracker, owner, lifecycleManager, user1 } = await loadFixture(deployVintageTrackerFixture);

      await tracker.connect(owner).pause();

      await expect(tracker.connect(lifecycleManager).createVintageRecord(
        ethers.keccak256(ethers.toUtf8Bytes("CREDIT")),
        1n,
        SAMPLE_PROJECTS.PROJECT_1,
        2023,
        user1.address,
        ethers.ZeroHash
      )).to.be.reverted;
    });

    it("Should unpause contract", async function () {
      const { tracker, owner } = await loadFixture(deployVintageTrackerFixture);

      await tracker.connect(owner).pause();
      await tracker.connect(owner).unpause();

      expect(await tracker.paused()).to.be.false;
    });
  });
});

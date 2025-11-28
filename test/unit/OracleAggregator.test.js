// SPDX-License-Identifier: MIT
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ROLES, SAMPLE_PROJECTS, ORACLE } = require("../helpers/constants");

describe("OracleAggregator", function () {
  // Oracle status enum
  const OracleStatus = {
    Active: 0,
    Suspended: 1,
    Deprecated: 2,
    Offline: 3,
  };

  // Aggregation strategy enum
  const AggregationStrategy = {
    Median: 0,
    WeightedMedian: 1,
    TrimmedMean: 2,
    WeightedAverage: 3,
  };

  // Data type enum
  const DataType = {
    EmissionRate: 0,
    ReductionAmount: 1,
    SensorReading: 2,
    VerificationScore: 3,
    PriceData: 4,
    WeatherData: 5,
    Custom: 6,
  };

  // Main deployment fixture
  async function deployOracleAggregatorFixture() {
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

  // Fixture with registered oracles
  async function deployWithOraclesFixture() {
    const deployment = await deployOracleAggregatorFixture();
    const { aggregator, admin, oracle1, oracle2, oracle3 } = deployment;

    // Register 3 oracles (minimum required)
    await aggregator.connect(admin).registerOracle(
      oracle1.address,
      "Oracle One",
      "https://oracle1.example.com",
      5000,  // weight
      3600,  // heartbeat
      false, // not chainlink
      ethers.ZeroHash
    );

    await aggregator.connect(admin).registerOracle(
      oracle2.address,
      "Oracle Two",
      "https://oracle2.example.com",
      3000,
      3600,
      false,
      ethers.ZeroHash
    );

    await aggregator.connect(admin).registerOracle(
      oracle3.address,
      "Oracle Three",
      "https://oracle3.example.com",
      2000,
      3600,
      false,
      ethers.ZeroHash
    );

    // Grant oracle node role
    await aggregator.grantRole(ROLES.ORACLE_NODE_ROLE, oracle1.address);
    await aggregator.grantRole(ROLES.ORACLE_NODE_ROLE, oracle2.address);
    await aggregator.grantRole(ROLES.ORACLE_NODE_ROLE, oracle3.address);

    return deployment;
  }

  // Fixture with data feed
  async function deployWithDataFeedFixture() {
    const deployment = await deployWithOraclesFixture();
    const { aggregator, admin } = deployment;

    const feedId = ethers.keccak256(ethers.toUtf8Bytes("EMISSION_FEED_001"));
    const projectId = SAMPLE_PROJECTS.PROJECT_1;

    await aggregator.connect(admin).createDataFeed(
      feedId,
      projectId,
      DataType.EmissionRate,
      "Emission rate feed for project 1",
      AggregationStrategy.Median,
      3,     // minOracles
      2000,  // maxDeviation (20%)
      3600   // heartbeat
    );

    return { ...deployment, feedId, projectId };
  }

  describe("Deployment", function () {
    it("Should deploy successfully", async function () {
      const { aggregator } = await loadFixture(deployOracleAggregatorFixture);
      expect(await aggregator.getAddress()).to.not.equal(ethers.ZeroAddress);
    });

    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { aggregator, owner } = await loadFixture(deployOracleAggregatorFixture);
      expect(await aggregator.hasRole(ROLES.DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should initialize with correct constants", async function () {
      const { aggregator } = await loadFixture(deployOracleAggregatorFixture);

      expect(await aggregator.MIN_ORACLES()).to.equal(3);
      expect(await aggregator.MAX_ORACLES()).to.equal(20);
      expect(await aggregator.MAX_DEVIATION_PERCENTAGE()).to.equal(2000);
      expect(await aggregator.MIN_QUALITY_SCORE()).to.equal(5000);
    });

    it("Should initialize circuit breaker as inactive", async function () {
      const { aggregator } = await loadFixture(deployOracleAggregatorFixture);
      expect(await aggregator.circuitBreakerActive()).to.be.false;
    });
  });

  describe("Oracle Registration", function () {
    it("Should register oracle successfully", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployOracleAggregatorFixture);

      await expect(aggregator.connect(admin).registerOracle(
        oracle1.address,
        "Test Oracle",
        "https://test.example.com",
        5000,
        3600,
        false,
        ethers.ZeroHash
      )).to.emit(aggregator, "OracleRegistered")
        .withArgs(oracle1.address, "Test Oracle", 5000);
    });

    it("Should store oracle configuration correctly", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployOracleAggregatorFixture);

      await aggregator.connect(admin).registerOracle(
        oracle1.address,
        "Test Oracle",
        "https://test.example.com",
        5000,
        3600,
        false,
        ethers.ZeroHash
      );

      const config = await aggregator.oracles(oracle1.address);
      expect(config.oracleAddress).to.equal(oracle1.address);
      expect(config.name).to.equal("Test Oracle");
      expect(config.weight).to.equal(5000);
      expect(config.heartbeat).to.equal(3600);
      expect(config.status).to.equal(OracleStatus.Active);
    });

    it("Should increment active oracle count", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployOracleAggregatorFixture);

      const countBefore = await aggregator.activeOracleCount();

      await aggregator.connect(admin).registerOracle(
        oracle1.address,
        "Test Oracle",
        "https://test.example.com",
        5000,
        3600,
        false,
        ethers.ZeroHash
      );

      expect(await aggregator.activeOracleCount()).to.equal(countBefore + 1n);
    });

    it("Should revert without ORACLE_ADMIN_ROLE", async function () {
      const { aggregator, user1, oracle1 } = await loadFixture(deployOracleAggregatorFixture);

      await expect(aggregator.connect(user1).registerOracle(
        oracle1.address,
        "Test Oracle",
        "https://test.example.com",
        5000,
        3600,
        false,
        ethers.ZeroHash
      )).to.be.reverted;
    });

    it("Should revert with zero address", async function () {
      const { aggregator, admin } = await loadFixture(deployOracleAggregatorFixture);

      await expect(aggregator.connect(admin).registerOracle(
        ethers.ZeroAddress,
        "Test Oracle",
        "https://test.example.com",
        5000,
        3600,
        false,
        ethers.ZeroHash
      )).to.be.revertedWith("Invalid oracle address");
    });

    it("Should revert with invalid weight", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployOracleAggregatorFixture);

      await expect(aggregator.connect(admin).registerOracle(
        oracle1.address,
        "Test Oracle",
        "https://test.example.com",
        0,     // Invalid weight
        3600,
        false,
        ethers.ZeroHash
      )).to.be.revertedWith("Invalid weight");
    });

    it("Should revert when registering same oracle twice", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployOracleAggregatorFixture);

      await aggregator.connect(admin).registerOracle(
        oracle1.address,
        "Test Oracle",
        "https://test.example.com",
        5000,
        3600,
        false,
        ethers.ZeroHash
      );

      await expect(aggregator.connect(admin).registerOracle(
        oracle1.address,
        "Test Oracle 2",
        "https://test2.example.com",
        3000,
        3600,
        false,
        ethers.ZeroHash
      )).to.be.revertedWith("Oracle already registered");
    });
  });

  describe("Oracle Status Management", function () {
    it("Should suspend oracle", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployWithOraclesFixture);

      await expect(aggregator.connect(admin).updateOracleStatus(oracle1.address, OracleStatus.Suspended))
        .to.emit(aggregator, "OracleStatusChanged")
        .withArgs(oracle1.address, OracleStatus.Active, OracleStatus.Suspended);

      const config = await aggregator.oracles(oracle1.address);
      expect(config.status).to.equal(OracleStatus.Suspended);
    });

    it("Should decrement active count when suspending", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployWithOraclesFixture);

      const countBefore = await aggregator.activeOracleCount();

      await aggregator.connect(admin).updateOracleStatus(oracle1.address, OracleStatus.Suspended);

      expect(await aggregator.activeOracleCount()).to.equal(countBefore - 1n);
    });

    it("Should reactivate suspended oracle", async function () {
      const { aggregator, admin, oracle1 } = await loadFixture(deployWithOraclesFixture);

      await aggregator.connect(admin).updateOracleStatus(oracle1.address, OracleStatus.Suspended);
      await aggregator.connect(admin).updateOracleStatus(oracle1.address, OracleStatus.Active);

      const config = await aggregator.oracles(oracle1.address);
      expect(config.status).to.equal(OracleStatus.Active);
    });
  });

  describe("Data Feed Management", function () {
    it("Should create data feed", async function () {
      const { aggregator, admin } = await loadFixture(deployWithOraclesFixture);

      const feedId = ethers.keccak256(ethers.toUtf8Bytes("TEST_FEED"));

      await expect(aggregator.connect(admin).createDataFeed(
        feedId,
        SAMPLE_PROJECTS.PROJECT_1,
        DataType.EmissionRate,
        "Test emission feed",
        AggregationStrategy.Median,
        3,
        2000,
        3600
      )).to.emit(aggregator, "DataFeedCreated");
    });

    it("Should store feed configuration correctly", async function () {
      const { aggregator, feedId, projectId } = await loadFixture(deployWithDataFeedFixture);

      const feed = await aggregator.dataFeeds(feedId);

      expect(feed.feedId).to.equal(feedId);
      expect(feed.projectId).to.equal(projectId);
      expect(feed.dataType).to.equal(DataType.EmissionRate);
      expect(feed.strategy).to.equal(AggregationStrategy.Median);
      expect(feed.minOracles).to.equal(3);
      expect(feed.maxDeviation).to.equal(2000);
      expect(feed.isActive).to.be.true;
    });

    it("Should revert creating feed with invalid min oracles", async function () {
      const { aggregator, admin } = await loadFixture(deployWithOraclesFixture);

      const feedId = ethers.keccak256(ethers.toUtf8Bytes("TEST_FEED"));

      await expect(aggregator.connect(admin).createDataFeed(
        feedId,
        SAMPLE_PROJECTS.PROJECT_1,
        DataType.EmissionRate,
        "Test feed",
        AggregationStrategy.Median,
        1,     // Below MIN_ORACLES
        2000,
        3600
      )).to.be.revertedWith("Min oracles too low");
    });

    it("Should deactivate data feed", async function () {
      const { aggregator, admin, feedId } = await loadFixture(deployWithDataFeedFixture);

      await aggregator.connect(admin).deactivateDataFeed(feedId);

      const feed = await aggregator.dataFeeds(feedId);
      expect(feed.isActive).to.be.false;
    });
  });

  describe("Data Submission", function () {
    it("Should submit data from oracle", async function () {
      const { aggregator, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      const value = ethers.parseEther("100");  // 100 with 18 decimals
      const dataHash = ethers.keccak256(ethers.toUtf8Bytes("test_data"));

      await expect(aggregator.connect(oracle1).submitData(
        feedId,
        value,
        dataHash,
        8000,  // 80% confidence
        "ipfs://QmTest123"
      )).to.emit(aggregator, "DataSubmitted");
    });

    it("Should store submission correctly", async function () {
      const { aggregator, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      const value = ethers.parseEther("100");
      const dataHash = ethers.keccak256(ethers.toUtf8Bytes("test_data"));

      await aggregator.connect(oracle1).submitData(
        feedId,
        value,
        dataHash,
        8000,
        "ipfs://QmTest123"
      );

      const submission = await aggregator.feedSubmissions(feedId, oracle1.address);
      expect(submission.value).to.equal(value);
      expect(submission.confidence).to.equal(8000);
      expect(submission.isValid).to.be.true;
    });

    it("Should revert submission without ORACLE_NODE_ROLE", async function () {
      const { aggregator, user1, feedId } = await loadFixture(deployWithDataFeedFixture);

      await expect(aggregator.connect(user1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8000,
        ""
      )).to.be.reverted;
    });

    it("Should revert submission to inactive feed", async function () {
      const { aggregator, admin, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      await aggregator.connect(admin).deactivateDataFeed(feedId);

      await expect(aggregator.connect(oracle1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8000,
        ""
      )).to.be.revertedWith("Feed not active");
    });

    it("Should update oracle success count", async function () {
      const { aggregator, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      const configBefore = await aggregator.oracles(oracle1.address);

      await aggregator.connect(oracle1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8000,
        ""
      );

      const configAfter = await aggregator.oracles(oracle1.address);
      expect(configAfter.successCount).to.equal(configBefore.successCount + 1n);
    });
  });

  describe("Data Aggregation", function () {
    async function submitMultipleDataFixture() {
      const deployment = await deployWithDataFeedFixture();
      const { aggregator, oracle1, oracle2, oracle3, feedId } = deployment;

      // All oracles submit similar values
      await aggregator.connect(oracle1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        9000,
        ""
      );

      await aggregator.connect(oracle2).submitData(
        feedId,
        ethers.parseEther("102"),
        ethers.ZeroHash,
        8500,
        ""
      );

      await aggregator.connect(oracle3).submitData(
        feedId,
        ethers.parseEther("98"),
        ethers.ZeroHash,
        8000,
        ""
      );

      return deployment;
    }

    it("Should aggregate data from multiple oracles", async function () {
      const { aggregator, admin, feedId } = await loadFixture(submitMultipleDataFixture);

      await expect(aggregator.connect(admin).aggregateData(feedId))
        .to.emit(aggregator, "DataAggregated");
    });

    it("Should store aggregated result", async function () {
      const { aggregator, admin, feedId } = await loadFixture(submitMultipleDataFixture);

      await aggregator.connect(admin).aggregateData(feedId);

      const result = await aggregator.latestResults(feedId);
      expect(result.feedId).to.equal(feedId);
      expect(result.oracleCount).to.equal(3);
      expect(result.value).to.be.gt(0);
    });

    it("Should calculate quality score", async function () {
      const { aggregator, admin, feedId } = await loadFixture(submitMultipleDataFixture);

      await aggregator.connect(admin).aggregateData(feedId);

      const result = await aggregator.latestResults(feedId);
      expect(result.qualityScore).to.be.gt(0);
      expect(result.qualityScore).to.be.lte(10000);
    });

    it("Should revert aggregation with insufficient oracles", async function () {
      const { aggregator, admin, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      // Only one oracle submits
      await aggregator.connect(oracle1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8000,
        ""
      );

      await expect(aggregator.connect(admin).aggregateData(feedId))
        .to.be.revertedWith("Insufficient oracle submissions");
    });

    it("Should return latest aggregated value", async function () {
      const { aggregator, admin, feedId } = await loadFixture(submitMultipleDataFixture);

      await aggregator.connect(admin).aggregateData(feedId);

      const [value, timestamp, quality] = await aggregator.getLatestValue(feedId);

      expect(value).to.be.gt(0);
      expect(timestamp).to.be.gt(0);
      expect(quality).to.be.gt(0);
    });
  });

  describe("Anomaly Detection", function () {
    it("Should detect anomaly when values deviate too much", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      // Submit normal values
      await aggregator.connect(oracle1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        9000,
        ""
      );

      await aggregator.connect(oracle2).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8500,
        ""
      );

      // Submit anomalous value (50% deviation)
      await aggregator.connect(oracle3).submitData(
        feedId,
        ethers.parseEther("150"),  // 50% higher
        ethers.ZeroHash,
        8000,
        ""
      );

      await expect(aggregator.connect(admin).aggregateData(feedId))
        .to.emit(aggregator, "AnomalyDetected");
    });

    it("Should record anomaly details", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      await aggregator.connect(oracle1).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 9000, "");
      await aggregator.connect(oracle2).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8500, "");
      await aggregator.connect(oracle3).submitData(feedId, ethers.parseEther("150"), ethers.ZeroHash, 8000, "");

      await aggregator.connect(admin).aggregateData(feedId);

      const anomalyCount = await aggregator.anomalyCount();
      expect(anomalyCount).to.be.gt(0);
    });

    it("Should resolve anomaly", async function () {
      const { aggregator, admin, resolver, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      await aggregator.connect(oracle1).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 9000, "");
      await aggregator.connect(oracle2).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8500, "");
      await aggregator.connect(oracle3).submitData(feedId, ethers.parseEther("150"), ethers.ZeroHash, 8000, "");

      await aggregator.connect(admin).aggregateData(feedId);

      await expect(aggregator.connect(resolver).resolveAnomaly(1, "Outlier oracle suspended"))
        .to.emit(aggregator, "AnomalyResolved");

      const anomaly = await aggregator.anomalies(1);
      expect(anomaly.isResolved).to.be.true;
    });
  });

  describe("Circuit Breaker", function () {
    it("Should activate circuit breaker on consecutive anomalies", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      // Create multiple anomalies by repeatedly submitting divergent data
      for (let i = 0; i < 3; i++) {
        await aggregator.connect(oracle1).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 9000, "");
        await aggregator.connect(oracle2).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8500, "");
        await aggregator.connect(oracle3).submitData(feedId, ethers.parseEther("200"), ethers.ZeroHash, 8000, ""); // Large deviation

        await aggregator.connect(admin).aggregateData(feedId);

        // Clear submissions for next round
        await time.increase(3601);  // Past heartbeat
      }

      expect(await aggregator.circuitBreakerActive()).to.be.true;
    });

    it("Should emit CircuitBreakerTriggered event", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      // This test would need proper setup to trigger circuit breaker
      // For now, test manual activation
      await expect(aggregator.connect(admin).activateCircuitBreaker("Manual test"))
        .to.emit(aggregator, "CircuitBreakerTriggered");
    });

    it("Should prevent data submission when circuit breaker active", async function () {
      const { aggregator, admin, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      await aggregator.connect(admin).activateCircuitBreaker("Test");

      await expect(aggregator.connect(oracle1).submitData(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8000,
        ""
      )).to.be.revertedWith("Circuit breaker active");
    });

    it("Should allow admin to deactivate circuit breaker", async function () {
      const { aggregator, admin } = await loadFixture(deployOracleAggregatorFixture);

      await aggregator.connect(admin).activateCircuitBreaker("Test");
      await aggregator.connect(admin).deactivateCircuitBreaker();

      expect(await aggregator.circuitBreakerActive()).to.be.false;
    });
  });

  describe("HSM Attestation", function () {
    it("Should register HSM attestation", async function () {
      const { aggregator, admin } = await loadFixture(deployOracleAggregatorFixture);

      const attestationId = ethers.keccak256(ethers.toUtf8Bytes("ATTESTATION_001"));
      const sensorId = ethers.keccak256(ethers.toUtf8Bytes("SENSOR_001"));
      const signature = "0x1234";  // Mock signature
      const publicKeyHash = ethers.keccak256(ethers.toUtf8Bytes("PUBLIC_KEY"));

      await expect(aggregator.connect(admin).registerHSMAttestation(
        attestationId,
        sensorId,
        signature,
        publicKeyHash,
        30 * 24 * 3600  // 30 day validity
      )).to.emit(aggregator, "HSMAttestationRegistered");
    });

    it("Should validate attestation before accepting sensor data", async function () {
      const { aggregator, admin, oracle1, feedId } = await loadFixture(deployWithDataFeedFixture);

      const sensorId = ethers.keccak256(ethers.toUtf8Bytes("SENSOR_001"));

      // Register attestation
      await aggregator.connect(admin).registerHSMAttestation(
        ethers.keccak256(ethers.toUtf8Bytes("ATTESTATION_001")),
        sensorId,
        "0x1234",
        ethers.keccak256(ethers.toUtf8Bytes("PUBLIC_KEY")),
        30 * 24 * 3600
      );

      // Submit data with sensor reference
      await expect(aggregator.connect(oracle1).submitDataWithSensor(
        feedId,
        ethers.parseEther("100"),
        ethers.ZeroHash,
        8000,
        "",
        sensorId
      )).to.emit(aggregator, "DataSubmitted");
    });
  });

  describe("Stale Data Detection", function () {
    it("Should mark data as stale after heartbeat period", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      // Submit data
      await aggregator.connect(oracle1).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 9000, "");
      await aggregator.connect(oracle2).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8500, "");
      await aggregator.connect(oracle3).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8000, "");

      await aggregator.connect(admin).aggregateData(feedId);

      // Advance time past staleness threshold
      await time.increase(ORACLE.MAX_STALENESS + 1);

      // Check data is stale
      const isStale = await aggregator.isDataStale(feedId);
      expect(isStale).to.be.true;
    });

    it("Should return fresh data within heartbeat period", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      await aggregator.connect(oracle1).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 9000, "");
      await aggregator.connect(oracle2).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8500, "");
      await aggregator.connect(oracle3).submitData(feedId, ethers.parseEther("100"), ethers.ZeroHash, 8000, "");

      await aggregator.connect(admin).aggregateData(feedId);

      const isStale = await aggregator.isDataStale(feedId);
      expect(isStale).to.be.false;
    });
  });

  describe("View Functions", function () {
    it("Should return oracle list", async function () {
      const { aggregator, oracle1, oracle2, oracle3 } = await loadFixture(deployWithOraclesFixture);

      const list = await aggregator.getOracleList();
      expect(list.length).to.equal(3);
      expect(list).to.include(oracle1.address);
      expect(list).to.include(oracle2.address);
      expect(list).to.include(oracle3.address);
    });

    it("Should return feed IDs", async function () {
      const { aggregator, feedId } = await loadFixture(deployWithDataFeedFixture);

      const feeds = await aggregator.getFeedIds();
      expect(feeds.length).to.equal(1);
      expect(feeds[0]).to.equal(feedId);
    });

    it("Should return result history", async function () {
      const { aggregator, admin, oracle1, oracle2, oracle3, feedId } = await loadFixture(deployWithDataFeedFixture);

      // Submit and aggregate twice
      for (let i = 0; i < 2; i++) {
        await aggregator.connect(oracle1).submitData(feedId, ethers.parseEther(String(100 + i)), ethers.ZeroHash, 9000, "");
        await aggregator.connect(oracle2).submitData(feedId, ethers.parseEther(String(100 + i)), ethers.ZeroHash, 8500, "");
        await aggregator.connect(oracle3).submitData(feedId, ethers.parseEther(String(100 + i)), ethers.ZeroHash, 8000, "");

        await aggregator.connect(admin).aggregateData(feedId);
        await time.increase(3601);
      }

      const history = await aggregator.getResultHistory(feedId);
      expect(history.length).to.be.gte(2);
    });
  });

  describe("Pause Functionality", function () {
    it("Should pause contract", async function () {
      const { aggregator, owner } = await loadFixture(deployOracleAggregatorFixture);

      await aggregator.connect(owner).pause();
      expect(await aggregator.paused()).to.be.true;
    });

    it("Should revert operations when paused", async function () {
      const { aggregator, owner, admin, oracle1 } = await loadFixture(deployWithOraclesFixture);

      await aggregator.connect(owner).pause();

      const feedId = ethers.keccak256(ethers.toUtf8Bytes("TEST_FEED"));

      await expect(aggregator.connect(admin).createDataFeed(
        feedId,
        SAMPLE_PROJECTS.PROJECT_1,
        DataType.EmissionRate,
        "Test",
        AggregationStrategy.Median,
        3,
        2000,
        3600
      )).to.be.reverted;
    });
  });
});

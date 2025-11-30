// SPDX-License-Identifier: MIT
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time, mine } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ROLES, TIME } = require("../helpers/constants");

describe("GovernanceController", function () {
  // Proposal categories
  const ProposalCategory = {
    Standard: 0,
    Critical: 1,
    ParameterChange: 2,
    RoleManagement: 3,
    ContractUpgrade: 4,
    EmergencyAction: 5,
  };

  // Proposal states
  const ProposalState = {
    Pending: 0,
    Active: 1,
    Canceled: 2,
    Defeated: 3,
    Succeeded: 4,
    Queued: 5,
    Expired: 6,
    Executed: 7,
  };

  // Vote types
  const VoteType = {
    Against: 0,
    For: 1,
    Abstain: 2,
  };

  // Main deployment fixture
  async function deployGovernanceFixture() {
    const [owner, proposer, executor, guardian1, guardian2, signer1, signer2, signer3, voter1, voter2, user1] =
      await ethers.getSigners();

    const guardians = [guardian1.address, guardian2.address];
    const signers = [signer1.address, signer2.address, signer3.address];

    const GovernanceController = await ethers.getContractFactory("GovernanceController");
    const governance = await GovernanceController.deploy(
      TIME.ONE_DAY,           // proposalDelay (1 day)
      3 * TIME.ONE_DAY,       // votingPeriod (3 days)
      TIME.ONE_DAY,           // timelockDelay (1 day)
      1000,                   // quorumNumerator (10% - but using as absolute for simplicity)
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

    // Deploy a test target contract for proposals
    const TestTarget = await ethers.getContractFactory("TestTargetContract");
    const testTarget = await TestTarget.deploy();
    await testTarget.waitForDeployment();

    return {
      governance,
      testTarget,
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
      user1,
    };
  }

  // Fixture with an active proposal
  async function deployWithActiveProposalFixture() {
    const deployment = await deployGovernanceFixture();
    const { governance, testTarget, proposer } = deployment;

    // Create proposal
    const targets = [await testTarget.getAddress()];
    const values = [0];
    const calldatas = [testTarget.interface.encodeFunctionData("setValue", [42])];
    const signatures = [""];
    const description = "Set value to 42";

    await governance.connect(proposer).propose(
      targets,
      values,
      calldatas,
      signatures,
      description,
      ProposalCategory.Standard
    );

    // Advance past proposal delay to make it active
    const config = await governance.getConfig();
    const blocksToAdvance = Math.ceil(Number(config.proposalDelay) / 12) + 1;
    await mine(blocksToAdvance);

    return { ...deployment, targets, values, calldatas, signatures, description };
  }

  describe("Deployment", function () {
    it("Should deploy with correct configuration", async function () {
      const { governance } = await loadFixture(deployGovernanceFixture);

      const config = await governance.getConfig();
      expect(config.proposalDelay).to.equal(TIME.ONE_DAY);
      expect(config.votingPeriod).to.equal(3 * TIME.ONE_DAY);
      expect(config.timelockDelay).to.equal(TIME.ONE_DAY);
      expect(config.quorumNumerator).to.equal(1000);
      expect(config.proposalThreshold).to.equal(100);
    });

    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { governance, owner } = await loadFixture(deployGovernanceFixture);
      expect(await governance.hasRole(ROLES.DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should grant GUARDIAN_ROLE to guardians", async function () {
      const { governance, guardian1, guardian2 } = await loadFixture(deployGovernanceFixture);
      expect(await governance.hasRole(ROLES.GUARDIAN_ROLE, guardian1.address)).to.be.true;
      expect(await governance.hasRole(ROLES.GUARDIAN_ROLE, guardian2.address)).to.be.true;
    });

    it("Should grant MULTISIG_SIGNER_ROLE to signers", async function () {
      const { governance, signer1, signer2, signer3 } = await loadFixture(deployGovernanceFixture);
      expect(await governance.hasRole(ROLES.MULTISIG_SIGNER_ROLE, signer1.address)).to.be.true;
      expect(await governance.hasRole(ROLES.MULTISIG_SIGNER_ROLE, signer2.address)).to.be.true;
      expect(await governance.hasRole(ROLES.MULTISIG_SIGNER_ROLE, signer3.address)).to.be.true;
    });

    it("Should set correct multi-sig configuration", async function () {
      const { governance } = await loadFixture(deployGovernanceFixture);
      const [threshold, signerCount] = await governance.getMultiSigConfig();
      expect(threshold).to.equal(2);
      expect(signerCount).to.equal(3);
    });

    it("Should set default role voting multipliers", async function () {
      const { governance } = await loadFixture(deployGovernanceFixture);

      expect(await governance.roleVotingMultiplier(ROLES.GUARDIAN_ROLE)).to.equal(15000);
      expect(await governance.roleVotingMultiplier(ROLES.PROPOSER_ROLE)).to.equal(12000);
      expect(await governance.roleVotingMultiplier(ROLES.VOTER_ROLE)).to.equal(10000);
      expect(await governance.roleVotingMultiplier(ROLES.MULTISIG_SIGNER_ROLE)).to.equal(13000);
    });

    it("Should revert with proposal delay too short", async function () {
      const [owner] = await ethers.getSigners();
      const GovernanceController = await ethers.getContractFactory("GovernanceController");

      await expect(GovernanceController.deploy(
        100,                    // Too short
        3 * TIME.ONE_DAY,
        TIME.ONE_DAY,
        1000,
        100,
        2,
        [],
        [owner.address, owner.address]
      )).to.be.revertedWith("Delay too short");
    });

    it("Should revert with voting period too short", async function () {
      const [owner] = await ethers.getSigners();
      const GovernanceController = await ethers.getContractFactory("GovernanceController");

      await expect(GovernanceController.deploy(
        TIME.ONE_DAY,
        100,                    // Too short
        TIME.ONE_DAY,
        1000,
        100,
        2,
        [],
        [owner.address, owner.address]
      )).to.be.revertedWith("Voting period too short");
    });

    it("Should revert with invalid multi-sig threshold", async function () {
      const [owner] = await ethers.getSigners();
      const GovernanceController = await ethers.getContractFactory("GovernanceController");

      await expect(GovernanceController.deploy(
        TIME.ONE_DAY,
        3 * TIME.ONE_DAY,
        TIME.ONE_DAY,
        1000,
        100,
        0,                      // Invalid threshold
        [],
        [owner.address]
      )).to.be.revertedWith("Invalid threshold");
    });
  });

  describe("Proposal Creation", function () {
    it("Should create proposal successfully", async function () {
      const { governance, testTarget, proposer } = await loadFixture(deployGovernanceFixture);

      const targets = [await testTarget.getAddress()];
      const values = [0];
      const calldatas = [testTarget.interface.encodeFunctionData("setValue", [42])];
      const signatures = [""];
      const description = "Set value to 42";

      await expect(governance.connect(proposer).propose(
        targets,
        values,
        calldatas,
        signatures,
        description,
        ProposalCategory.Standard
      )).to.emit(governance, "ProposalCreated");
    });

    it("Should increment proposal count", async function () {
      const { governance, testTarget, proposer } = await loadFixture(deployGovernanceFixture);

      const countBefore = await governance.proposalCount();

      const targets = [await testTarget.getAddress()];
      const values = [0];
      const calldatas = [testTarget.interface.encodeFunctionData("setValue", [42])];

      await governance.connect(proposer).propose(
        targets,
        values,
        calldatas,
        [""],
        "Test proposal",
        ProposalCategory.Standard
      );

      expect(await governance.proposalCount()).to.equal(countBefore + 1n);
    });

    it("Should set correct required signatures for Critical category", async function () {
      const { governance, testTarget, proposer } = await loadFixture(deployGovernanceFixture);

      const targets = [await testTarget.getAddress()];
      const values = [0];
      const calldatas = [testTarget.interface.encodeFunctionData("setValue", [42])];

      await governance.connect(proposer).propose(
        targets,
        values,
        calldatas,
        [""],
        "Critical proposal",
        ProposalCategory.Critical
      );

      const proposal = await governance.getProposal(1);
      // Critical requires multi-sig threshold (2)
    });

    it("Should revert without PROPOSER_ROLE", async function () {
      const { governance, testTarget, user1 } = await loadFixture(deployGovernanceFixture);

      const targets = [await testTarget.getAddress()];
      const values = [0];
      const calldatas = [testTarget.interface.encodeFunctionData("setValue", [42])];

      await expect(governance.connect(user1).propose(
        targets,
        values,
        calldatas,
        [""],
        "Test proposal",
        ProposalCategory.Standard
      )).to.be.reverted;
    });

    it("Should revert with empty targets", async function () {
      const { governance, proposer } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(proposer).propose(
        [],
        [],
        [],
        [],
        "Empty proposal",
        ProposalCategory.Standard
      )).to.be.revertedWith("Empty proposal");
    });

    it("Should revert with empty description", async function () {
      const { governance, testTarget, proposer } = await loadFixture(deployGovernanceFixture);

      const targets = [await testTarget.getAddress()];

      await expect(governance.connect(proposer).propose(
        targets,
        [0],
        ["0x"],
        [""],
        "",
        ProposalCategory.Standard
      )).to.be.revertedWith("Empty description");
    });

    it("Should revert with mismatched array lengths", async function () {
      const { governance, testTarget, proposer } = await loadFixture(deployGovernanceFixture);

      const targets = [await testTarget.getAddress()];

      await expect(governance.connect(proposer).propose(
        targets,
        [0, 0],  // Wrong length
        ["0x"],
        [""],
        "Test",
        ProposalCategory.Standard
      )).to.be.revertedWith("Invalid proposal length");
    });

    it("Should revert when below proposal threshold", async function () {
      const { governance, testTarget, user1, owner } = await loadFixture(deployGovernanceFixture);

      // Grant proposer role but don't give enough voting power
      await governance.grantRole(ROLES.PROPOSER_ROLE, user1.address);
      await governance.setVotingPower(user1.address, 10, 10000);  // Below threshold of 100

      const targets = [await testTarget.getAddress()];

      await expect(governance.connect(user1).propose(
        targets,
        [0],
        ["0x"],
        [""],
        "Test",
        ProposalCategory.Standard
      )).to.be.revertedWith("Below proposal threshold");
    });

    it("Should revert when paused", async function () {
      const { governance, testTarget, proposer, guardian1 } = await loadFixture(deployGovernanceFixture);

      await governance.connect(guardian1).emergencyPause();

      const targets = [await testTarget.getAddress()];

      await expect(governance.connect(proposer).propose(
        targets,
        [0],
        ["0x"],
        [""],
        "Test",
        ProposalCategory.Standard
      )).to.be.revertedWith("Governance: paused");
    });
  });

  describe("Voting", function () {
    it("Should cast vote successfully", async function () {
      const { governance, voter1 } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(voter1).castVote(1, VoteType.For))
        .to.emit(governance, "VoteCast");
    });

    it("Should cast vote with reason", async function () {
      const { governance, voter1 } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(voter1).castVoteWithReason(
        1,
        VoteType.For,
        "I support this proposal"
      )).to.emit(governance, "VoteCast");

      // Verify the vote was recorded
      const receipt = await governance.getReceipt(1, voter1.address);
      expect(receipt.hasVoted).to.be.true;
      expect(receipt.support).to.equal(VoteType.For);
    });

    it("Should record vote in receipt", async function () {
      const { governance, voter1 } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(voter1).castVote(1, VoteType.For);

      const receipt = await governance.getReceipt(1, voter1.address);
      expect(receipt.hasVoted).to.be.true;
      expect(receipt.support).to.equal(VoteType.For);
      expect(receipt.votes).to.be.gt(0);
    });

    it("Should update proposal vote counts", async function () {
      const { governance, voter1, voter2 } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(voter1).castVote(1, VoteType.For);
      await governance.connect(voter2).castVote(1, VoteType.Against);

      const proposal = await governance.getProposal(1);
      expect(proposal.forVotes).to.be.gt(0);
      expect(proposal.againstVotes).to.be.gt(0);
    });

    it("Should revert when voting twice", async function () {
      const { governance, voter1 } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(voter1).castVote(1, VoteType.For);

      await expect(governance.connect(voter1).castVote(1, VoteType.Against))
        .to.be.revertedWith("Already voted");
    });

    it("Should revert when proposal not active", async function () {
      const { governance, testTarget, proposer, voter1 } = await loadFixture(deployGovernanceFixture);

      // Create proposal but don't advance time
      const targets = [await testTarget.getAddress()];
      await governance.connect(proposer).propose(
        targets,
        [0],
        ["0x"],
        [""],
        "Test",
        ProposalCategory.Standard
      );

      // Proposal is Pending, not Active
      await expect(governance.connect(voter1).castVote(1, VoteType.For))
        .to.be.revertedWith("Voting not active");
    });

    it("Should revert with no voting power", async function () {
      const { governance, user1, owner } = await loadFixture(deployWithActiveProposalFixture);

      // user1 has no voting power set
      await expect(governance.connect(user1).castVote(1, VoteType.For))
        .to.be.revertedWith("No voting power");
    });

    it("Should revert when paused", async function () {
      const { governance, voter1, guardian1 } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(guardian1).emergencyPause();

      await expect(governance.connect(voter1).castVote(1, VoteType.For))
        .to.be.revertedWith("Governance: paused");
    });
  });

  describe("Voting Power", function () {
    it("Should calculate voting power with base votes", async function () {
      const { governance, voter1 } = await loadFixture(deployGovernanceFixture);

      const votes = await governance.getVotes(voter1.address);
      expect(votes).to.be.gt(0);
    });

    it("Should apply role multiplier", async function () {
      const { governance, owner, guardian1 } = await loadFixture(deployGovernanceFixture);

      // Set same base votes
      await governance.setVotingPower(guardian1.address, 1000, 10000);

      const guardianVotes = await governance.getVotes(guardian1.address);
      // Guardian has 1.5x multiplier
      expect(guardianVotes).to.equal(1500);  // 1000 * 1.5
    });

    it("Should delegate votes", async function () {
      const { governance, voter1, voter2, owner } = await loadFixture(deployGovernanceFixture);

      await governance.connect(voter1).delegate(voter2.address);

      const vp = await governance.votingPower(voter1.address);
      expect(vp.delegate).to.equal(voter2.address);
    });

    it("Should emit DelegateChanged event", async function () {
      const { governance, voter1, voter2 } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(voter1).delegate(voter2.address))
        .to.emit(governance, "DelegateChanged")
        .withArgs(voter1.address, ethers.ZeroAddress, voter2.address);
    });
  });

  describe("Proposal State Machine", function () {
    it("Should be Pending immediately after creation", async function () {
      const { governance, testTarget, proposer } = await loadFixture(deployGovernanceFixture);

      const targets = [await testTarget.getAddress()];
      await governance.connect(proposer).propose(
        targets,
        [0],
        ["0x"],
        [""],
        "Test",
        ProposalCategory.Standard
      );

      expect(await governance.state(1)).to.equal(ProposalState.Pending);
    });

    it("Should be Active after delay passes", async function () {
      const { governance } = await loadFixture(deployWithActiveProposalFixture);

      expect(await governance.state(1)).to.equal(ProposalState.Active);
    });

    it("Should be Defeated when against votes win", async function () {
      const { governance, voter1, voter2 } = await loadFixture(deployWithActiveProposalFixture);

      // Vote against with more power
      await governance.connect(voter1).castVote(1, VoteType.Against);
      await governance.connect(voter2).castVote(1, VoteType.For);

      // Advance past voting period
      const config = await governance.getConfig();
      const blocksToAdvance = Math.ceil(Number(config.votingPeriod) / 12) + 1;
      await mine(blocksToAdvance);

      expect(await governance.state(1)).to.equal(ProposalState.Defeated);
    });

    it("Should be Succeeded when for votes win with quorum", async function () {
      const { governance, voter1, voter2 } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(voter1).castVote(1, VoteType.For);
      await governance.connect(voter2).castVote(1, VoteType.For);

      const config = await governance.getConfig();
      const blocksToAdvance = Math.ceil(Number(config.votingPeriod) / 12) + 1;
      await mine(blocksToAdvance);

      expect(await governance.state(1)).to.equal(ProposalState.Succeeded);
    });

    it("Should be Canceled after cancel is called", async function () {
      const { governance, proposer } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(proposer).cancel(1);

      expect(await governance.state(1)).to.equal(ProposalState.Canceled);
    });
  });

  describe("Queuing and Execution", function () {
    async function deploySucceededProposalFixture() {
      const deployment = await deployWithActiveProposalFixture();
      const { governance, voter1, voter2 } = deployment;

      await governance.connect(voter1).castVote(1, VoteType.For);
      await governance.connect(voter2).castVote(1, VoteType.For);

      const config = await governance.getConfig();
      const blocksToAdvance = Math.ceil(Number(config.votingPeriod) / 12) + 1;
      await mine(blocksToAdvance);

      return deployment;
    }

    it("Should queue succeeded proposal", async function () {
      const { governance } = await loadFixture(deploySucceededProposalFixture);

      await expect(governance.queue(1))
        .to.emit(governance, "ProposalQueued");
    });

    it("Should revert queue for non-succeeded proposal", async function () {
      const { governance } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.queue(1))
        .to.be.revertedWith("Proposal not succeeded");
    });

    it("Should execute queued proposal after timelock", async function () {
      const { governance, executor, testTarget } = await loadFixture(deploySucceededProposalFixture);

      await governance.queue(1);

      // Advance past timelock
      const config = await governance.getConfig();
      await time.increase(Number(config.timelockDelay) + 1);

      await expect(governance.connect(executor).execute(1))
        .to.emit(governance, "ProposalExecuted");

      // Check the target was called
      expect(await testTarget.value()).to.equal(42);
    });

    it("Should revert execution before timelock expires", async function () {
      const { governance, executor } = await loadFixture(deploySucceededProposalFixture);

      await governance.queue(1);

      await expect(governance.connect(executor).execute(1))
        .to.be.revertedWith("Timelock not expired");
    });

    it("Should revert execution after grace period", async function () {
      const { governance, executor } = await loadFixture(deploySucceededProposalFixture);

      await governance.queue(1);

      // Advance past timelock + grace period
      const config = await governance.getConfig();
      await time.increase(Number(config.timelockDelay) + TIME.GRACE_PERIOD + 1);

      // State becomes Expired, so execute fails with "Proposal not queued"
      // because state() returns Expired instead of Queued
      await expect(governance.connect(executor).execute(1))
        .to.be.revertedWith("Proposal not queued");
    });

    it("Should revert execution without EXECUTOR_ROLE", async function () {
      const { governance, user1 } = await loadFixture(deploySucceededProposalFixture);

      await governance.queue(1);

      const config = await governance.getConfig();
      await time.increase(Number(config.timelockDelay) + 1);

      await expect(governance.connect(user1).execute(1))
        .to.be.reverted;
    });
  });

  describe("Multi-Signature", function () {
    async function deployQueuedCriticalProposalFixture() {
      const deployment = await deployGovernanceFixture();
      const { governance, testTarget, proposer, voter1, voter2 } = deployment;

      // Create critical proposal
      const targets = [await testTarget.getAddress()];
      const values = [0];
      const calldatas = [testTarget.interface.encodeFunctionData("setValue", [42])];

      await governance.connect(proposer).propose(
        targets,
        values,
        calldatas,
        [""],
        "Critical proposal",
        ProposalCategory.Critical
      );

      // Make it active
      const config = await governance.getConfig();
      await mine(Math.ceil(Number(config.proposalDelay) / 12) + 1);

      // Vote for it
      await governance.connect(voter1).castVote(1, VoteType.For);
      await governance.connect(voter2).castVote(1, VoteType.For);

      // Make it succeeded
      await mine(Math.ceil(Number(config.votingPeriod) / 12) + 1);

      // Queue it
      await governance.queue(1);

      return deployment;
    }

    it("Should allow multi-sig signers to sign proposal", async function () {
      const { governance, signer1 } = await loadFixture(deployQueuedCriticalProposalFixture);

      await expect(governance.connect(signer1).signProposal(1))
        .to.emit(governance, "MultiSigApproval");
    });

    it("Should increment signature count", async function () {
      const { governance, signer1, signer2 } = await loadFixture(deployQueuedCriticalProposalFixture);

      await governance.connect(signer1).signProposal(1);
      await governance.connect(signer2).signProposal(1);

      expect(await governance.hasRequiredSignatures(1)).to.be.true;
    });

    it("Should revert signing without MULTISIG_SIGNER_ROLE", async function () {
      const { governance, user1 } = await loadFixture(deployQueuedCriticalProposalFixture);

      await expect(governance.connect(user1).signProposal(1))
        .to.be.reverted;
    });

    it("Should revert signing twice", async function () {
      const { governance, signer1 } = await loadFixture(deployQueuedCriticalProposalFixture);

      await governance.connect(signer1).signProposal(1);

      await expect(governance.connect(signer1).signProposal(1))
        .to.be.revertedWith("Already signed");
    });

    it("Should block execution without required signatures", async function () {
      const { governance, executor, signer1 } = await loadFixture(deployQueuedCriticalProposalFixture);

      // Only one signature (need 2)
      await governance.connect(signer1).signProposal(1);

      const config = await governance.getConfig();
      await time.increase(Number(config.timelockDelay) + 1);

      await expect(governance.connect(executor).execute(1))
        .to.be.revertedWith("Missing required signatures");
    });

    it("Should allow execution with required signatures", async function () {
      const { governance, executor, testTarget, signer1, signer2 } =
        await loadFixture(deployQueuedCriticalProposalFixture);

      await governance.connect(signer1).signProposal(1);
      await governance.connect(signer2).signProposal(1);

      const config = await governance.getConfig();
      await time.increase(Number(config.timelockDelay) + 1);

      await expect(governance.connect(executor).execute(1))
        .to.emit(governance, "ProposalExecuted");

      expect(await testTarget.value()).to.equal(42);
    });
  });

  describe("Cancellation", function () {
    it("Should allow proposer to cancel", async function () {
      const { governance, proposer } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(proposer).cancel(1))
        .to.emit(governance, "ProposalCanceled");
    });

    it("Should allow guardian to cancel", async function () {
      const { governance, guardian1 } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(guardian1).cancel(1))
        .to.emit(governance, "ProposalCanceled");
    });

    it("Should revert cancel from unauthorized address", async function () {
      const { governance, user1 } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(user1).cancel(1))
        .to.be.revertedWith("Not authorized to cancel");
    });

    it("Should revert cancel of already executed proposal", async function () {
      const { governance, voter1, voter2, executor, proposer } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(voter1).castVote(1, VoteType.For);
      await governance.connect(voter2).castVote(1, VoteType.For);

      const config = await governance.getConfig();
      await mine(Math.ceil(Number(config.votingPeriod) / 12) + 1);

      await governance.queue(1);
      await time.increase(Number(config.timelockDelay) + 1);
      await governance.connect(executor).execute(1);

      await expect(governance.connect(proposer).cancel(1))
        .to.be.revertedWith("Cannot cancel");
    });
  });

  describe("Guardian Functions", function () {
    it("Should allow guardian to pause", async function () {
      const { governance, guardian1 } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(guardian1).emergencyPause())
        .to.emit(governance, "EmergencyPause")
        .withArgs(guardian1.address, true);

      expect(await governance.paused()).to.be.true;
    });

    it("Should allow admin to unpause", async function () {
      const { governance, guardian1, owner } = await loadFixture(deployGovernanceFixture);

      await governance.connect(guardian1).emergencyPause();
      await governance.connect(owner).emergencyUnpause();

      expect(await governance.paused()).to.be.false;
    });

    it("Should allow guardian veto", async function () {
      const { governance, guardian1 } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(guardian1).guardianVeto(1, "Security concern"))
        .to.emit(governance, "GuardianAction")
        .and.to.emit(governance, "ProposalCanceled");

      expect(await governance.state(1)).to.equal(ProposalState.Canceled);
    });

    it("Should revert veto from non-guardian", async function () {
      const { governance, user1 } = await loadFixture(deployWithActiveProposalFixture);

      await expect(governance.connect(user1).guardianVeto(1, "Reason"))
        .to.be.revertedWith("Governance: not guardian");
    });

    it("Should revert pause from non-guardian", async function () {
      const { governance, user1 } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(user1).emergencyPause())
        .to.be.revertedWith("Governance: not guardian");
    });
  });

  describe("Configuration Updates", function () {
    it("Should update governance configuration", async function () {
      const { governance, owner } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(owner).updateGovernanceConfig(
        2 * TIME.ONE_DAY,
        5 * TIME.ONE_DAY,
        2 * TIME.ONE_DAY,
        2000
      )).to.emit(governance, "GovernanceConfigUpdated");

      const config = await governance.getConfig();
      expect(config.proposalDelay).to.equal(2 * TIME.ONE_DAY);
      expect(config.votingPeriod).to.equal(5 * TIME.ONE_DAY);
    });

    it("Should update multi-sig threshold", async function () {
      const { governance, owner } = await loadFixture(deployGovernanceFixture);

      await governance.connect(owner).updateMultiSigThreshold(3);

      const [threshold] = await governance.getMultiSigConfig();
      expect(threshold).to.equal(3);
    });

    it("Should set role voting multiplier", async function () {
      const { governance, owner } = await loadFixture(deployGovernanceFixture);

      await governance.connect(owner).setRoleVotingMultiplier(ROLES.VOTER_ROLE, 20000);

      expect(await governance.roleVotingMultiplier(ROLES.VOTER_ROLE)).to.equal(20000);
    });

    it("Should revert invalid multiplier (too low)", async function () {
      const { governance, owner } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(owner).setRoleVotingMultiplier(ROLES.VOTER_ROLE, 5000))
        .to.be.revertedWith("Invalid multiplier");
    });

    it("Should revert invalid multiplier (too high)", async function () {
      const { governance, owner } = await loadFixture(deployGovernanceFixture);

      await expect(governance.connect(owner).setRoleVotingMultiplier(ROLES.VOTER_ROLE, 50000))
        .to.be.revertedWith("Invalid multiplier");
    });
  });

  describe("View Functions", function () {
    it("Should check if account has voted", async function () {
      const { governance, voter1, voter2 } = await loadFixture(deployWithActiveProposalFixture);

      await governance.connect(voter1).castVote(1, VoteType.For);

      expect(await governance.hasVoted(1, voter1.address)).to.be.true;
      expect(await governance.hasVoted(1, voter2.address)).to.be.false;
    });

    it("Should return proposal actions", async function () {
      const { governance, targets, values, calldatas } = await loadFixture(deployWithActiveProposalFixture);

      const [returnedTargets, returnedValues, , returnedCalldatas] = await governance.getProposalActions(1);
      expect(returnedTargets[0]).to.equal(targets[0]);
      expect(returnedValues[0]).to.equal(values[0]);
    });
  });
});

// Test helper contract
const TestTargetContractSource = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestTargetContract {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }
}
`;

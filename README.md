# LMCX Carbon Credit

A comprehensive blockchain-based carbon credit tokenization system using **ERC1155** with multi-framework regulatory compliance, DAO governance, cryptographic verification, multi-oracle redundancy, vintage lifecycle tracking, and optional insurance/rating integrations.

## Overview

LMCX Carbon Credit is an enterprise-grade ERC1155 multi-token system designed to tokenize verified carbon credits while ensuring adherence to multiple international environmental standards. Each token unit represents 1 tonne of CO2 equivalent avoided or removed.

## Key Features

### Multi-Framework Regulatory Compliance
- **ISO 14064-2/3**: Project-level GHG quantification, validation, and verification
- **OGMP 2.0**: 5-level reporting framework with Gold Standard criteria
- **EPA Subpart W**: 40 CFR Part 98 compliance for petroleum and natural gas systems
- **UNFCCC CDM AM0023**: Methane avoidance methodology for waste management
- **CORSIA**: Aviation carbon offset compliance

### DAO Governance (GovernanceController)
- Time-locked proposals with configurable delays (1-30 days)
- Multi-signature requirements for critical operations
- Tiered voting weights based on stakeholder roles
- Guardian council for emergency oversight and veto power
- Proposal categories: Standard, Critical, ParameterChange, RoleManagement, ContractUpgrade, EmergencyAction

### Cryptographic Verification (VerificationRegistry)
- Merkle tree proofs for verification data integrity
- Multi-verifier signature aggregation with reputation scoring
- Immutable chain-of-custody tracking
- Zero-knowledge proof support for sensitive data
- IPFS/Arweave permanent storage references

### Multi-Oracle Redundancy (OracleAggregator)
- Minimum 3 independent data sources required
- Weighted median calculation for manipulation resistance
- Automatic anomaly detection with circuit breaker
- Data quality scoring (freshness, deviation, oracle count)
- HSM attestation for sensor integrity verification

### Vintage Lifecycle Tracking (VintageTracker)
- **No cooling-off period** - credits immediately transferable upon minting
- Vintage grade classification with **gradual discount curve**:
  - Premium (< 2 years): 0% discount
  - Standard (2-4 years): 2% discount
  - Discount (4-6 years): 5% discount
  - Legacy (6-8 years): 10% discount
  - Archive (8-10 years): 20% discount
- Full provenance tracking with immutable history
- Geofencing for jurisdiction-specific compliance
- Retirement certificate management

### Optional Insurance Integration
- Credit-level insurance policies (feature can be enabled/disabled)
- Risk-based premium calculation
- Claims processing and payout management
- Multiple coverage types (reversal, invalidation, delivery, political)
- Time-delayed risk score updates to prevent front-running

### Optional Rating Agency Access
- Registered rating agency support (feature can be enabled/disabled)
- Score-based grading system (AAA to D)
- Rating history and audit trails
- Watch list management
- Integration with insurance for risk pricing

### Real-Time dMRV (Enovate.ai Integration)
- Continuous monitoring data ingestion
- Sensor management and calibration
- Anomaly detection and alerting
- Monitoring report generation and verification

### SMART Protocol Compliance
- Physical location governance
- Temporal binding for measurements
- Multi-party verification without conflict of interest
- Event sequencing and governance workflows
- Traceable restatement processes
- Data custody and lineage tracking

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LMCXCarbonCredit (ERC1155)                          │
│   Token Contract with Governance, Verification, Oracle, Vintage Integration │
└───────────────────────────────────────┬─────────────────────────────────────┘
                                        │
         ┌──────────────────────────────┼──────────────────────────┐
         │                              │                          │
         ▼                              ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ GovernanceController│    │ VerificationRegistry │    │   OracleAggregator  │
│  - DAO proposals    │    │  - Merkle proofs     │    │  - Multi-oracle     │
│  - Time-locks       │    │  - Verifier sigs     │    │  - Anomaly detect   │
│  - Multi-sig        │    │  - Chain of custody  │    │  - Circuit breaker  │
│  - Guardian council │    │  - ZK proof support  │    │  - HSM attestation  │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
         │                              │                          │
         └──────────────────────────────┼──────────────────────────┘
                                        │
         ┌──────────────────────────────┼──────────────────────────┐
         │                              │                          │
         ▼                              ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   VintageTracker    │    │   InsuranceManager  │    │ RatingAgencyRegistry│
│  - No cooling-off   │    │  - Optional feature │    │  - Optional feature │
│  - Gradual discounts│    │  - Risk premiums    │    │  - Score grading    │
│  - Provenance       │    │  - Claims process   │    │  - Audit trails     │
│  - Geofencing       │    │  - Front-run protect│    │  - Watch lists      │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
         │                              │                          │
         └──────────────────────────────┼──────────────────────────┘
                                        │
                    ┌───────────────────┴───────────────┐
                    │                                   │
                    ▼                                   ▼
         ┌─────────────────────┐             ┌─────────────────────┐
         │  ComplianceManager  │             │     DMRVOracle      │
         │  - Regulatory checks│             │  - Enovate.ai       │
         │  - Minting approval │             │  - Sensor data      │
         │  - Aggregate scoring│             │  - Measurements     │
         └─────────────────────┘             └─────────────────────┘
                    │
         ┌──────────┴──────────┬──────────────┬──────────────┐
         ▼                     ▼              ▼              ▼
┌─────────────────┐   ┌─────────────────┐  ┌──────────┐  ┌──────────┐
│ ISO14064Validator│  │ OGMP2Validator  │  │EPASubpart│  │CDMAM0023 │
│  - Baseline      │  │  - 5-level      │  │Validator │  │Validator │
│  - Additionality │  │  - Gold Standard│  │          │  │          │
│  - Verification  │  │  - Reconciliation│ │          │  │          │
└─────────────────┘   └─────────────────┘  └──────────┘  └──────────┘
```

## Contracts Overview

| Contract | Purpose |
|----------|---------|
| **LMCXCarbonCredit** | ERC1155 multi-token with comprehensive integrations |
| **GovernanceController** | DAO governance with time-locks, multi-sig, guardian council |
| **VerificationRegistry** | Cryptographic proof chains and chain-of-custody tracking |
| **OracleAggregator** | Multi-oracle redundancy with anomaly detection |
| **VintageTracker** | Credit lifecycle, vintage grading, geofencing |
| **ComplianceManager** | Orchestrates regulatory checks and minting approval |
| **InsuranceManager** | Optional insurance policies, premiums, and claims |
| **RatingAgencyRegistry** | Optional rating agency registration and credit ratings |
| **DMRVOracle** | Ingests real-time monitoring data from Enovate.ai |
| **ISO14064Validator** | ISO 14064-2/3 compliance validation |
| **OGMP2Validator** | OGMP 2.0 5-level reporting framework |
| **EPASubpartWValidator** | EPA 40 CFR Part 98 Subpart W compliance |
| **CDMAM0023Validator** | UNFCCC CDM AM0023 methodology compliance |

## Optional Features

The system includes several optional features that can be enabled/disabled by administrators:

```solidity
// Enable/disable features
token.setFeatureFlags(
    true,   // insuranceEnabled
    true,   // ratingsEnabled
    true    // vintageTrackingEnabled
);

// Or individually
token.enableInsurance();
token.disableRatings();
```

## Vintage Discount Schedule

Credits retain high value over time with a gradual discount curve:

| Grade | Age Range | Discount | Quality Score |
|-------|-----------|----------|---------------|
| Premium | < 2 years | 0% | 100% |
| Standard | 2-4 years | 2% | 98% |
| Discount | 4-6 years | 5% | 95% |
| Legacy | 6-8 years | 10% | 90% |
| Archive | 8-10 years | 20% | 80% |

This reflects that methane reduction today is worth more than methane reduction tomorrow, while still maintaining significant value for older credits.

## Quick Start

### Installation

```bash
git clone https://github.com/YOUR_USERNAME/lmcx-carbon-credit.git
cd lmcx-carbon-credit
npm install
```

### Compile

```bash
npx hardhat compile
```

### Deploy

```bash
npx hardhat run scripts/deploy.js --network <network>
```

## Usage Examples

### Minting with Full Compliance

```solidity
// 1. Register project with SMART compliance
smartRegistry.registerLocation(projectId, lat, long, country, region, siteId);
smartRegistry.assignCustody(projectId, custodian, orgId, orgName, scope, expiry, hash);

// 2. Submit dMRV data
dmrvOracle.submitMeasurement(measurementId, projectId, sensorId, value, unit, type, hash);
dmrvOracle.submitMonitoringReport(reportId, projectId, start, end, count, emissions, reductions, hash);

// 3. Set compliance on validators
ogmpValidator.setCompliance(projectId, true, evidenceHash);
// ... other validators

// 4. Request and approve minting
complianceManager.requestMinting(beneficiary, amount, projectId, vintage, methodology, hash);
complianceManager.approveMinting(requestId);
```

### Governance Operations

```solidity
// Create a proposal
governanceController.propose(
    targets,
    values,
    calldatas,
    signatures,
    "Update compliance threshold",
    ProposalCategory.ParameterChange
);

// Vote on proposal
governanceController.castVoteWithReason(proposalId, VoteType.For, "Supports better integrity");

// Queue and execute after timelock
governanceController.queue(proposalId);
// ... wait for timelock delay ...
governanceController.execute(proposalId);
```

### Verification with Merkle Proofs

```solidity
// Create verification record
verificationRegistry.createVerificationRecord(
    recordId, projectId, creditTokenId, merkleRoot, leafCount,
    requiredSignatures, ipfsHash, methodologyHash, vintageYear
);

// Verifiers sign attestations
verificationRegistry.signVerification(recordId, signature, verifiedReductions, "Verified");

// Verify Merkle inclusion
bool isValid = verificationRegistry.verifyMerkleProof(recordId, leaf, merkleProof);
```

### Oracle Data Aggregation

```solidity
// Submit data from multiple oracles (minimum 3 required)
oracleAggregator.submitData(feedId, value, dataHash, confidence, sourceRef);

// Get aggregated result
(int256 value, uint256 timestamp, uint256 quality) = oracleAggregator.getLatestValue(feedId);
```

### Vintage Tracking

```solidity
// Get vintage discount-adjusted value
uint256 effectiveValue = token.getEffectiveValue(tokenId, baseValue);

// Check if credit is transferable
bool canTransfer = token.isCreditTransferable(tokenId);

// Retire with certificate
token.retireCreditsWithCertificate(tokenId, amount, reason, beneficiary, certificateHash);
```

## Roles

| Role | Permissions |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | System administration, role management |
| `COMPLIANCE_MANAGER_ROLE` | Mint tokens, update SMART compliance |
| `INSURANCE_MANAGER_ROLE` | Update insurance status (when enabled) |
| `RATING_AGENCY_ROLE` | Update ratings (when enabled) |
| `DMRV_ORACLE_ROLE` | Update dMRV monitoring data |
| `GOVERNANCE_ROLE` | Execute governance actions |
| `VINTAGE_TRACKER_ROLE` | Manage vintage lifecycle |
| `PROPOSER_ROLE` | Create governance proposals |
| `GUARDIAN_ROLE` | Emergency actions, veto power |

## Security Considerations

- Role-based access control for all privileged operations
- Reentrancy protection on financial operations
- Pausable functionality for emergency stops
- Time-delayed risk score updates to prevent front-running
- Multi-oracle redundancy with anomaly detection
- Circuit breaker for automatic pause on anomalies
- Merkle proofs for verification integrity
- Multi-signature requirements for critical operations
- Guardian council for emergency oversight

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contact

Last Mile Production, LLC

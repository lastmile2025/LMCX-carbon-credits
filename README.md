# LMCX Carbon Credit

A comprehensive blockchain-based carbon credit tokenization system using **ERC1155** with multi-framework regulatory compliance, insurance integration, rating agency support, real-time dMRV monitoring, and SMART Protocol data governance.

## Overview

LMCX Carbon Credit is an enterprise-grade ERC1155 multi-token system designed to tokenize verified carbon credits while ensuring adherence to multiple international environmental standards. Each token unit represents 1 tonne of CO2 equivalent avoided or removed.

## Key Features

### 🔐 Multi-Framework Regulatory Compliance
- OGMP 2.0, ISO 14065, CORSIA, EPA Subpart W, CDM AM0023

### 🛡️ Insurance Integration
- Credit-level insurance policies
- Risk-based premium calculation
- Claims processing and payout management
- Multiple coverage types (reversal, invalidation, delivery, political)

### 📊 Rating Agency Access
- Registered rating agency support
- Score-based grading system (AAA to D)
- Rating history and audit trails
- Watch list management
- Integration with insurance for risk pricing

### 📡 Real-Time dMRV (Enovate.ai Integration)
- Continuous monitoring data ingestion
- Sensor management and calibration
- Anomaly detection and alerting
- Monitoring report generation and verification

### ✅ SMART Protocol Compliance
- Physical location governance
- Temporal binding for measurements
- Multi-party verification without conflict of interest
- Event sequencing and governance workflows
- Traceable restatement processes
- Data custody and lineage tracking

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         LMCXCarbonCredit (ERC1155)                       │
│   Token Contract with Insurance, Rating, dMRV, SMART Integration         │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
         ▼                          ▼                          ▼
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ InsuranceManager │    │ RatingAgencyRegistry │    │     DMRVOracle      │
│  - Policies      │    │  - Agency mgmt       │    │  - Sensor data      │
│  - Claims        │    │  - Ratings           │    │  - Measurements     │
│  - Premiums      │    │  - Watch lists       │    │  - Reports          │
└─────────────────┘    └─────────────────────┘    └─────────────────────┘
         │                          │                          │
         └──────────────────────────┼──────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
         ┌─────────────────────┐         ┌─────────────────────┐
         │  SMARTDataRegistry  │         │  ComplianceManager  │
         │  - Location         │         │  - Regulatory checks│
         │  - Temporal binding │         │  - Minting approval │
         │  - Verification     │         │  - Request workflow │
         │  - Custody          │         └─────────────────────┘
         │  - Lineage          │
         └─────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
┌─────────────────┐   ┌─────────────────┐
│    Validators   │   │    Validators   │
│  OGMP2, ISO,    │   │  EPA, CDM,      │
│  CORSIA         │   │  etc.           │
└─────────────────┘   └─────────────────┘
```

## Project Structure

```
lmcx-carbon-credit/
├── contracts/
│   ├── LMCXCarbonCredit.sol           # Main ERC1155 token
│   ├── ComplianceManager.sol           # Regulatory orchestration
│   ├── governance/
│   │   └── SMARTDataRegistry.sol       # SMART Protocol compliance
│   ├── insurance/
│   │   └── InsuranceManager.sol        # Insurance policies & claims
│   ├── oracle/
│   │   └── DMRVOracle.sol              # Enovate.ai dMRV integration
│   ├── ratings/
│   │   └── RatingAgencyRegistry.sol    # Rating agency management
│   └── validators/
│       ├── OGMP2Validator.sol
│       ├── ISO14065Verifier.sol
│       ├── CORSIACompliance.sol
│       ├── EPASubpartWValidator.sol
│       └── CDMAM0023Validator.sol
├── docs/
│   └── DEPLOYMENT.md
├── scripts/
│   └── deploy.js
└── README.md
```

## Contracts Overview

| Contract | Purpose |
|----------|---------|
| **LMCXCarbonCredit** | ERC1155 multi-token with comprehensive integrations |
| **ComplianceManager** | Orchestrates regulatory checks and minting approval |
| **InsuranceManager** | Manages insurance policies, premiums, and claims |
| **RatingAgencyRegistry** | Handles rating agency registration and credit ratings |
| **DMRVOracle** | Ingests real-time monitoring data from Enovate.ai |
| **SMARTDataRegistry** | Enforces SMART Protocol data governance |

## SMART Protocol Implementation

The system implements all SMART Protocol requirements:

| Requirement | Implementation |
|-------------|----------------|
| **Physical Location** | `registerLocation()` - Coordinates, country, site ID |
| **Temporal Binding** | `bindTemporalPeriod()` - Start/end timestamps, period type |
| **Verification** | `recordVerification()` - Multi-party with conflict checks |
| **Event Sequencing** | `recordGovernanceEvent()` - Chained event hashes |
| **Restatements** | `submitRestatement()` - Justified corrections with approval |
| **Aggregation** | `setAggregationParams()` - Persisted assumptions/constants |
| **Data Custody** | `assignCustody()` - Clear responsibility assignment |
| **Lineage** | `recordLineage()` - Parent/child relationships |

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

### Insurance Operations

```solidity
// Calculate premium
uint256 premium = insuranceManager.calculatePremium(
    tokenId,
    creditsToInsure,
    coverageAmount,
    durationDays,
    CoverageType.COMPREHENSIVE
);

// Purchase policy
insuranceManager.purchasePolicy{value: premium}(
    providerId,
    tokenId,
    creditsToInsure,
    coverageAmount,
    durationDays,
    CoverageType.COMPREHENSIVE,
    termsHash
);

// Submit claim if needed
insuranceManager.submitClaim(policyId, claimAmount, reason, evidenceHash);
```

### Rating Operations

```solidity
// Issue rating (as registered agency)
ratingRegistry.issueRating(
    tokenId,
    8500,  // Score (AA+ grade)
    365,   // Valid for 1 year
    "Strong project fundamentals with verified methodology",
    reportHash,
    RatingBreakdown({
        projectQuality: 8800,
        methodology: 8500,
        permanence: 8200,
        additionality: 8600,
        verification: 8700,
        governance: 8400
    })
);

// Check rating
(uint256 score, string memory grade, uint256 count) = token.getRating(tokenId);
bool investmentGrade = token.isInvestmentGrade(tokenId);
```

### Querying Comprehensive Token Info

```solidity
(
    CreditMetadata memory metadata,
    InsuranceStatus memory insurance,
    RatingInfo memory rating,
    DMRVStatus memory dmrv,
    SMARTCompliance memory smart,
    uint256 supply
) = token.getComprehensiveTokenInfo(tokenId);
```

## Roles

| Role | Permissions |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | System administration, role management |
| `COMPLIANCE_MANAGER_ROLE` | Mint tokens, update SMART compliance |
| `INSURANCE_MANAGER_ROLE` | Update insurance status |
| `RATING_AGENCY_ROLE` | Update ratings |
| `DMRV_ORACLE_ROLE` | Update dMRV monitoring data |
| `ISSUER_ROLE` | Submit minting requests |
| `ADMIN_ROLE` | Approve/reject minting |

## Compiler Settings

```json
{
  "solidity": {
    "version": "0.8.19",
    "settings": {
      "optimizer": {
        "enabled": true,
        "runs": 200
      }
    }
  }
}
```

## Security Considerations

- Role-based access control for all privileged operations
- Reentrancy protection on financial operations
- Pausable functionality for emergency stops
- Conflict of interest checks for verifications
- Audit trail for all rating and compliance changes
- Data lineage verification

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contact

Last Mile Production, LLC

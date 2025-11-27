# Security Policy

## Overview

The LMCX Carbon Credit system handles tokenized carbon credits with integrated governance, verification, multi-oracle data feeds, vintage lifecycle tracking, and optional insurance/ratings. Security is critical given the financial nature of these assets.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| < 1.0   | No        |

## Reporting a Vulnerability

**DO NOT** create a public GitHub issue for security vulnerabilities.

### How to Report

- **Email**: security@lmcx.global
- **Subject Line**: [SECURITY] LMCX Carbon Credit - Brief Description
- **Include**:
  - Description of the vulnerability
  - Steps to reproduce
  - Potential impact assessment
  - Any suggested fixes (optional)

### What to Expect

| Timeframe | Action |
|-----------|--------|
| 24 hours | Acknowledgment of your report |
| 72 hours | Initial assessment and severity classification |
| 7 days | Detailed response with remediation plan |
| 30 days | Resolution target for critical issues |

## Severity Classifications

| Level | Description | Response Time |
|-------|-------------|---------------|
| Critical | Fund theft, token manipulation, access control bypass | Immediate |
| High | Data corruption, denial of service, privilege escalation | 24-48 hours |
| Medium | Information disclosure, minor access issues | 7 days |
| Low | Best practice violations, minor bugs | 30 days |

## Scope

### In Scope

- All smart contracts in the repository
- Core contracts:
  - LMCXCarbonCredit.sol - Main token contract
  - GovernanceController.sol - DAO governance
  - VerificationRegistry.sol - Cryptographic proof chains
  - OracleAggregator.sol - Multi-oracle aggregation
  - VintageTracker.sol - Credit lifecycle tracking
  - ComplianceManager.sol - Regulatory orchestration
  - InsuranceManager.sol - Optional insurance
  - RatingAgencyRegistry.sol - Optional ratings
  - DMRVOracle.sol - dMRV data ingestion
  - All compliance validators (ISO14064, OGMP2, EPA, CDM)
- Access control vulnerabilities
- Reentrancy attacks
- Integer overflow/underflow
- Logic errors in compliance checks
- Oracle manipulation
- Insurance/rating calculation errors
- Governance proposal manipulation
- Verification proof forgery
- Vintage tracking manipulation
- Front-running attacks

### Out of Scope

- Third-party dependencies (report to respective maintainers)
- Issues in test files only
- Documentation errors
- Social engineering attacks
- Attacks requiring compromised private keys

## Smart Contract Security Considerations

### Critical Components

| Contract | Risk Level | Description |
|----------|------------|-------------|
| LMCXCarbonCredit.sol | High | Core token with minting authority |
| GovernanceController.sol | Critical | Controls system-wide changes |
| VerificationRegistry.sol | High | Cryptographic proof integrity |
| OracleAggregator.sol | Critical | Multi-oracle data aggregation |
| VintageTracker.sol | Medium | Credit lifecycle management |
| ComplianceManager.sol | High | Controls minting approval |
| InsuranceManager.sol | Critical | Handles funds and payouts |
| RatingAgencyRegistry.sol | Medium | Affects insurance pricing |
| DMRVOracle.sol | Medium | External data ingestion |

### Security Features Implemented

#### Governance Security
- **Time-locks**: All governance proposals have configurable delays (1-30 days minimum)
- **Multi-signature**: Critical operations require multiple signatures
- **Guardian Council**: Emergency veto power for malicious proposals
- **Role-based voting**: Tiered voting weights prevent single-party control

#### Oracle Security
- **Multi-oracle requirement**: Minimum 3 independent data sources
- **Anomaly detection**: Automatic detection of outliers and manipulation attempts
- **Circuit breaker**: Automatic pause when anomaly threshold exceeded
- **Weighted median**: Manipulation-resistant aggregation algorithm
- **HSM attestation**: Sensor integrity verification

#### Verification Security
- **Merkle proofs**: Cryptographic verification of data integrity
- **Multi-verifier signatures**: Required attestations from multiple parties
- **Chain of custody**: Immutable tracking of all credit transfers
- **Revocation support**: Ability to revoke compromised verifications

#### Insurance Security (When Enabled)
- **Time-delayed risk scores**: Prevents front-running premium arbitrage
- **Committed capital tracking**: Prevents reserve inflation attacks
- **Reentrancy protection**: All financial functions protected

#### Vintage Tracking Security
- **No cooling-off period**: Credits immediately transferable (design decision)
- **Gradual discount curve**: 0%, 2%, 5%, 10%, 20% over 10 years
- **Geofencing**: Jurisdiction-specific transfer restrictions
- **Provenance tracking**: Immutable history of all state changes

### Known Attack Vectors We Monitor

| Attack Vector | Mitigation |
|---------------|------------|
| Reentrancy | All financial functions use ReentrancyGuard |
| Access Control | Role-based permissions via OpenZeppelin |
| Oracle Manipulation | Multi-oracle with anomaly detection and circuit breaker |
| Front-running | Time-delayed risk scores, governance timelocks |
| Integer Issues | Solidity 0.8.x built-in overflow protection |
| Governance Attacks | Time-locks, multi-sig, guardian veto |
| Merkle Proof Forgery | Standard OpenZeppelin MerkleProof library |
| Vintage Manipulation | Lifecycle state machine with restricted transitions |

## Security Best Practices for Users

### For Contract Administrators

- Use hardware wallets for admin keys
- Implement multisig for critical operations
- Monitor contract events continuously
- Maintain separate keys for different roles
- Review all governance proposals carefully before voting

### For Governance Participants

- Verify proposal targets and calldata before voting
- Allow sufficient time for community review
- Use guardian veto for obviously malicious proposals
- Monitor for unusual voting patterns

### For Oracle Operators

- Secure oracle submission keys
- Implement rate limiting on submissions
- Monitor for anomalous data patterns
- Maintain HSM attestations for sensors

### For Verifiers

- Protect verification signing keys
- Implement internal review before signing
- Monitor for unauthorized signature attempts
- Maintain reputation by accurate verifications

### For Rating Agencies (When Enabled)

- Secure rating submission keys
- Implement internal controls before submitting ratings
- Monitor for unauthorized rating changes

### For Insurance Providers (When Enabled)

- Maintain adequate capital reserves
- Implement fraud detection for claims
- Secure payout addresses
- Monitor committed capital vs available reserves

### For Enovate.ai Node Operators

- Secure sensor data transmission
- Implement data validation before submission
- Monitor for anomalous readings
- Maintain sensor calibration records

## Patched Vulnerabilities

### November 2024

1. **Reserve Inflation via Buy-Cancel Loop (Critical)**
   - Issue: cancelPolicy() paid refunds without decrementing capitalReserve
   - Fix: Added proper reserve decrement and committed capital tracking
   - Status: Patched

2. **Front-Running Insurance Purchase via Spot Risk Score (High)**
   - Issue: updateRiskScore() took effect immediately, enabling premium arbitrage
   - Fix: Implemented time-delayed risk score updates (1 hour delay)
   - Status: Patched

## Audit Status

| Audit | Status | Date | Auditor |
|-------|--------|------|---------|
| Initial Security Review | Pending | TBD | TBD |
| Formal Audit | Pending | TBD | TBD |

**Note**: This codebase has NOT been formally audited. Use at your own risk until audit completion.

## Bug Bounty Program

We are considering a bug bounty program. Details will be announced here when available.

### Potential Rewards (Subject to Change)

| Severity | Reward Range |
|----------|--------------|
| Critical | TBD |
| High | TBD |
| Medium | TBD |
| Low | TBD |

## Disclosure Policy

- We follow responsible disclosure practices
- Researchers will be credited (unless anonymity requested)
- We will not pursue legal action against good-faith researchers
- Please allow reasonable time for fixes before public disclosure

## Security Contact

- **Primary**: security@lmcx.global
- **Backup**: zach@lastmile-tx.com

## Changelog

- 2025-11-27: Updated security policy for new governance, verification, oracle, and vintage contracts
- 2025-11-27: Added documentation for patched vulnerabilities
- 2025-11-24: Initial security policy created

Thank you for helping keep LMCX Carbon Credit secure.

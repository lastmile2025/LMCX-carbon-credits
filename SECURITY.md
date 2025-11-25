# Security Policy

Overview
The LMCX Carbon Credit system handles tokenized carbon credits with integrated insurance, ratings, and real-time monitoring. Security is critical given the financial nature of these assets.
Supported Versions
VersionSupported1.0.x:white_check_mark:< 1.0:x:
Reporting a Vulnerability
DO NOT create a public GitHub issue for security vulnerabilities.
How to Report

Email: security@lastmileproduction.com
Subject Line: [SECURITY] LMCX Carbon Credit - Brief Description
Include:

Description of the vulnerability
Steps to reproduce
Potential impact assessment
Any suggested fixes (optional)



What to Expect
TimeframeAction24 hoursAcknowledgment of your report72 hoursInitial assessment and severity classification7 daysDetailed response with remediation plan30 daysResolution target for critical issues
Severity Classifications
LevelDescriptionResponse TimeCriticalFund theft, token manipulation, access control bypassImmediateHighData corruption, denial of service, privilege escalation24-48 hoursMediumInformation disclosure, minor access issues7 daysLowBest practice violations, minor bugs30 days
Scope
In Scope

All smart contracts in /contracts/
Deployment scripts in /scripts/
Access control vulnerabilities
Reentrancy attacks
Integer overflow/underflow
Logic errors in compliance checks
Oracle manipulation
Insurance/rating calculation errors
SMART Protocol data integrity issues

Out of Scope

Third-party dependencies (report to respective maintainers)
Issues in test files only
Documentation errors
Social engineering attacks
Attacks requiring compromised private keys

Smart Contract Security Considerations
Critical Components
ComponentRisk LevelDescriptionLMCXCarbonCredit.solHighCore token with minting authorityComplianceManager.solHighControls minting approvalInsuranceManager.solCriticalHandles funds and payoutsRatingAgencyRegistry.solMediumAffects insurance pricingDMRVOracle.solMediumExternal data ingestionSMARTDataRegistry.solMediumData integrity controls
Known Attack Vectors We Monitor

Reentrancy - All financial functions use ReentrancyGuard
Access Control - Role-based permissions via OpenZeppelin
Oracle Manipulation - Validator role restrictions on data submission
Front-running - Considered in compliance check design
Integer Issues - Solidity 0.8.x built-in overflow protection

Security Best Practices for Users
For Contract Administrators

Use hardware wallets for admin keys
Implement multisig for critical operations
Monitor contract events continuously
Maintain separate keys for different roles

For Rating Agencies

Secure your rating submission keys
Implement internal controls before submitting ratings
Monitor for unauthorized rating changes

For Insurance Providers

Maintain adequate capital reserves
Implement fraud detection for claims
Secure payout addresses

For Enovate.ai Node Operators

Secure sensor data transmission
Implement data validation before submission
Monitor for anomalous readings

Audit Status
AuditStatusDateAuditorInitial Security ReviewPendingTBDTBDFormal AuditPendingTBDTBD
Note: This codebase has NOT been formally audited. Use at your own risk until audit completion.
Bug Bounty Program
We are considering a bug bounty program. Details will be announced here when available.
Potential Rewards (Subject to Change)
SeverityReward Range: TBD
Disclosure Policy

We follow responsible disclosure practices
Researchers will be credited (unless anonymity requested)
We will not pursue legal action against good-faith researchers
Please allow reasonable time for fixes before public disclosure

Security Contact

Primary: security@lmcx.global
Backup: zach@lastmile-tx.com

Changelog
2025-11-24 Initial security policy created

Thank you for helping keep LMCX Carbon Credit secure.

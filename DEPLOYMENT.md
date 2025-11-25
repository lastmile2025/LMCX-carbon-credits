# Deployment Guide (ERC1155 Version)

This guide covers deploying the LMCX Carbon Credit ERC1155 system to various EVM-compatible blockchains.

## Key Differences from ERC20

The ERC1155 version requires:
- **Base URI** parameter in constructor for metadata
- New minting interface with `methodology` parameter
- Different balance querying (by tokenId instead of just address)

## Prerequisites

- Solidity compiler ^0.8.19
- Node.js v16+ (for Hardhat deployment)
- Funded wallet for gas fees
- RPC endpoint for target network

## Compiler Settings

**Critical:** The optimizer must be enabled to avoid "stack too deep" errors.

```json
{
  "solidity": {
    "version": "0.8.19",
    "settings": {
      "optimizer": {
        "enabled": true,
        "runs": 200
      },
      "evmVersion": "london"
    }
  }
}
```

## Deployment Order

Contracts must be deployed in this specific order due to dependencies:

### Step 1: Deploy Token Contract (ERC1155)

```
LMCXCarbonCredit.sol
```

**Constructor argument:**
- `baseURI_`: Base URI for token metadata (e.g., `"https://api.lmcx.io/metadata/"`)

The token URI for each token ID will be: `{baseURI}{tokenId}`

**Save the deployed address as:** `TOKEN_ADDRESS`

### Step 2: Deploy Validator Contracts

Deploy all five validators (order among these doesn't matter):

```
1. OGMP2Validator.sol
2. ISO14065Verifier.sol
3. CORSIACompliance.sol
4. EPASubpartWValidator.sol
5. CDMAM0023Validator.sol
```

No constructor arguments needed for any validator.

**Save addresses as:**
- `OGMP2_ADDRESS`
- `ISO14065_ADDRESS`
- `CORSIA_ADDRESS`
- `EPA_ADDRESS`
- `CDM_ADDRESS`

### Step 3: Deploy ComplianceManager

```
ComplianceManager.sol
```

**Constructor arguments (in order):**
1. `_tokenContract`: TOKEN_ADDRESS
2. `_ogmpValidator`: OGMP2_ADDRESS
3. `_isoVerifier`: ISO14065_ADDRESS
4. `_corsiaCompliance`: CORSIA_ADDRESS
5. `_epaSubpartWValidator`: EPA_ADDRESS
6. `_cdmAM0023Validator`: CDM_ADDRESS

**Save address as:** `COMPLIANCE_MANAGER_ADDRESS`

### Step 4: Configure Permissions

On the LMCXCarbonCredit contract, call:

```solidity
setComplianceManager(COMPLIANCE_MANAGER_ADDRESS)
```

This grants `COMPLIANCE_MANAGER_ROLE` to the ComplianceManager contract.

## Kaleido Deployment

For Kaleido blockchain platform:

### Compiler Settings in Kaleido UI

1. **Compiler Version:** 0.8.19 (or "Use version specified in source")
2. **EVM Version:** spuriousDragon (or as configured for your network)
3. **Optimization:** ENABLED
4. **Runs:** 200

### Token Contract Deployment

When deploying LMCXCarbonCredit in Kaleido:
1. Upload the contract file
2. Enter the constructor argument:
   - `baseURI_`: `"https://your-api.com/metadata/"` (or leave as empty string `""` to set later)

### If Using Standalone Contracts

If your Kaleido environment has issues with OpenZeppelin imports, you'll need standalone versions with embedded OpenZeppelin code.

## Verification Checklist

After deployment, verify each contract:

### Token Contract (ERC1155)
```solidity
// Check basic info
name()   // "LMCX Carbon Credit"
symbol() // "LMCXCC"

// Check deployer has admin role
hasRole(DEFAULT_ADMIN_ROLE, YOUR_ADDRESS) // Should return true

// Check total credit types (should be 0 initially)
getTotalCreditTypes() // 0
```

### Validator Contracts
```solidity
// Each validator should return your address as owner
owner() // Should return deployer address
```

### ComplianceManager
```solidity
// Check all validator addresses are set correctly
tokenContract()           // Should return TOKEN_ADDRESS
ogmpValidator()           // Should return OGMP2_ADDRESS
isoVerifier()             // Should return ISO14065_ADDRESS
corsiaCompliance()        // Should return CORSIA_ADDRESS
epaSubpartWValidator()    // Should return EPA_ADDRESS
cdmAM0023Validator()      // Should return CDM_ADDRESS

// Check roles
hasRole(ADMIN_ROLE, YOUR_ADDRESS)  // Should return true
hasRole(ISSUER_ROLE, YOUR_ADDRESS) // Should return true
```

### Token-ComplianceManager Integration
```solidity
// On token contract
hasRole(COMPLIANCE_MANAGER_ROLE, COMPLIANCE_MANAGER_ADDRESS) // Should return true
```

## Deployed Addresses Template

After deployment, record your addresses:

```
Network: ________________
Date: ________________
Token Standard: ERC1155

Contracts:
- LMCXCarbonCredit:      0x________________
- OGMP2Validator:        0x________________
- ISO14065Verifier:      0x________________
- CORSIACompliance:      0x________________
- EPASubpartWValidator:  0x________________
- CDMAM0023Validator:    0x________________
- ComplianceManager:     0x________________

Base URI: ________________
Deployer Address: 0x________________
```

## Post-Deployment Setup

### 1. Set Metadata URI (if not set during deployment)

```solidity
token.setURI("https://your-api.com/metadata/");
```

### 2. Set Up Project Compliance Data

For each project that will issue credits, register compliance status on each validator:

```solidity
// On OGMP2Validator
ogmpValidator.setCompliance(projectId, true, evidenceHash);

// On ISO14065Verifier
iso14065Verifier.setVerification(
    projectId,
    verificationBodyAddress,
    expirationTimestamp,
    certificateHash,
    accreditationId
);

// On CORSIACompliance
corsiaCompliance.setEligibility(
    projectId,
    true,
    firstVintageYear,
    lastVintageYear,
    programId,
    evidenceHash
);

// On EPASubpartWValidator
epaValidator.setCompliance(projectId, true, ghgrpReportId, evidenceHash);

// On CDMAM0023Validator
cdmValidator.setCompliance(
    projectId,
    true,
    creditingStartYear,
    creditingEndYear,
    cdmProjectNumber,
    pddHash
);
```

### 3. Grant Issuer Role (if needed)

To allow other addresses to submit minting requests:

```solidity
// On ComplianceManager
grantRole(ISSUER_ROLE, newIssuerAddress);
```

## Metadata API

The ERC1155 token expects a metadata API that returns JSON for each token ID:

**URL Pattern:** `{baseURI}{tokenId}`

**Example Response:**
```json
{
  "name": "LMCX Carbon Credit - Project ABC 2024",
  "description": "Verified carbon credit from Project ABC, vintage 2024",
  "image": "https://your-api.com/images/credit.png",
  "attributes": [
    {
      "trait_type": "Project ID",
      "value": "0x1234..."
    },
    {
      "trait_type": "Vintage Year",
      "value": 2024
    },
    {
      "trait_type": "Methodology",
      "value": "CDM-AM0023"
    },
    {
      "trait_type": "Unit",
      "value": "tCO2e"
    }
  ]
}
```

## Troubleshooting

### "Stack too deep" Error
- Enable optimizer with at least 200 runs
- Use standalone contract versions if needed

### "Source not found" Error (OpenZeppelin)
- Use standalone contract versions with embedded OpenZeppelin code
- Or configure your environment to resolve npm dependencies

### Transaction Reverts on Minting
- Check all compliance checks pass: `isFullyCompliant(requestId)`
- Verify ComplianceManager has `COMPLIANCE_MANAGER_ROLE` on token
- Ensure methodology parameter is provided

### "URI query for nonexistent token" Error
- The token ID hasn't been minted yet
- Minting creates the token type automatically

### Gas Estimation Fails
- Check contract addresses in ComplianceManager are correct
- Verify all constructor arguments were provided correctly
- For token contract, ensure baseURI was provided

## ERC1155 Specific Operations

### Checking Balances

```solidity
// By token ID
uint256 balance = token.balanceOf(account, tokenId);

// By project and vintage
uint256 balance = token.balanceOfByProject(account, projectId, vintageYear);
```

### Batch Operations

```solidity
// Batch balance check
uint256[] memory balances = token.balanceOfBatch(accounts, tokenIds);

// Batch transfer
token.safeBatchTransferFrom(from, to, tokenIds, amounts, "");
```

### Retiring Credits

```solidity
token.retireCredits(tokenId, amount, "Retirement reason", "Beneficiary name");
```

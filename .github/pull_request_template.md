## Description

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

<!-- Mark the appropriate option with an "x" -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Security fix
- [ ] Dependency update
- [ ] CI/CD change

## Related Issues

<!-- Link any related issues using "Fixes #123" or "Relates to #123" -->

Fixes #

## Smart Contract Changes

<!-- If this PR modifies smart contracts, complete this section -->

### Contracts Modified

- [ ] LMCXCarbonCredit.sol
- [ ] GovernanceController.sol
- [ ] ComplianceManager.sol
- [ ] OracleAggregator.sol
- [ ] VintageTracker.sol
- [ ] InsuranceManager.sol
- [ ] Other: _________________

### Security Considerations

<!-- Describe any security implications of these changes -->

- [ ] Access control changes reviewed
- [ ] Reentrancy protection verified
- [ ] Input validation added/updated
- [ ] No new external calls without checks
- [ ] Gas optimization reviewed

### Gas Impact

<!-- Estimate gas impact if applicable -->

- [ ] No significant gas impact
- [ ] Gas optimization (reduces gas)
- [ ] Increases gas usage (explain why)

## Testing

<!-- Describe how you tested these changes -->

- [ ] All existing tests pass (`npx hardhat test`)
- [ ] New tests added for new functionality
- [ ] Manual testing performed
- [ ] Edge cases tested

### Test Results

```
<!-- Paste test output here -->
npx hardhat test
```

## Deployment Considerations

<!-- Note any deployment considerations -->

- [ ] No deployment changes needed
- [ ] Requires contract upgrade
- [ ] Requires migration script
- [ ] Requires configuration change

## Checklist

<!-- Ensure all items are completed before requesting review -->

- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or my feature works
- [ ] New and existing unit tests pass locally with my changes
- [ ] Any dependent changes have been merged and published

## Security Checklist

<!-- For smart contract changes -->

- [ ] No hardcoded addresses or private keys
- [ ] No use of `tx.origin` for authorization
- [ ] Proper use of `require` statements for validation
- [ ] Events emitted for state changes
- [ ] No unbounded loops
- [ ] Integer overflow/underflow handled (Solidity 0.8+)
- [ ] Reentrancy guards applied where needed

## Screenshots (if applicable)

<!-- Add screenshots to help explain your changes -->

## Additional Notes

<!-- Add any additional notes for reviewers -->

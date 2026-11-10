# Security

## Reporting a vulnerability

Email security@altofoundation.org with a description of the issue, the affected contracts and steps to reproduce. Do not open a public issue or pull request for a vulnerability.

## Audits and bug bounty

Audit reports, the commit each review covered, the bug bounty terms and the list of in-scope deployed contracts are published in [security-review-engagements](https://github.com/altomoney/security-review-engagements). The reviewed commits are tagged in this repository as `audit/<year>-<month>-<provider>`.

## Audit status of contracts

The audit table in that repository lists the contracts each review covered. Contracts whose NatSpec carries `@custom:audit Pending` have not been reviewed yet; they are not deployed on mainnet and are outside the bug bounty scope.

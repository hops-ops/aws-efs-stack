# Repository Guidelines

Start by reading `README.md` to understand this stack.

Avoid Upbound-hosted configuration packages - they have paid-account restrictions.
Favor `crossplane-contrib` packages.

Target Crossplane 2+: don't set `deletionPolicy` on managed resources; use
`managementPolicies` and defaults.

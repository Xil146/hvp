# Security policy

## Supported versions

HVP has not released V1. Security fixes will target the latest supported release once releases begin.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository rather than opening a public issue. Include the affected version/commit, reproduction steps, impact, and any relevant sample metadata. Do not upload copyrighted media or personal file paths; create a minimal synthetic fixture when possible.

If private reporting is not enabled yet, contact the repository owner privately and ask that it be enabled before sharing details.

## Security posture

HVP parses untrusted media, subtitle, and metadata inputs through native libraries. Releases therefore pin native dependencies, record their provenance and checksums, and require targeted update and regression testing. V1 is local-only and will not include telemetry, accounts, or network features.

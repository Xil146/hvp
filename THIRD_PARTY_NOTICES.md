# Third-party notices

HVP source is MIT licensed. A native-bearing build is not approved or shipped by
this repository yet. Consequently this file is a release template, not a claim
that HVP currently distributes any native dependency.

Before any native-bearing release, the exact candidate must replace this
template with a notice inventory generated from its reviewed native candidate
manifest. That inventory must identify each shipped binary, owner/source,
declared license, engineering license conclusion and evidence, and the location
of the complete applicable license text in `licenses/`. The release gate rejects
missing candidate evidence; it does not substitute for legal review.

The candidate must also ship its corresponding source archive inputs, patches,
build instructions, SHA-256 values, and SPDX 2.3 SBOM. FFmpeg source and notices
must be visibly identified. Distribution terms must not prohibit LGPL reverse
engineering for debugging modifications.

See `eng/native/templates/` and `eng/native/scripts/Test-NativeCandidateConsistency.ps1`.

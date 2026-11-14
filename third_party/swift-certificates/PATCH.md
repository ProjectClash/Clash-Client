# swift-certificates 1.9.0, patched

This directory is a source snapshot of [apple/swift-certificates](https://github.com/apple/swift-certificates)
at tag `1.9.0` (commit `86eca758281a7187191fcb4e0ae5a87dbd876095`), the version the client
pinned before it carried its own copy. `LICENSE.txt` and `NOTICE.txt` are upstream's, unchanged.
Only `Package.swift`, `LICENSE.txt`, `NOTICE.txt` and `Sources/` are carried; upstream's tests,
benchmarks, CMake and CI files are not.

Two changes, nothing else:

1. `Sources/X509/OCSP/OCSPPolicy.swift`: the three `Date` comparisons in
   `OCSPResponseData.verifyTime` and `OCSPSingleResponse.verifyTime` are written
   `a.timeIntervalSince(b) <= 0` / `>= 0` instead of `a <= b` / `a >= b`, operands in the same
   order (Foundation's own inline implementation of the operators is this comparison).

   Why: Xcode 27.2's SDK declares Foundation's `Date.<=` and `Date.>=`
   `@backDeployed(before: iOS 27.2, macOS 27.2, ...)`. Every call compiled against it becomes a
   thunk that, on a system reporting 27.2 or later, calls Foundation's own symbol, linked weakly.
   The iOS 27.2 betas 24B5084k and 24B5089g report 27.2 and lack the symbol, so the weak import
   resolves to null: the client's own uses crashed its iOS builds 158-160 at every launch. The
   client's code no longer calls the operators; these three were the last references in the
   App and the tunnel extensions, kept alive by OCSP verification the client never runs. With
   them gone the two operators are not imported at all, and scripts/check_weak_imports.py
   stops any binary that imports them again.

   Upstream still writes `<=` / `>=` here at `1.21.1`, its latest tag when this was taken
   (`Sources/X509/OCSP/OCSPPolicy.swift` lines 650, 682 and 689), so no version of the package
   can be pinned instead.

2. `Package.swift`: the two test targets (`X509Tests`, `CertificateInternalsTests`) are removed,
   because their sources are not carried. The products, the two library targets, their settings
   and the dependencies on swift-crypto and swift-asn1 are upstream's.

Each changed file says so in a comment at the change (Apache-2.0 section 4(b)).

To move to another upstream version: take its `Package.swift`, `LICENSE.txt`, `NOTICE.txt` and
`Sources/`, reapply both changes if upstream still needs them, and update the version the
client's acknowledgements credit (the swift-certificates row of `ThirdPartyLicenses.json`).

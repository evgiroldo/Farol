# 0014. Distribution, build and quality tooling

- Status: Accepted
- Date: 2026-11-14

## Decision

### Distribution
- Develop unsigned; join the Apple Developer Program (USD 99/year) and sign with Developer ID plus notarization **when M1 is ready to publish**. Never ship unsigned binaries, which train users to bypass Gatekeeper.
- Channels: GitHub Releases (with SHA-256), Homebrew (own tap first, official cask later), and build from source.
- Official builds run on **GitHub Actions** from public commits, with signed **build provenance attestations** (`gh attestation verify`). Signing credentials are stored as encrypted repository secrets.

### Tooling and quality
- Native Xcode project with **synchronized folders** (minimal project-file churn) — no XcodeGen or Tuist.
- **Zero third-party dependencies**; only Apple frameworks.
- **Swift Testing** for `FarolCore`; **swift-format** for style; both run on every pull request.
- **Resource budgets enforced in CI** (initial values, to be tuned after measuring): main window updating every second < 1% of a core and < 60 MB; menu bar only < 0.3% of a core and < 30 MB (the sentinel target in ADR 0011 is stricter).

## Consequences
- The maintainer needs Xcode and the GitHub CLI installed locally.
- CI on macOS runners must measure resource usage reliably; budgets may need tolerance bands.

# Security Policy

Farol can see every process on a Mac and, with the user's confirmation, will be able to pause the user's own processes. Security is a core requirement, not a feature.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Include:

- the Farol version and macOS version,
- what an attacker could do, and under which conditions,
- steps to reproduce, if you have them.

You will receive an acknowledgement as soon as possible. Fixes for confirmed issues are released with a public advisory crediting the reporter, unless you prefer to stay anonymous.

## Security model (summary)

- **No root.** Farol and its menu bar sentinel run as the logged-in user. There is no privileged helper.
- **No network.** Farol never opens a network connection. Updates come through Homebrew or GitHub Releases. Anonymous reports are reviewed and sent by the user through their own browser (ADR 0036).
- **Least privilege.** Hardened Runtime is enabled; entitlements are limited to what is strictly needed.
- **Process control is opt-in.** Pausing an app requires explicit confirmation for every test, applies only to the user's own processes and only to executables inside the app's own bundle, lasts 3 seconds at a time, never runs while any app is using the microphone, never targets protected processes, and re-verifies each process right before and after acting. A separate watchdog resumes everything at once if Farol crashes; if both crash, Farol offers to resume frozen apps the next time it opens. macOS offers no race-free process handle, so a very small window between verification and signal remains (ADRs 0023, 0034).
- **Private APIs are read-only and isolated.** Sensors that rely on undocumented macOS interfaces live in a separate module and fail closed ("unavailable").
- **No third-party dependencies.** Only Apple frameworks are used.
- **Verifiable builds.** Official releases will be built by GitHub Actions from public commits and ship with signed build provenance (`gh attestation verify`).

## What the history protection does and does not cover

- The history lives in `~/Library/Application Support/Farol/`, with permissions that **keep other user accounts out** (directory `0700`, files `0600`). It is excluded from Time Machine backups.
- Permissions do **not** protect it from other software running under **your own account**: any non-sandboxed app you run can read or modify it. Farol therefore treats the history file as untrusted input — invalid rows are skipped, reads are bounded, the schema is not trusted, and nothing read from the file is ever used to act on a process.
- **Delete history** removes the data from Farol's files (database, WAL and shared-memory files). It cannot remove copies in APFS snapshots or in backups made before you installed Farol.

The full reasoning behind each item is documented in [`docs/adr/`](docs/adr/).

# Security Policy

Farol can see every process on a Mac and, with the user's confirmation, can pause the user's own processes. Security is a core requirement, not a feature.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Include:

- the Farol version and macOS version,
- what an attacker could do, and under which conditions,
- steps to reproduce, if you have them.

You will receive an acknowledgement as soon as possible. Fixes for confirmed issues are released with a public advisory crediting the reporter, unless you prefer to stay anonymous.

## Security model (summary)

- **No root.** Farol and its menu bar sentinel run as the logged-in user. There is no privileged helper.
- **No network.** Farol never opens a network connection. Updates come through Homebrew or GitHub Releases.
- **Least privilege.** Hardened Runtime is enabled; entitlements are limited to what is strictly needed.
- **Process control is opt-in.** Pausing a process requires explicit confirmation for every proof, applies only to the user's own processes, lasts at most 3 seconds, never targets protected processes, and is always resumed by a watchdog.
- **Private APIs are read-only and isolated.** Sensors that rely on undocumented macOS interfaces live in a separate module and fail closed ("unavailable").
- **No third-party dependencies.** Only Apple frameworks are used.
- **Verifiable builds.** Official releases are built by GitHub Actions from public commits and ship with signed build provenance (`gh attestation verify`).

The full reasoning behind each item is documented in [`docs/adr/`](docs/adr/).

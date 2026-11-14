# 0009. Zero network access

- Status: Accepted; clarified by ADR 0036
- Date: 2026-11-14

## Context
Monitors that "phone home" (update checks, telemetry, cloud AI) expand the attack surface and require users to trust claims they cannot verify.

## Options
- Zero network; updates via Homebrew and GitHub Releases.
- In-app update checks through Sparkle (EdDSA-signed).

## Decision
**Farol never opens a network connection.**

## Consequences
- "Farol sends nothing" is trivially auditable.
- Users update through Homebrew or by downloading a new release.
- Any future feature needing the network (e.g. iPhone companion) requires a new ADR.

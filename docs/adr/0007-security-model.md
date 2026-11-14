# 0007. Security model: least privilege

- Status: Accepted; cost of `/bin/ps` amended by ADR 0021
- Date: 2026-11-14

## Context
A system monitor sees every process on the machine. Privileged components are prime attack targets.

## Options
- Process termination: own user only, or any process through a root helper (`SMAppService`).
- Isolation: App Sandbox, or Hardened Runtime without sandbox.

## Decision
- **No privileged helper.** Farol can only signal processes owned by the logged-in user.
- **Hardened Runtime, no App Sandbox.** The sandbox blocks reading other processes' information, which a monitor needs. Hardened Runtime blocks code injection and unsigned libraries. Entitlements are limited to what is strictly required.
- CPU time of system daemons is read through Apple's own setuid `/bin/ps` (targeted `-p` queries, measured at ~0 ms each); Farol itself gains no privilege. `top` was rejected: ~13% of a core while streaming.

## Consequences
- Farol cannot kill root processes; it can explain them and, where relevant, identify the user app driving them.
- Not eligible for the Mac App Store (also due to ADR 0008).

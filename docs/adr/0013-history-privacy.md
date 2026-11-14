# 0013. History privacy

- Status: Accepted; amended by ADR 0019
- Date: 2026-11-14

## Context
A per-process history reveals what the user did and when, even if it never leaves the Mac.

## Decision
- Detailed per-process data is recorded **only during incidents**; outside incidents, only aggregates.
- Short, configurable retention.
- Files readable only by the user.
- A "Delete history" button.
- Shared diagnostic reports strip personal data (user names, file paths, window titles).

## Consequences
- Some long-range questions cannot be answered from detailed data; aggregates must be designed to cover experiments (M4).

# 0000. Record architecture decisions

- Status: Accepted
- Date: 2026-11-14

## Context
Farol is open source and built with AI assistance. Contributors (and future maintainers) need to know not only *what* was decided but *why*, and which alternatives were rejected.

## Decision
Every significant architectural decision is recorded as a short Markdown file in `docs/adr/`, numbered sequentially, with: status, date, context, options considered, decision and consequences. Accepted ADRs are never edited in substance; a new ADR supersedes an old one. Only the Status line may change, to point to the amending ADR (ADR 0019).

## Consequences
- Pull requests that change an architectural decision must include a new or superseding ADR.
- The index in [`README.md`](README.md) lists all ADRs.

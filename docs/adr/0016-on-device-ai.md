# 0016. On-device AI for explanations

- Status: Deferred — revisit after M2
- Date: 2026-11-14

## Context
Apple's Foundation Models framework (macOS 26) offers an on-device language model that could phrase diagnoses in natural language without network access.

## Options
- Use it to write explanations, always citing measured evidence.
- Never use it; explanations come from deterministic rules.

## Decision
Deferred. Diagnosis is built first from rules, statistics and proofs. After M2, evaluate whether the model adds enough value to justify its cost, its requirement that Apple Intelligence be enabled, and the risk of non-deterministic wording.

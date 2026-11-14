# 0020. Plain-language positioning

- Status: Accepted (amends the wording of the promise in ADR 0003)
- Date: 2026-11-14

## Context
The first person outside the project to see the repository — a Brazilian Mac user who speaks English — did not understand the tagline "The Mac monitor that finds the real culprit — and proves it": the word *culprit* was unfamiliar, and the sentence did not say *of what*. The audience decided in ADR 0003 includes non-technical users, so this is a product defect, not a translation detail.

## Options
- Tagline: start from the symptom ("Why is your Mac slow? …"), a short direct line, or a list of symptoms.
- Language: English only, a Portuguese summary in the README, or a full Portuguese README.

## Decision
- Tagline (README title line and GitHub description): **"Why is your Mac slow? Farol tells you which app is causing it — and shows the proof."**
- The README starts with what Farol is and the problem it solves, explains how it works in three plain steps with an example, and moves technical detail further down.
- User-facing text avoids jargon and rare words, starts from the symptom the person feels, and explains technical terms on first use. This applies to the app UI and alerts too.
- Documentation stays in English only (ADR 0015 unchanged).

## Consequences
- Every new user-facing text should be checked against a non-technical reader; feedback from real users outranks the team's wording.

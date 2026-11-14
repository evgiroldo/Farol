# 0031. Solve, don't show

- Status: Accepted; amended by ADR 0035
- Date: 2026-11-15
- Amends: 0003 (first screen), 0006 (what the window shows first)

## Context
The maintainer's guiding example: if you open a resource monitor or the Windows Task Manager in front of a non-technical person, they have no idea what to do. Farol exists to remove that gap. A person who feels their Mac is slow or freezing must open Farol, see what is causing it, and fix it — without understanding processes, cores or graphs. It must be self-explanatory and intuitive, the way things on a Mac usually are.

Farol's answers come with different levels of certainty (ADRs 0022–0024): some causes are measured directly, some are only suspected until a cause test confirms them, and some are normal macOS work.

## Decision

### The first screen is the answer and one action
The window opens on **one card for the most important problem**: a plain sentence naming the cause, one line saying why in everyday words, one main button, and a short line under it saying what the button will do and what it will not do. Numbers, graphs and process lists live one level down, under "Details". When there is more than one problem, the others appear as a discreet "2 more things" link below the main card.

### The four card states
| State | Headline example | Main button | Other button |
|---|---|---|---|
| **Measured cause** | "Chrome is slowing down your Mac" | **Fix** ("Resolver") | See details |
| **Suspect** | "Slack may be slowing down your Mac" — "We're not sure yet." | **Pause to confirm** ("Pausar para confirmar") | Not now |
| **Confirming** | "Checking whether it's Slack…" with progress | — | Cancel and resume Slack |
| **Normal macOS work** | "Your Mac is organizing your photos" | Got it | Tell me if it takes long |

- A suspect becomes a measured cause only after the cause test proves it (ADR 0022); the card then turns into a "Fix" card. An inconclusive test says so plainly and suggests what to try next.
- The line under "Pause to confirm" always states the consequence: the app freezes three times for 3 seconds, about how long it takes in total, and that nothing is closed.
- Durations are typical values, never predictions (ADR 0030).

### What "Fix" does for an app
**Restart the app**: Farol asks it to quit the normal way — the app can ask the user to save — and opens it again; browsers restore their tabs. Farol never force-quits without a separate, explicit confirmation. If the app refuses to quit (for example, a save dialog), Farol waits and tells the user what is happening. For causes that are not an app (full disk, heat, low memory), "Fix" becomes a guided step in plain words, never a silent action.

### Using data to make life easier
Farol uses its local history to anticipate problems with plain statistics — for example "at this rate your disk fills up in 12 days" or "every Monday at 9 a.m. Teams slows down your Mac". AI remains optional (ADR 0016). Which predictions enter version 1.0 is decided with the pending design decisions; the scope in ADR 0029 still applies.

### Usability evaluation
Usability is evaluated by the team; there is no formal acceptance test with a non-technical user before version 1.0.

## Consequences
- Every card text is written for a non-technical reader (ADR 0020) in English and Brazilian Portuguese; button labels are verbs, 1–3 words.
- "Restart the app" needs the app to be relaunchable (`NSWorkspace`), and must handle apps that refuse to quit and apps with unsaved documents.
- Detailed views remain for technical users, so the audience decision in ADR 0003 (both, in layers) still holds.

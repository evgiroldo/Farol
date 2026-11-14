# 0024. Alert content and frequency

- Status: Accepted; clarified by ADR 0030
- Date: 2026-11-14
- Amends: 0012 (alerts on by default — still true — now with content and rate rules)

## Context
Alerts are on by default (ADR 0012). The first review pointed out that when an alert fires, only correlation is available — the cause test needs the user and the app (ADR 0022) — and in the prototype correlation ranked an unrelated process first. A wrong accusation in the first alert would destroy trust in a product whose promise is evidence. It was also undecided which process sends alerts and how often.

## Options
- Content: symptom plus directly measured facts, or symptom only.
- Frequency: balanced (2 min, 1 per incident, 3 per day), sensitive (30 s, no daily limit), or critical-only.
- Known normal macOS work: icon only, or an explanatory alert.

## Decision
1. **Alerts state facts, never suspicions.**
   - The *symptom* is always allowed: "Your Mac has been working harder than usual for 5 minutes. Open Farol to find out why."
   - An app is named only for a **directly measured** fact about that app itself: "Chrome has been using 3 full CPU cores for 10 minutes."
   - Correlation-based suspicions ("Slack is slowing down WindowServer") never appear in alerts; they appear only in the app, after or alongside the cause test.
2. **Frequency.** An alert is sent only after **2 minutes** of continuous problem, at most **once per incident** and **3 times per day**. The menu bar icon always reflects the current state, with or without alerts. macOS Focus modes are respected by the system.
3. **Normal macOS work** that the knowledge base recognizes (e.g. Spotlight indexing after an update) sends **no alert**; the icon changes and Farol explains it when opened ("normal, usually ends in about 20 minutes").
4. **The sentinel sends alerts**, as the only always-running process. It asks for notification permission (its bundle shows as "Farol"). Clicking an alert opens the Farol app on that incident. The memory cost of the notifications framework must fit the sentinel budget and is part of the planned re-measurement (ADR 0019).
5. Alert texts follow ADR 0020 (plain language, symptom first) and are localized in English and Brazilian Portuguese.

## Consequences
- Alert rules (thresholds, rate limits, normal-work suppression) are covered by unit tests on the decision logic, separate from the notification API.
- If the notifications framework does not fit the sentinel budget, a new ADR must decide between a separate tiny notifier and icon-only alerts.

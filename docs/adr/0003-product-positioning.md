# 0003. Product positioning: prove causes, for everyone

- Status: Accepted
- Date: 2026-11-14

## Context
Mac resource monitors are a crowded category (Activity Monitor, Stats, iStat Menus, btop, TMOG). Market research in November 2026 showed that "explain why the Mac is slow" (iKnowMyMac, System Sentinel), "rewind history" (Mac Performance Monitor, ProcessSpy) and proactive alerts (System Sentinel, MacThrottle, Alertivity) already exist. No tool was found that:
- **proves** a cause by intervention instead of correlation,
- attributes system-daemon load (`WindowServer`, `mds_stores`…) to the app that triggered it,
- runs statistically sound personal A/B experiments.

Users open a monitor only when the Mac *feels wrong*; graphs alone do not answer their question.

## Decision
Farol's promise: **"The Mac monitor that finds the real culprit — and proves it."**
- Signature capabilities: causal attribution with proof by pause (ADR 0010) and experiments (milestone M4).
- Explanation and history are the foundation, not the differentiator.
- Diagnosis is **symptom-led** (thermal throttling, memory pressure and swap, full disk and I/O saturation, hung apps, post-update maintenance, sleep and battery), backed by a knowledge base of macOS processes ("what is it, is it normal, how long will it last"). "Nothing is wrong, this ends in ~20 min" is a valid diagnosis.
- The first screen is the **verdict** (one sentence, evidence, one action); graphs are one level down.
- The loop is closed: action → verification ("after quitting X, WindowServer dropped 70% — solved").
- Comparison against the Mac's **own baseline**.
- Entry points: menu bar, global shortcut, Spotlight, Siri and Shortcuts (App Intents).
- A privacy-safe, shareable diagnostic report for asking someone for help.
- **Audience: both** non-technical and technical users, in layers — plain verdict on top, raw data underneath.

## Consequences
- Every number carries a provenance label: *measured*, *estimated* or *inferred* (with confidence).
- Farol must stay lighter than the problems it diagnoses (ADR 0011, ADR 0014).

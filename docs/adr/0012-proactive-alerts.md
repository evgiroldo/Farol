# 0012. Proactive alerts on by default

- Status: Accepted; content and frequency rules in ADR 0024
- Date: 2026-11-14

## Context
With the sentinel, Farol can notify users before they notice a problem. Too many notifications erode trust and get disabled.

## Decision
Alerts are **on by default** and can be turned off. They are rare and sent only with high confidence, naming the cause and one action (e.g. "Your Mac is heating up because of X").

## Consequences
- The first launch asks for notification permission.
- Alert thresholds and rate limits are part of the test suite.

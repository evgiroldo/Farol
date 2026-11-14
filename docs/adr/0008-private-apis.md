# 0008. Private APIs, isolated and read-only

- Status: Accepted; amended by ADR 0019
- Date: 2026-11-14

## Context
Power in watts per component and temperature sensors have no public API on macOS. Every monitor that shows them uses undocumented interfaces (e.g. IOReport, SMC/HID sensors).

## Options
1. Public APIs only: stable, but no watts and no temperatures (only `ProcessInfo.thermalState`).
2. Private APIs, isolated in a separate read-only module.

## Decision
Option 2. Private APIs live in a dedicated module inside `FarolCore`, are used read-only, and **fail closed**: if a macOS update breaks them, Farol shows "unavailable" — it never crashes and never invents a value.

## Consequences
- Not eligible for the Mac App Store.
- Each macOS release requires verifying the sensor module.

# 0027. Grouping processes into apps

- Status: Accepted; amended by ADR 0034
- Date: 2026-11-14

## Context
Plain-language verdicts (ADR 0020) and the whole-app pause (ADR 0022) need to know which app each process belongs to: users must read "Chrome", not "Google Chrome Helper (Renderer)". The history stored only the short process name.

## Options
1. Group by **app bundle path**: every process whose executable lives inside `X.app` belongs to X. Public and stable, but fails for apps whose helpers run from system frameworks — notably Safari's web content processes (WebKit) and other Apple apps.
2. Bundle path **plus the "responsible process"** macOS records for each process (used by Activity Monitor), through an undocumented function, isolated and read-only per ADR 0008, falling back to option 1 when unavailable.

## Decision
Option 2.
- First, the responsible process (private, in the isolated sensor module); if unavailable or failing, the **outermost `.app` bundle** in the executable path (`proc_pidpath`).
- The app's display name and icon come from its bundle (`CFBundleDisplayName`, icon), shown with `NSRunningApplication`/`NSWorkspace` where available.
- Processes outside any app (command-line tools) form their own group under their name.
- Results are cached per process identity. The history stores an app key in a small `processes` table instead of repeating names on every row.
- Grouping is never a security decision: protections (ADR 0023) still check each process's path and code signature.

## Consequences
- When the private function breaks after a macOS update, Safari tabs appear separately from Safari until fixed; the UI must still work.

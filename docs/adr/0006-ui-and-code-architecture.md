# 0006. UI and code architecture

- Status: Accepted; amended by ADR 0019
- Date: 2026-11-14

## Context
A monitor redraws constantly; a careless UI makes the monitor itself a top CPU consumer.

## Options
- UI: SwiftUI only, or SwiftUI with targeted AppKit.
- Charts: Swift Charts, custom `Canvas`, or both.
- Code: one target, or a measurement core separated from the UI.

## Decision
- **SwiftUI** for windows, sidebar, settings and menu bar; **AppKit `NSOutlineView`** for the process list (cell reuse, cheap updates of thousands of rows).
- **Custom `Canvas` charts** only — minimal redraw work and an original look. No Swift Charts.
- **`FarolCore`** Swift package does measurement only (no UI); the app only displays. The future iPhone companion and the experiments engine reuse the core.
- **Swift 6** with strict concurrency checking; `@Observable` models.

## Consequences
- Measurements are testable without launching the UI.
- Code that talks to the OS is isolated and easy to audit.

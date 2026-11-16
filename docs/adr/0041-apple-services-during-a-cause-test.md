# 0041. Apple services attributed to an app during a cause test

- Status: Accepted
- Date: 2026-11-16
- Amends: 0034 §3 (what "the whole app" means)

## Context
ADR 0034 §3 pauses only executables inside the app's bundle plus the WebKit helpers that belong to it, and refuses the test if the app's group contains any other executable. The attribution spike v2 (ADR 0040) found that macOS attributes other Apple services to an app that shows web content: `MTLCompilerService` (Metal shader compiler), `SetStoreUpdateService` and `com.apple.audio.SandboxHelper` (*measured*, responsible process = the app in every web test). As written, ADR 0034 would refuse the test for almost every app that shows web content — the most common culprits.

The spike left these services running and paused only the app and its WebKit helpers. WindowServer was still proven in 3 of 3 tests, with 97–98% of its load attributed to the app.

Options considered: leave them running; pause them with the app; refuse the test (ADR 0034 as written).

## Decision
A member of the app's group is **left running, and does not cause a refusal**, when all of these hold:
- it is signed by Apple (`anchor apple`),
- its executable is under `/System/`,
- its responsible process is the app (or a process of the app's group),
- it is not a WebKit helper (those are still paused with the app, ADR 0034 §3).

Any other executable outside the bundle still makes Farol refuse the test. The confirmation's count ("pauses N processes") includes only the processes actually paused.

## Consequences
- Farol never pauses an Apple system service; pausing an audio or graphics service could cause glitches in other parts of the system.
- A load generated directly by one of these services (for example a long shader compilation) is not removed by the pause, so the test reports "unclear" rather than proving it — the safe direction.
- New Apple services may appear in future macOS versions; the rule is by signature and location, not by a list of names.

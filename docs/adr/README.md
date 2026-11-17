# Architecture Decision Records

| # | Decision | Status |
|---|---|---|
| [0000](0000-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0001](0001-original-clean-room-implementation.md) | Original, clean-room implementation | Accepted |
| [0002](0002-name-and-license.md) | Name "Farol" and GPLv3 license | Accepted |
| [0003](0003-product-positioning.md) | Product positioning: prove causes, for everyone | Amended by 0020, 0023, 0031 |
| [0004](0004-platform-and-minimum-os.md) | macOS only, Apple silicon, macOS 26+ | Accepted |
| [0005](0005-milestones.md) | Milestones | Superseded by 0029 |
| [0006](0006-ui-and-code-architecture.md) | UI and code architecture | Amended by 0019, 0031 |
| [0007](0007-security-model.md) | Security model: least privilege | Amended by 0021 |
| [0008](0008-private-apis.md) | Private APIs, isolated and read-only | Amended by 0019 |
| [0009](0009-zero-network.md) | Zero network access | Amended by 0036 |
| [0010](0010-causal-attribution-and-proof-by-pause.md) | Causal attribution: suspects by correlation, proof by pause | Amended by 0019, 0022, 0023 |
| [0011](0011-always-on-menu-bar-sentinel.md) | Always-on sentinel in the menu bar | Amended by 0017, 0019, 0021, 0028, 0030 |
| [0012](0012-proactive-alerts.md) | Proactive alerts on by default | Amended by 0024 |
| [0013](0013-history-privacy.md) | History privacy | Amended by 0019 |
| [0014](0014-distribution-and-tooling.md) | Distribution, build and quality tooling | Amended by 0019, 0030 |
| [0015](0015-documentation-language.md) | English for code and docs; app in English and Portuguese | Accepted |
| [0016](0016-on-device-ai.md) | On-device AI for explanations | Deferred |
| [0017](0017-two-process-model.md) | Two processes: sentinel and app | Amended by 0011, 0025 |
| [0018](0018-identity-history-store-retention.md) | Bundle identifier, history store and retention | Amended by 0019, 0032 |
| [0019](0019-corrections-after-first-review.md) | Corrections after the first independent review | Accepted |
| [0020](0020-plain-language-positioning.md) | Plain-language positioning | Amended by 0003 |
| [0021](0021-watching-system-daemons.md) | Watching system daemons without breaking the idle budget | Amended by 0030, 0032, 0039, 0042, 0043 |
| [0022](0022-cause-test-protocol.md) | Cause test protocol: repeated pause and resume | Amended by 0033 |
| [0023](0023-pause-safety-and-limits-of-proof.md) | Pause safety and the limits of proof | Amended by 0034 |
| [0024](0024-alert-content-and-frequency.md) | Alert content and frequency | Amended by 0030, 0032, 0035 |
| [0025](0025-app-sentinel-communication.md) | App–sentinel communication over XPC | Amended by 0035 |
| [0026](0026-versions-updates-and-lifecycle.md) | Versions, updates and the sentinel lifecycle | Amended by 0035 |
| [0027](0027-grouping-processes-into-apps.md) | Grouping processes into apps | Amended by 0034 |
| [0028](0028-budget-policy.md) | Resource budget policy | Accepted |
| [0029](0029-scope-of-version-1.md) | Scope of version 1.0 | Amended by 0030, 0035, 0036, 0040 |
| [0030](0030-clarifications-after-second-review.md) | Clarifications after the second review | Amended by 0037 |
| [0031](0031-solve-dont-show.md) | Solve, don't show | Amended by 0035 |
| [0032](0032-detection-details.md) | Detection details: suspicion sequence, "normal" work, incident limits | Amended by 0039 |
| [0033](0033-cause-test-statistics.md) | Cause test statistics | Amended by 0040 |
| [0034](0034-pause-safety-details.md) | Pause safety details | Amended by 0041 |
| [0035](0035-results-settings-alerts-and-lifecycle.md) | Test results, settings, alert filters, disk and sentinel lifecycle | Accepted |
| [0036](0036-anonymous-reports-sent-by-the-user.md) | Anonymous reports sent by the user | Accepted |
| [0037](0037-process-sampler-caches.md) | Process sampler caches | Amended by 0043 |
| [0038](0038-platform-scope-reconsidered.md) | Platform scope reconsidered: no Intel, no older macOS (for now) | Accepted |
| [0039](0039-quieter-detection-and-sampling.md) | Quieter detection and slower sampling | Amended by 0042 |
| [0040](0040-cause-test-results-and-scope.md) | Cause test results: WindowServer in 1.0, Spotlight later | Accepted |
| [0041](0041-apple-services-during-a-cause-test.md) | Apple services attributed to an app during a cause test | Accepted |
| [0042](0042-ring-under-suspicion-and-memory-relief.md) | Ring sampled under suspicion; allocator memory returned | Accepted |
| [0043](0043-slower-background-checks.md) | Slower background checks while the Mac is quiet | Accepted |

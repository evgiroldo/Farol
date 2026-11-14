# 0028. Resource budget policy

- Status: Accepted
- Date: 2026-11-14
- Amends: 0011 and 0019 (how the sentinel budgets are set)

## Context
The sentinel budgets (< 0.1% of one core and < 15 MB idle) came from a prototype that had almost none of the real sentinel's parts. Decisions C1–C5 added a SQLite connection, `ps` queries and a 60-second memory ring (ADR 0021), the notifications framework (ADR 0024), an XPC listener (ADR 0025) and a menu. The prototype already used 14.2 MB.

## Options
- Set budgets from a 24-hour measurement of a realistic prototype, or raise them by estimate now.
- Memory over 15 MB: measured value plus margin with a hard ceiling; keep 15 MB and optimize; or no memory budget.
- Idle CPU: keep < 0.1% strict, or relax to 0.2%.
- Machines: the maintainer's Mac plus a second (ideally 8 GB) Mac now, or the maintainer's Mac only for now.

## Decision
1. **Measure before promising.** Build a realistic, throwaway sentinel prototype with all of the parts above and run it for **24 hours** on the maintainer's Mac, logging its own CPU time, `phys_footprint` and wakeups. Budgets are set from that data.
2. **Memory:** budget = measured peak **+ 20%**, never above **25 MB**. If the measurement exceeds 25 MB, a new ADR splits responsibilities (for example, alerts sent by a separate tiny process) instead of raising the ceiling.
3. **Idle CPU stays strict at < 0.1% of one core.** It is the core of the "lighter than the problem it diagnoses" promise, and all measurements so far fit it with margin.
4. **One machine for now.** A second Mac, ideally with 8 GB of memory, is required before the first public release; until then the README states that budgets were measured on a single Mac.

## Consequences
- The README budget table is updated with the measured values and the date of measurement.
- The 24-hour measurement is the first task of the implementation phase, before the real sentinel is built.

# 0038. Platform scope reconsidered: no Intel, no older macOS (for now)

- Status: Accepted
- Date: 2026-11-15
- Confirms: 0004

## Context
Older Macs are where slowdowns are most common, so supporting Intel Macs and older macOS versions could reach more people who need Farol. Facts checked on 2026-11-15:
- macOS 26 (Tahoe) is the last macOS for Intel Macs; macOS 27 runs only on Apple silicon. Tahoe runs on only four Intel models (16-inch MacBook Pro 2019, 13-inch MacBook Pro 2020 with four Thunderbolt ports, 27-inch iMac 2020, Mac Pro 2019). Reaching older Intel Macs would require macOS 13 or 14.
- Every Apple silicon Mac since the M1 (2020) runs macOS 26, including the many 8 GB M1 and M2 machines that are now the typical "my Mac got slow" case, and Apple's low-cost MacBook with an A-series chip.

## Options
1. Keep Apple silicon and macOS 26+.
2. Apple silicon with macOS 15+ (reaches people who postpone updates; no Liquid Glass below 26).
3. Add Intel with macOS 26 (universal binary, doubled testing, four models).
4. Add Intel and older macOS (largest reach; very large cost; macOS versions without security fixes).

## Decision
Option 1. Supporting Intel or older macOS would double the test and calibration work (no efficiency cores, different thermal behavior and sensors, different budgets), require older UI and APIs, and expose a monitoring tool on systems that no longer receive security fixes — for a platform Apple has ended. The cost is too high for a first-time maintainer and for version 1.0.

## Consequences
- Revisit only with evidence of demand: anonymous reports (ADR 0036) and GitHub issues asking for macOS 15 or Intel support. Option 2 is the first candidate if demand appears.

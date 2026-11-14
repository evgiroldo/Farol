# 0004. macOS only, Apple silicon, macOS 26+

- Status: Accepted
- Date: 2026-11-14

## Context
The project focuses on Apple platforms, written in Swift, with modern design (Liquid Glass) and the cleanest possible code.

## Options
- Platforms: Mac only, or Mac plus an iPhone companion (requires pairing, local networking and encryption).
- Architecture: Universal (Intel + Apple silicon) or Apple silicon only.
- Minimum OS: macOS 26+ (Liquid Glass introduced) or macOS 27 only.

## Decision
- **Mac only** for now; an iPhone companion may be reconsidered after the MVP.
- **Apple silicon only** (arm64).
- **macOS 26 or later.** As far as known, every Apple silicon Mac runs both macOS 26 and 27, so the choice excludes no hardware, only users who have not upgraded.

## Consequences
- A few `if #available(macOS 27, *)` checks for newer APIs; testing on two OS versions.
- No Intel-specific code paths; efficiency/performance core topology can be assumed.

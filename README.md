# Farol

**Why is your Mac slow? Farol tells you which app is causing it — and shows the proof.**

Farol is a free, open-source app for Macs with Apple silicon. When your Mac feels slow, freezes, gets hot or drains the battery, open Farol and it tells you, in plain words, what is going on and what to do about it.

> Status: early development — there is nothing to install yet. Follow the repository to hear when the first version is ready.

## How it works

1. **It quietly keeps watch.** A tiny helper in the menu bar notices when your Mac starts working harder than usual and keeps a short record of what was running. It uses almost no battery or memory.
2. **You ask "why?".** Open Farol and it shows a short answer first — for example: *"Your Mac is slow because Photos is analyzing your library. This is normal after adding many photos and often takes from minutes to a few hours."* The details and graphs are there if you want them.
3. **It checks before it blames.** When an app looks guilty, Farol can pause it for a moment (only if you agree) and watch whether the Mac calms down. That way it shows evidence instead of guessing.

Sometimes the honest answer is "nothing is wrong, this is normal and will end soon" — and Farol will say so.

## What makes it different

- **Finds the app behind the slowdown.** On a Mac, the process using the most power is often just doing work *for* another app (for example, the system that draws the screen or the one that indexes files for search). Farol tries to trace that work back to the app that caused it.
- **Shows evidence, not guesses.** Every answer comes with how sure Farol is — or says "not sure" when the data is not enough. (Early prototypes showed the idea can work; the method is still being validated, see [ADR 0019](docs/adr/0019-corrections-after-first-review.md).)
- **Remembers what you missed.** If the Mac was slow two minutes ago and is fine now, Farol can still tell you what happened.
- **Settles debates with your own data** *(planned)*. Guided tests such as "does Safari really save battery compared to Chrome — on my Mac, with my use?"
- **Honest numbers.** Every value is labeled *measured*, *estimated* or *inferred*; missing data is shown as missing, never invented.
- **Lighter than the problem it diagnoses.** See the targets below.

Some problems cannot be tested by pausing an app — an overheating Mac, too little memory, a full disk, or work done by macOS itself. For those, Farol explains what it sees instead of claiming proof.

## Principles

| | |
|---|---|
| **Privacy** | Zero network access. Nothing leaves your Mac. History is minimal, local, excluded from backups and deletable. |
| **Security** | Nothing runs as root. Hardened Runtime. No third-party dependencies. Release builds will be reproducible from public commits with signed provenance. |
| **Performance** | Resource budgets will be enforced in CI and checked on real hardware before each release. |

### Resource budget targets

Targets, pending measurement with the real sentinel ([ADR 0019](docs/adr/0019-corrections-after-first-review.md)). This table is the single source of truth.

| Process | State | CPU (of one core) | Memory |
|---|---|---|---|
| Sentinel (menu bar) | Idle | < 0.1% | < 15 MB |
| Sentinel (menu bar) | Recording an incident | < 1% | < 15 MB |
| Farol app | Window open, updating every second | < 1% | < 60 MB |

Monitoring runs at low priority (`utility`/`background` QoS), which keeps it mostly on the efficiency cores.

## Requirements

- Mac with Apple silicon (M1 or later)
- macOS 26 or later

## Roadmap

**Version 1.0** ([ADR 0029](docs/adr/0029-scope-of-version-1.md)):
- The menu bar helper with alerts and a short history of slowdowns.
- A window that gives the answer first, with processes and performance views underneath.
- Cause testing for the two classic cases: the system process that draws the screen (WindowServer) and the one that indexes files for search (Spotlight).
- Heat and battery information, and plain explanations of about 20 common macOS processes, in English and Portuguese.

**After 1.0**, in an order chosen with user feedback: detailed power and temperature sensors, personal A/B experiments, Siri and Shortcuts, a shareable report, and cause testing for more system processes.

## Contributing

Read the [architecture decision records](docs/adr/) to understand why things are the way they are. Security issues: see [SECURITY.md](SECURITY.md).

```bash
cd FarolCore && swift test
```

## License

Farol is free software, licensed under the [GNU General Public License v3.0](LICENSE).

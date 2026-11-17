# Farol

**Why is your Mac slow? Farol tells you which app is causing it — and shows the proof.**

Farol is a free, open-source app for Macs with Apple silicon. When your Mac feels slow, freezes, gets hot or runs out of space, open Farol: it tells you in plain words what is causing it, and gives you one button to fix it. You don't need to know anything about processes, CPU or memory.

*Farol* means *lighthouse* in Portuguese.

> **Status:** in development — there is nothing to install yet. The design is complete and its core is being measured and validated. Watch or star the repository to hear when the first version is ready.

## How it works

1. **It quietly keeps watch.** A tiny helper in the menu bar notices when your Mac starts working harder than usual and keeps a short record of what was running — so Farol can explain a slowdown even after it's over.
2. **You open Farol and see the answer first.** One card, one sentence, one button. For example:
   - *"Chrome is slowing down your Mac."* → **Fix** — Farol restarts Chrome the normal way (it asks you to save anything first, and your tabs come back).
   - *"Your Mac is organizing your photos."* → It explains that this is normal after adding many photos, and offers to tell you if it goes on for too long.
3. **When Farol isn't sure, it checks before it blames.** Sometimes an app makes *macOS* work harder — for example, by making the system redraw the screen all the time. Then Farol says *"Slack may be slowing down your Mac. We're not sure yet."* and offers **Pause to confirm**: with your OK, it pauses the app three times for 3 seconds (about 36 seconds in total) and watches whether your Mac calms down. Nothing is closed. If it's confirmed, you get the Fix button; if the result is unclear, Farol says so.

Graphs, numbers and process lists are still there under **Details**, for anyone who wants them.

## Why it's different

- **It fixes, it doesn't just show.** Most monitors give you a wall of numbers. Farol gives you the cause and one safe action.
- **It finds the app behind the slowdown.** On a Mac, the process using the most power is often just working *for* another app — like the system that draws the screen, or the one that indexes files for search. Farol traces that work back to the app that caused it.
- **It shows evidence, not guesses.** Every answer says how sure Farol is. Suspicions are never presented as facts, and its automatic alerts only state things it measured directly.
- **It looks ahead.** It warns you before your disk fills up ("at this rate, your disk will be full in 12 days").
- **It's lighter than the problem it diagnoses.** The menu bar helper is designed to use a tiny fraction of your Mac (see the targets below).

Some problems can't be tested by pausing an app — heat, too little memory, a full disk, or work macOS does on its own. For those, Farol explains what it sees and what you can do, without claiming proof.

## Is it safe?

- **Farol never closes or pauses anything without asking you.** Fix restarts an app the normal way, so you're asked to save your work.
- **No pausing during calls.** If any app is using the microphone, Farol doesn't run its pause test, and it never pauses system apps like Finder or Dock.
- **Paused apps always come back.** A separate safety helper resumes them even if Farol itself crashes.
- **Nothing runs with administrator rights.**

## Privacy

- **Farol never connects to the internet.** Everything stays on your Mac.
- **You can choose to help improve Farol** by sharing an anonymous report. You see its full content first and send it yourself, through your browser. It never contains your name, files, exact times or anything that could identify you.
- The short history of slowdowns stays on your Mac, is excluded from backups, is kept for 7 days, and can be deleted at any time.

## Requirements

- A Mac with Apple silicon (M1 or later)
- macOS 26 or later
- Interface in English and Brazilian Portuguese

## Roadmap

**Version 1.0** ([ADR 0029](docs/adr/0029-scope-of-version-1.md), [ADR 0031](docs/adr/0031-solve-dont-show.md)):
- The menu bar helper with alerts and a short history of slowdowns.
- The answer-first window with the Fix and Pause to confirm buttons.
- Cause testing for the classic case: the system process that draws the screen (WindowServer). Spotlight, which indexes files for search, is explained but not tested yet: its work comes in bursts that a short pause cannot measure reliably.
- Heat, battery and free-space information, including the "disk full in N days" warning.
- Plain explanations of about 20 common macOS processes.
- "Was this helpful?" after every fix, and optional anonymous reports.

**After 1.0**, in an order chosen with user feedback: detailed power and temperature sensors, personal A/B tests ("does Safari really save battery compared to Chrome, on my Mac?"), Siri and Shortcuts, a report you can send to someone helping you, and cause testing for more system processes.

---

## For developers

Farol is written in Swift for macOS 26+, with **no third-party dependencies**. Every architectural decision — and every correction after independent reviews — is recorded in the [architecture decision records](docs/adr/). Prototypes used as evidence are in [`docs/spikes/`](docs/spikes/).

| Principle | In practice |
|---|---|
| Privacy | No networking code in Farol at all; a CI check will enforce it. |
| Security | No root, no privileged helper, Hardened Runtime; history treated as untrusted input. Release builds will be reproducible from public commits with signed provenance. See [SECURITY.md](SECURITY.md). |
| Performance | Resource budgets checked in CI and on real hardware before each release. |

### Resource budget targets

Provisional. A 24-hour measurement with every part of the real helper is running now; the final numbers will come from it ([ADR 0028](docs/adr/0028-budget-policy.md)). This table is the single source of truth.

| Process | State | CPU (of one core) | Memory |
|---|---|---|---|
| Menu bar helper | Idle | < 0.1% | measured peak + 20%, at most 25 MB |
| Menu bar helper | Recording a slowdown | < 1% | same as idle |
| Farol app | Window open, updating every second | < 1% | < 60 MB |

Monitoring runs at low priority, which keeps it mostly on the efficiency cores.

### Build and test

```bash
cd FarolCore && swift test
```

Security issues: please report them privately, as described in [SECURITY.md](SECURITY.md).

## License

Farol is free software, licensed under the [GNU General Public License v3.0](LICENSE).

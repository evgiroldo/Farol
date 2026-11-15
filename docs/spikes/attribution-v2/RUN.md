# How to run the attribution spike (for the maintainer)

This is a one-off experiment, not Farol. It checks whether Farol's "cause test" (briefly freezing an app to see if a busy system process calms down) can be trusted, and how strict it must be.

## In short

| | |
|---|---|
| **How long** | About 52 minutes (at most about an hour). It prints the estimate before starting. |
| **What you do** | Start it, write down the start time, leave the Mac alone, write down the end time. |
| **What it freezes** | Only programs it starts itself. Never your apps. |
| **How to stop** | Press `Ctrl-C` in the Terminal window. Everything is un-frozen and closed. |

## Before you start

1. **Be at the Mac, logged in, screen on and unlocked.** The test needs to show a window. If the screen is asleep or locked it refuses to start and says so. It keeps the screen awake by itself while it runs.
2. **Plug in the charger.** The test keeps the Mac busy for close to an hour.
3. **The 24-hour measurement will be disturbed.** This test puts real load on the Mac. Run it only when you accept a gap in the 24-hour measurement (`FarolSpike.app`), and note the start and end time (step 3 below) so that window can be left out.
4. Open **Terminal** (the app, on the Mac itself — not a remote connection).

## Run it

```bash
cd "/Users/evgiroldo/Claude Code/Farol/docs/spikes/attribution-v2"
./build.sh
build/attrib2 all
```

1. It prints the estimated duration, a line starting with **`START TIME:`**, and waits 5 seconds (last chance to press `Ctrl-C`).
2. Leave the Mac alone until it prints **`Done.`** — no typing, no clicking, no moving windows. Anything you do changes what is being measured.
3. **Write down the `START TIME:` and `END TIME:` lines.** These are the times to exclude from the 24-hour measurement. (They are also saved in `phases.csv` in the data folder.)

## What you will see on screen

- **First 3 minutes: nothing.** It only listens.
- **Then a large dark window** titled "Farol spike: test load" with slowly drifting blue shapes. It stays on top of other windows on purpose. It may close and reopen up to twice in the first minute while the test finds a strong enough load, and once more around the middle. The motion is slow and low-contrast; there is no flashing.
- **The window freezes for 3 seconds, several times.** That is the test itself: it freezes its own window and watches what happens. This is expected.
- **Around the middle, small boxes appear on top of the window** for about 20 seconds each ("small static panel", "full cover"). They check whether Farol's own window would hide the problem it is trying to measure.
- At the end the window closes by itself.

It also writes many small text files (so that Spotlight has something to index) into its own data folder, `data/<date-time>/spotlight-test-files`, and **deletes them at the end**. They never take more than about 10 MB of disk space, but they are rewritten continuously: expect roughly 2 GB of writing over the run, and up to about 13 GB if the test has to raise the load to its highest level.

## What it does and does not touch

- It **freezes only programs it started itself**: its test window (with the WebKit helper programs macOS starts for that window), its file writer, and two programs that only use the processor. Before every freeze it checks that the program is exactly the one it started (same number, same start time, same file); if anything does not match, it un-freezes everything and stops that test.
- It **never freezes or closes your apps** and sends them no signal of any kind.
- It only **reads** how busy two system processes are (WindowServer, which draws the screen, and Spotlight's indexer).
- A separate small **watchdog** program is started first. If the test crashes, is force-quit, or its Terminal window is closed, the watchdog un-freezes everything within about a second, and the test programs close by themselves. Before any real test, the spike proves this works on your Mac (the "safety check", 15 seconds); if the proof fails, it does not freeze anything and tells you.
- It uses no network. It should not ask for any password or permission; if a permission dialog does appear, press `Ctrl-C` and report it.

## How to stop it safely

- **Press `Ctrl-C`** in the Terminal window. It un-freezes everything, closes its window, deletes its test files and prints the end time.
- Closing the Terminal window, or even force-quitting the test, is also safe: the watchdog takes over.
- If you ever suspect something of the test is still on screen or frozen (it should not happen), this is harmless and cleans up — it only names the test's own two programs:

```bash
killall -CONT FarolSpikeWeb attrib2; killall FarolSpikeWeb attrib2
```

  and you may delete any leftover `spotlight-test-files` folder inside `docs/spikes/attribution-v2/data/`. If in doubt, logging out and back in clears everything.

## When it is done

- The summary is `docs/spikes/attribution-v2/data/<date-time>/results.md`; the raw numbers are the `.csv` files next to it.
- Nothing is committed to git and nothing outside this folder is changed.
- If it stopped early, the reason is in the Terminal output and in `notes.txt` in the data folder. Partial data is kept; `build/attrib2 analyze` summarises whatever exists.

## Shorter runs

| Command | Time | Windows | Freezes |
|---|---|---|---|
| `build/attrib2 safety-check` | 15 s | no | one helper program it starts |
| `build/attrib2 record --seconds 3600` | as long as you say | no | nothing — it only listens; good to run for hours during normal use, then `build/attrib2 analyze` |
| `build/attrib2 test --n 3` | about 10 min | yes | only its own programs |
| `build/attrib2 occlusion` | about 5 min | yes | nothing |
| `build/attrib2 all --idle-min 2 --steady-min 6 --pulsed-min 4 --n-steady 3 --n-pulsed 2` | about 30 min | yes | only its own programs |

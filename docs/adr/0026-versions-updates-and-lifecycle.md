# 0026. Versions, updates and the sentinel's lifecycle

- Status: Accepted; amended by ADR 0035
- Date: 2026-11-14

## Context
After an update (Homebrew or manual), the old sentinel keeps running until logout. If the history schema changed, an old writer and a new reader disagree. The review also found undecided states: the user disabling the login item, App Translocation when run from Downloads, and uninstall.

## Options
- App restarts the sentinel when versions differ; or that plus the sentinel exiting on its own when its executable changes on disk.

## Decision
1. **Two mechanisms together.** On launch, the app asks the sentinel its version over XPC (ADR 0025) and, if it differs, asks it to restart (launchd relaunches the new binary). Independently, the sentinel checks every 30 s (its existing heartbeat) whether its own executable on disk changed, and if so exits so launchd starts the new one — covering updates where the app is not opened.
2. **Schema.** Only the sentinel migrates the database (ordered migrations). The app refuses a newer schema and tells the user, in plain words, to update Farol.
3. **Login item states.** The app reads `SMAppService` status: *requires approval* → shows how to approve in System Settings; *disabled by the user* → respects it and shows that history is off; *not found* (e.g. App Translocation) → asks the user to move Farol to Applications.
4. **Uninstall.** The app has an "Uninstall Farol" action that unregisters the sentinel and deletes the history; the Homebrew cask includes a `zap` stanza for the same files.

## Consequences
- Version checks and the sentinel's self-exit need tests, including a downgrade scenario (older sentinel, newer database → the sentinel refuses to write and reports it).

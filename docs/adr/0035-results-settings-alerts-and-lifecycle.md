# 0035. Test results, settings, alert filters, disk and sentinel lifecycle

- Status: Accepted
- Date: 2026-11-15
- Amends: 0024, 0025, 0026, 0029, 0031

## Decision
1. **Cause-test results are stored.** The app sends the result to the sentinel over XPC (`recordTestResult`); the sentinel validates it (known incident, plausible values, rate limit) and writes it to the history. A card that became "Fix" stays "Fix" when Farol is reopened.
2. **Settings belong to the sentinel.** Retention, alerts and similar settings live in the sentinel's preferences; the app requests changes over XPC (`setSetting`), and the sentinel validates every value as untrusted input.
3. **Alert filters.** No alert when the top consumer is the **frontmost app** (the user is working with it on purpose). Separate daily limits: 3 symptom alerts and 3 alerts that name an app.
4. **Full disk in 1.0.** Farol shows free space and a **"full in N days" prediction** from the free-space trend, and its "Fix" button opens Storage in System Settings, which already shows what uses the space. Farol's own disk analyzer comes after 1.0.
5. **Predictions in 1.0.** Only the disk-full prediction. Recurring patterns and "your Mac is getting slower" need longer history than the 7-day retention and come after 1.0.
6. **Alert clicks** open the Farol app on the incident through a validated identifier; the link can only navigate, never act.
7. **Sentinel lifecycle details** (amends 0026):
   - The launch agent is kept alive only after an abnormal exit (`KeepAlive` → `SuccessfulExit = false`); "Quit" from its menu stops it until the next login or until the app restarts it.
   - After its executable changes, the sentinel exits only once the new executable has been stable for two heartbeats and its code signature validates.
   - The app restarts the sentinel at most once per launch; if versions still differ (two copies of Farol), it explains instead of looping.
   - If its bundle is in the Trash or missing, the sentinel stops and unregisters itself.
   - If it cannot open the history (newer schema, damaged file), it runs in a degraded "history off" state, and "Delete history" works at the file level without opening the database.

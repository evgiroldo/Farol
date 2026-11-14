# 0036. Anonymous reports sent by the user

- Status: Accepted
- Date: 2026-11-15
- Amends: 0009 (clarifies what "zero network" allows), 0029 (adds to version 1.0)

## Context
Once Farol runs on many Macs, data from real use would help improve it: calibrating the cause test across machines (ADR 0033 needs more than one Mac), learning which fixes actually help, and growing the knowledge base. Farol promises zero network access (ADR 0009), which any automatic sending would break. "Completely anonymous" is also harder than it looks: a combination of Mac model, macOS version, time zone and a few uncommon app names can identify a person, and under the GDPR the sender's IP address is personal data at collection time.

## Options
1. **A report the user reviews and sends themselves**: Farol never touches the network.
2. Opt-in automatic telemetry over the internet: needs a server, a privacy policy, GDPR compliance, and ends the zero-network promise.
3. No usage data; learn only from GitHub issues and discussions.

## Decision
Option 1, in version 1.0.

- **"Was this helpful?"** After every Fix and every cause test, Farol asks one yes/no question. The answer is stored locally with the result (through the sentinel, ADR 0035).
- **"Share an anonymous report"** creates a JSON file and shows its full content in plain words before anything else happens. The user can cancel at any point.
- **Sending is done by the user, in their browser.** Farol saves the file and opens a prefilled page on the project's GitHub (an issue template) where the user attaches it. Farol itself makes no network connection; opening a link in the user's browser at the user's request is not network access by Farol. Reports on GitHub are public, so their content must be safe to publish.
- **What a report contains:**
  - Mac family and memory size in buckets (e.g. "M2, 8 GB"), macOS major and minor version, Farol version.
  - Results of cause tests: daemon, measured effect, verdict, natural fluctuation, test duration.
  - Answers to "Was this helpful?", per kind of problem and fix.
  - Counts of incidents by reason.
- **What a report never contains:** names, accounts, serial numbers or hardware identifiers, host name, file paths, window titles, IP or network details, exact timestamps (day only), time zone, or any random identifier that could link two reports. App names appear only if they are on a **public list of popular apps** kept in the repository; every other app becomes "another app".
- The report format is versioned and documented in the repository, so anyone can check what Farol sends.

## Consequences
- The README's privacy line becomes: "Farol never connects to the internet. You can choose to share an anonymous report yourself."
- Sending requires a GitHub account; a simpler channel can be added later without giving Farol network access.
- A future decision for automatic telemetry would need its own ADR and would change the privacy promise.

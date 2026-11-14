# 0002. Name "Farol" and GPLv3 license

- Status: Accepted
- Date: 2026-11-14

## Context
The project needs a distinctive name and a free-software license.

## Options
- Names: Pulso, Sonda, Vigia, Lumen, Farol, Lucerna. "Lumen" was rejected: a Homebrew cask `lumen` (a brightness app) and "Lumen Widgets" (which shows CPU usage) already exist. "Farol" (Portuguese for *lighthouse*) had no conflict on Homebrew or GitHub at the time of the search; trademark registries were not checked.
- Licenses: MIT (simplest, allows closed forks), Apache 2.0 (permissive plus patent grant), GPLv3 (copyleft).

## Decision
Name: **Farol**. License: **GPLv3**.

## Consequences
- Anyone who distributes a modified Farol must publish their source under GPLv3; nobody can turn it into a closed product.
- Some companies avoid GPL code; adoption by them is traded for keeping the project free.

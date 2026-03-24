# Project Commands

Use these prompts directly with Codex from this repo when you want local automation without manually using PowerShell.

## Rule

Whenever a new repeatable automation, verification flow, or maintenance task is added to this project, add a matching prompt entry to this file.

The goal is:

- if a task can be reasonably triggered by asking Codex to run something local
- and it is likely to be reused
- it should get a self-contained command prompt here

## Sleeper ID Parser

Set or replace a `sleeperLeagueId` from a Sleeper URL or raw ID:

```text
Run the Sleeper ID parser for league record CH1 using this input: https://sleeper.com/leagues/1339342261023961088/predraft
```

```text
Run the Sleeper ID parser for league record BBU5 using this input: 1339095453291003904
```

## Next League ID

Get the next suggested internal ID for a format:

```text
Run the next league ID helper for the chopped format and tell me the suggested new ID.
```

```text
Run the next league ID helper for bracket and show me the next internal ID.
```

## League Intake

Create a new league record through the intake flow:

```text
Run the league intake script to create a new chopped league record and walk me through the required fields.
```

Update an existing league record through the intake flow:

```text
Run the league intake script to update CH1 and prompt me for any missing fields.
```

## Sleeper Sync Report

Refresh Sleeper-owned fields and summarize the result, without changing local names or statuses:

```text
Run the local Sleeper sync report and summarize what changed and what still needs attention.
```

Refresh Sleeper-owned fields and also update local statuses:

```text
Run the local Sleeper sync report, update statuses from Sleeper where appropriate, and summarize the warnings.
```

Refresh Sleeper-owned fields and also overwrite local names from Sleeper:

```text
Run the local Sleeper sync report, update local names from Sleeper too, and summarize every changed league.
```

## League JSON Validation

Run the local validator and summarize all errors and warnings:

```text
Run the league JSON validator and tell me every error and warning in plain English.
```

Run the validator in strict mode:

```text
Run the league JSON validator in strict mode and tell me if the file is clean enough to push.
```

## Donation Updates

Apply the documented donation workflow to a batch of form responses:

```text
Use the donation update workflow to apply the latest Google Form responses and update data/donations.json.
```

If I paste exported response rows next, use them to update the current donation totals:

```text
Use the donation update workflow with the form rows I paste next, update data/donations.json, and summarize what changed.
```

## Donation Validation

Run the donation JSON validator and summarize all errors and warnings:

```text
Run the donation JSON validator and tell me every error and warning in plain English.
```

Run the donation validator and include live DonorsChoose link checks:

```text
Run the donation JSON validator with live link checks and tell me if any project links look broken.
```

## Keeper Ledger

Build or refresh the keeper commissioner worksheet from Sleeper:

```text
Run the keeper ledger sync and build data/keeper-ledger.json from the current keeper leagues, preserving any manual keeper entries already in the file.
```

Sync only one keeper league:

```text
Run the keeper ledger sync for KP1 only and summarize which managers were pulled into the local keeper tracker.
```

## Bracket Ledger

Build or refresh the combined bracket seeding worksheet from Sleeper:

```text
Run the bracket ledger sync and refresh data/bracket-ledger.json from Sleeper so the grouped bracket leagues, standings, seeds, wild cards, and Week 13 matchups are up to date.
```

Sync only one bracket group:

```text
Run the bracket ledger sync for BRACKET-2026-1 only and summarize the current division winners, Seeds 1-30, and wild cards.
```

Refresh the full combined standings table for one bracket group:

```text
Run the bracket ledger sync and refresh data/bracket-ledger.json from Sleeper, then give me the current combined overall standings for BRACKET-2026-1 with rank, team name, league/division, record, and points for. If the season is not far enough along or the group is not full yet, tell me the standings are provisional.
```

Generate the weekly-style bracket standings report:

```text
Run the bracket ledger sync for BRACKET-2026-1, then run the bracket report exporter using Week 9 and give me the full report with division playoff counts plus all ranked teams from 1 through the bottom of the group. If the season data is still incomplete, tell me the report is provisional.
```

## League Data Diff

Compare a before snapshot to the current league data and summarize every changed league:

```text
Run the league data diff report using this before snapshot path and summarize every added, removed, and changed league.
```

Compare two explicit league JSON files:

```text
Run the league data diff report comparing these two league JSON files and give me a human-readable summary.
```

## Local Preview

Open or reopen the local site:

```text
Start localhost for this repo and open the homepage in Chrome.
```

Open the chopped constitution directly:

```text
Open the chopped constitution on localhost in Chrome.
```

Open a cache-busted preview after league-data edits:

```text
Run the preview script and open the homepage with cache-busting so I can verify the latest changes.
```

## Constitution Checks

Run the constitution-page checker and summarize any missing back links, banner images, or structure issues:

```text
Run the constitution-page check and tell me if any constitution is missing the Back to Hub link, banner image, or section structure.
```

Run the broad site check, including constitutions:

```text
Run the one-command site check and include the constitution-page results in the summary.
```

## Cache Busting

Update the homepage asset version strings after frontend edits:

```text
Run the cache-busting helper and update the homepage asset version strings in index.html.
```

Preview the next cache-busting version without writing the file:

```text
Preview the cache-busting helper output and tell me what version it would apply without changing index.html.
```

## Release Helper

Run the release helper and tell me if the site is ready to push:

```text
Run the release helper and tell me whether the site is ready to push.
```

Run the release helper without opening the browser:

```text
Run the release helper with no preview open and summarize any blocking issues or warnings before push.
```

## Dynasty Future Pick Audit

Check which managers have traded away future picks in a dynasty league:

```text
Run the dynasty future-pick audit for DYN1 and tell me which managers owe 2027 or 2028 payment based on traded-away picks only.
```

```text
Run the dynasty future-pick audit for DYN3 and draft me a Sleeper @all payment reminder post using the current LeagueSafe links.
```
## Thumbnail Image

Create a general Sleeper thumbnail from the current site artwork:

```text
Generate the general Sleeper thumbnail image from the current banner and league-format artwork, then show me where it was saved.
```

## Combined Check

Run the sync report first, then validate, then tell me the net result:

```text
Run the Sleeper sync report, then run the league JSON validator, and give me a short action list of what is still missing.
```

Run the local one-command site check:

```text
Run the one-command site check and tell me any errors or warnings before commit.
```

## Recommended Usage

- Use the parser when you get a new Sleeper link for an existing league record.
- Use the next-ID helper before creating a new league record.
- Use the league intake script when you want one guided flow for creating or updating a league record.
- Use the sync report when you want current fill counts and a warning summary.
- Use the donation workflow when you want to turn reported donations into updated homepage totals without inventing a new admin system.
- Use the donation validator when you want to sanity-check `data/donations.json` before pushing donation updates.
- Use the league data diff report when you want a human-readable review of what changed in `data/leagues.json`.
- Use the preview script when you want localhost reopened with a cache-busted URL.
- Use the cache-busting helper when frontend changes are correct but your browser is still serving old CSS or JS.
- Use the release helper when you want one command to check the site, optionally reopen preview, and tell you if the repo is ready to push.
- Use the constitution-page check when you want a fast pass on Back to Hub links, banner image references, and basic constitution structure.
- Use the validator before commit or push.
- Use the one-command site check when you want the broadest local pre-push pass.

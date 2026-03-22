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
- Use the preview script when you want localhost reopened with a cache-busted URL.
- Use the validator before commit or push.
- Use the one-command site check when you want the broadest local pre-push pass.

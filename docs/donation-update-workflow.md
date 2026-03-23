# Donation Update Workflow

## Goal

Keep the homepage donation section current without adding a backend, a live spreadsheet dependency, or a complex admin flow.

## Source Of Truth

- Google Form responses are the intake queue.
- `data/donations.json` is the published homepage source of truth.
- The live DonorsChoose project page is the source of truth for each project's current `remaining` amount.

Do not try to make the form update the site automatically. Keep it as a lightweight manual batch workflow.

## Recommended Response-Sheet Setup

If the linked Google Form is connected to a response sheet, add these helper columns to the sheet:

- `Processed`
- `Matched Project`
- `Applied Amount`
- `Applied At`
- `Notes`

This keeps the workflow lightweight while still leaving an audit trail.

## Processing Cadence

Process form responses:

- when a small batch of new donations comes in
- before you post updated totals publicly
- before you rotate donation projects on the homepage

## Lightweight Workflow

1. Open the Google Form response sheet and filter to rows that are not marked `Processed`.
2. Ignore obvious test entries, duplicates, or responses that do not include enough information to match a project.
3. Match each valid response to a homepage project.
   - Match by exact DonorsChoose link first if the response includes it.
   - If no link is present, match by project title.
   - If the project cannot be matched confidently, leave the row unprocessed and note the issue.
4. Group the approved new donations by project.
5. Update `data/donations.json`.
   - Add the approved amount to that project's `donated` total.
   - Refresh `remaining` from the live DonorsChoose page when possible.
   - Leave slot order and project order stable unless you are intentionally rotating projects.
6. Mark the applied rows in the response sheet.
   - Set `Processed` to `yes`.
   - Fill in `Matched Project`.
   - Fill in `Applied Amount`.
   - Add `Applied At` with the processing date.
   - Use `Notes` for edge cases or partial matches.
7. If a project is fully funded or no longer suitable for the homepage, replace it in `data/donations.json` during the next content refresh instead of trying to keep historical projects mixed into the live homepage slots.

## Matching Rules

- Prefer exact project links over project names.
- If two responses appear to be the same donation, stop and review before applying both.
- If a donor reports a donation to a project that is no longer in the current homepage rotation, decide whether to:
  - apply it to the archived project record manually, or
  - leave it out of the live homepage totals and track it separately in the sheet notes

## Recommended Form Fields Later

If you revise the form later, prioritize these fields:

- donation timestamp
- donor name or handle
- DonorsChoose project link
- project title
- donation amount
- optional proof or notes

## Codex Usage

When you want help applying a batch manually, provide the response rows or an export and ask:

`Use the donation update workflow to apply these form responses and update data/donations.json.`

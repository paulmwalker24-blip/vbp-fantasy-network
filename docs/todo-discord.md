# Discord TODO

Use this list for Discord server structure, webhook automation, testing-channel posts, and GitHub Actions workflow health.

## Immediate

- [ ] Add the `DISCORD_WEBHOOK_*_TESTING` repository secrets listed in `docs/discord-server/testing-channel-map.md`.
- [ ] Rerun the `Discord Testing Channel Stack` GitHub Action after secrets are added and confirm the workflow no longer fails at webhook-config build time.
- [ ] Keep the local GitHub CLI at `.tools/bin/gh.exe` for inspecting Actions runs; `.tools/` is intentionally gitignored.
- [ ] Decide which testing channels should exist before broad launch, then create or archive Discord channels to match `docs/discord-server/testing-channel-map.md`.
- [ ] Post or update the `start-here`, `rules-and-links`, and league directory front-door messages.

## Automation

- [ ] Use `scripts/post-discord-testing-channel-stack.ps1 -DryRun` locally before live posts when copy or counts change.
- [ ] After the first successful live workflow run, verify `data/discord-message-state.json` is saved so future posts update in place.
- [ ] Confirm Discord webhook permissions after any channel rename from `*-testing` to final public names.
- [ ] Decide whether the scheduled six-hour workflow should remain active during setup or move to manual-only until the server is public.

## Content

- [ ] Keep Discord status-board counts aligned with `data/leagues.json` and the current assigned-team rule for Redraft Bracket.
- [ ] Remove stale guide/explanation posts from testing channels once the consolidated status board is readable on desktop and mobile.
- [ ] Publish constitution forum posts or channel posts after the server structure is final.

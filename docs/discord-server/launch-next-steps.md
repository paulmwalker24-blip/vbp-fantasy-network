# Discord Server Launch Next Steps

Use this as the near-term launch checklist for getting the VBP Fantasy Network Discord usable quickly.

The goal for launch is not a finished server. The goal is a clean front door, current openings, public rules/resources, and tested automation paths.

## Launch Target

Get the server ready for real invites by the end of the next setup pass.

Minimum ready state:

- New members land in `start-here`.
- Old channels are archived or hidden below the new structure.
- `League Openings` testing channels have format explanations plus current webhook boards.
- `rules-and-links` points to the public hub, constitutions, and league centers.
- Discord automation can dry-run into `automation-test`.
- The first live posts are made only after the dry-runs look clean.

## Priority Order

### 1. Lock The Server Skeleton

Create or confirm these categories and channels:

```text
START HERE
- start-here
- rules-and-links
- announcements

COMMUNITY
- general-discussion
- nfl-discussion
- fantasy-football-discussion
- fantasy-football-draft-questions
- league-questions

LEAGUE HUBS
- redraft-bracket
- dynasty-bracket
- best-ball-union

LEAGUE OPENINGS
- 32-team-redraft-testing
- best-ball-gauntlet-testing
- best-ball-union-testing
- chopped-testing
- co-manager-testing
- dynasty-bracket-testing
- dynasty-testing
- keeper-testing
- pickem-testing
- redraft-bracket-testing
- redraft-testing
- sacrifice-testing

STAFF
- commissioner-log
- automation-test
```

Archive old channels under:

```text
ARCHIVE - OLD STRUCTURE
```

Do this before inviting more people so nobody lands in stale league-list or rules channels.

### 2. Keep Roles Minimal

Start with:

```text
Commissioner
Current Owner
Prospect
Bot
```

Recommended first-pass permissions:

- `start-here`, `rules-and-links`, `announcements`, and League Opening testing/status channels: everyone can read; only Commissioner/Bot can post.
- Community channels: Current Owner can post; Prospect can post if you want public Q&A.
- League Hub channels: Current Owner can post; Prospect can read only or be excluded.
- `commissioner-log` and `automation-test`: Commissioner/Bot only.

Launch decision:

- Decide whether Prospects can post in `general-chat`, or whether they should read and DM/reply for placement.

### 3. Post The Front-Door Messages

Post these first, manually if needed:

- `start-here`: short welcome, what the server is for, where to go.
- `rules-and-links`: main site, constitutions, Bracket Center, Best Ball Union Center, power rankings.
- League Opening testing channels: format explanation first, then full/opening status webhooks underneath.
- `announcements`: leave quiet unless there is a true network-wide note.

Source docs:

- Full rebuild outline: `docs/discord-server/discord-audit-template.md`
- Testing channel map: `docs/discord-server/testing-channel-map.md`
- Open-leagues guide source: `docs/discord-server/league-openings-top-post.md`
- Paste-ready recruiting copy: `marketing/recruiting-copy-ready.txt`
- Public hub: `https://vbp-fantasy-network.vercel.app/`

### 4. Test Automation In Private

Use `automation-test` first. Do not post live automation into public channels until each board looks right.

Dry-run these in this order:

```text
Post or update the Discord redraft guide webhook in the redraft testing channel before posting the redraft status board.
```

```text
Post or update the Discord server rules message with professional VBP server conduct, league operations, payment, integrity, and enforcement standards.
```

```text
Post or update the Discord league directory message with the network snapshot, league-type channel list, and quick openings summary.
```

```text
Post or update the Discord redraft openings status message with only open standard seasonal redraft leagues. Use live assigned Sleeper spots and the local Discord paid-count overrides.
```

```text
Post or update the Discord redraft bracket status message with the overview at the top and all five divisions alphabetically underneath it as embeds with division graphics. Use live assigned Sleeper spots and the current redraft bracket payment report.
```

```text
Post or update the Discord Best Ball Union status message with filled rooms, drafted full rooms, the current overall high-score pot, and active room cards.
```

```text
Post or update separate Discord forum posts for each public VBP league constitution, one post per league type.
```

If a post looks too long, stale, or confusing, fix the script or data before posting publicly.

### 5. Publish The First Live Boards

Once the dry-runs look clean, post publicly in this order:

1. `rules-and-links`: server rules and constitution/forum links.
2. League Opening testing channels: explanation first, then the matching status board webhook.
3. `announcements`: one short launch note pointing members to `League Openings` and `rules-and-links`.

Keep public posts living and update-in-place where the scripts support saved Discord message state.

### 6. Invite Flow Test

Before broad promotion:

- Create a fresh Discord invite.
- Open it in a browser or alternate account.
- Confirm the first visible channel is `start-here`.
- Confirm the `League Openings` category is obvious.
- Confirm old archived channels are not the first thing people see.
- Confirm a current owner can find bracket chat.
- Confirm a prospect can ask a question or knows how to DM/reply.

### 7. First Week Operating Rule

For the first week, keep the server intentionally small.

Do:

- Update the matching League Opening status channel when counts change.
- Remove or update stale recruiting posts quickly.
- Use `announcements` sparingly.
- Track repeated questions in `commissioner-log`.

Do not add:

- Format-specific roles.
- A large channel tree.
- Trade block channels.
- Bot commands.
- Scheduled posts.

Add those only after the simple version is working and owners are actually using it.

## Immediate Owner Checklist

- [ ] Create/archive the Discord channel structure.
- [ ] Choose Prospect posting access.
- [ ] Add or confirm the Discord webhooks for `automation-test`, `rules-and-links`, each League Opening testing channel, and any forum-style constitution channel.
- [ ] Run all Discord scripts as dry-runs.
- [ ] Post server rules and constitution links.
- [ ] Post each League Opening channel explanation, then the matching active format board underneath it.
- [ ] Test a fresh invite.
- [ ] Start sharing the Discord invite in recruiting replies after the test passes.

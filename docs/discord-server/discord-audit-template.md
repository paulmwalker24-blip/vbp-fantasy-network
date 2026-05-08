# Discord Server Rebuild Outline

This is the practical rebuild path for the VBP Fantasy Network Discord.

The goal is not to audit the old server forever. The goal is to rebuild it into a simple communication hub with automation.

## What This Discord Is For

The server should do four things:

1. Help prospects find open VBP leagues.
2. Give current owners a network-wide communication space.
3. Give 60-team and 48-team leagues cross-division chat.
4. Use automation so the commissioner is not manually reposting the same updates.

## What To Ignore From The Old Server

Do not spend time cleaning old content.

Ignore and replace:

- old pinned constitution text
- old rules channels
- old LeagueSafe channels
- old moderator-only structure
- duplicate `links` channels
- old league-list channels
- old role/label structure

The old server is just a shell.

## Step 1: Create An Archive Category

Create one category:

```text
ARCHIVE - OLD STRUCTURE
```

Move old channels into it instead of deleting them immediately.

Move these first:

```text
leaguesafe-id
leaguesafe-link
links
tgo-league-list
constitution-list
redraft-bracket-announcements
division-information
trades
bbu-league-list
dynasty-list
dynasty-league-announcements
dynasty-general-chat
```

Leave `general-chat` alone until the new chat structure exists.

## Step 2: Build The New Minimum Server

Create these categories and channels.

```text
START HERE
- start-here
- rules-and-links
- open-leagues
- announcements

COMMUNITY
- general-chat

BRACKET HUBS
- redraft-bracket-chat
- dynasty-bracket-chat

STAFF
- commissioner-log
- automation-test
```

This is the first version. Do not add more channels yet.

## Step 3: Set Each Channel's Job

Use these descriptions.

```text
start-here
Purpose: first stop for everyone. Explains what the server is and where to go.

rules-and-links
Purpose: links to the Vercel hub, constitutions, league centers, and key resources.

open-leagues
Purpose: automated or commissioner-posted list of leagues currently recruiting.

announcements
Purpose: important network-wide updates only.

general-chat
Purpose: general VBP community talk that does not belong to one format.

redraft-bracket-chat
Purpose: shared conversation space for the 60-team redraft bracket across divisions.

dynasty-bracket-chat
Purpose: shared conversation space for the 48-team dynasty bracket across divisions.

commissioner-log
Purpose: private staff notes, manual decisions, payment/admin reminders.

automation-test
Purpose: private test channel for webhook/bot messages before posting publicly.
```

## Step 4: Keep Roles Minimal

Start with only these roles:

```text
Commissioner
Current Owner
Prospect
Bot
```

Do not create format-specific roles yet.

Add format roles later only if they unlock a real channel or notification need.

## Step 5: Set Basic Permissions

Recommended first pass:

```text
start-here
- everyone can read
- only Commissioner/Bot can post

rules-and-links
- everyone can read
- only Commissioner/Bot can post

open-leagues
- everyone can read
- only Commissioner/Bot can post

announcements
- everyone can read
- only Commissioner/Bot can post

general-chat
- Current Owner can post
- Prospect can read/post if you want public conversation

redraft-bracket-chat
- Current Owner can read/post
- Prospect can read only, or no access

dynasty-bracket-chat
- Current Owner can read/post
- Prospect can read only, or no access

commissioner-log
- Commissioner only

automation-test
- Commissioner and Bot only
```

Decision needed:

```text
Should prospects be allowed to chat, or only read and DM/reply when interested?
```

## Step 6: Write The First Three Public Posts

Create these messages first.

### start-here

```text
Welcome to VBP Fantasy Network.

This Discord is the communication hub for VBP leagues. Use it to find open leagues, ask questions, follow network updates, and talk across large formats that are split into separate Sleeper divisions.

Start here:
- Open leagues: #open-leagues
- Rules and links: #rules-and-links
- General questions: #general-chat
- 60-team redraft bracket chat: #redraft-bracket-chat
- 48-team dynasty bracket chat: #dynasty-bracket-chat

Main hub:
https://vbp-fantasy-network.vercel.app/
```

### rules-and-links

```text
Main hub:
https://vbp-fantasy-network.vercel.app/

Constitutions:
Redraft: https://vbp-fantasy-network.vercel.app/redraft-constitution.html
Dynasty: https://vbp-fantasy-network.vercel.app/dynasty-constitution.html
Dynasty Bracket: https://vbp-fantasy-network.vercel.app/dynasty-bracket-constitution.html
Best Ball: https://vbp-fantasy-network.vercel.app/bestball-constitution.html
Bracket Redraft: https://vbp-fantasy-network.vercel.app/bracket-constitution.html
Keeper: https://vbp-fantasy-network.vercel.app/keeper-constitution.html
Chopped: https://vbp-fantasy-network.vercel.app/chopped-constitution.html

League Centers:
Bracket Center: https://vbp-fantasy-network.vercel.app/bracket-center.html
Best Ball Union Center: https://vbp-fantasy-network.vercel.app/bestball-center.html
```

### open-leagues

Use this manually first. Later, automation should generate it.

```text
Current VBP openings:

Dynasty 6
- $30 fast Superflex startup
- 3 years due up front
- https://sleeper.com/i/Y2V7Pl0EnAzlj

Chopped League #1
- $15 elimination redraft
- 9/18 paid
- https://sleeper.com/i/Y2VKoEON1XkqR

Best Ball Union
- $10 fast-draft best ball
- http://sleeper.com/i/LVoN4RXgLDk9w

Dynasty Bracket
- $50 Superflex startup
- shared 48-team playoff format
- ask for the best current room

Main hub:
https://vbp-fantasy-network.vercel.app/
```

## Step 7: Automation Plan

Automation is required.

Build it in this order:

1. Manual `open-leagues` message.
2. Webhook test into `automation-test`.
3. Script-generated open-leagues message from `data/leagues.json`.
4. Commissioner-reviewed post into `open-leagues`.
5. Later: direct scheduled posts if the output is reliable.

Recommended first automation path:

```text
local PowerShell script -> Discord webhook -> automation-test
```

Why:

- easiest to test
- no bot permissions yet
- no hosting decision yet
- uses the data already in the repo

Later options:

```text
GitHub Actions -> Discord webhook
Vercel/serverless route -> Discord webhook
Discord bot -> richer commands and role automation
```

## Step 8: What The First Automation Should Post

First automated post should only handle open leagues.

Data source:

```text
data/leagues.json
```

Include:

- league name
- format
- buy-in
- filled / teams
- status
- invite link
- constitution link

Special note:

- If marketing paid count differs from site occupancy, use commissioner-approved marketing copy instead of blindly posting `filled`.

## Step 9: Test Invite Flow

After the new channels exist:

1. Create a fresh Discord invite.
2. Open it in a browser or alt account.
3. Confirm the first visible channel makes sense.
4. Confirm a new person can find `open-leagues`.
5. Confirm a current owner can find bracket chat.
6. Confirm old channels are not the first thing people see.

## Step 10: Stop Before Adding More

Run the simplified server for one week.

During that week, track:

- what people ask repeatedly
- whether `open-leagues` is easy to maintain
- whether bracket owners use cross-division chat
- whether prospects get lost
- whether automation reduces work or creates noise

Only add more channels after that.

## Later Additions

Only consider these after the first version works:

- format-specific channels
- paid-owner-only channels
- trade block channels
- bot commands
- role self-selection
- weekly scoreboard posts
- automatic Bracket Center updates
- automatic Best Ball Union updates

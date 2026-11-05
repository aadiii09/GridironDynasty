# Gridiron Dynasty (working title)

Roblox football card game: collect player cards, open packs, build a 7v7 lineup, play AI games.

## Folders

| Folder | What's in it | Public? |
|---|---|---|
| `pipeline/` | Python script that pulls weekly NFL stats (nflverse via nflreadpy, CC-BY 4.0) and builds card data | yes |
| `private/` | Real-player to fictional-player mapping, raw downloads | **never committed** (gitignored) |
| `site/` | Output JSON served by GitHub Pages and fetched by Roblox | yes |
| `roblox/` | Luau source backups of the scripts in Studio | yes |
| `art/` | Logos, card frames, UI art | yes |

## IP rules

- No real NFL/league/team names, logos, numbers, likenesses, or EA/Madden branding anywhere in the game or this repo.
- Fictional league, teams and player names only.
- The real-to-fictional mapping lives only in `private/` and is never committed or published.
- `site/` JSON contains fictional IDs only: no real names, no nflverse/gsis player IDs.

Data credit: nflverse (CC-BY 4.0).

## Weekly card updates

`pipeline/weekly_update.ps1` downloads the latest nflverse stats, builds cards for every newly
finished week (all games final and fully loaded: a half-loaded week is never used, since cards
are permanent) and, if anything is new, commits and pushes only `docs/cards.json`. Live servers
pick it up within 30 minutes; no republish needed. It runs on this PC so the private mapping
never leaves it. Log: `private/logs/weekly_update.log`.

- Install the daily 10:00 schedule: `powershell -ExecutionPolicy Bypass -File pipeline\install_weekly_task.ps1`
- Run it now: `Start-ScheduledTask -TaskName "Gridiron Dynasty card update"`
- Remove it: `Unregister-ScheduledTask -TaskName "Gridiron Dynasty card update" -Confirm:$false`
- New season: change the `--season` default in `pipeline/build.py`.

## Badges
Badge milestones live in `roblox/ReplicatedStorage/Shared/BadgeConfig.lua` (first game, first win,
10/50 wins, Elite/Icon pulls, an interception, Gold/Dynasty ranked divisions, the Rainbow jersey).
Each starts with `id = 0` (skipped). To turn one on: Creator Hub -> your experience -> Engagement ->
Badges -> Create, upload `art/out/badge_<key>.png`, then paste the new badge ID into its `id`.
Players who already reached a milestone get the badge the next time they join.

## Invites and settings
- **INVITE** (top bar) opens Roblox's invite prompt. A friend who joins through it on a brand-new save
  gets 500 Coins, and so does the inviter (right away, or the next time they join). Each inviter is
  paid for at most 10 friends.
- **Gear** (top bar): music and sound-effect volume, camera shake, rating callouts and lobby camera
  motion, saved to the player's account. **CONTROLS** (PC) rebinds every game key: click an action,
  then press any key or mouse button (e.g. CATCH -> left click). Actions used at the same moment
  can't share a key, so rebinding onto one swaps the two. Defaults: throw = left click, snap = Space,
  switch = Q, catch = C, jump = Space, juke = Q, spin = R, stiff arm = F, dive = E, block = X.

## Custom 7v7 (friends)
PLAY -> **CUSTOM 7v7**: create a game (or join one in this server), pick HOME or AWAY, one offensive
spot and one defensive spot, and the host presses START. Up to 7 players a team.
- Everyone plays as their own best card at the spot they picked; open spots are AI players around
  the team's average (a team nobody joined is a full CPU team).
- Whoever plays QB calls the offense; otherwise the team's first player (its captain) calls and snaps.
  The captain also calls the defense. Play clocks keep things moving.
- No rewards (no Coins, wins, challenges or leaderboard), so friends can't farm each other.
- After the game everyone is back in the lobby, ready to run it back. Someone who leaves mid-game
  hands their spots back to the AI.
- Code: `CustomService` (lobbies), `MatchService` (stand-in "proxy" units let any player take an NPC's
  spot), `CustomLobbyUI` (the tab and the party pill). In Studio, `Remotes.DevStartCustom` starts a
  test game with a scripted bot ("mate" = on your team, anything else = the other team's QB).

## Practice
PLAY -> **PRACTICE**: a solo playground on the real field with the AI playing everyone else. No Coins,
no record, no play clock, and the drive never ends. Switch drills any time from the list on the left:
- **QB: Passing** - you call the plays and throw.
- **WR: Catching** - the AI QB throws to you every play.
- **RB: Running** - every play is a handoff to you (juke, spin, stiff arm, dive).
- **DB: Coverage** - you're the cornerback on WR1 in man; most throws go at your man.
- **LB: Tackling** - every play is a run at you.
Code: `MatchService` (`PRACTICE` drills on top of the custom-game proxies, `StartPractice`, the
"drill" action), `PracticeUI` (the tab and the in-game drill list).

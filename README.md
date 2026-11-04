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

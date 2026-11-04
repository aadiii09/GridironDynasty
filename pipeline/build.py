"""Gridiron Dynasty card pipeline.

Downloads nflverse data (CC-BY 4.0), rates every qualifying player, maps each one to a
fictional identity, and writes docs/cards.json for GitHub Pages.

Rules this script enforces:
  * Card ratings are FIXED. Cards already in docs/cards.json are never changed;
    each run only ADDS cards (new players' Base cards, new Week Standout cards).
  * The real -> fictional mapping lives only in private/ (gitignored).
  * docs/cards.json contains no real names, IDs, numbers or headshots
    (checked at the end; the script fails instead of writing if it finds any).

Only weeks whose games are all final (and fully loaded in nflverse) are used. When nothing new
has happened since the published cards, nothing is written.

Run:  .venv\\Scripts\\python.exe -I -X utf8 pipeline\\build.py [--season 2026] [--offline]
Weekly automation: pipeline\\weekly_update.ps1
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import polars as pl

sys.path.insert(0, str(Path(__file__).parent))
from names import FIRST, LAST  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PRIVATE = ROOT / "private"
RAW = PRIVATE / "raw"
DOCS = ROOT / "docs"
OUT = DOCS / "cards.json"
PLAYER_MAP = PRIVATE / "players_map.json"
TEAM_MAP = PRIVATE / "team_map.json"
TEAMS = Path(__file__).parent / "teams.json"

BASE_URL = "https://github.com/nflverse/nflverse-data/releases/download"
SCHEDULE_URL = "https://github.com/nflverse/nfldata/raw/master/data/games.csv"

# ---------------------------------------------------------------- positions

POS_MAP = {
    "QB": "QB", "RB": "RB", "HB": "RB", "FB": "RB", "WR": "WR", "TE": "TE",
    "T": "OL", "G": "OL", "C": "OL", "OL": "OL", "LT": "OL", "RT": "OL", "LG": "OL", "RG": "OL", "OT": "OL", "OG": "OL",
    "DE": "DL", "DT": "DL", "NT": "DL", "DL": "DL",
    "OLB": "LB", "ILB": "LB", "MLB": "LB", "LB": "LB",
    "CB": "CB", "NB": "CB", "DB": "CB",
    "S": "S", "FS": "S", "SS": "S",
}
OFFENSE = {"QB", "RB", "WR", "TE", "OL"}
# Football attributes, grouped the way the card detail screen shows them.
ATTR_GROUPS = {
    "Physical": ["SPD", "ACC", "AGI", "STR", "AWR"],
    "Passing": ["THP", "SAC", "MAC", "DAC", "RUN", "TUP"],
    "Ball Carrier": ["CAR", "TRK", "ELU", "BCV", "SFA", "JKM", "SPM"],
    "Receiving": ["CTH", "CIT", "SPC", "SRR", "MRR", "DRR", "RLS"],
    "Blocking": ["PBK", "PBP", "PBF", "RBK", "RBP", "RBF"],
    "Defense": ["TAK", "POW", "BSH", "PMV", "FMV", "PUR", "PRC", "MCV", "ZCV", "PRS"],
}
ATTRS = [a for group in ATTR_GROUPS.values() for a in group]
SWING_SCALE = 1.7  # how strongly real stats separate players of the same OVR
ATTR_SCHEMA = 2  # bump when the attribute list changes; older cards get new attributes, same OVR

# Offset from OVR for each attribute: a per-group default, then per-attribute overrides.
# Attributes within 6 of OVR are the position's core; their average is kept equal to OVR.
_G = ["Physical", "Passing", "Ball Carrier", "Receiving", "Blocking", "Defense"]
_GROUP_OFFSETS = {
    "QB": [-12, 0, -30, -45, -55, -60],
    "RB": [0, -60, 0, -12, -30, -50],
    "WR": [0, -60, -14, 0, -38, -55],
    "TE": [-8, -62, -20, -4, -6, -50],
    "OL": [-30, -65, -55, -60, 0, -45],
    "DL": [-14, -65, -55, -58, -35, 0],
    "LB": [-6, -65, -50, -40, -40, 0],
    "CB": [0, -65, -40, -22, -50, 0],
    "S":  [-3, -65, -45, -24, -45, 0],
}
_OVERRIDES = {
    "QB": dict(AWR=0, SPD=-14, STR=-20, ELU=-22, JKM=-26),
    "RB": dict(STR=-6, AWR=-6, CTH=-8, RLS=-25, PBK=-18),
    "WR": dict(STR=-18, AWR=-6, CAR=-8, ELU=-6, JKM=-6, CIT=-4, SPC=-4),
    "TE": dict(STR=-2, AWR=-4, TRK=-8, SFA=-10, CAR=-10, DRR=-12, RLS=-10, PBF=-10, RBF=-10, SPC=-8),
    "OL": dict(STR=0, AWR=-2, AGI=-18, ACC=-20, POW=-30, BSH=-30),
    "DL": dict(STR=0, AWR=-6, ACC=-8, TAK=-4, POW=-6, PUR=-6, PRC=-6, MCV=-50, ZCV=-45, PRS=-45),
    "LB": dict(STR=-6, AWR=0, POW=-2, BSH=-2, PMV=-12, FMV=-12, MCV=-10, ZCV=-4, PRS=-20),
    "CB": dict(STR=-20, AWR=-4, CTH=-14, TAK=-14, POW=-16, BSH=-30, PMV=-45, FMV=-40, PUR=-6, PRC=-4, PRS=-2),
    "S":  dict(STR=-12, AWR=0, CTH=-16, TAK=-2, POW=-2, BSH=-16, PMV=-30, FMV=-30, MCV=-6, PRS=-12),
}
TEMPLATE = {
    pos: {a: _OVERRIDES[pos].get(a, offs[_G.index(g)]) for g, attrs in ATTR_GROUPS.items() for a in attrs}
    for pos, offs in _GROUP_OFFSETS.items()
}

# How real stats and combine results move each attribute: (feature, swing). A player at the
# top of his position in that feature gets +swing/2, the bottom gets -swing/2.
_PHYS = {
    "SPD": [("forty", 16)], "ACC": [("forty", 8), ("shuttle", 6), ("broad", 4)],
    "AGI": [("cone", 10), ("shuttle", 6)], "STR": [("weight", 10), ("bench", 10)],
    "AWR": [("exp", 14), ("snap_share", 6)],
}
_REC = {
    "CTH": [("catch_rate", 16)], "CIT": [("catch_rate", 6), ("weight", 8), ("re_fdr", 8)],
    "SPC": [("vertical", 10), ("td_tgt", 8), ("re_long", 6)],
    "SRR": [("catch_rate", 8), ("re_short", 10)], "MRR": [("re_epa", 10), ("re_fdr", 8)],
    "DRR": [("re_adot", 12), ("re_long", 8)], "RLS": [("tshare", 12), ("weight", 4)],
    "ELU": [("yac", 12)], "BCV": [("yac", 8), ("re_epa", 4)], "JKM": [("yac", 8), ("cone", 6)],
    "SPM": [("yac", 6), ("shuttle", 6)], "SPD": [("forty", 16), ("re_long", 8), ("yac", 4)],
}
_DEF_BACK = {
    "TAK": [("d_tk", 14)], "POW": [("d_ff", 10), ("weight", 6)], "PUR": [("d_tk", 8), ("forty", 6)],
    "PRC": [("d_int", 8), ("d_tfl", 4), ("exp", 6)], "BSH": [("d_tfl", 10)], "PRS": [("weight", 10), ("d_pd", 6)],
    "CTH": [("d_int", 14)], "SPC": [("d_int", 8), ("vertical", 6)],
}
INFLUENCE = {
    "QB": {
        "THP": [("qb_aya", 12), ("qb_deep", 10)], "SAC": [("qb_cmp", 14), ("qb_cpoe", 6)],
        "MAC": [("qb_cpoe", 12), ("qb_epa", 8)], "DAC": [("qb_deep", 12), ("qb_cpoe", 6), ("qb_intr", 6)],
        "RUN": [("ru_ypg", 12), ("qb_epa", 6)], "TUP": [("qb_sackr", 14), ("qb_epa", 6)],
        "AWR": [("qb_intr", 8), ("qb_epa", 6), ("exp", 10)], "SPD": [("ru_ypg", 14), ("forty", 10)],
        "ACC": [("ru_ypg", 8), ("forty", 6)], "AGI": [("ru_ypg", 8), ("cone", 6)],
        "ELU": [("ru_ypg", 16)], "BCV": [("ru_epa", 10)], "CAR": [("qb_fum", 10)],
    },
    "RB": {
        **_PHYS,
        "CAR": [("ru_fum", 16)], "TRK": [("weight", 14), ("ru_tdc", 6), ("ru_fdr", 6)],
        "ELU": [("ru_long", 12), ("ru_ypc", 8)], "BCV": [("ru_epa", 12), ("ru_fdr", 8)],
        "SFA": [("weight", 12), ("ru_fdr", 6)], "JKM": [("cone", 10), ("ru_long", 8), ("ru_ypc", 4)],
        "SPM": [("ru_ypc", 10), ("shuttle", 6)], "SPD": [("forty", 16), ("ru_long", 6)],
        "CTH": [("catch_rate", 10), ("re_ypg", 8)], "SRR": [("re_ypg", 10)], "MRR": [("re_ypg", 8)],
        "RLS": [("re_ypg", 6)], "PBK": [("weight", 10)], "PBP": [("weight", 8)], "PBF": [("cone", 6)],
    },
    "WR": {**_PHYS, **_REC},
    "TE": {**_PHYS, **_REC, "PBK": [("tshare_inv", 12), ("weight", 8)], "RBK": [("tshare_inv", 12), ("weight", 8)],
           "PBP": [("weight", 10)], "RBP": [("weight", 10), ("bench", 6)], "TRK": [("weight", 10), ("yac", 6)],
           "SFA": [("weight", 8), ("yac", 6)]},
    "OL": {
        **_PHYS,
        "PBK": [("team_pass", 14), ("snap_share", 6)], "PBP": [("weight", 12), ("bench", 6), ("team_pass", 4)],
        "PBF": [("cone", 8), ("shuttle", 6), ("team_pass", 4)], "RBK": [("team_rush", 14), ("snap_share", 6)],
        "RBP": [("weight", 12), ("bench", 6), ("team_rush", 4)], "RBF": [("cone", 8), ("forty", 6), ("team_rush", 4)],
    },
    "DL": {
        **_PHYS,
        "PMV": [("d_sk", 10), ("weight", 10), ("bench", 6)], "FMV": [("d_qbh", 12), ("d_sk", 6), ("forty", 8)],
        "BSH": [("d_tfl", 12), ("weight", 8)], "TAK": [("d_tk", 12)], "POW": [("d_ff", 8), ("weight", 8)],
        "PUR": [("d_tk", 10), ("forty", 6)], "PRC": [("d_tfl", 8), ("exp", 6)],
    },
    "LB": {
        **_PHYS,
        "TAK": [("d_tk", 14)], "POW": [("d_ff", 8), ("weight", 8)], "BSH": [("d_tfl", 10), ("weight", 6)],
        "PMV": [("d_sk", 12), ("weight", 6)], "FMV": [("d_sk", 8), ("d_qbh", 8)], "PUR": [("d_tk", 10), ("forty", 6)],
        "PRC": [("d_tfl", 6), ("d_int", 6), ("exp", 6)], "MCV": [("d_pd", 10), ("forty", 6)],
        "ZCV": [("d_pd", 8), ("d_int", 10)],
    },
    "CB": {**_PHYS, **_DEF_BACK, "MCV": [("d_pd", 12), ("forty", 8)], "ZCV": [("d_int", 14), ("d_pd", 6)]},
    "S":  {**_PHYS, **_DEF_BACK, "MCV": [("d_pd", 10), ("forty", 6)], "ZCV": [("d_int", 12), ("d_pd", 8)],
           "TAK": [("d_tk", 14)], "PUR": [("d_tk", 10), ("forty", 6)], "PRS": [("weight", 8)]},
}

# Archetype = the attribute set where a player stands out most compared with others at his position.
ARCHETYPES = {
    "QB": [("Strong Arm", ["THP", "DAC"]), ("Field General", ["SAC", "MAC", "AWR"]),
           ("Scrambler", ["SPD", "RUN", "ELU"]), ("Improviser", ["TUP", "RUN", "AGI"])],
    "RB": [("Power Back", ["TRK", "SFA", "STR"]), ("Elusive Back", ["ELU", "JKM", "SPM", "AGI"]),
           ("Receiving Back", ["CTH", "SRR", "MRR"]), ("Speed Back", ["SPD", "ACC"])],
    "WR": [("Deep Threat", ["SPD", "DRR"]), ("Route Runner", ["SRR", "MRR", "RLS"]),
           ("Physical", ["CIT", "SPC", "STR"]), ("Slot", ["AGI", "ACC", "ELU"])],
    "TE": [("Vertical Threat", ["SPD", "DRR", "SPC"]), ("Possession", ["CTH", "CIT", "SRR"]),
           ("Blocking", ["RBK", "PBK", "STR"])],
    "OL": [("Pass Protector", ["PBK", "PBF"]), ("Power", ["RBP", "PBP", "STR"]), ("Agile", ["RBF", "PBF", "AGI"])],
    "DL": [("Power Rusher", ["PMV", "STR"]), ("Speed Rusher", ["FMV", "SPD", "ACC"]), ("Run Stopper", ["BSH", "TAK"])],
    "LB": [("Field General", ["PRC", "AWR", "ZCV"]), ("Pass Coverage", ["MCV", "ZCV", "SPD"]),
           ("Run Stopper", ["TAK", "BSH", "PUR"]), ("Power Rusher", ["PMV", "FMV"])],
    "CB": [("Man to Man", ["MCV", "PRS", "SPD"]), ("Zone", ["ZCV", "PRC"]), ("Slot", ["AGI", "ACC", "MCV"])],
    "S":  [("Zone", ["ZCV", "PRC", "SPD"]), ("Run Support", ["TAK", "POW", "PUR"]), ("Hybrid", ["MCV", "BSH", "AWR"])],
}
JERSEY_RANGES = {
    "QB": [(1, 19)], "RB": [(0, 49)], "WR": [(0, 19), (80, 89)], "TE": [(80, 89), (40, 49)],
    "OL": [(50, 79)], "DL": [(90, 99), (50, 79)], "LB": [(40, 59), (90, 99)], "CB": [(0, 49)], "S": [(0, 49)],
}

TIERS = [(92, "Icon"), (87, "Elite"), (80, "Epic"), (70, "Rare"), (0, "Common")]


def tier_for(ovr: int) -> str:
    return next(name for floor, name in TIERS if ovr >= floor)


# ---------------------------------------------------------------- data

def fetch(name: str, url: str, offline: bool) -> Path:
    RAW.mkdir(parents=True, exist_ok=True)
    dest = RAW / name
    if offline and dest.exists():
        return dest
    print(f"  downloading {name}")
    req = urllib.request.Request(url, headers={"User-Agent": "gridiron-dynasty-pipeline"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        dest.write_bytes(resp.read())
    return dest


def load(season: int, offline: bool):
    read = lambda p: pl.read_csv(p, infer_schema_length=10000, null_values=["NA", ""])
    stats = read(fetch(f"stats_player_week_{season}.csv", f"{BASE_URL}/stats_player/stats_player_week_{season}.csv", offline))
    roster = read(fetch(f"roster_weekly_{season}.csv", f"{BASE_URL}/weekly_rosters/roster_weekly_{season}.csv", offline))
    snaps = read(fetch(f"snap_counts_{season}.csv", f"{BASE_URL}/snap_counts/snap_counts_{season}.csv", offline))
    combine = read(fetch("combine.csv", f"{BASE_URL}/combine/combine.csv", offline))
    games = read(fetch("games.csv", SCHEDULE_URL, offline))
    return stats, roster, snaps, combine, games


def last_complete_week(season: int, games, stats, snaps) -> int:
    """The latest regular-season week whose games are ALL final and whose box scores and snap
    counts are in for every team that played. Cards are permanent, so a half-loaded week (e.g.
    Sunday's games in but not Monday night's) must never be used."""
    g = games.filter((pl.col("season") == season) & (pl.col("game_type") == "REG"))
    done = 0
    for week in sorted(g["week"].unique().to_list()):
        wk = g.filter(pl.col("week") == week)
        if wk["home_score"].null_count() > 0 or wk["away_score"].null_count() > 0:
            break
        played = set(wk["home_team"].to_list()) | set(wk["away_team"].to_list())
        in_stats = set(stats.filter((pl.col("week") == week) & (pl.col("season_type") == "REG"))["team"].drop_nulls().to_list())
        in_snaps = set(snaps.filter((pl.col("week") == week) & (pl.col("game_type") == "REG"))["team"].drop_nulls().to_list())
        missing = (played - in_stats) | (played - in_snaps)
        if missing:
            print(f"  week {week}: games are final but data is still loading for {len(missing)} teams")
            break
        done = week
    return done


# ---------------------------------------------------------------- rating helpers

def pct_rank(col: str, desc: bool = True) -> pl.Expr:
    """Percentile 0..1 within the current position group (1 = best)."""
    e = pl.col(col).fill_null(pl.col(col).median().over("grp"))
    r = e.rank("average", descending=not desc).over("grp")
    n = pl.len().over("grp")
    return ((r - 1) / (n - 1).clip(lower_bound=1)).alias(col + "_p")


# Score percentile within position -> OVR. Base cards top out at 96; Week Standouts can reach 99.
OVR_CURVE = [(0.0, 58), (0.5, 68), (0.75, 76), (0.88, 83), (0.95, 88), (0.98, 92), (1.0, 96)]


def ovr_from_pct(p: float) -> int:
    p = max(0.0, min(1.0, p))
    for (p0, o0), (p1, o1) in zip(OVR_CURVE, OVR_CURVE[1:]):
        if p <= p1:
            return int(round(o0 + (o1 - o0) * (p - p0) / (p1 - p0)))
    return OVR_CURVE[-1][1]


def clamp(v: float, lo: int = 25, hi: int = 99) -> int:
    return int(max(lo, min(hi, round(v))))


# ---------------------------------------------------------------- main build

def build_pool(stats, roster, snaps, combine, team_map):
    week = int(stats["week"].max())
    latest = roster.filter((pl.col("week") == roster["week"].max()) & (pl.col("status") == "ACT"))
    latest = latest.with_columns(
        pl.col("depth_chart_position").fill_null(pl.col("position")).replace_strict(POS_MAP, default=None).alias("grp")
    ).filter(pl.col("grp").is_not_null() & pl.col("team").is_in(list(team_map)))

    # snap share (join by pfr id, fall back to name + team)
    snap_agg = (
        snaps.filter(pl.col("game_type") == "REG")
        .with_columns(pl.max_horizontal(pl.col("offense_pct").fill_null(0), pl.col("defense_pct").fill_null(0)).alias("share"))
        .group_by(["pfr_player_id", "player", "team"])
        .agg(pl.col("share").mean().alias("snap_share"), pl.len().alias("snap_games"))
    )
    by_id = snap_agg.group_by("pfr_player_id").agg(pl.col("snap_share").max(), pl.col("snap_games").sum())
    by_name = snap_agg.select(pl.col("player").alias("full_name"), "team", pl.col("snap_share").alias("ss2"), pl.col("snap_games").alias("sg2"))
    latest = (
        latest.join(by_id, left_on="pfr_id", right_on="pfr_player_id", how="left")
        .join(by_name, on=["full_name", "team"], how="left")
        .with_columns(
            pl.coalesce("snap_share", "ss2").fill_null(0).alias("snap_share"),
            pl.coalesce("snap_games", "sg2").fill_null(0).alias("snap_games"),
        )
        .drop("ss2", "sg2")
        .unique("gsis_id")
    )

    # season production totals (REG)
    reg = stats.filter(pl.col("season_type") == "REG")
    num = [c for c, t in zip(reg.columns, reg.dtypes) if t.is_numeric() and c not in ("season", "week")]
    tot = reg.group_by("player_id").agg([pl.col(c).fill_null(0).sum() for c in num] + [pl.len().alias("games")])
    df = latest.join(tot, left_on="gsis_id", right_on="player_id", how="left").with_columns(
        pl.col("games").fill_null(0)
    )
    for c in num:
        df = df.with_columns(pl.col(c).fill_null(0))

    # team blocking quality (no individual OL stats exist): low sack rate + good rushing EPA
    team_ol = (
        reg.group_by("team")
        .agg(
            (pl.col("sacks_suffered").fill_null(0).sum() / (pl.col("attempts").fill_null(0).sum() + pl.col("sacks_suffered").fill_null(0).sum())).alias("sack_rate"),
            (pl.col("rushing_epa").fill_null(0).sum() / pl.col("carries").fill_null(0).sum()).alias("team_rush_epa"),
        )
        .with_columns(
            ((-pl.col("sack_rate")).rank() / pl.len() * 0.5 + pl.col("team_rush_epa").rank() / pl.len() * 0.5).alias("team_ol"),
            (-pl.col("sack_rate")).alias("team_pass"),
            pl.col("team_rush_epa").alias("team_rush"),
        )
        .select("team", "team_ol", "team_pass", "team_rush")
    )
    df = df.join(team_ol, on="team", how="left")

    # combine testing (speed, quickness, strength, leaping)
    drills = ["forty", "cone", "shuttle", "bench", "vertical", "broad_jump"]
    comb = combine.filter(pl.col("pfr_id").is_not_null()).select(["pfr_id"] + drills).unique("pfr_id")
    df = df.join(comb, on="pfr_id", how="left").rename({"broad_jump": "broad"})

    # qualification: real role on the field
    g = pl.col("games").clip(lower_bound=1)
    df = df.filter((pl.col("snap_games") >= 2) & (pl.col("snap_share") >= 0.25))

    df = df.with_columns(
        # per-game / efficiency production features
        (pl.col("passing_epa") / pl.col("attempts").clip(lower_bound=1)).alias("qb_epa"),
        (pl.col("passing_yards") / g).alias("qb_ypg"),
        (pl.col("passing_tds") / g).alias("qb_tdpg"),
        (pl.col("passing_interceptions") / pl.col("attempts").clip(lower_bound=1)).alias("qb_intr"),
        (pl.col("passing_air_yards") / pl.col("attempts").clip(lower_bound=1)).alias("qb_aya"),
        (pl.col("completions") / pl.col("attempts").clip(lower_bound=1)).alias("qb_cmp"),
        (pl.col("rushing_yards") / g).alias("ru_ypg"),
        (pl.col("rushing_epa") / pl.col("carries").clip(lower_bound=1)).alias("ru_epa"),
        ((pl.col("rushing_tds") + pl.col("receiving_tds")) / g).alias("td_pg"),
        (pl.col("receiving_yards") / g).alias("re_ypg"),
        (pl.col("receiving_epa") / pl.col("targets").clip(lower_bound=1)).alias("re_epa"),
        (pl.col("receptions") / pl.col("targets").clip(lower_bound=1)).alias("catch_rate"),
        (pl.col("target_share") / g).alias("tshare"),
        (pl.col("receiving_yards_after_catch") / pl.col("receptions").clip(lower_bound=1)).alias("yac"),
        (pl.col("def_sacks") / g).alias("d_sk"),
        (pl.col("def_qb_hits") / g).alias("d_qbh"),
        (pl.col("def_tackles_for_loss") / g).alias("d_tfl"),
        ((pl.col("def_tackles_solo") + 0.5 * pl.col("def_tackle_assists")) / g).alias("d_tk"),
        (pl.col("def_pass_defended") / g).alias("d_pd"),
        (pl.col("def_interceptions") / g).alias("d_int"),
        (pl.col("def_fumbles_forced") / g).alias("d_ff"),
        pl.col("draft_number").cast(pl.Float64).fill_null(300.0).alias("pick"),
        # extra detail for position attributes
        (pl.col("passing_cpoe")).alias("qb_cpoe"),
        (pl.col("passing_20") / pl.col("attempts").clip(lower_bound=1)).alias("qb_deep"),
        (pl.col("sacks_suffered") / (pl.col("attempts") + pl.col("sacks_suffered")).clip(lower_bound=1)).alias("qb_sackr"),
        ((pl.col("sack_fumbles") + pl.col("rushing_fumbles")) / (pl.col("attempts") + pl.col("carries")).clip(lower_bound=1)).alias("qb_fum"),
        (pl.col("rushing_yards") / pl.col("carries").clip(lower_bound=1)).alias("ru_ypc"),
        (pl.col("rushing_20") / pl.col("carries").clip(lower_bound=1)).alias("ru_long"),
        (pl.col("rushing_first_downs") / pl.col("carries").clip(lower_bound=1)).alias("ru_fdr"),
        (pl.col("rushing_tds") / pl.col("carries").clip(lower_bound=1)).alias("ru_tdc"),
        ((pl.col("rushing_fumbles") + pl.col("receiving_fumbles")) / (pl.col("carries") + pl.col("receptions")).clip(lower_bound=1)).alias("ru_fum"),
        (pl.col("receiving_air_yards") / pl.col("targets").clip(lower_bound=1)).alias("re_adot"),
        (-pl.col("receiving_air_yards") / pl.col("targets").clip(lower_bound=1)).alias("re_short"),
        (pl.col("receiving_20") / pl.col("receptions").clip(lower_bound=1)).alias("re_long"),
        (pl.col("receiving_first_downs") / pl.col("targets").clip(lower_bound=1)).alias("re_fdr"),
        (pl.col("receiving_tds") / pl.col("targets").clip(lower_bound=1)).alias("td_tgt"),
        (-pl.col("target_share") / g).alias("tshare_inv"),
        pl.col("years_exp").cast(pl.Float64).alias("exp"),
    )

    feats = ["qb_epa", "qb_ypg", "qb_tdpg", "qb_intr", "qb_aya", "qb_cmp", "ru_ypg", "ru_epa", "td_pg", "re_ypg",
             "re_epa", "catch_rate", "tshare", "yac", "d_sk", "d_qbh", "d_tfl", "d_tk", "d_pd", "d_int", "d_ff",
             "snap_share", "weight", "forty", "team_ol",
             "qb_cpoe", "qb_deep", "qb_sackr", "qb_fum", "ru_ypc", "ru_long", "ru_fdr", "ru_tdc", "ru_fum",
             "re_adot", "re_short", "re_long", "re_fdr", "td_tgt", "tshare_inv", "exp", "team_pass", "team_rush",
             "cone", "shuttle", "bench", "vertical", "broad"]
    lower_better = {"qb_intr", "forty", "cone", "shuttle", "qb_sackr", "qb_fum", "ru_fum"}
    df = df.with_columns([pct_rank(f, desc=f not in lower_better) for f in feats] + [pct_rank("pick", desc=False)])

    P = lambda c: pl.col(c + "_p")
    prod = (
        pl.when(pl.col("grp") == "QB").then(0.35 * P("qb_epa") + 0.25 * P("qb_ypg") + 0.2 * P("qb_tdpg") + 0.1 * P("qb_intr") + 0.1 * P("ru_ypg"))
        .when(pl.col("grp") == "RB").then(0.4 * P("ru_ypg") + 0.2 * P("ru_epa") + 0.2 * P("td_pg") + 0.2 * P("re_ypg"))
        .when(pl.col("grp").is_in(["WR", "TE"])).then(0.4 * P("re_ypg") + 0.2 * P("re_epa") + 0.2 * P("td_pg") + 0.2 * P("tshare"))
        .when(pl.col("grp") == "DL").then(0.4 * P("d_sk") + 0.25 * P("d_qbh") + 0.2 * P("d_tfl") + 0.15 * P("d_tk"))
        .when(pl.col("grp") == "LB").then(0.4 * P("d_tk") + 0.2 * P("d_tfl") + 0.15 * P("d_sk") + 0.15 * P("d_pd") + 0.1 * P("d_int"))
        .when(pl.col("grp").is_in(["CB", "S"])).then(0.35 * P("d_pd") + 0.3 * P("d_int") + 0.25 * P("d_tk") + 0.1 * P("d_ff"))
        .otherwise(pl.lit(0.5))
    )
    score = (
        pl.when(pl.col("grp") == "OL").then(0.45 * P("team_ol") + 0.4 * P("snap_share") + 0.15 * P("pick"))
        .otherwise(0.65 * prod + 0.25 * P("snap_share") + 0.10 * P("pick"))
    )
    df = df.with_columns(score.alias("score"))
    df = df.with_columns(pct_rank("score"))
    return df, week


def make_attrs(row: dict, ovr: int, seed: str) -> dict:
    """Every attribute = OVR + position template + what this player's real stats and combine
    results say about it + a little noise. Core attributes are then re-centred on OVR, so the
    OVR stays honest while players of the same OVR still play very differently."""
    grp = row["grp"]
    rng = random.Random(seed)
    tpl = TEMPLATE[grp]
    p = lambda c: (row.get(c + "_p") if row.get(c + "_p") is not None else 0.5) - 0.5  # -0.5..0.5
    a = {}
    for k in ATTRS:
        v = ovr + tpl[k] + rng.uniform(-3, 3)
        for feat, swing in INFLUENCE[grp].get(k, []):
            v += p(feat) * swing * SWING_SCALE
        a[k] = v
    # OL have no individual box-score stats: give each a personal strength in pass or run blocking
    if grp == "OL":
        lean = rng.uniform(-5, 5)
        for k in ("PBK", "PBP", "PBF"):
            a[k] += lean
        for k in ("RBK", "RBP", "RBF"):
            a[k] -= lean
    core = [k for k, off in tpl.items() if off >= -6]
    drift = ovr - sum(a[k] for k in core) / len(core)
    return {k: clamp(v + drift if k in core else v) for k, v in a.items()}


def assign_archetypes(cards: list[dict]):
    """Archetype = the attribute set where this player stands out most compared with others at
    the same position (percentile of mean(attrs) - OVR), so labels vary within a position."""
    by_pos: dict[str, list[dict]] = {}
    for c in cards:
        by_pos.setdefault(c["pos"], []).append(c)
    for pos, group in by_pos.items():
        score = {}
        for label, keys in ARCHETYPES[pos]:
            devs = [sum(c["attrs"][k] for k in keys) / len(keys) - c["ovr"] for c in group]
            order = sorted(range(len(group)), key=lambda i: devs[i])
            n = max(1, len(group) - 1)
            for rank, i in enumerate(order):
                score[(label, group[i]["id"])] = rank / n
        for c in group:
            c["archetype"] = max(ARCHETYPES[pos], key=lambda x: score[(x[0], c["id"])])[0]


def standout_attrs(base: dict, boost: int) -> dict:
    """A Week Standout card lifts the player's real skills (anything near his OVR) by the boost."""
    return {k: (min(99, v + boost) if v >= base["ovr"] - 12 else v) for k, v in base["attrs"].items()}


def week_scores(stats: pl.DataFrame) -> pl.DataFrame:
    s = stats.filter(pl.col("season_type") == "REG").fill_null(0)
    return s.with_columns(
        pl.when(pl.col("position_group").is_in(["QB", "RB", "WR", "TE"]))
        .then(pl.col("fantasy_points_ppr"))
        .otherwise(
            6 * pl.col("def_sacks") + 7 * pl.col("def_interceptions") + 2.5 * pl.col("def_pass_defended")
            + pl.col("def_tackles_solo") + 0.5 * pl.col("def_tackle_assists") + 2 * pl.col("def_tackles_for_loss")
            + 4 * pl.col("def_fumbles_forced") + 6 * pl.col("def_tds")
        ).alias("gscore"),
        pl.col("position_group").is_in(["QB", "RB", "WR", "TE"]).alias("is_off"),
    ).select("player_id", "week", "gscore", "is_off")


# ---------------------------------------------------------------- identities

def assign_identity(gid: str, grp: str, team: str, real_num, real_names: set, pmap: dict, used_names: set, used_nums: dict):
    if gid in pmap:
        return pmap[gid]
    rng = random.SystemRandom()  # truly random: not reproducible from public code
    for _ in range(500):
        first, last = rng.choice(FIRST), rng.choice(LAST)
        full = f"{first} {last}"
        if full.lower() not in real_names and full not in used_names:
            break
    used_names.add(full)
    taken = used_nums.setdefault(team, set())
    nums = [n for lo, hi in JERSEY_RANGES[grp] for n in range(lo, hi + 1) if n not in taken and n != real_num]
    num = rng.choice(nums) if nums else rng.randint(0, 99)
    taken.add(num)
    pid = "P" + hashlib.sha1(f"{rng.random()}{gid}".encode()).hexdigest()[:8].upper()
    pmap[gid] = {"pid": pid, "first": first, "last": last, "number": num, "team": team, "pos": grp}
    return pmap[gid]


# ---------------------------------------------------------------- output safety

def check_no_real_data(text: str, roster: pl.DataFrame):
    problems = []
    if re.search(r"00-00\d{5}", text):
        problems.append("real gsis ids")
    if "headshot" in text or "static.www.nfl.com" in text:
        problems.append("headshot urls")
    lowered = text.lower()
    for name in roster["full_name"].drop_nulls().unique().to_list():
        if len(name) > 6 and f'"{name.lower()}"' in lowered:
            problems.append(f"real name: {name}")
            break
    for word in ("nfl", "madden", "ea sports"):
        if re.search(rf"\b{word}\b", lowered):
            problems.append(f"branding: {word}")
    if problems:
        raise SystemExit("REFUSING TO WRITE OUTPUT - found " + ", ".join(problems))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--season", type=int, default=2026)
    ap.add_argument("--offline", action="store_true", help="reuse files in private/raw")
    args = ap.parse_args()

    team_map = json.loads(TEAM_MAP.read_text())
    team_map.pop("_note", None)
    league = json.loads(TEAMS.read_text())
    pmap = json.loads(PLAYER_MAP.read_text()) if PLAYER_MAP.exists() else {}
    existing = json.loads(OUT.read_text()) if OUT.exists() else None

    print("Loading nflverse data...")
    stats, roster, snaps, combine, games = load(args.season, args.offline)
    through = last_complete_week(args.season, games, stats, snaps)
    if through == 0:
        raise SystemExit("No completed weeks yet - nothing to build.")
    # only use finished weeks
    stats = stats.filter(pl.col("week") <= through)
    snaps = snaps.filter(pl.col("week") <= through)
    roster = roster.filter(pl.col("week") <= through)
    pool, week = build_pool(stats, roster, snaps, combine, team_map)
    print(f"  season {args.season}, through week {week}, {pool.height} qualifying players")

    real_names = {n.lower() for n in roster["full_name"].drop_nulls().unique().to_list()}
    used_names = {f"{v['first']} {v['last']}" for v in pmap.values()}
    used_nums: dict = {}
    for v in pmap.values():
        used_nums.setdefault(v["team"], set()).add(v["number"])

    players = dict(existing["players"]) if existing else {}
    cards = {c["id"]: c for c in existing["cards"]} if existing else {}
    base_by_gid = {}
    new_base: list[dict] = []
    rows_by_pid: dict = {}
    rebuilt_extra: list[dict] = []
    upgrade = bool(existing) and existing.get("attrSchema", 1) < ATTR_SCHEMA
    added = 0

    for row in pool.sort("score", descending=True).iter_rows(named=True):
        gid, grp = row["gsis_id"], row["grp"]
        team = team_map[row["team"]]
        ident = assign_identity(gid, grp, team, row.get("jersey_number"), real_names, pmap, used_names, used_nums)
        pid = ident["pid"]
        players.setdefault(pid, {"first": ident["first"], "last": ident["last"], "pos": ident["pos"],
                                 "team": ident["team"], "number": ident["number"]})
        cid = f"{pid}-BASE"
        if cid not in cards:  # fixed ratings: never overwrite an existing card
            ovr = ovr_from_pct(row["score_p"])
            attrs = make_attrs(row, ovr, cid)
            cards[cid] = {"id": cid, "pid": pid, "program": "Base", "week": 0, "ovr": ovr, "tier": tier_for(ovr),
                          "pos": grp, "team": team, "archetype": None, "attrs": attrs}
            new_base.append(cards[cid])
            added += 1
        elif upgrade:  # same OVR, new attribute list
            cards[cid]["attrs"] = make_attrs(row, cards[cid]["ovr"], cid)
            new_base.append(cards[cid])
        base_by_gid[gid] = cards[cid]
        rows_by_pid[pid] = row
    if upgrade:
        # base cards whose player no longer qualifies: rebuild from the position template alone
        for c in cards.values():
            if c["program"] == "Base" and c["pid"] not in rows_by_pid:
                c["attrs"] = make_attrs({"grp": c["pos"]}, c["ovr"], c["id"])
                new_base.append(c)
        base_by_pid = {c["pid"]: c for c in cards.values() if c["program"] == "Base"}
        for c in cards.values():
            if c["program"] != "Base":
                base = base_by_pid[c["pid"]]
                c["attrs"] = standout_attrs(base, c["ovr"] - base["ovr"])
                c["archetype"] = None
                rebuilt_extra.append(c)
        print(f"  attribute list upgraded to schema {ATTR_SCHEMA}: {len(new_base) + len(rebuilt_extra)} cards rebuilt (OVRs unchanged)")
    assign_archetypes(new_base)
    if upgrade:
        for c in rebuilt_extra:
            c["archetype"] = base_by_pid[c["pid"]]["archetype"]

    # Week Standout cards: top offensive and defensive performers of each completed week
    ws = week_scores(stats).filter(pl.col("player_id").is_in(list(base_by_gid)))
    for w in sorted(ws["week"].unique().to_list()):
        wk = ws.filter(pl.col("week") == w)
        picks = (wk.filter(pl.col("is_off")).sort("gscore", descending=True).head(8).to_dicts()
                 + wk.filter(~pl.col("is_off")).sort("gscore", descending=True).head(6).to_dicts())
        for rank, r in enumerate(picks):
            base = base_by_gid[r["player_id"]]
            cid = f"{base['pid']}-WK{w}"
            if cid in cards:
                continue
            # picks: 0-7 offense, 8-13 defense. Top 2 offense + top defender get the biggest boost.
            boost = 5 if rank in (0, 1, 8) else 3 if rank < 5 or rank in (9, 10) else 2
            ovr = min(99, base["ovr"] + boost)
            attrs = standout_attrs(base, boost)
            cards[cid] = {"id": cid, "pid": base["pid"], "program": "Week Standout", "week": w, "ovr": ovr,
                          "tier": tier_for(ovr), "pos": base["pos"], "team": base["team"],
                          "archetype": base["archetype"], "attrs": attrs}
            added += 1

    if existing and added == 0 and not upgrade and existing.get("week") == week:
        print(f"  no changes: data is through week {week}, same as the published cards (version {existing['version']})")
        print("RESULT unchanged")
        return

    out = {
        "version": (existing["version"] + 1) if existing else 1,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "season": args.season,
        "week": week,
        "league": league["league"],
        "teams": league["teams"],
        "tiers": [{"name": n, "min": m} for m, n in TIERS],
        "attrs": ATTRS,
        "attrGroups": ATTR_GROUPS,
        "attrSchema": ATTR_SCHEMA,
        "players": players,
        "cards": sorted(cards.values(), key=lambda c: (-c["ovr"], c["id"])),
        "credits": "Statistics derived from nflverse data (CC-BY 4.0). All names, teams and logos are fictional.",
    }
    text = json.dumps(out, separators=(",", ":"))
    check_no_real_data(text, roster)

    PRIVATE.mkdir(exist_ok=True)
    PLAYER_MAP.write_text(json.dumps(pmap, indent=1))
    DOCS.mkdir(exist_ok=True)
    OUT.write_text(text)

    tiers = {}
    for c in cards.values():
        tiers[c["tier"]] = tiers.get(c["tier"], 0) + 1
    print(f"  wrote {OUT.relative_to(ROOT)}: {len(players)} players, {len(cards)} cards ({added} new), "
          f"{len(text) // 1024} KB, version {out['version']}")
    print("  tiers:", ", ".join(f"{t}={tiers.get(t, 0)}" for _, t in TIERS))
    print(f"RESULT updated week={week} version={out['version']} added={added}")


if __name__ == "__main__":
    main()

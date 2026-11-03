"""Gridiron Dynasty card pipeline.

Downloads nflverse data (CC-BY 4.0), rates every qualifying player, maps each one to a
fictional identity, and writes docs/cards.json for GitHub Pages.

Rules this script enforces:
  * Card ratings are FIXED. Cards already in docs/cards.json are never changed;
    each run only ADDS cards (new players' Base cards, new Week Standout cards).
  * The real -> fictional mapping lives only in private/ (gitignored).
  * docs/cards.json contains no real names, IDs, numbers or headshots
    (checked at the end; the script fails instead of writing if it finds any).

Run:  .venv\\Scripts\\python.exe -I -X utf8 pipeline\\build.py [--season 2026] [--offline]
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
ATTRS = ["SPD", "AGI", "STR", "CTH", "CAR", "THP", "THA", "BLK", "TAK", "COV", "PRS"]

# Attribute offsets from OVR for each position (key attributes near 0, off-role very negative).
TEMPLATE = {
    "QB": dict(SPD=-14, AGI=-10, STR=-20, CTH=-40, CAR=-18, THP=0, THA=0, BLK=-50, TAK=-55, COV=-60, PRS=-60),
    "RB": dict(SPD=0, AGI=0, STR=-6, CTH=-10, CAR=0, THP=-50, THA=-55, BLK=-22, TAK=-45, COV=-55, PRS=-55),
    "WR": dict(SPD=0, AGI=-1, STR=-18, CTH=0, CAR=-10, THP=-50, THA=-55, BLK=-30, TAK=-50, COV=-45, PRS=-60),
    "TE": dict(SPD=-10, AGI=-10, STR=-4, CTH=-3, CAR=-12, THP=-55, THA=-60, BLK=-6, TAK=-45, COV=-55, PRS=-50),
    "OL": dict(SPD=-35, AGI=-20, STR=0, CTH=-60, CAR=-60, THP=-65, THA=-65, BLK=0, TAK=-45, COV=-65, PRS=-40),
    "DL": dict(SPD=-16, AGI=-12, STR=0, CTH=-55, CAR=-60, THP=-65, THA=-65, BLK=-35, TAK=-4, COV=-45, PRS=0),
    "LB": dict(SPD=-8, AGI=-8, STR=-6, CTH=-35, CAR=-55, THP=-65, THA=-65, BLK=-40, TAK=0, COV=-8, PRS=-8),
    "CB": dict(SPD=0, AGI=0, STR=-22, CTH=-18, CAR=-45, THP=-65, THA=-65, BLK=-50, TAK=-14, COV=0, PRS=-45),
    "S":  dict(SPD=-3, AGI=-4, STR=-14, CTH=-20, CAR=-50, THP=-65, THA=-65, BLK=-45, TAK=-3, COV=-2, PRS=-30),
}
# Archetype = the label of whichever key attribute beats its template by the most.
ARCHETYPES = {
    "QB": [("THP", "Gunslinger"), ("THA", "Field General"), ("SPD", "Dual Threat")],
    "RB": [("SPD", "Breakaway Back"), ("STR", "Power Back"), ("CTH", "Receiving Back"), ("AGI", "Elusive Back")],
    "WR": [("SPD", "Deep Threat"), ("CTH", "Possession Receiver"), ("AGI", "Elite Route Runner")],
    "TE": [("CTH", "Vertical Threat"), ("BLK", "Blocking TE"), ("STR", "Hybrid TE")],
    "OL": [("STR", "Road Grader"), ("AGI", "Pass Protector"), ("BLK", "Anchor")],
    "DL": [("PRS", "Pass Rusher"), ("STR", "Run Stopper"), ("SPD", "Speed Rusher")],
    "LB": [("TAK", "Thumper"), ("COV", "Coverage Backer"), ("PRS", "Blitzer")],
    "CB": [("COV", "Lockdown Corner"), ("SPD", "Ballhawk"), ("TAK", "Physical Corner")],
    "S":  [("TAK", "Enforcer"), ("COV", "Center Fielder"), ("SPD", "Hybrid Safety")],
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
    return stats, roster, snaps, combine


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
            ((-pl.col("sack_rate")).rank() / pl.len() * 0.5 + pl.col("team_rush_epa").rank() / pl.len() * 0.5).alias("team_ol")
        )
        .select("team", "team_ol")
    )
    df = df.join(team_ol, on="team", how="left")

    # combine forty (speed hint)
    forty = combine.filter(pl.col("forty").is_not_null()).select(pl.col("pfr_id"), pl.col("forty")).unique("pfr_id")
    df = df.join(forty, on="pfr_id", how="left")

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
    )

    feats = ["qb_epa", "qb_ypg", "qb_tdpg", "qb_intr", "qb_aya", "qb_cmp", "ru_ypg", "ru_epa", "td_pg", "re_ypg",
             "re_epa", "catch_rate", "tshare", "yac", "d_sk", "d_qbh", "d_tfl", "d_tk", "d_pd", "d_int", "d_ff",
             "snap_share", "weight", "forty", "team_ol"]
    lower_better = {"qb_intr", "forty"}
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
    grp = row["grp"]
    rng = random.Random(seed)
    tpl = TEMPLATE[grp]
    a = {k: ovr + tpl[k] + rng.uniform(-3, 3) for k in ATTRS}
    p = lambda c: (row.get(c + "_p") if row.get(c + "_p") is not None else 0.5) - 0.5  # -0.5..0.5

    if row.get("forty") is not None:
        a["SPD"] += p("forty") * 14
        a["AGI"] += p("forty") * 6
    a["STR"] += p("weight") * 12
    if grp == "QB":
        a["THP"] += p("qb_aya") * 10
        a["THA"] += p("qb_cmp") * 10 + p("qb_epa") * 4
        a["SPD"] += p("ru_ypg") * 16
    elif grp == "RB":
        a["CAR"] += p("ru_epa") * 8
        a["CTH"] += p("re_ypg") * 14
        a["AGI"] += p("ru_epa") * 6
    elif grp in ("WR", "TE"):
        a["CTH"] += p("catch_rate") * 12
        a["AGI"] += p("re_epa") * 6
        a["SPD"] += p("yac") * 6
        if grp == "TE":
            a["BLK"] += -p("tshare") * 12
    elif grp == "DL":
        a["PRS"] += p("d_sk") * 10
        a["TAK"] += p("d_tk") * 8
    elif grp == "LB":
        a["TAK"] += p("d_tk") * 10
        a["COV"] += p("d_pd") * 12
        a["PRS"] += p("d_sk") * 14
    elif grp in ("CB", "S"):
        a["COV"] += p("d_pd") * 10 + p("d_int") * 6
        a["TAK"] += p("d_tk") * 12
    out = {k: clamp(v) for k, v in a.items()}

    # keep OVR honest: average of the position's key attributes should sit near OVR
    keys = [k for k, off in tpl.items() if off >= -10]
    drift = ovr - sum(out[k] for k in keys) / len(keys)
    for k in keys:
        out[k] = clamp(out[k] + drift)
    return out


def assign_archetypes(new_cards: list[dict]):
    """Archetype = the candidate attribute where this player stands out most compared with
    others at the same position (percentile of attr - OVR), so labels vary within a position."""
    by_pos: dict[str, list[dict]] = {}
    for c in new_cards:
        by_pos.setdefault(c["pos"], []).append(c)
    for pos, group in by_pos.items():
        pct = {}
        for attr, _ in ARCHETYPES[pos]:
            devs = sorted(c["attrs"][attr] - c["ovr"] for c in group)
            n = max(1, len(devs) - 1)
            pct[attr] = {d: i / n for i, d in enumerate(devs)}  # last index wins on ties
        for c in group:
            attr, label = max(ARCHETYPES[pos], key=lambda x: pct[x[0]][c["attrs"][x[0]] - c["ovr"]])
            c["archetype"] = label


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
    stats, roster, snaps, combine = load(args.season, args.offline)
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
        base_by_gid[gid] = cards[cid]
    assign_archetypes(new_base)

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
            attrs = {k: (min(99, v + boost) if v >= base["ovr"] - 12 else v) for k, v in base["attrs"].items()}
            cards[cid] = {"id": cid, "pid": base["pid"], "program": "Week Standout", "week": w, "ovr": ovr,
                          "tier": tier_for(ovr), "pos": base["pos"], "team": base["team"],
                          "archetype": base["archetype"], "attrs": attrs}
            added += 1

    out = {
        "version": (existing["version"] + 1) if existing else 1,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "season": args.season,
        "week": week,
        "league": league["league"],
        "teams": league["teams"],
        "tiers": [{"name": n, "min": m} for m, n in TIERS],
        "attrs": ATTRS,
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


if __name__ == "__main__":
    main()

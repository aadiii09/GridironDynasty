-- Daily and weekly challenges. Everyone gets the same 3 dailies each UTC day and the same 3
-- weeklies each week (Monday 00:00 UTC), picked from these pools by the date.
--
-- stat: what counts. Match stats are counted when a game finishes (a game you quit doesn't
-- count): games, wins, winsPro (Pro or harder), winsAllPro (All-Pro or harder), td, passTd,
-- rushTd, yards (your offense), sacks, ints, fumbles (forced), stops (tackles by your
-- defense), broken (tackles you break), shutouts. Other: packs (packs opened).
-- reward: { coins = n } or { pack = packId } (a free pack, opened on the spot).

local ChallengeConfig = {}

ChallengeConfig.Daily = {
	{ id = "d_win1", text = "Win a game", stat = "wins", target = 1, reward = { coins = 200 } },
	{ id = "d_play2", text = "Play 2 games", stat = "games", target = 2, reward = { coins = 150 } },
	{ id = "d_td3", text = "Score 3 touchdowns", stat = "td", target = 3, reward = { coins = 200 } },
	{ id = "d_passtd2", text = "Throw 2 touchdown passes", stat = "passTd", target = 2, reward = { coins = 200 } },
	{ id = "d_rushtd1", text = "Run for a touchdown", stat = "rushTd", target = 1, reward = { coins = 200 } },
	{ id = "d_sack2", text = "Get 2 sacks", stat = "sacks", target = 2, reward = { coins = 200 } },
	{ id = "d_int1", text = "Intercept a pass", stat = "ints", target = 1, reward = { coins = 250 } },
	{ id = "d_yards150", text = "Gain 150 yards on offense", stat = "yards", target = 150, reward = { coins = 200 } },
	{ id = "d_broken3", text = "Break 3 tackles", stat = "broken", target = 3, reward = { coins = 200 } },
	{ id = "d_stops10", text = "Make 10 tackles on defense", stat = "stops", target = 10, reward = { coins = 200 } },
	{ id = "d_pack1", text = "Open a pack", stat = "packs", target = 1, reward = { coins = 150 } },
	{ id = "d_winpro", text = "Win a game on Pro or harder", stat = "winsPro", target = 1, reward = { coins = 300 } },
}

ChallengeConfig.Weekly = {
	{ id = "w_win8", text = "Win 8 games", stat = "wins", target = 8, reward = { coins = 2500 } },
	{ id = "w_td20", text = "Score 20 touchdowns", stat = "td", target = 20, reward = { coins = 2000 } },
	{ id = "w_sack10", text = "Get 10 sacks", stat = "sacks", target = 10, reward = { coins = 1500 } },
	{ id = "w_int5", text = "Intercept 5 passes", stat = "ints", target = 5, reward = { coins = 1500 } },
	{ id = "w_allpro3", text = "Win 3 games on All-Pro or harder", stat = "winsAllPro", target = 3, reward = { pack = "pro" } },
	{ id = "w_yards1000", text = "Gain 1,000 yards on offense", stat = "yards", target = 1000, reward = { coins = 2000 } },
	{ id = "w_broken15", text = "Break 15 tackles", stat = "broken", target = 15, reward = { coins = 1500 } },
	{ id = "w_fumble3", text = "Force 3 fumbles", stat = "fumbles", target = 3, reward = { coins = 1500 } },
	{ id = "w_shutout1", text = "Win a game without giving up a point", stat = "shutouts", target = 1, reward = { pack = "pro" } },
	{ id = "w_pack5", text = "Open 5 packs", stat = "packs", target = 5, reward = { coins = 1500 } },
}

ChallengeConfig.PerDay = 3
ChallengeConfig.PerWeek = 3
-- finish (and claim) all of a set for a bonus pack
ChallengeConfig.DailyBonus = { pack = "starter" }
ChallengeConfig.WeeklyBonus = { pack = "elite" }

ChallengeConfig.ById = {}
for _, c in ChallengeConfig.Daily do
	ChallengeConfig.ById[c.id] = c
end
for _, c in ChallengeConfig.Weekly do
	ChallengeConfig.ById[c.id] = c
end

function ChallengeConfig.Day(t)
	return math.floor((t or os.time()) / 86400)
end

function ChallengeConfig.Week(t)
	return math.floor((ChallengeConfig.Day(t) + 3) / 7) -- day 0 (1 Jan 1970) was a Thursday
end

function ChallengeConfig.DayEnds(day)
	return (day + 1) * 86400
end

function ChallengeConfig.WeekEnds(week)
	return ((week + 1) * 7 - 3) * 86400
end

-- n distinct picks from a pool, the same for everyone for this period
local function pick(pool, n, seed)
	local order = table.clone(pool)
	local r = Random.new(seed)
	for i = #order, 2, -1 do
		local j = r:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	for i = 1, math.min(n, #order) do
		out[i] = order[i]
	end
	return out
end

function ChallengeConfig.DailyFor(day)
	return pick(ChallengeConfig.Daily, ChallengeConfig.PerDay, day * 7919 + 17)
end

function ChallengeConfig.WeeklyFor(week)
	return pick(ChallengeConfig.Weekly, ChallengeConfig.PerWeek, week * 104729 + 3)
end

function ChallengeConfig.RewardText(reward)
	if reward.coins then
		return ("%s COINS"):format(tostring(reward.coins):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	return string.upper(reward.pack) .. " PACK"
end

return ChallengeConfig

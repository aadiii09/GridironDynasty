-- Badges (Roblox badges, shown on players' profiles). Create each one on the Creator Hub
-- (Experience -> Engagement -> Badges, image from art/out/badge_<key>.png) and paste its ID here.
-- A badge with id 0 is simply skipped.

local BadgeConfig = {}

BadgeConfig.List = {
	{ key = "rookie_camp", id = 0, name = "Rookie Camp", desc = "Finished your first game in Gridiron Dynasty." },
	{ key = "first_win", id = 0, name = "First Win", desc = "Won your first game." },
	{ key = "wins_10", id = 0, name = "Contender", desc = "Won 10 games." },
	{ key = "wins_50", id = 0, name = "Franchise Player", desc = "Won 50 games." },
	{ key = "elite_pull", id = 0, name = "Elite Pull", desc = "Pulled an Elite card (or better) from a pack." },
	{ key = "icon_pull", id = 0, name = "Icon Pull", desc = "Pulled an Icon card from a pack." },
	{ key = "ballhawk", id = 0, name = "Ballhawk", desc = "Intercepted a pass as a defender." },
	{ key = "gold_div", id = 0, name = "Gold Standard", desc = "Reached the Gold division in Ranked." },
	{ key = "dynasty_div", id = 0, name = "Dynasty", desc = "Reached the Dynasty division in Ranked." },
	{ key = "rainbow", id = 0, name = "Full Spectrum", desc = "Unlocked the Rainbow jersey (250 wins)." },
}

BadgeConfig.ByKey = {}
for _, b in BadgeConfig.List do
	BadgeConfig.ByKey[b.key] = b
end

return BadgeConfig

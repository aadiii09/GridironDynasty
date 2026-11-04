-- Solo match (7v7 vs AI) rules, field size and play designs. Shared by server and client.
-- Field coordinates: x = sideways in studs (0 = middle), y = studs downfield from your goal line.

local MatchConfig = {}

MatchConfig.Yard = 3 -- studs per yard
MatchConfig.FieldYards = 60 -- goal line to goal line
MatchConfig.EndZoneYards = 8
MatchConfig.WidthYards = 36
MatchConfig.DrivesPerTeam = 4
MatchConfig.StartYard = 15 -- every drive starts at your own 15
MatchConfig.FirstDownYards = 10
MatchConfig.TouchdownPoints = 7 -- extra point included
MatchConfig.SafetyPoints = 2
MatchConfig.MaxPlaySeconds = 20

MatchConfig.Rewards = { Win = 400, Tie = 250, Loss = 150 }

-- AI difficulty: the CPU team is built around your team rating + ovr, and Coin rewards scale.
-- Every win counts toward your record, jerseys and the leaderboards.
MatchConfig.Difficulties = {
	{ id = "rookie", name = "ROOKIE", ovr = -7, reward = 0.75, color = Color3.fromRGB(64, 160, 255), desc = "Weaker opponents. Learn the game." },
	{ id = "pro", name = "PRO", ovr = 0, reward = 1, color = Color3.fromRGB(46, 255, 140), desc = "An even matchup with your team." },
	{ id = "allpro", name = "ALL-PRO", ovr = 5, reward = 1.5, color = Color3.fromRGB(255, 196, 46), desc = "Better players at every spot." },
	{ id = "legend", name = "LEGEND", ovr = 10, reward = 2.25, color = Color3.fromRGB(255, 80, 90), desc = "Stacked teams. Only for the best." },
}
MatchConfig.DefaultDifficulty = "pro"
MatchConfig.DifficultyById = {}
for i, d in MatchConfig.Difficulties do
	d.order = i
	MatchConfig.DifficultyById[d.id] = d
end

-- Coins for a result at a difficulty (before the VIP double)
function MatchConfig.RewardFor(result, difficultyId)
	local d = MatchConfig.DifficultyById[difficultyId] or MatchConfig.DifficultyById[MatchConfig.DefaultDifficulty]
	return math.floor(MatchConfig.Rewards[result] * d.reward / 5 + 0.5) * 5
end

-- Pre-snap spots in yards relative to the ball (x sideways, y downfield; negative y = backfield)
MatchConfig.Formation = {
	Offense = {
		WR1 = { -12, 0 }, OL1 = { -1.2, 0 }, OL2 = { 1.2, 0 }, TE = { 3.6, 0 }, WR2 = { 12, 0 },
		QB = { 0, -4 }, RB = { 1.8, -6.5 },
	},
	Defense = {
		CB1 = { -12, 5 }, DL1 = { -1.4, 2 }, DL2 = { 1.4, 2 }, CB2 = { 12, 5 },
		LB1 = { -4.5, 5 }, LB2 = { 4.5, 5 }, S = { 0, 13 },
	},
}

-- Who each defender covers or attacks
MatchConfig.Coverage = { CB1 = "WR1", CB2 = "WR2", LB1 = "TE", LB2 = "RB" }
MatchConfig.BlockAssignments = { OL1 = "DL1", OL2 = "DL2" }

-- Receivers you can throw to, in key order (1-4)
MatchConfig.Targets = { "WR1", "WR2", "TE", "RB" }

-- Routes: waypoints in yards from the player's pre-snap spot. Positive x = toward his own
-- sideline (outside), negative x = toward the middle. "block" = stays in to block.
MatchConfig.Plays = {
	{
		id = "quick",
		name = "QUICK PASS",
		desc = "Slant, out, drag and a flat: get it out fast",
		routes = {
			WR1 = { { 0, 3 }, { -6, 8 }, { -12, 14 } },
			WR2 = { { 0, 6 }, { 7, 6 }, { 9, 6 } },
			TE = { { 0, 2 }, { -8, 4 }, { -16, 4 } },
			RB = { { 3, 1 }, { 9, 2 }, { 12, 3 } },
		},
	},
	{
		id = "deep",
		name = "DEEP PASS",
		desc = "Go route, post and seam with the RB staying in to block",
		routes = {
			WR1 = { { 0, 32 } },
			WR2 = { { 0, 10 }, { -9, 24 }, { -12, 32 } },
			TE = { { 0, 22 } },
			RB = "block",
		},
	},
	{
		id = "run",
		name = "RUN",
		desc = "Handoff to your RB: you take control and find a hole",
		run = true,
		routes = {
			WR1 = { { 0, 10 } },
			WR2 = { { 0, 10 } },
			TE = "block",
			RB = "carry",
		},
	},
}

MatchConfig.PlaysById = {}
for _, play in MatchConfig.Plays do
	MatchConfig.PlaysById[play.id] = play
end

-- Defensive calls (yours when the CPU has the ball; the CPU picks one when you have it)
MatchConfig.DefenseCalls = {
	{ id = "man", name = "MAN COVERAGE", desc = "Every receiver is shadowed. Solid against everything" },
	{ id = "zone", name = "DEEP ZONE", desc = "Corners stay over the top: no deep balls, gives up short ones" },
	{ id = "blitz", name = "BLITZ", desc = "Both linebackers rush the QB: fast pressure, open middle" },
}
MatchConfig.DefenseCallsById = {}
for _, call in MatchConfig.DefenseCalls do
	MatchConfig.DefenseCallsById[call.id] = call
end

-- Which defender you control when the CPU has the ball (Q switches during the play)
-- You're a free player: if you control someone with a man assignment, the AI safety takes his man.
MatchConfig.DefaultControl = "S"
MatchConfig.ControlCycle = { "S", "LB1", "LB2", "CB1", "CB2", "DL1", "DL2" }

-- Card attribute -> movement speed (studs/second)
-- (extra gain above 75 so elite speed really shows: 70 -> 16.4, 85 -> 20.3, 95 -> 23.3)
function MatchConfig.SpeedFor(spd)
	spd = spd or 50
	return 11 + math.clamp(spd - 40, 0, 60) * 0.18 + math.max(0, spd - 75) * 0.12
end

-- ACC -> seconds to reach top speed (95 -> 0.35s, 70 -> 0.6s, 50 -> 0.8s)
function MatchConfig.RampTime(acc)
	return math.clamp(1.3 - (acc or 50) * 0.01, 0.3, 0.9)
end

-- Fraction of top speed after `elapsed` seconds of building up (starts at 35%)
function MatchConfig.Ramp(rampTime, elapsed)
	return 0.35 + 0.65 * math.clamp(elapsed / rampTime, 0, 1)
end

function MatchConfig.FieldLength()
	return MatchConfig.FieldYards * MatchConfig.Yard
end

function MatchConfig.HalfWidth()
	return MatchConfig.WidthYards * MatchConfig.Yard / 2
end

-- "OWN 25" / "OPP 18" / "50"
function MatchConfig.SpotText(yardsFromOwnGoal)
	local yd = math.floor(yardsFromOwnGoal + 0.5)
	local half = MatchConfig.FieldYards / 2
	if yd == half then
		return tostring(yd)
	elseif yd < half then
		return "OWN " .. yd
	end
	return "OPP " .. (MatchConfig.FieldYards - yd)
end

return MatchConfig

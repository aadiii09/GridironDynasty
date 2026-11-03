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

-- Card attribute -> movement speed (studs/second)
function MatchConfig.SpeedFor(spd)
	return 11 + math.clamp((spd or 50) - 40, 0, 60) * 0.21 -- 40 -> 11, 70 -> 17.3, 99 -> 23.4
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

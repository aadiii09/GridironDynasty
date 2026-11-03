-- 7v7 lineup: 7 offensive and 7 defensive slots (shared by server validation and client UI).
-- x/y place each slot on the lineup screen's field (0-1, y = 0 is the line of scrimmage side).

local LineupConfig = {}

LineupConfig.Slots = {
	-- Offense: 2-man line with a TE, two receivers split wide, QB and RB in the backfield
	{ id = "WR1", pos = "WR", side = "Offense", label = "WR", x = 0.09, y = 0.27 },
	{ id = "OL1", pos = "OL", side = "Offense", label = "OL", x = 0.36, y = 0.27 },
	{ id = "OL2", pos = "OL", side = "Offense", label = "OL", x = 0.5, y = 0.27 },
	{ id = "TE", pos = "TE", side = "Offense", label = "TE", x = 0.64, y = 0.27 },
	{ id = "WR2", pos = "WR", side = "Offense", label = "WR", x = 0.91, y = 0.27 },
	{ id = "QB", pos = "QB", side = "Offense", label = "QB", x = 0.43, y = 0.74 },
	{ id = "RB", pos = "RB", side = "Offense", label = "RB", x = 0.6, y = 0.74 },
	-- Defense: 2 down linemen, 2 linebackers, 2 corners, 1 safety
	{ id = "CB1", pos = "CB", side = "Defense", label = "CB", x = 0.09, y = 0.27 },
	{ id = "DL1", pos = "DL", side = "Defense", label = "DL", x = 0.38, y = 0.27 },
	{ id = "DL2", pos = "DL", side = "Defense", label = "DL", x = 0.62, y = 0.27 },
	{ id = "CB2", pos = "CB", side = "Defense", label = "CB", x = 0.91, y = 0.27 },
	{ id = "LB1", pos = "LB", side = "Defense", label = "LB", x = 0.28, y = 0.74 },
	{ id = "S", pos = "S", side = "Defense", label = "S", x = 0.5, y = 0.74 },
	{ id = "LB2", pos = "LB", side = "Defense", label = "LB", x = 0.72, y = 0.74 },
}

-- Rating used for an empty slot when averaging team ratings.
LineupConfig.EmptySlotRating = 40

LineupConfig.ById = {}
for _, slot in LineupConfig.Slots do
	LineupConfig.ById[slot.id] = slot
end

-- lineup = { [slotId] = uid }, cardOf(uid) -> card table (with .ovr) or nil
function LineupConfig.TeamRatings(lineup, cardOf)
	local sums = { Offense = 0, Defense = 0 }
	local counts = { Offense = 0, Defense = 0 }
	local filled = 0
	for _, slot in LineupConfig.Slots do
		local uid = lineup[slot.id]
		local card = uid and cardOf(uid)
		local ovr = card and card.ovr or LineupConfig.EmptySlotRating
		if card then
			filled += 1
		end
		sums[slot.side] += ovr
		counts[slot.side] += 1
	end
	local off = sums.Offense / counts.Offense
	local def = sums.Defense / counts.Defense
	return {
		ovr = math.floor((sums.Offense + sums.Defense) / (counts.Offense + counts.Defense) + 0.5),
		off = math.floor(off + 0.5),
		def = math.floor(def + 0.5),
		filled = filled,
		total = #LineupConfig.Slots,
	}
end

return LineupConfig

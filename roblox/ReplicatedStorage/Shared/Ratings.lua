-- Player attributes: names, groups, the key ones for each position, and safe lookup.
-- Card data (cards.json) carries every attribute for every card; this module is shared by the
-- match engine (server) and the card screens (client).

local Ratings = {}

Ratings.Groups = {
	{ name = "PHYSICAL", keys = { "SPD", "ACC", "AGI", "STR", "AWR" } },
	{ name = "PASSING", keys = { "THP", "SAC", "MAC", "DAC", "RUN", "TUP" } },
	{ name = "BALL CARRIER", keys = { "CAR", "TRK", "ELU", "BCV", "SFA", "JKM", "SPM" } },
	{ name = "RECEIVING", keys = { "CTH", "CIT", "SPC", "SRR", "MRR", "DRR", "RLS" } },
	{ name = "BLOCKING", keys = { "PBK", "PBP", "PBF", "RBK", "RBP", "RBF" } },
	{ name = "DEFENSE", keys = { "TAK", "POW", "BSH", "PMV", "FMV", "PUR", "PRC", "MCV", "ZCV", "PRS" } },
}

Ratings.All = {}
for _, g in Ratings.Groups do
	for _, k in g.keys do
		table.insert(Ratings.All, k)
	end
end

Ratings.Names = {
	SPD = "Speed", ACC = "Acceleration", AGI = "Agility", STR = "Strength", AWR = "Awareness",
	THP = "Throw Power", SAC = "Short Accuracy", MAC = "Medium Accuracy", DAC = "Deep Accuracy",
	RUN = "Throw on the Run", TUP = "Throw Under Pressure",
	CAR = "Carrying", TRK = "Trucking", ELU = "Elusiveness", BCV = "Ball Carrier Vision",
	SFA = "Stiff Arm", JKM = "Juke Move", SPM = "Spin Move",
	CTH = "Catching", CIT = "Catch in Traffic", SPC = "Spectacular Catch",
	SRR = "Short Route Running", MRR = "Medium Route Running", DRR = "Deep Route Running", RLS = "Release",
	PBK = "Pass Block", PBP = "Pass Block Power", PBF = "Pass Block Finesse",
	RBK = "Run Block", RBP = "Run Block Power", RBF = "Run Block Finesse",
	TAK = "Tackle", POW = "Hit Power", BSH = "Block Shedding", PMV = "Power Moves", FMV = "Finesse Moves",
	PUR = "Pursuit", PRC = "Play Recognition", MCV = "Man Coverage", ZCV = "Zone Coverage", PRS = "Press",
}

-- What each one does in a game (shown on the card detail screen).
Ratings.Effects = {
	SPD = "Top running speed", ACC = "How fast he hits top speed", AGI = "Quickness in and out of cuts",
	STR = "Wins power battles at the line", AWR = "Reads and reacts faster",
	THP = "Ball speed and how deep he can throw", SAC = "Accuracy under 10 yards", MAC = "Accuracy 10-20 yards",
	DAC = "Accuracy beyond 20 yards", RUN = "Accuracy while scrambling", TUP = "Accuracy with a rusher on him",
	CAR = "Holds on to the ball on hits", TRK = "Runs over tacklers", ELU = "Dodges tacklers in the open field",
	BCV = "Sees the hole and the open lane", SFA = "Shoves tacklers away", JKM = "Jukes tacklers",
	SPM = "Spins out of tackles",
	CTH = "Catches open passes", CIT = "Catches with a defender on him", SPC = "Reaches off-target throws",
	SRR = "Separation on short routes", MRR = "Separation on medium routes", DRR = "Separation on deep routes",
	RLS = "Beats press coverage at the snap",
	PBK = "Holds off pass rushers", PBP = "Anchors against power rushers", PBF = "Mirrors finesse rushers",
	RBK = "Opens running lanes", RBP = "Drives defenders off the ball", RBF = "Reaches and seals defenders",
	TAK = "Finishes tackles", POW = "Big hits that force fumbles", BSH = "Gets off blocks on runs",
	PMV = "Bull-rushes past blockers", FMV = "Swims and spins past blockers", PUR = "Takes good angles to the ball",
	PRC = "Diagnoses runs quickly", MCV = "Sticks to his man in man coverage", ZCV = "Breaks on throws in zone",
	PRS = "Jams receivers at the line",
}

-- The ratings that matter most for each position (shown first, and on the card face).
Ratings.Key = {
	QB = { "THP", "SAC", "MAC", "DAC", "TUP", "RUN", "AWR", "SPD" },
	RB = { "SPD", "ACC", "ELU", "TRK", "BCV", "JKM", "CAR", "CTH" },
	WR = { "SPD", "CTH", "SRR", "MRR", "DRR", "RLS", "CIT", "SPC" },
	TE = { "CTH", "CIT", "SPD", "MRR", "RBK", "PBK", "STR", "SPC" },
	OL = { "PBK", "PBP", "PBF", "RBK", "RBP", "RBF", "STR", "AWR" },
	DL = { "PMV", "FMV", "BSH", "TAK", "STR", "PUR", "SPD", "POW" },
	LB = { "TAK", "PUR", "PRC", "BSH", "ZCV", "MCV", "POW", "SPD" },
	CB = { "MCV", "ZCV", "PRS", "SPD", "ACC", "AGI", "PRC", "TAK" },
	S = { "ZCV", "MCV", "TAK", "PUR", "PRC", "POW", "SPD", "SPC" },
}

-- Cards made before the full attribute list (cached old card data) only had these.
local LEGACY = {
	ACC = "SPD", AWR = "STR",
	SAC = "THA", MAC = "THA", DAC = "THA", RUN = "THA", TUP = "THA",
	TRK = "STR", ELU = "AGI", BCV = "AGI", SFA = "STR", JKM = "AGI", SPM = "AGI",
	CIT = "CTH", SPC = "CTH", SRR = "AGI", MRR = "AGI", DRR = "SPD", RLS = "AGI",
	PBK = "BLK", PBP = "BLK", PBF = "BLK", RBK = "BLK", RBP = "BLK", RBF = "BLK",
	POW = "TAK", BSH = "STR", PMV = "PRS", FMV = "PRS", PUR = "SPD", PRC = "COV",
	MCV = "COV", ZCV = "COV",
}

function Ratings.Get(attrs, key)
	if not attrs then
		return 50
	end
	if attrs.SAC == nil then -- old attribute list: PRS meant pass rush back then
		if key == "PRS" then
			return attrs.COV or 50
		end
		local alt = LEGACY[key]
		return attrs[key] or (alt and attrs[alt]) or 50
	end
	return attrs[key] or 50
end

-- A read-only view where every attribute is always a number.
function Ratings.Wrap(attrs)
	return setmetatable({}, {
		__index = function(_, key)
			return Ratings.Get(attrs, key)
		end,
	})
end

return Ratings

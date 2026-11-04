-- Team jerseys you unlock by winning games. Shared by the server (unlock checks, match colors)
-- and clients (Locker screen, animated jerseys in games).
--
-- primary = jersey, helmet and pads; secondary = numbers, gloves, socks, stripes.
-- fx jerseys animate their primary color on every client (see Client/JerseyFX.lua):
--   shine (metal sheen), pulse (glow), lava, galaxy, rainbow.

local Jerseys = {}

local rgb = Color3.fromRGB

Jerseys.List = {
	{ id = "dynasty", name = "Dynasty Black", wins = 0, primary = rgb(20, 22, 30), secondary = rgb(46, 255, 140) },
	{ id = "arctic", name = "Arctic White", wins = 0, primary = rgb(228, 230, 236), secondary = rgb(28, 32, 44) },
	{ id = "crimson", name = "Crimson", wins = 1, primary = rgb(168, 22, 40), secondary = rgb(250, 250, 250) },
	{ id = "royal", name = "Royal Blue", wins = 3, primary = rgb(26, 68, 188), secondary = rgb(255, 200, 40) },
	{ id = "forest", name = "Forest", wins = 5, primary = rgb(18, 92, 52), secondary = rgb(236, 226, 190) },
	{ id = "sunset", name = "Sunset Orange", wins = 8, primary = rgb(240, 110, 24), secondary = rgb(24, 24, 30) },
	{ id = "purple", name = "Purple Reign", wins = 12, primary = rgb(92, 36, 168), secondary = rgb(255, 196, 46) },
	{ id = "teal", name = "Riptide Teal", wins = 16, primary = rgb(0, 128, 132), secondary = rgb(255, 255, 255) },
	{ id = "blackout", name = "Blackout", wins = 20, primary = rgb(12, 12, 14), secondary = rgb(70, 72, 80) },
	{ id = "ice", name = "Ice Storm", wins = 30, primary = rgb(160, 220, 255), secondary = rgb(255, 255, 255), fx = "shine", material = "Glass" },
	{ id = "chrome", name = "Chrome", wins = 40, primary = rgb(190, 196, 206), secondary = rgb(26, 28, 36), fx = "shine", material = "Foil" },
	{ id = "gold", name = "24K Gold", wins = 60, primary = rgb(255, 190, 40), secondary = rgb(34, 26, 8), fx = "shine", material = "Foil" },
	{ id = "neon", name = "Neon Pulse", wins = 80, primary = rgb(46, 255, 140), secondary = rgb(14, 16, 22), fx = "pulse" },
	{ id = "lava", name = "Lava", wins = 100, primary = rgb(210, 50, 14), secondary = rgb(255, 214, 110), fx = "lava" },
	{ id = "galaxy", name = "Galaxy", wins = 150, primary = rgb(80, 40, 180), secondary = rgb(255, 255, 255), fx = "galaxy" },
	{ id = "rainbow", name = "Rainbow", wins = 250, primary = rgb(255, 60, 60), secondary = rgb(255, 255, 255), fx = "rainbow" },
}

Jerseys.Default = "dynasty"
Jerseys.ById = {}
for i, j in Jerseys.List do
	j.order = i
	Jerseys.ById[j.id] = j
end

function Jerseys.Get(id)
	return Jerseys.ById[id] or Jerseys.ById[Jerseys.Default]
end

function Jerseys.IsUnlocked(id, wins)
	local j = Jerseys.ById[id]
	return j ~= nil and (wins or 0) >= j.wins
end

-- The jerseys a win count unlocks that the previous count didn't (for "NEW JERSEY" banners)
function Jerseys.NewlyUnlocked(winsBefore, winsAfter)
	local out = {}
	for _, j in Jerseys.List do
		if j.wins > winsBefore and j.wins <= winsAfter then
			table.insert(out, j)
		end
	end
	return out
end

-- The next jersey still locked at this win count (nil when everything is unlocked)
function Jerseys.Next(wins)
	for _, j in Jerseys.List do
		if j.wins > (wins or 0) then
			return j
		end
	end
	return nil
end

-- Primary color of an animated jersey at time t. `offset` (0..1) shifts the pattern per part
-- (height on the body), so colors flow over the player instead of flashing all at once.
function Jerseys.ColorAt(j, t, offset)
	offset = offset or 0
	local fx = j.fx
	if fx == "rainbow" then
		return Color3.fromHSV((t * 0.22 + offset) % 1, 0.82, 1)
	elseif fx == "galaxy" then
		local s = math.sin(t * 1.3 + offset * 9)
		local hue = 0.72 + 0.1 * s -- violet <-> magenta <-> deep blue
		return Color3.fromHSV(hue % 1, 0.75, 0.55 + 0.3 * (0.5 + 0.5 * math.sin(t * 2.1 + offset * 14)))
	elseif fx == "lava" then
		local s = 0.5 + 0.5 * math.sin(t * 2.4 + offset * 11)
		return rgb(150, 18, 8):Lerp(rgb(255, 140, 20), s)
	elseif fx == "pulse" then
		local s = 0.5 + 0.5 * math.sin(t * 3)
		return j.primary:Lerp(rgb(10, 60, 36), 0.55 * (1 - s))
	elseif fx == "shine" then
		-- a bright band sweeps up the jersey every couple of seconds
		local band = math.max(0, 1 - math.abs(((t * 0.45 - offset) % 1.6) - 0.5) * 6)
		return j.primary:Lerp(Color3.new(1, 1, 1), band * 0.55)
	end
	return j.primary
end

return Jerseys

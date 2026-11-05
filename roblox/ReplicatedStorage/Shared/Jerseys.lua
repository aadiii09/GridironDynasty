-- Team jerseys you unlock by winning games. Shared by the server (unlock checks, match colors)
-- and clients (Locker screen, animated jerseys in games).
--
-- primary = jersey, helmet and pads; secondary = numbers, gloves, socks, stripes.
-- fx jerseys animate their primary color on every client (see Client/JerseyFX.lua):
--   shine (metal sheen), pulse (glow), lava, galaxy, rainbow, toxic, ocean, candy, ember, aurora,
--   storm, plasma, bloodmoon, void, holo, solar, prism, legend.

local Jerseys = {}

local rgb = Color3.fromRGB

Jerseys.List = {
	{ id = "dynasty", name = "Dynasty Black", wins = 0, primary = rgb(20, 22, 30), secondary = rgb(46, 255, 140) },
	{ id = "arctic", name = "Arctic White", wins = 0, primary = rgb(228, 230, 236), secondary = rgb(28, 32, 44) },
	{ id = "crimson", name = "Crimson", wins = 1, primary = rgb(168, 22, 40), secondary = rgb(250, 250, 250) },
	{ id = "navy", name = "Midnight Navy", wins = 2, primary = rgb(14, 28, 68), secondary = rgb(255, 196, 46) },
	{ id = "royal", name = "Royal Blue", wins = 3, primary = rgb(26, 68, 188), secondary = rgb(255, 200, 40) },
	{ id = "forest", name = "Forest", wins = 5, primary = rgb(18, 92, 52), secondary = rgb(236, 226, 190) },
	{ id = "sunset", name = "Sunset Orange", wins = 8, primary = rgb(240, 110, 24), secondary = rgb(24, 24, 30) },
	{ id = "maroon", name = "Maroon", wins = 10, primary = rgb(110, 18, 36), secondary = rgb(255, 196, 46) },
	{ id = "purple", name = "Purple Reign", wins = 12, primary = rgb(92, 36, 168), secondary = rgb(255, 196, 46) },
	{ id = "sky", name = "Sky Blue", wins = 14, primary = rgb(110, 180, 240), secondary = rgb(14, 28, 68) },
	{ id = "teal", name = "Riptide Teal", wins = 16, primary = rgb(0, 128, 132), secondary = rgb(255, 255, 255) },
	{ id = "blackout", name = "Blackout", wins = 20, primary = rgb(12, 12, 14), secondary = rgb(70, 72, 80) },
	{ id = "lime", name = "Volt Lime", wins = 25, primary = rgb(150, 230, 40), secondary = rgb(16, 18, 24) },
	{ id = "ice", name = "Ice Storm", wins = 30, primary = rgb(160, 220, 255), secondary = rgb(255, 255, 255), fx = "shine", material = "Glass" },
	{ id = "pink", name = "Hot Pink", wins = 35, primary = rgb(255, 60, 150), secondary = rgb(255, 255, 255) },
	{ id = "chrome", name = "Chrome", wins = 40, primary = rgb(190, 196, 206), secondary = rgb(26, 28, 36), fx = "shine", material = "Foil" },
	{ id = "steel", name = "Steel Blaze", wins = 50, primary = rgb(90, 100, 115), secondary = rgb(255, 120, 30) },
	{ id = "gold", name = "24K Gold", wins = 60, primary = rgb(255, 190, 40), secondary = rgb(34, 26, 8), fx = "shine", material = "Foil" },
	{ id = "bronze", name = "Bronze", wins = 70, primary = rgb(176, 108, 52), secondary = rgb(24, 20, 16), fx = "shine", material = "Foil" },
	{ id = "neon", name = "Neon Pulse", wins = 80, primary = rgb(46, 255, 140), secondary = rgb(14, 16, 22), fx = "pulse" },
	{ id = "lava", name = "Lava", wins = 100, primary = rgb(210, 50, 14), secondary = rgb(255, 214, 110), fx = "lava" },
	{ id = "galaxy", name = "Galaxy", wins = 150, primary = rgb(80, 40, 180), secondary = rgb(255, 255, 255), fx = "galaxy" },
	{ id = "rainbow", name = "Rainbow", wins = 250, primary = rgb(255, 60, 60), secondary = rgb(255, 255, 255), fx = "rainbow" },
	{ id = "toxic", name = "Toxic", wins = 300, primary = rgb(120, 255, 40), secondary = rgb(20, 22, 16), fx = "toxic", material = "Neon" },
	{ id = "ocean", name = "Ocean Wave", wins = 400, primary = rgb(20, 110, 210), secondary = rgb(255, 255, 255), fx = "ocean" },
	{ id = "candy", name = "Candy Cane", wins = 500, primary = rgb(230, 30, 50), secondary = rgb(255, 255, 255), fx = "candy" },
	{ id = "ember", name = "Ember", wins = 600, primary = rgb(120, 20, 10), secondary = rgb(255, 170, 60), fx = "ember" },
	{ id = "aurora", name = "Aurora", wins = 750, primary = rgb(40, 220, 170), secondary = rgb(255, 255, 255), fx = "aurora" },
	{ id = "diamond", name = "Diamond", wins = 1000, primary = rgb(225, 240, 255), secondary = rgb(40, 90, 160), fx = "shine", material = "Glass" },
	{ id = "storm", name = "Thunderstorm", wins = 1250, primary = rgb(44, 48, 62), secondary = rgb(255, 230, 80), fx = "storm" },
	{ id = "plasma", name = "Plasma", wins = 1500, primary = rgb(60, 220, 255), secondary = rgb(255, 255, 255), fx = "plasma" },
	{ id = "bloodmoon", name = "Blood Moon", wins = 2000, primary = rgb(150, 0, 20), secondary = rgb(20, 0, 4), fx = "bloodmoon" },
	{ id = "void", name = "The Void", wins = 2500, primary = rgb(8, 4, 16), secondary = rgb(170, 80, 255), fx = "void" },
	{ id = "holo", name = "Holographic", wins = 3000, primary = rgb(200, 210, 255), secondary = rgb(20, 22, 30), fx = "holo", material = "Foil" },
	{ id = "solar", name = "Solar Flare", wins = 3500, primary = rgb(255, 160, 20), secondary = rgb(255, 255, 255), fx = "solar", material = "Neon" },
	{ id = "prism", name = "Prism", wins = 4000, primary = rgb(255, 255, 255), secondary = rgb(20, 22, 30), fx = "prism", material = "Glass" },
	{ id = "legend", name = "Dynasty Legend", wins = 5000, primary = rgb(255, 196, 46), secondary = rgb(14, 14, 18), fx = "legend", material = "Foil" },
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
	elseif fx == "toxic" then
		-- bubbling acid green: lime <-> yellow-green blobs
		local s = 0.5 + 0.5 * math.sin(t * 3.4 + offset * 17) * math.sin(t * 1.3 + offset * 5)
		return rgb(40, 200, 20):Lerp(rgb(220, 255, 60), s)
	elseif fx == "ocean" then
		-- waves rolling up the body: deep blue -> cyan -> white crest
		local w = 0.5 + 0.5 * math.sin(t * 2.2 - offset * 10)
		local c = rgb(8, 50, 140):Lerp(rgb(30, 170, 230), w)
		return c:Lerp(Color3.new(1, 1, 1), math.max(0, w - 0.85) * 4)
	elseif fx == "candy" then
		-- red and white stripes scrolling up
		local band = ((offset * 4 + t * 0.8) % 1) < 0.5
		return band and j.primary or rgb(250, 250, 250)
	elseif fx == "ember" then
		-- glowing coals: dark red with flickering orange
		local f = math.noise(t * 4, offset * 12, 3.1) * 0.5 + 0.5
		return rgb(70, 10, 6):Lerp(rgb(255, 120, 20), math.clamp(f * 1.3 - 0.2, 0, 1))
	elseif fx == "aurora" then
		-- northern lights: teal -> green -> violet curtains
		local hue = 0.42 + 0.16 * math.sin(t * 0.9 + offset * 6) + 0.05 * math.sin(t * 2.3)
		return Color3.fromHSV(hue % 1, 0.7, 0.85 + 0.15 * math.sin(t * 1.7 + offset * 9))
	elseif fx == "storm" then
		-- dark clouds, and every few seconds a lightning flash
		local cloud = 0.5 + 0.5 * math.sin(t * 0.8 + offset * 5)
		local c = rgb(30, 32, 44):Lerp(rgb(70, 76, 96), cloud)
		local phase = t % 3.7
		local flash = (phase < 0.08 or (phase > 0.18 and phase < 0.24)) and 1 or 0
		return c:Lerp(rgb(235, 240, 255), flash * 0.85)
	elseif fx == "plasma" then
		-- electric cyan <-> magenta, fast
		local s = 0.5 + 0.5 * math.sin(t * 4 + offset * 13)
		return rgb(40, 220, 255):Lerp(rgb(255, 40, 220), s)
	elseif fx == "bloodmoon" then
		-- slow heavy pulse of deep red
		local s = 0.5 + 0.5 * math.sin(t * 1.6)
		return rgb(60, 0, 8):Lerp(rgb(200, 10, 30), s)
	elseif fx == "void" then
		-- near-black with violet light slipping across it
		local s = math.max(0, math.sin(t * 1.4 + offset * 8)) ^ 3
		return rgb(6, 2, 14):Lerp(rgb(140, 60, 255), s * 0.8)
	elseif fx == "holo" then
		-- iridescent foil: soft pastel hues shifting with height
		return Color3.fromHSV((t * 0.15 + offset * 1.6) % 1, 0.28, 1)
	elseif fx == "solar" then
		-- churning gold, orange and white-hot
		local s = 0.5 + 0.5 * math.sin(t * 2.8 + offset * 9) * math.cos(t * 1.1 - offset * 4)
		local c = rgb(255, 90, 10):Lerp(rgb(255, 200, 40), s)
		return c:Lerp(Color3.new(1, 1, 0.9), math.max(0, s - 0.8) * 3)
	elseif fx == "prism" then
		-- glass splitting light: a fast, bright rainbow
		return Color3.fromHSV((t * 0.45 + offset * 2.2) % 1, 0.55, 1)
	elseif fx == "legend" then
		-- gold with a rainbow sheen sweeping over it
		local band = math.max(0, 1 - math.abs(((t * 0.4 - offset) % 1.4) - 0.5) * 4)
		return j.primary:Lerp(Color3.fromHSV((t * 0.3 + offset) % 1, 0.6, 1), band * 0.8)
	elseif fx == "shine" then
		-- a bright band sweeps up the jersey every couple of seconds
		local band = math.max(0, 1 - math.abs(((t * 0.45 - offset) % 1.6) - 0.5) * 6)
		return j.primary:Lerp(Color3.new(1, 1, 1), band * 0.55)
	end
	return j.primary
end

return Jerseys

-- Builds a 7v7 stadium: striped turf, yard numbers, hash marks, painted end zones, goal posts,
-- stands with a crowd, LED ribbon boards, light towers and a big screen.
-- Matches get their own stadium far from the lobby; the lobby has one at the origin.
--
-- Coordinates are always in the frame of the team with the ball: y = studs from THEIR own goal
-- line. When the CPU has the ball, `flipped` mirrors the frame. Downfield (unflipped) is world -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local Field = {}
Field.__index = Field

local GROUND_TOP = 1
local slotsInUse = {}
local FONT = Font.fromEnum(Enum.Font.GothamBlack)
local WHITE = Color3.new(1, 1, 1)

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- text painted on the top of a flat part. `rot` turns the text on the ground (degrees).
local function paint(parent, text, cf, size, color, rot, transparency)
	local p = part({ Size = Vector3.new(size.X, 0.05, size.Y), CFrame = cf * CFrame.Angles(0, math.rad(rot or 0), 0), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 1
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.FontFace = FONT
	l.TextScaled = true
	l.TextColor3 = color or WHITE
	l.TextTransparency = transparency or 0
	l.Text = text
	l.Parent = sg
	sg.Parent = p
	return p
end

-- opts: { homeName, awayName, homeColor2, awayColor2, crowd = {Color3...}, origin = Vector3,
--         dims = { FieldYards, EndZoneYards, WidthYards } (default: MatchConfig's full field) }
function Field.new(homeColor, awayColor, opts)
	opts = opts or {}
	local slot
	if not opts.origin then
		slot = 1
		while slotsInUse[slot] do
			slot += 1
		end
		slotsInUse[slot] = true
	end

	local self = setmetatable({}, Field)
	self.slot = slot
	self.origin = opts.origin or Vector3.new(3000 + slot * 1000, 0, 0)

	local dims = opts.dims or MatchConfig
	local fieldYards = dims.FieldYards
	local Y = MatchConfig.Yard
	local L = fieldYards * Y
	local EZ = dims.EndZoneYards * Y
	local W = dims.WidthYards * Y
	self.L, self.EZ, self.W = L, EZ, W
	local model = Instance.new("Model")
	model.Name = opts.name or ("MatchField_" .. (slot or 0))
	self.model = model
	local deco = Instance.new("Folder")
	deco.Name = "Stadium"
	deco.Parent = model

	local function at(x, y, h)
		return self.origin + Vector3.new(x, GROUND_TOP + (h or 0), -y)
	end
	local mid = at(0, L / 2, 0)

	-- ground + turf --------------------------------------------------------------------
	part({ Name = "Ground", Size = Vector3.new(W + 150, 2, L + EZ * 2 + 120), Position = Vector3.new(mid.X, GROUND_TOP - 1, mid.Z), Color = Color3.fromRGB(38, 92, 46), Material = Enum.Material.Grass }, model)
	local stripes = fieldYards / 5
	for i = 0, stripes - 1 do
		local shade = i % 2 == 0 and Color3.fromRGB(52, 138, 62) or Color3.fromRGB(44, 122, 54)
		part({ Size = Vector3.new(W, 0.06, 5 * Y), Position = at(0, (i + 0.5) * 5 * Y, 0.02), Color = shade, Material = Enum.Material.Grass, CanCollide = false }, deco)
	end
	-- sideline apron
	for _, side in { -1, 1 } do
		part({ Size = Vector3.new(14, 0.05, L + EZ * 2 + 20), Position = at(side * (W / 2 + 7), L / 2, 0.01), Color = Color3.fromRGB(34, 84, 42), Material = Enum.Material.Grass, CanCollide = false }, deco)
	end

	-- end zones with painted names
	local function endZone(y, color, name, rot)
		part({ Size = Vector3.new(W, 0.07, EZ), Position = at(0, y, 0.03), Color = color, CanCollide = false }, deco)
		if name then
			paint(deco, string.upper(name), CFrame.new(at(0, y, 0.09)), Vector2.new(EZ * 0.7, W * 0.8), WHITE, rot, 0.05)
		end
	end
	-- painted names run across the field, readable from the field of play
	endZone(-EZ / 2, homeColor, opts.homeName, 90)
	endZone(L + EZ / 2, awayColor, opts.awayName, -90)

	-- lines: goal lines, every 5 yards, sidelines, hash marks, yard numbers
	for yd = 0, fieldYards, 5 do
		local major = yd % 10 == 0
		part({ Size = Vector3.new(W, 0.08, (yd == 0 or yd == fieldYards) and 0.9 or (major and 0.45 or 0.3)), Position = at(0, yd * Y, 0.05), Color = WHITE, CanCollide = false, Transparency = major and 0 or 0.25 }, deco)
	end
	for yd = 1, fieldYards - 1 do
		if yd % 5 ~= 0 then
			for _, x in { -W * 0.16, W * 0.16, -W / 2 + 1.2, W / 2 - 1.2 } do
				part({ Size = Vector3.new(1.4, 0.08, 0.22), Position = at(x, yd * Y, 0.05), Color = WHITE, CanCollide = false, Transparency = 0.15 }, deco)
			end
		end
	end
	for yd = 10, fieldYards - 10, 10 do
		local n = yd <= fieldYards / 2 and yd or fieldYards - yd
		for _, side in { -1, 1 } do
			paint(deco, tostring(n), CFrame.new(at(side * (W / 2 - 9), yd * Y, 0.09)), Vector2.new(9, 6), WHITE, side == 1 and 90 or -90, 0.05)
		end
	end
	for _, side in { -1, 1 } do
		part({ Size = Vector3.new(1, 0.09, L + EZ * 2), Position = at(side * W / 2, L / 2, 0.06), Color = WHITE, CanCollide = false }, deco)
	end

	-- goal posts (yellow, at the back of each end zone)
	for _, y in { -EZ, L + EZ } do
		local yellow = Color3.fromRGB(255, 214, 40)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 0.7, 0.7), CFrame = CFrame.new(at(0, y, 5)) * CFrame.Angles(0, 0, math.rad(90)), Color = yellow, Material = Enum.Material.Metal }, deco)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(18, 0.6, 0.6), CFrame = CFrame.new(at(0, y, 10)), Color = yellow, Material = Enum.Material.Metal }, deco)
		for _, x in { -9, 9 } do
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(24, 0.5, 0.5), CFrame = CFrame.new(at(x, y, 22)) * CFrame.Angles(0, 0, math.rad(90)), Color = yellow, Material = Enum.Material.Metal }, deco)
		end
	end

	-- field details: pylons, midfield logo, sideline restraining line, team bench areas ------------
	local ORANGE = Color3.fromRGB(255, 120, 30)
	for _, gy in { 0, -EZ, L, L + EZ } do
		for _, sx in { -1, 1 } do
			part({ Name = "Pylon", Size = Vector3.new(0.7, 2.2, 0.7), Position = at(sx * (W / 2 + 0.4), gy, 1.1), Color = ORANGE, Material = Enum.Material.SmoothPlastic, CanCollide = false }, deco)
		end
	end
	-- midfield logo: a team-tinted circle with the GD mark
	part({ Name = "MidLogo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 30, 30), CFrame = CFrame.new(at(0, L / 2, 0.07)) * CFrame.Angles(0, 0, math.rad(90)), Color = homeColor, Transparency = 0.45, CanCollide = false }, deco)
	paint(deco, "GD", CFrame.new(at(0, L / 2, 0.1)), Vector2.new(12, 20), WHITE, -90, 0.1)
	for _, side in { -1, 1 } do
		-- orange dashed restraining line just outside the sideline
		for yd = -MatchConfig.EndZoneYards, (L + EZ) / Y, 3 do
			part({ Size = Vector3.new(0.5, 0.07, 1.6), Position = at(side * (W / 2 + 5), yd * Y, 0.04), Color = ORANGE, CanCollide = false }, deco)
		end
		-- team bench area between the 30s with a bench
		local benchColor = side < 0 and homeColor or awayColor
		part({ Size = Vector3.new(9, 0.06, L * 0.4), Position = at(side * (W / 2 + 11), L / 2, 0.03), Color = benchColor:Lerp(Color3.new(0, 0, 0), 0.45), CanCollide = false }, deco)
		part({ Size = Vector3.new(1.4, 1.4, L * 0.3), Position = at(side * (W / 2 + 14), L / 2, 0.7), Color = Color3.fromRGB(34, 36, 44), Material = Enum.Material.Metal }, deco)
	end

	-- the bowl: a lower deck, a lit fascia, an upper deck and a roof with light banks ---------------
	-- Every row is one step with a crowd texture on its field-facing face (cheap: a few dozen parts
	-- instead of a thousand single fans).
	local CROWD = "rbxassetid://138227626787476"
	local CONCRETE = Color3.fromRGB(52, 56, 66)
	local function tint(c)
		return Color3.new(1, 1, 1):Lerp(c, 0.2)
	end
	-- one row: at distance `d` outward from the field edge, `h` tall, `len` long. axis "x" = runs
	-- along the sideline (stands on the sides), "y" = runs across the field (end stands)
	local function row(axis, side, edge, d, h, len, center, color)
		local size, pos, face
		if axis == "x" then
			size = Vector3.new(4.2, h, len)
			pos = at(side * (edge + d), center, h / 2)
			face = side > 0 and Enum.NormalId.Left or Enum.NormalId.Right
		else
			size = Vector3.new(len, h, 4.2)
			pos = at(center, edge + side * d, h / 2)
			face = side > 0 and Enum.NormalId.Front or Enum.NormalId.Back
		end
		local step = part({ Size = size, Position = pos, Color = CONCRETE, Material = Enum.Material.Concrete }, deco)
		local tex = Instance.new("Texture")
		tex.Texture = CROWD
		tex.Face = face
		tex.StudsPerTileU = 26
		tex.StudsPerTileV = 6.4
		tex.OffsetStudsV = (h % 6.4) -- keep the fans standing on the step
		tex.Color3 = color
		tex.Parent = step
		return step
	end
	local LOWER, UPPER = 9, 9
	local RISE = 2.6
	local function deck(axis, side, edge, len, center, color, rows0)
		local tops = {}
		for i = 0, LOWER - 1 do
			tops[i] = 2 + i * RISE
			row(axis, side, edge, 24 + i * 4.2, tops[i], len, center, color)
		end
		-- fascia between the decks: a lit ribbon
		local fasciaD = 24 + LOWER * 4.2 + 1
		local fasciaH = tops[LOWER - 1] + 7
		local fascia
		if axis == "x" then
			fascia = part({ Size = Vector3.new(2, fasciaH, len), Position = at(side * (edge + fasciaD), center, fasciaH / 2), Color = Color3.fromRGB(14, 16, 24), Material = Enum.Material.SmoothPlastic }, deco)
		else
			fascia = part({ Size = Vector3.new(len, fasciaH, 2), Position = at(center, edge + side * fasciaD, fasciaH / 2), Color = Color3.fromRGB(14, 16, 24), Material = Enum.Material.SmoothPlastic }, deco)
		end
		for i = 0, UPPER - 1 do
			row(axis, side, edge, fasciaD + 2 + i * 4.2, fasciaH + 2 + i * RISE, len, center, color)
		end
		return fascia, fasciaD, fasciaH, fasciaH + 2 + (UPPER - 1) * RISE, fasciaD + 2 + UPPER * 4.2
	end
	local function ribbonOn(fasciaPart, face)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 10
		sg.LightInfluence = 0
		sg.Brightness = 2
		local bar = Instance.new("TextLabel")
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.fromScale(0, 1)
		bar.Size = UDim2.new(1, 0, 0, 40)
		bar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
		bar.FontFace = FONT
		bar.TextScaled = true
		bar.TextColor3 = Color3.fromRGB(46, 255, 140)
		bar.Text = string.rep("GRIDIRON DYNASTY   ///   ", 8)
		bar.Parent = sg
		sg.Parent = fasciaPart
		self.ribbons = self.ribbons or {}
		table.insert(self.ribbons, bar)
	end
	local sideLen = L + EZ * 2 + 70
	for _, side in { -1, 1 } do
		local color = tint(side < 0 and homeColor or awayColor)
		local fascia, _, _, topH, backD = deck("x", side, W / 2, sideLen, L / 2, color)
		ribbonOn(fascia, side > 0 and Enum.NormalId.Left or Enum.NormalId.Right)
		-- back wall + roof canopy with a light bank along its front edge
		local wallX = side * (W / 2 + backD + 1)
		part({ Size = Vector3.new(2, topH + 14, sideLen), Position = at(wallX, L / 2, (topH + 14) / 2), Color = Color3.fromRGB(26, 28, 36), Material = Enum.Material.Concrete }, deco)
		local roofH = topH + 14
		part({ Size = Vector3.new(30, 1.5, sideLen), Position = at(wallX - side * 15, L / 2, roofH), Color = Color3.fromRGB(30, 32, 40), Material = Enum.Material.Metal }, deco)
		local bankX = wallX - side * 29
		local n = math.max(3, math.floor(sideLen / 60))
		for k = 0, n - 1 do
			local y = -EZ - 35 + (k + 0.5) * sideLen / n
			local bank = part({ Name = "LightBank", Size = Vector3.new(1, 4, sideLen / n * 0.7), CFrame = CFrame.lookAt(at(bankX, y, roofH - 2.5), at(0, y, 0)), Color = Color3.fromRGB(255, 252, 238), Material = Enum.Material.Neon, CanCollide = false }, deco)
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Range = 240
			light.Angle = 75
			light.Brightness = 1.6
			light.Color = Color3.fromRGB(255, 246, 225)
			light.Shadows = false
			light.Parent = bank
		end
	end
	-- home end: a full bowl section behind the end zone (the away end keeps the big screen)
	do
		local fascia = deck("y", -1, -EZ, W + 70, 0, tint(homeColor))
		ribbonOn(fascia, Enum.NormalId.Back)
	end
	-- away end: a low stand under the big screen
	for i = 0, 3 do
		row("y", 1, L + EZ, 24 + i * 4.2, 2 + i * RISE, W + 70, 0, tint(awayColor))
	end

	-- big screen behind the away end zone
	if opts.screen ~= false then
		local scr = part({ Size = Vector3.new(70, 28, 2), Position = at(0, L + EZ + 50, 26), Color = Color3.fromRGB(8, 10, 16), Material = Enum.Material.SmoothPlastic }, deco)
		part({ Size = Vector3.new(4, 26, 4), Position = at(-22, L + EZ + 51, 6), Color = Color3.fromRGB(60, 64, 74), Material = Enum.Material.Metal }, deco)
		part({ Size = Vector3.new(4, 26, 4), Position = at(22, L + EZ + 51, 6), Color = Color3.fromRGB(60, 64, 74), Material = Enum.Material.Metal }, deco)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.CanvasSize = Vector2.new(700, 280)
		sg.LightInfluence = 0
		sg.Brightness = 1.5
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
		bg.Parent = sg
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(Color3.fromRGB(30, 60, 50), Color3.fromRGB(8, 10, 16))
		grad.Parent = bg
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(0.9, 0.42)
		title.Position = UDim2.fromScale(0.05, 0.12)
		title.FontFace = FONT
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(46, 255, 140)
		title.Text = "GRIDIRON DYNASTY"
		title.Parent = bg
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(0.9, 0.22)
		sub.Position = UDim2.fromScale(0.05, 0.62)
		sub.FontFace = FONT
		sub.TextScaled = true
		sub.TextColor3 = WHITE
		sub.Text = opts.screenText or ""
		sub.Parent = bg
		sg.Parent = scr
		self.screenText = sub
	end

	-- invisible walls so nobody wanders off
	for _, side in { -1, 1 } do
		part({ Size = Vector3.new(2, 14, L + EZ * 2 + 40), Position = at(side * (W / 2 + 18), L / 2, 7), Transparency = 1 }, model)
	end
	for _, y in { -EZ - 18, L + EZ + 18 } do
		part({ Size = Vector3.new(W + 36, 14, 2), Position = at(0, y, 7), Transparency = 1 }, model)
	end

	-- markers moved every play (lines on the field + the chain crew's poles on the sideline)
	self.downPole = part({ Name = "DownMarker", Size = Vector3.new(0.5, 7, 0.5), Color = ORANGE, Material = Enum.Material.Neon, CanCollide = false, Transparency = 1 }, model)
	self.chainPole = part({ Name = "ChainMarker", Size = Vector3.new(0.5, 7, 0.5), Color = ORANGE, Material = Enum.Material.Neon, CanCollide = false, Transparency = 1 }, model)
	self.losMarker = part({ Name = "LineOfScrimmage", Size = Vector3.new(W, 0.1, 0.5), Color = Color3.fromRGB(70, 160, 255), CanCollide = false, Material = Enum.Material.Neon, Transparency = 1 }, model)
	self.firstDownMarker = part({ Name = "FirstDown", Size = Vector3.new(W, 0.1, 0.5), Color = Color3.fromRGB(255, 214, 40), CanCollide = false, Material = Enum.Material.Neon, Transparency = 1 }, model)

	model.Parent = workspace
	return self
end

function Field:ToWorld(x, y, h)
	if self.flipped then
		x, y = -x, self.L - y
	end
	return self.origin + Vector3.new(x, GROUND_TOP + (h or 0), -y)
end

function Field:ToField(pos)
	local rel = pos - self.origin
	local x, y = rel.X, -rel.Z
	if self.flipped then
		x, y = -x, self.L - y
	end
	return x, y
end

function Field:Downfield()
	return self.flipped and Vector3.new(0, 0, 1) or Vector3.new(0, 0, -1)
end

function Field:CFrameAt(x, y, h, facingDownfield)
	local p = self:ToWorld(x, y, h)
	local dir = facingDownfield and self:Downfield() or -self:Downfield()
	return CFrame.lookAt(p, p + dir)
end

function Field:SetMarkers(losY, firstDownY)
	local sideX = -(self.W / 2 + 4)
	if self.downPole then
		self.downPole.Position = self:ToWorld(self.flipped and -sideX or sideX, losY, 3.5)
		self.downPole.Transparency = 0
		self.chainPole.Position = self:ToWorld(self.flipped and -sideX or sideX, math.min(firstDownY, self.L), 3.5)
		self.chainPole.Transparency = firstDownY >= self.L and 1 or 0
	end
	self.losMarker.Transparency = 0.45
	self.losMarker.Position = self:ToWorld(0, losY, 0.1)
	self.firstDownMarker.Position = self:ToWorld(0, math.min(firstDownY, self.L), 0.1)
	self.firstDownMarker.Transparency = firstDownY >= self.L and 1 or 0.3
end

function Field:SetScreen(text)
	if self.screenText then
		self.screenText.Text = text
	end
end

function Field:Destroy()
	if self.slot then
		slotsInUse[self.slot] = nil
	end
	self.model:Destroy()
end

return Field

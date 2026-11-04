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

-- opts: { homeName, awayName, homeColor2, awayColor2, crowd = {Color3...}, origin = Vector3 }
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
	self.origin = opts.origin or Vector3.new(3000 + slot * 900, 0, 0)

	local Y = MatchConfig.Yard
	local L = MatchConfig.FieldLength()
	local EZ = MatchConfig.EndZoneYards * Y
	local W = MatchConfig.WidthYards * Y
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
	local stripes = MatchConfig.FieldYards / 5
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
	for yd = 0, MatchConfig.FieldYards, 5 do
		local major = yd % 10 == 0
		part({ Size = Vector3.new(W, 0.08, (yd == 0 or yd == MatchConfig.FieldYards) and 0.9 or (major and 0.45 or 0.3)), Position = at(0, yd * Y, 0.05), Color = WHITE, CanCollide = false, Transparency = major and 0 or 0.25 }, deco)
	end
	for yd = 1, MatchConfig.FieldYards - 1 do
		if yd % 5 ~= 0 then
			for _, x in { -W * 0.16, W * 0.16, -W / 2 + 1.2, W / 2 - 1.2 } do
				part({ Size = Vector3.new(1.4, 0.08, 0.22), Position = at(x, yd * Y, 0.05), Color = WHITE, CanCollide = false, Transparency = 0.15 }, deco)
			end
		end
	end
	for yd = 10, MatchConfig.FieldYards - 10, 10 do
		local n = yd <= MatchConfig.FieldYards / 2 and yd or MatchConfig.FieldYards - yd
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

	-- stands + crowd on both sidelines -----------------------------------------------------
	-- crowd colors are toned down so the stadium lights + bloom don't blow them out
	local crowd = {}
	for _, c in opts.crowd or { homeColor, awayColor, WHITE, Color3.fromRGB(40, 40, 46) } do
		table.insert(crowd, c:Lerp(Color3.fromRGB(30, 30, 38), 0.35))
	end
	local rng = Random.new(self.origin.X)
	local standLen = L + EZ * 2 + 10
	for _, side in { -1, 1 } do
		local x0 = side * (W / 2 + 22)
		for row = 0, 6 do
			local x = x0 + side * row * 5
			local h = row * 3
			part({ Size = Vector3.new(5, h + 2, standLen), Position = at(x, L / 2, h / 2), Color = Color3.fromRGB(58, 62, 72), Material = Enum.Material.Concrete }, deco)
			-- crowd: chunky "fans" in team colors
			local y = -EZ
			while y < L + EZ do
				local len = rng:NextNumber(2.4, 4.2)
				part({ Size = Vector3.new(2.6, rng:NextNumber(2.6, 3.4), len - 0.4), Position = at(x, y + len / 2, h + 2.4), Color = crowd[rng:NextInteger(1, #crowd)], CanCollide = false, Material = Enum.Material.SmoothPlastic }, deco)
				y += len
			end
		end
		-- back wall with LED ribbon
		local xw = x0 + side * 36
		part({ Size = Vector3.new(2, 26, standLen), Position = at(xw, L / 2, 13), Color = Color3.fromRGB(30, 32, 40), Material = Enum.Material.Concrete }, deco)
		local ribbon = part({ Size = Vector3.new(0.4, 3, standLen), Position = at(x0 - side * 1.5, L / 2, 2.2), Color = Color3.fromRGB(10, 12, 18), Material = Enum.Material.SmoothPlastic, CanCollide = false }, deco)
		local sg = Instance.new("SurfaceGui")
		sg.Face = side == 1 and Enum.NormalId.Left or Enum.NormalId.Right
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 12
		sg.LightInfluence = 0
		sg.Brightness = 2
		local bar = Instance.new("TextLabel")
		bar.Size = UDim2.fromScale(1, 1)
		bar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
		bar.FontFace = FONT
		bar.TextScaled = true
		bar.TextColor3 = Color3.fromRGB(46, 255, 140)
		bar.Text = string.rep("GRIDIRON DYNASTY   ///   ", 6)
		bar.Parent = sg
		sg.Parent = ribbon
		self.ribbons = self.ribbons or {}
		table.insert(self.ribbons, bar)
	end

	-- light towers (real SpotLights aimed at the field)
	for _, sx in { -1, 1 } do
		for _, y in { -EZ * 0.5, L + EZ * 0.5 } do
			local base = at(sx * (W / 2 + 62), y, 0)
			part({ Size = Vector3.new(2.5, 70, 2.5), Position = base + Vector3.new(0, 35, 0), Color = Color3.fromRGB(70, 74, 84), Material = Enum.Material.Metal }, deco)
			local head = part({ Size = Vector3.new(14, 8, 1.5), CFrame = CFrame.lookAt(base + Vector3.new(0, 72, 0), mid), Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon }, deco)
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Range = 160
			light.Angle = 60
			light.Brightness = 1.8
			light.Color = Color3.fromRGB(255, 246, 225)
			light.Shadows = false
			light.Parent = head
		end
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

	-- markers moved every play
	self.losMarker = part({ Name = "LineOfScrimmage", Size = Vector3.new(W, 0.1, 0.5), Color = Color3.fromRGB(70, 160, 255), CanCollide = false, Material = Enum.Material.Neon, Transparency = 1 }, model)
	self.firstDownMarker = part({ Name = "FirstDown", Size = Vector3.new(W, 0.1, 0.5), Color = Color3.fromRGB(255, 214, 40), CanCollide = false, Material = Enum.Material.Neon, Transparency = 1 }, model)

	model.Parent = workspace
	return self
end

function Field:ToWorld(x, y, h)
	if self.flipped then
		x, y = -x, MatchConfig.FieldLength() - y
	end
	return self.origin + Vector3.new(x, GROUND_TOP + (h or 0), -y)
end

function Field:ToField(pos)
	local rel = pos - self.origin
	local x, y = rel.X, -rel.Z
	if self.flipped then
		x, y = -x, MatchConfig.FieldLength() - y
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
	self.losMarker.Transparency = 0.45
	self.losMarker.Position = self:ToWorld(0, losY, 0.1)
	self.firstDownMarker.Position = self:ToWorld(0, math.min(firstDownY, MatchConfig.FieldLength()), 0.1)
	self.firstDownMarker.Transparency = firstDownY >= MatchConfig.FieldLength() and 1 or 0.3
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

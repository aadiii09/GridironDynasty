-- CardRenderer (client): Gridiron Dynasty player cards.
-- Layers (bottom to top): dark base -> team-colored energy tint -> team logo watermark ->
-- player figure in team colors -> neon frame in the tier color -> text. Elite and Icon cards
-- get an animated holo shimmer.
--
--   CardRenderer.Create(info, { figure = true, shimmer = true, stats = true }) -> Frame (info from CardData.Describe)
--   CardRenderer.Back(tier?) -> Frame

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Ratings = require(ReplicatedStorage.Shared.Ratings)

local CardRenderer = {}

local WHITE = Color3.new(1, 1, 1)
local FONT_HEAVY = Font.fromEnum(Enum.Font.GothamBlack)
local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local FONT_MED = Font.fromEnum(Enum.Font.GothamMedium)

local function hex(s, fallback)
	if type(s) ~= "string" then
		return fallback
	end
	local ok, c = pcall(Color3.fromHex, s)
	return ok and c or fallback
end

local function new(className, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end

local function label(props)
	local l = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, TextScaled = true, FontFace = FONT_BOLD })
	for k, v in props do
		l[k] = v
	end
	return l
end

local function image(id, props)
	local i = new("ImageLabel", { BackgroundTransparency = 1, Image = id, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch })
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

local function spaced(text)
	return (string.upper(text):gsub("(.)", "%1 "):gsub(" $", ""))
end

local function hasArt()
	return Assets.card_base ~= "" and Assets.card_frame ~= ""
end

-- Footballer figure for the card (pads, helmet with facemask, team colors) -------------------
local function buildFigure(primary, secondary)
	local model = Instance.new("Model")
	local function part(size, cf, color, shape, material)
		local p = new("Part", {
			Size = size,
			CFrame = cf,
			Color = color,
			Anchored = true,
			Material = material or Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local skin = Color3.fromRGB(176, 120, 86)
	local pants = Color3.fromRGB(235, 235, 240)
	local dark = Color3.fromRGB(25, 25, 30)
	-- torso + jersey
	part(Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), primary)
	part(Vector3.new(2.02, 0.22, 1.02), CFrame.new(0, -0.55, 0), secondary)
	-- shoulder pads (rounded with cylinders)
	for _, sx in { -1, 1 } do
		part(Vector3.new(1.0, 1.25, 1.25), CFrame.new(sx * 0.85, 0.82, 0) * CFrame.Angles(0, 0, math.rad(90)), primary, Enum.PartType.Cylinder)
	end
	part(Vector3.new(1.6, 0.5, 1.3), CFrame.new(0, 0.95, 0), primary)
	-- arms: sleeve + skin + glove; right arm cradles the ball
	part(Vector3.new(0.85, 0.9, 0.85), CFrame.new(-1.45, 0.3, 0) * CFrame.Angles(0, 0, math.rad(-10)), primary)
	part(Vector3.new(0.8, 1.1, 0.8), CFrame.new(-1.6, -0.65, 0) * CFrame.Angles(0, 0, math.rad(-6)), skin)
	part(Vector3.new(0.82, 0.4, 0.82), CFrame.new(-1.66, -1.3, 0), secondary)
	part(Vector3.new(0.85, 0.9, 0.85), CFrame.new(1.45, 0.3, -0.1) * CFrame.Angles(math.rad(25), 0, math.rad(10)), primary)
	part(Vector3.new(0.8, 1.1, 0.8), CFrame.new(1.35, -0.45, -0.6) * CFrame.Angles(math.rad(70), 0, math.rad(20)), skin)
	local ball = part(Vector3.new(0.75, 0.75, 1.2), CFrame.new(0.95, -0.55, -0.85) * CFrame.Angles(0, math.rad(25), 0), Color3.fromRGB(122, 66, 36), nil, Enum.Material.Leather)
	new("SpecialMesh", { MeshType = Enum.MeshType.Sphere }).Parent = ball
	-- legs: pants + socks + cleats, mid-stride
	part(Vector3.new(0.95, 1.4, 0.95), CFrame.new(-0.5, -1.7, 0.25) * CFrame.Angles(math.rad(18), 0, 0), pants)
	part(Vector3.new(0.95, 1.4, 0.95), CFrame.new(0.5, -1.6, -0.35) * CFrame.Angles(math.rad(-28), 0, 0), pants)
	part(Vector3.new(0.9, 0.8, 0.9), CFrame.new(-0.5, -2.7, 0.55) * CFrame.Angles(math.rad(18), 0, 0), secondary)
	part(Vector3.new(0.9, 0.8, 0.9), CFrame.new(0.5, -2.45, -0.9) * CFrame.Angles(math.rad(-28), 0, 0), secondary)
	part(Vector3.new(0.95, 0.35, 1.2), CFrame.new(-0.5, -3.15, 0.55), dark)
	part(Vector3.new(0.95, 0.35, 1.2), CFrame.new(0.5, -2.9, -1.1) * CFrame.Angles(math.rad(-20), 0, 0), dark)
	-- helmet: AI-made helmet + pads meshes when available, otherwise built from parts
	part(Vector3.new(0.6, 0.35, 0.6), CFrame.new(0, 1.2, 0), skin)
	local art = ReplicatedStorage:FindFirstChild("Art")
	local helmet = art and art:FindFirstChild("Helmet")
	local pads = art and art:FindFirstChild("Pads")
	if pads then
		local p = pads:Clone()
		p.TextureID = ""
		p.Color = primary
		p.Material = Enum.Material.Fabric
		p.Size = Vector3.new(2.7, 2.3, 1.5)
		p.CFrame = CFrame.new(0, 0.25, 0)
		p.Parent = model
	end
	if helmet then
		local h = helmet:Clone()
		local pivot = h:GetPivot()
		local scale = 2.05 / 1.94
		for _, p in h:GetDescendants() do
			if p:IsA("MeshPart") then
				local rel = pivot:ToObjectSpace(p.CFrame)
				p.TextureID = ""
				p.Color = p.Name == "facemask" and Color3.fromRGB(205, 208, 214) or primary
				p.Material = p.Name == "facemask" and Enum.Material.Metal or Enum.Material.SmoothPlastic
				p.Size = p.Size * scale
				p.CFrame = CFrame.new(0, 2.0, 0) * (rel - rel.Position) + rel.Position * scale
			end
		end
		h.Parent = model
	else
		part(Vector3.new(1.85, 1.85, 1.85), CFrame.new(0, 2.0, 0.05), primary, Enum.PartType.Ball, Enum.Material.SmoothPlastic)
		part(Vector3.new(0.3, 0.3, 1.9), CFrame.new(0, 2.85, 0.05), secondary)
		part(Vector3.new(0.95, 0.75, 0.3), CFrame.new(0, 1.9, -0.72), skin)
		local mask = Color3.fromRGB(210, 210, 215)
		for i, y in { 2.15, 1.85, 1.55 } do
			part(Vector3.new(1.25 - i * 0.12, 0.1, 0.1), CFrame.new(0, y, -0.95), mask)
		end
		for _, x in { -0.25, 0.25 } do
			part(Vector3.new(0.1, 0.7, 0.1), CFrame.new(x, 1.85, -0.97), mask)
		end
	end
	model:PivotTo(CFrame.Angles(0, math.rad(-22), 0))
	return model
end

local function addFigure(parent, primary, secondary)
	local vp = new("ViewportFrame", {
		Name = "Figure",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.92, 0.56),
		Position = UDim2.fromScale(0.04, 0.13),
		-- camera looks toward +Z, so light travels +Z to hit the player's front
		Ambient = Color3.fromRGB(150, 150, 162),
		LightColor = Color3.fromRGB(255, 252, 245),
		LightDirection = Vector3.new(0.45, -0.55, 1),
		ZIndex = 4,
	})
	buildFigure(primary, secondary).Parent = vp
	local cam = new("Camera", { FieldOfView = 28 })
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, -12), Vector3.new(0, -0.35, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = parent
	return vp
end

-- A standalone figure in any jersey (Locker preview). Parts in the jersey color are marked
-- JerseyPrimary so the caller can animate them; material applies to special jerseys.
function CardRenderer.Figure(primary, secondary, material)
	local vp = addFigure(nil, primary, secondary)
	vp.Size = UDim2.fromScale(1, 1)
	vp.Position = UDim2.new()
	-- whole body in view (card faces crop at the knees)
	vp.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(0, -0.3, -16), Vector3.new(0, -0.55, 0))
	local parts = {}
	for _, d in vp:GetDescendants() do
		if d:IsA("BasePart") and d.Color == primary then
			d:SetAttribute("JerseyPrimary", true)
			if material then
				d.Material = Enum.Material[material]
			end
			table.insert(parts, d)
		end
	end
	return vp, parts
end

-- Animated holo sweep across the card (Elite / Icon)
local function addShimmer(root, color)
	local holo = image(Assets.card_tint ~= "" and Assets.card_tint or "", {
		Name = "Shimmer",
		ImageColor3 = color:Lerp(WHITE, 0.5),
		ImageTransparency = 0.35,
		ZIndex = 7,
	})
	if Assets.card_tint == "" then
		holo.BackgroundTransparency = 0.6
		holo.BackgroundColor3 = WHITE
	end
	local grad = new("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	})
	grad.Parent = holo
	holo.Parent = root
	local tween = TweenService:Create(grad, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 1.2), { Offset = Vector2.new(1, 0) })
	tween:Play()
	holo.Destroying:Connect(function()
		tween:Cancel()
	end)
end

function CardRenderer.Create(info, opts)
	opts = opts or {}
	local card = info.card
	local team = info.team or {}
	local primary = hex(team.primary, Color3.fromRGB(40, 40, 50))
	local secondary = hex(team.secondary, WHITE)
	local tierColor = GameConfig.TierColors[card.tier] or WHITE
	local art = hasArt()

	local root = new("Frame", {
		Name = "Card_" .. card.id,
		BackgroundTransparency = art and 1 or 0,
		BackgroundColor3 = Color3.fromRGB(12, 14, 20),
		Size = UDim2.fromOffset(200, 300),
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 2 / 3 }),
	})
	root:SetAttribute("CardId", card.id)

	if art then
		image(Assets.card_base, { Name = "Base", ZIndex = 1 }).Parent = root
		image(Assets.card_tint, { Name = "Tint", ImageColor3 = primary, ZIndex = 2 }).Parent = root
	else
		new("UICorner", { CornerRadius = UDim.new(0.05, 0) }).Parent = root
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(primary, Color3.fromRGB(8, 8, 12)) }).Parent = root
		new("UIStroke", { Color = tierColor, Thickness = opts.stroke or 3 }).Parent = root
	end

	local logo = Assets.Logo(team.id)
	if logo ~= "" then
		image(logo, { Name = "Watermark", ImageTransparency = 0.82, Size = UDim2.fromScale(0.8, 0.533), Position = UDim2.fromScale(0.1, 0.17), ZIndex = 3 }).Parent = root
	end

	if opts.figure ~= false then
		addFigure(root, primary, secondary)
	end

	if art then
		image(Assets.card_frame, { Name = "Frame", ImageColor3 = tierColor, ZIndex = 5 }).Parent = root
	end
	if opts.shimmer ~= false and (card.tier == "Elite" or card.tier == "Icon") then
		addShimmer(root, tierColor)
	end

	-- rating + position
	local ovr = label({ Name = "OVR", Text = tostring(card.ovr), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.36, 0.13), Position = UDim2.fromScale(0.075, 0.05), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 205, 215)) }).Parent = ovr
	ovr.Parent = root
	label({ Name = "POS", Text = card.pos, FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.25, 0.07), Position = UDim2.fromScale(0.08, 0.19), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 }).Parent = root
	if info.number then
		label({ Text = "#" .. info.number, FontFace = FONT_BOLD, TextColor3 = tierColor, Size = UDim2.fromScale(0.2, 0.035), Position = UDim2.fromScale(0.085, 0.292), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 }).Parent = root
	end

	-- brand plate (top right)
	label({ Text = "GRIDIRON\nDYNASTY", FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.34, 0.06), Position = UDim2.fromScale(0.59, 0.058), ZIndex = 8 }).Parent = root
	if card.program ~= "Base" then
		local tag = card.program == "Week Standout" and ("WK " .. card.week .. " STANDOUT") or string.upper(card.program)
		label({ Text = tag, FontFace = FONT_HEAVY, TextColor3 = tierColor, Size = UDim2.fromScale(0.4, 0.032), Position = UDim2.fromScale(0.545, 0.172), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8 }).Parent = root
	end

	-- signature ratings: this player's three best ratings for his position
	local keys = Ratings.Key[card.pos]
	if keys and opts.stats ~= false then
		local top = table.clone(keys)
		table.sort(top, function(a, b)
			return Ratings.Get(card.attrs, a) > Ratings.Get(card.attrs, b)
		end)
		for i = 1, 3 do
			local k = top[i]
			new("Frame", {
				Name = "Stat" .. i,
				BackgroundColor3 = Color3.fromRGB(10, 12, 18),
				BackgroundTransparency = 0.2,
				Size = UDim2.fromScale(0.27, 0.058),
				Position = UDim2.fromScale(0.685, 0.235 + (i - 1) * 0.07),
				ZIndex = 8,
			}, {
				new("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
				new("UIStroke", { Color = tierColor, Transparency = 0.45, Thickness = 1 }),
				label({ Text = tostring(Ratings.Get(card.attrs, k)), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.46, 0.78), Position = UDim2.fromScale(0.05, 0.11), ZIndex = 9 }),
				label({ Text = k, FontFace = FONT_BOLD, TextColor3 = tierColor, Size = UDim2.fromScale(0.42, 0.56), Position = UDim2.fromScale(0.52, 0.22), ZIndex = 9 }),
			}).Parent = root
		end
	end

	-- name plate: logo | FIRST / LAST
	if logo ~= "" then
		image(logo, { Size = UDim2.fromScale(0.21, 0.14), Position = UDim2.fromScale(0.065, 0.695), ZIndex = 8 }).Parent = root
	else
		new("Frame", { BackgroundColor3 = primary, Size = UDim2.fromScale(0.2, 0.133), Position = UDim2.fromScale(0.07, 0.698), ZIndex = 8 }, {
			new("UICorner", { CornerRadius = UDim.new(1, 0) }),
			new("UIStroke", { Color = secondary, Thickness = 2 }),
			label({ Text = team.id or "", FontFace = FONT_HEAVY, TextColor3 = secondary, Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.25), ZIndex = 9 }),
		}).Parent = root
	end
	label({ Text = string.upper(info.first), FontFace = FONT_BOLD, TextColor3 = Color3.fromRGB(225, 228, 235), Size = UDim2.fromScale(0.6, 0.045), Position = UDim2.fromScale(0.33, 0.7), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 }).Parent = root
	local last = label({ Text = string.upper(info.last), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.6, 0.075), Position = UDim2.fromScale(0.33, 0.748), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 195, 205)) }).Parent = last
	last.Parent = root

	label({
		Text = spaced(((team.city or "") .. " " .. (team.name or ""))),
		FontFace = FONT_MED,
		TextColor3 = Color3.fromRGB(215, 218, 226),
		Size = UDim2.fromScale(0.86, 0.03),
		Position = UDim2.fromScale(0.07, 0.866),
		ZIndex = 8,
	}).Parent = root
	label({ Text = string.upper(card.archetype or ""), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.62, 0.036), Position = UDim2.fromScale(0.19, 0.918), ZIndex = 8 }).Parent = root

	return root
end

function CardRenderer.Back(tier)
	local glow = tier and GameConfig.TierColors[tier] or Color3.fromRGB(120, 200, 255)
	local root = new("Frame", {
		Name = "CardBack",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 300),
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 2 / 3 }),
	})
	if Assets.card_back ~= "" then
		image(Assets.card_back, { ImageColor3 = glow:Lerp(WHITE, 0.55), ZIndex = 1 }).Parent = root
		if Assets.card_frame ~= "" then
			image(Assets.card_frame, { Name = "Frame", ImageColor3 = glow, ZIndex = 2 }).Parent = root
		end
	else
		root.BackgroundTransparency = 0
		root.BackgroundColor3 = Color3.fromRGB(16, 20, 32)
		new("UICorner", { CornerRadius = UDim.new(0.05, 0) }).Parent = root
		new("UIStroke", { Color = glow, Thickness = 3 }).Parent = root
	end
	label({ Text = "GRIDIRON DYNASTY", FontFace = FONT_HEAVY, TextColor3 = glow, Size = UDim2.fromScale(0.7, 0.04), Position = UDim2.fromScale(0.15, 0.78), ZIndex = 3 }).Parent = root
	return root
end

return CardRenderer

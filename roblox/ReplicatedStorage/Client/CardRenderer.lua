-- CardRenderer (client): builds a player card GUI in the Gridiron Dynasty style.
-- Layout: OVR + position top-left, brand plate top-right, player figure in team colors,
-- name panel with team badge, spaced team name, archetype tag. Border glows in the tier color.
--
--   CardRenderer.Create(info, { figure = true }) -> Frame   (info from CardData.Describe)
--   CardRenderer.Back(tier?) -> Frame                       (face-down card for pack reveals)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

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

local function darken(c, f)
	return Color3.new(c.R * f, c.G * f, c.B * f)
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
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		TextScaled = true,
		FontFace = FONT_BOLD,
	})
	for k, v in props do
		l[k] = v
	end
	return l
end

local function spaced(text)
	return (string.upper(text):gsub("(.)", "%1 "):gsub(" $", ""))
end

local function corner(scale)
	return new("UICorner", { CornerRadius = UDim.new(scale, 0) })
end

-- Blocky footballer in team colors (head is a helmet with a facemask).
local function buildFigure(primary, secondary)
	local model = Instance.new("Model")
	local function part(name, size, cf, color, shape)
		local p = new("Part", {
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Anchored = true,
			Material = Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local skin = Color3.fromRGB(204, 142, 105)
	part("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), primary)
	part("Pads", Vector3.new(2.7, 0.6, 1.3), CFrame.new(0, 0.85, 0), primary)
	part("Stripe", Vector3.new(2.02, 0.25, 1.02), CFrame.new(0, -0.4, 0), secondary)
	part("LeftArm", Vector3.new(0.9, 2, 0.9), CFrame.new(-1.5, -0.1, 0) * CFrame.Angles(0, 0, math.rad(-8)), primary)
	part("RightArm", Vector3.new(0.9, 2, 0.9), CFrame.new(1.5, 0.1, -0.3) * CFrame.Angles(math.rad(35), 0, math.rad(8)), primary)
	part("LeftHand", Vector3.new(0.85, 0.5, 0.85), CFrame.new(-1.62, -1.2, 0), skin)
	part("RightSleeve", Vector3.new(0.92, 0.35, 0.92), CFrame.new(1.5, 0.75, -0.0) * CFrame.Angles(math.rad(35), 0, math.rad(8)), secondary)
	part("Ball", Vector3.new(0.8, 0.8, 1.3), CFrame.new(1.45, -0.65, -0.95) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(120, 66, 38), Enum.PartType.Ball)
	part("LeftLeg", Vector3.new(0.95, 2, 0.95), CFrame.new(-0.5, -2, 0.15) * CFrame.Angles(math.rad(10), 0, 0), WHITE)
	part("RightLeg", Vector3.new(0.95, 2, 0.95), CFrame.new(0.5, -1.95, -0.25) * CFrame.Angles(math.rad(-18), 0, 0), WHITE)
	part("LeftSock", Vector3.new(0.97, 0.5, 0.97), CFrame.new(-0.5, -2.75, 0.28) * CFrame.Angles(math.rad(10), 0, 0), secondary)
	part("RightSock", Vector3.new(0.97, 0.5, 0.97), CFrame.new(0.5, -2.65, -0.47) * CFrame.Angles(math.rad(-18), 0, 0), secondary)
	part("Neck", Vector3.new(0.6, 0.4, 0.6), CFrame.new(0, 1.15, 0), skin)
	part("Helmet", Vector3.new(1.75, 1.75, 1.75), CFrame.new(0, 1.95, 0), primary, Enum.PartType.Ball)
	part("HelmetStripe", Vector3.new(0.25, 0.25, 1.8), CFrame.new(0, 2.55, 0.05), secondary)
	part("Face", Vector3.new(0.9, 0.7, 0.3), CFrame.new(0, 1.85, -0.72), skin)
	part("MaskBar1", Vector3.new(1.1, 0.12, 0.12), CFrame.new(0, 1.95, -0.92), Color3.fromRGB(30, 30, 30))
	part("MaskBar2", Vector3.new(1.1, 0.12, 0.12), CFrame.new(0, 1.65, -0.92), Color3.fromRGB(30, 30, 30))
	part("MaskBar3", Vector3.new(0.12, 0.6, 0.12), CFrame.new(0, 1.8, -0.95), Color3.fromRGB(30, 30, 30))
	model:PivotTo(CFrame.Angles(0, math.rad(-20), 0))
	return model
end

local function addFigure(parent, primary, secondary)
	local vp = new("ViewportFrame", {
		Name = "Figure",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.9, 0.52),
		Position = UDim2.fromScale(0.05, 0.17),
		Ambient = Color3.fromRGB(150, 150, 150),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.5, -1, -0.8),
		ZIndex = 3,
	})
	local model = buildFigure(primary, secondary)
	model.Parent = vp
	local cam = new("Camera", { FieldOfView = 30 })
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.3, -10.5), Vector3.new(0, -0.15, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = parent
	return vp
end

function CardRenderer.Create(info, opts)
	opts = opts or {}
	local card = info.card
	local team = info.team or {}
	local primary = hex(team.primary, Color3.fromRGB(40, 40, 50))
	local secondary = hex(team.secondary, WHITE)
	local tierColor = GameConfig.TierColors[card.tier] or WHITE

	local root = new("Frame", {
		Name = "Card_" .. card.id,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(200, 300),
		ClipsDescendants = true,
	}, {
		corner(0.05),
		new("UIAspectRatioConstraint", { AspectRatio = 2 / 3 }),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, darken(primary, 0.95)),
				ColorSequenceKeypoint.new(0.6, darken(primary, 0.45)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 12)),
			}),
		}),
		new("UIStroke", { Color = tierColor, Thickness = opts.stroke or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	root:SetAttribute("CardId", card.id)

	-- inner neon frame in team secondary
	new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.92, 0.94),
		Position = UDim2.fromScale(0.04, 0.03),
		ZIndex = 2,
	}, {
		corner(0.04),
		new("UIStroke", { Color = tierColor, Thickness = 1, Transparency = 0.35 }),
	}).Parent = root

	-- big faint team code behind the player
	label({
		Text = team.id or "",
		FontFace = FONT_HEAVY,
		TextTransparency = 0.86,
		Size = UDim2.fromScale(1.1, 0.3),
		Position = UDim2.fromScale(-0.05, 0.3),
		ZIndex = 2,
	}).Parent = root

	label({ Name = "OVR", Text = tostring(card.ovr), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.36, 0.15), Position = UDim2.fromScale(0.07, 0.035), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }).Parent = root
	label({ Name = "POS", Text = card.pos, FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.3, 0.075), Position = UDim2.fromScale(0.08, 0.18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }).Parent = root
	if info.number then
		label({ Text = "#" .. info.number, FontFace = FONT_MED, TextColor3 = secondary, Size = UDim2.fromScale(0.2, 0.045), Position = UDim2.fromScale(0.08, 0.255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }).Parent = root
	end

	-- brand plate
	new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(0.42, 0.085),
		Position = UDim2.fromScale(0.53, 0.045),
		ZIndex = 4,
	}, {
		corner(0.2),
		new("UIStroke", { Color = tierColor, Transparency = 0.5, Thickness = 1 }),
		label({ Text = "GRIDIRON\nDYNASTY", FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), ZIndex = 5 }),
	}).Parent = root

	if card.program ~= "Base" then
		local tag = card.program == "Week Standout" and ("WEEK " .. card.week .. " STANDOUT") or string.upper(card.program)
		label({ Text = tag, FontFace = FONT_HEAVY, TextColor3 = tierColor, Size = UDim2.fromScale(0.42, 0.04), Position = UDim2.fromScale(0.53, 0.14), ZIndex = 5 }).Parent = root
	end

	if opts.figure ~= false then
		addFigure(root, primary, secondary)
	end

	-- name panel
	local panel = new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		Size = UDim2.fromScale(0.92, 0.17),
		Position = UDim2.fromScale(0.04, 0.68),
		ZIndex = 4,
	}, {
		corner(0.12),
		new("UIStroke", { Color = tierColor, Transparency = 0.4, Thickness = 1 }),
	})
	panel.Parent = root
	new("Frame", {
		BackgroundColor3 = primary,
		Size = UDim2.fromScale(0.24, 0.78),
		Position = UDim2.fromScale(0.03, 0.11),
		ZIndex = 5,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		new("UIStroke", { Color = secondary, Thickness = 2 }),
		label({ Text = team.id or "", FontFace = FONT_HEAVY, TextColor3 = secondary, Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.25), ZIndex = 6 }),
	}).Parent = panel
	new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.4, BorderSizePixel = 0, Size = UDim2.fromScale(0.006, 0.7), Position = UDim2.fromScale(0.3, 0.15), ZIndex = 5 }).Parent = panel
	label({ Text = string.upper(info.first), FontFace = FONT_BOLD, Size = UDim2.fromScale(0.64, 0.3), Position = UDim2.fromScale(0.33, 0.08), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }).Parent = panel
	label({ Text = string.upper(info.last), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.64, 0.52), Position = UDim2.fromScale(0.33, 0.38), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }).Parent = panel

	label({
		Text = spaced(((team.city or "") .. " " .. (team.name or ""))),
		FontFace = FONT_MED,
		TextColor3 = Color3.fromRGB(220, 220, 225),
		Size = UDim2.fromScale(0.9, 0.04),
		Position = UDim2.fromScale(0.05, 0.86),
		ZIndex = 5,
	}).Parent = root

	new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(0.72, 0.055),
		Position = UDim2.fromScale(0.14, 0.912),
		ZIndex = 4,
	}, {
		corner(0.3),
		new("UIStroke", { Color = tierColor, Thickness = 1 }),
		label({ Text = string.upper(card.archetype or ""), FontFace = FONT_HEAVY, Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15), ZIndex = 5 }),
	}).Parent = root

	return root
end

function CardRenderer.Back(tier)
	local glow = tier and GameConfig.TierColors[tier] or Color3.fromRGB(90, 100, 120)
	return new("Frame", {
		Name = "CardBack",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(200, 300),
	}, {
		corner(0.05),
		new("UIAspectRatioConstraint", { AspectRatio = 2 / 3 }),
		new("UIStroke", { Color = glow, Thickness = 3 }),
		new("UIGradient", {
			Rotation = 135,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 70, 110)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(22, 28, 44)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(46, 120, 90)),
			}),
		}),
		new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.86, 0.9),
			Position = UDim2.fromScale(0.07, 0.05),
		}, {
			corner(0.05),
			new("UIStroke", { Color = glow, Thickness = 1, Transparency = 0.4 }),
		}),
		label({ Text = "GRIDIRON\nDYNASTY", FontFace = FONT_HEAVY, TextColor3 = glow, Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.1, 0.4) }),
	})
end

return CardRenderer

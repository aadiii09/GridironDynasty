-- Footballer NPCs: R15 rigs in full uniform (helmet + facemask, shoulder pads, jersey numbers,
-- sleeves, gloves, pants, socks, cleats), body size by position, run/idle animations.
-- Driven by their card's attributes.
--
-- If ServerStorage.Art has "Helmet" / "Pads" / "Football" MeshParts (AI-generated), those are
-- used; otherwise the gear is built from parts.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Ratings = require(ReplicatedStorage.Shared.Ratings)

local Npc = {}
Npc.__index = Npc

Npc.CollisionGroup = "Footballers"
pcall(function()
	PhysicsService:RegisterCollisionGroup(Npc.CollisionGroup)
	PhysicsService:CollisionGroupSetCollidable(Npc.CollisionGroup, Npc.CollisionGroup, false)
end)

local SKINS = {
	Color3.fromRGB(234, 192, 160), Color3.fromRGB(204, 142, 105), Color3.fromRGB(160, 102, 70),
	Color3.fromRGB(124, 78, 52), Color3.fromRGB(92, 58, 40),
}
local PANTS = Color3.fromRGB(196, 198, 206) -- off-white so bloom doesn't make them glow
local CLEATS = Color3.fromRGB(22, 22, 26)
local MASK = Color3.fromRGB(205, 208, 214)
local FONT_NUM = Font.fromEnum(Enum.Font.GothamBlack)

local BUILD = { -- body proportions by position group
	OL = { width = 1.18, depth = 1.12, height = 1.02 },
	DL = { width = 1.14, depth = 1.1, height = 1.02 },
	TE = { width = 1.06, depth = 1.04, height = 1.04 },
	LB = { width = 1.05, depth = 1.03, height = 1.0 },
	QB = { width = 1.0, depth = 1.0, height = 1.03 },
	RB = { width = 1.0, depth = 1.0, height = 0.96 },
	WR = { width = 0.94, depth = 0.95, height = 1.04 },
	CB = { width = 0.94, depth = 0.95, height = 1.0 },
	S = { width = 0.97, depth = 0.97, height = 1.0 },
}

local rigCache = {} -- [build key] = Model (plain rig, cloned per NPC)

local function baseRig(pos)
	local b = BUILD[pos] or BUILD.QB
	local key = pos
	if rigCache[key] then
		return rigCache[key]
	end
	local desc = Instance.new("HumanoidDescription")
	desc.WidthScale = b.width
	desc.DepthScale = b.depth
	desc.HeightScale = b.height
	desc.HeadScale = 1
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = "Footballer"
	local head = model:FindFirstChild("Head")
	local face = head and head:FindFirstChildOfClass("Decal")
	if face then
		face:Destroy() -- the helmet covers the face
	end
	rigCache[key] = model
	return model
end

local function weldTo(part, target, offset)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = target.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = target
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	part.Parent = target.Parent
	return part
end

local function newPart(props)
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	return p
end

local function artMesh(name)
	local folder = ReplicatedStorage:FindFirstChild("Art") or ServerStorage:FindFirstChild("Art")
	local mesh = folder and folder:FindFirstChild(name)
	return mesh and mesh:Clone() or nil
end

-- recolor an AI-generated mesh (drop its texture so the team color shows)
local function paint(meshModel, color)
	for _, d in (meshModel:IsA("BasePart") and { meshModel } or meshModel:GetDescendants()) do
		if d:IsA("MeshPart") then
			d.TextureID = ""
			d.Color = color
		elseif d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
end

local function addHelmet(model, primary, secondary)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local mesh = artMesh("Helmet")
	if mesh then
		-- AI helmet: front faces -Z like the head. Scale it to the head, paint shell + mask.
		paint(mesh, primary)
		local mask = mesh:FindFirstChild("facemask", true)
		if mask and mask:IsA("BasePart") then
			mask.Color = MASK
			mask.Material = Enum.Material.Metal
		end
		local shell = mesh:FindFirstChild("shell", true)
		if shell and shell:IsA("BasePart") then
			shell.Reflectance = 0.06
		end
		local scale = head.Size.X * 1.42 / 1.94
		local pivot = mesh:GetPivot()
		for _, p in mesh:GetDescendants() do
			if p:IsA("BasePart") then
				local rel = pivot:ToObjectSpace(p.CFrame)
				p.Size = p.Size * scale
				weldTo(p, head, CFrame.new(0, head.Size.Y * 0.12, head.Size.Z * 0.04) * (rel - rel.Position) + rel.Position * scale)
			end
		end
		return
	end
	-- built helmet: shell, center stripe, facemask bars, ear holes
	weldTo(newPart({ Name = "Helmet", Shape = Enum.PartType.Ball, Size = Vector3.new(1.62, 1.62, 1.62), Color = primary, Material = Enum.Material.SmoothPlastic, Reflectance = 0.08 }), head, CFrame.new(0, 0.14, 0.06))
	weldTo(newPart({ Name = "HelmetStripe", Size = Vector3.new(0.22, 0.12, 1.5), Color = secondary }), head, CFrame.new(0, 0.93, 0.08))
	for i, y in { 0.12, -0.12, -0.36 } do
		weldTo(newPart({ Name = "Mask", Size = Vector3.new(1.05 - i * 0.1, 0.09, 0.09), Color = MASK, Material = Enum.Material.Metal }), head, CFrame.new(0, y, -0.78))
	end
	for _, x in { -0.28, 0.28 } do
		weldTo(newPart({ Name = "Mask", Size = Vector3.new(0.09, 0.55, 0.09), Color = MASK, Material = Enum.Material.Metal }), head, CFrame.new(x, -0.12, -0.8))
	end
	for _, x in { -0.81, 0.81 } do
		weldTo(newPart({ Name = "EarHole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.28, 0.28), Color = Color3.fromRGB(20, 20, 24) }), head, CFrame.new(x, 0.05, 0.05))
	end
end

-- Jersey over shoulder pads: a jersey shell a touch bigger than the torso (the numbers go on it),
-- rounded pads on the shoulders, a collar, sleeve stripes. Built to the torso's own size, so it
-- fits any avatar body.
local function addPads(model, primary, secondary)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso then
		return
	end
	local s = torso.Size
	local shell = weldTo(newPart({ Name = "Pads", Size = Vector3.new(s.X * 1.1, s.Y * 0.98, s.Z * 1.3), Color = primary, Material = Enum.Material.Fabric }), torso, CFrame.new(0, s.Y * 0.03, 0))
	for _, sx in { -1, 1 } do
		-- a rounded pad on top of each shoulder, running front to back
		weldTo(newPart({ Name = "ShoulderPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(s.Z * 1.42, s.X * 0.4, s.X * 0.4), Color = primary, Material = Enum.Material.Fabric }), torso, CFrame.new(sx * s.X * 0.36, s.Y * 0.42, 0) * CFrame.Angles(0, math.rad(90), 0))
	end
	-- V collar, front and back
	for _, z in { -1, 1 } do
		weldTo(newPart({ Name = "Collar", Size = Vector3.new(s.X * 0.36, s.Y * 0.07, 0.05), Color = secondary }), torso, CFrame.new(0, s.Y * 0.46, z * s.Z * 0.66))
	end
	-- sleeves: two stripes near the cuff
	for _, armName in { "LeftUpperArm", "RightUpperArm" } do
		local arm = model:FindFirstChild(armName)
		if arm then
			for _, y in { -0.26, -0.38 } do
				weldTo(newPart({ Name = "SleeveStripe", Size = arm.Size * Vector3.new(1.05, 0.07, 1.05), Color = secondary, Material = Enum.Material.Fabric }), arm, CFrame.new(0, arm.Size.Y * y, 0))
			end
		end
	end
	-- pants stripe down each leg
	for _, legName in { "LeftUpperLeg", "RightUpperLeg" } do
		local leg = model:FindFirstChild(legName)
		if leg then
			local side = legName:find("Left") and -1 or 1
			weldTo(newPart({ Name = "PantsStripe", Size = Vector3.new(0.06, leg.Size.Y * 0.96, leg.Size.Z * 0.22), Color = primary }), leg, CFrame.new(side * leg.Size.X * 0.51, 0, 0))
		end
	end
	return shell
end

local function addNumbers(model, number, lastName, primary, secondary)
	-- on the pads shell when present (it covers the torso), otherwise on the torso
	local torso = model:FindFirstChild("Pads", true) or model:FindFirstChild("UpperTorso")
	if not torso then
		return
	end
	local function surface(face, showName)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.CanvasSize = Vector2.new(200, 200)
		sg.LightInfluence = 1
		sg.Adornee = torso
		if showName then
			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1
			nm.Size = UDim2.fromScale(1, 0.2)
			nm.Position = UDim2.fromScale(0, 0.06)
			nm.FontFace = FONT_NUM
			nm.TextScaled = true
			nm.TextColor3 = secondary
			nm.Text = string.upper(lastName or "")
			nm.Parent = sg
		end
		local num = Instance.new("TextLabel")
		num.BackgroundTransparency = 1
		num.Size = UDim2.fromScale(0.9, showName and 0.68 or 0.78)
		num.Position = UDim2.fromScale(0.05, showName and 0.27 or 0.14)
		num.FontFace = FONT_NUM
		num.TextScaled = true
		num.TextColor3 = secondary
		num.TextStrokeColor3 = primary:Lerp(Color3.new(0, 0, 0), 0.5)
		num.TextStrokeTransparency = 0.2
		num.Text = tostring(number or "")
		num.Parent = sg
		sg.Parent = torso
	end
	surface(Enum.NormalId.Front, false)
	surface(Enum.NormalId.Back, true)
end

-- Paint body parts as a uniform
local function dress(model, primary, secondary, skin, keepHead)
	local colors = {
		Head = skin,
		UpperTorso = primary,
		LowerTorso = PANTS,
		LeftUpperArm = primary, RightUpperArm = primary,
		LeftLowerArm = skin, RightLowerArm = skin,
		LeftHand = secondary, RightHand = secondary,
		LeftUpperLeg = PANTS, RightUpperLeg = PANTS,
		LeftLowerLeg = secondary, RightLowerLeg = secondary,
		LeftFoot = CLEATS, RightFoot = CLEATS,
	}
	if keepHead then
		colors.Head = nil
	end
	for name, color in colors do
		local p = model:FindFirstChild(name)
		if p then
			p.Color = color
			p.Material = name == "UpperTorso" and Enum.Material.Fabric or Enum.Material.SmoothPlastic
		end
	end
end

-- Tag every part painted in the jersey color (so animated jerseys can recolor them on clients),
-- give special jerseys their material, and flag animated ones for Client/JerseyFX.
local function applyJersey(container, primary, jersey)
	if not jersey then
		return
	end
	local function close(c)
		return math.abs(c.R - primary.R) + math.abs(c.G - primary.G) + math.abs(c.B - primary.B) < 0.015
	end
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and close(d.Color) then
			d:SetAttribute("JerseyPrimary", true)
			if jersey.material then
				d.Material = Enum.Material[jersey.material]
				if jersey.material == "Glass" then
					d.Transparency = 0
				end
			end
		end
	end
	if jersey.fx then
		container:SetAttribute("JerseyId", jersey.id)
		CollectionService:AddTag(container, "JerseyFx")
	end
end

function Npc.SetCollisionGroup(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = Npc.CollisionGroup
		end
	end
end

-- A player's own avatar in full uniform (the hub and every game): team jersey with their name
-- and number, pads, helmet, pants, socks, gloves, cleats. Their clothes, body colors and
-- accessories are put away in StoredLook and come back with Unequip.
local BODY_PARTS = { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" }

local function numberFor(character)
	local p = Players:GetPlayerFromCharacter(character)
	local id = p and p.UserId or 0
	return (math.abs(id) % 98) + 1, p and p.DisplayName or ""
end

function Npc.Equip(character, primary, secondary, jersey, number, name)
	local gear = Instance.new("Folder")
	gear.Name = "MatchGear"
	gear.Parent = character
	-- put the avatar's own look away
	local stored = character:FindFirstChild("StoredLook") or Instance.new("Folder")
	stored.Name = "StoredLook"
	stored.Parent = character
	for _, d in character:GetChildren() do
		if d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") then
			d.Parent = stored
		end
	end
	for _, partName in BODY_PARTS do
		local p = character:FindFirstChild(partName)
		if p and p:IsA("BasePart") and p:GetAttribute("OrigColor") == nil then
			p:SetAttribute("OrigColor", p.Color)
			p:SetAttribute("OrigMaterial", p.Material.Name)
		end
	end
	-- skin from their own arms (the head keeps its face and color)
	local arm = character:FindFirstChild("LeftLowerArm")
	local skin = arm and (arm:GetAttribute("OrigColor") or arm.Color) or SKINS[2]
	dress(character, primary, secondary, skin, true)
	local before = {}
	for _, d in character:GetChildren() do
		before[d] = true
	end
	addHelmet(character, primary, secondary)
	addPads(character, primary, secondary)
	for _, d in character:GetChildren() do
		if not before[d] and d:IsA("BasePart") then
			d.Parent = gear
		end
	end
	local defNumber, defName = numberFor(character)
	addNumbers(gear, number or defNumber, name or defName, primary, secondary)
	applyJersey(character, primary, jersey)
	-- every accessory hides (hats and hair under the helmet, the rest under the uniform)
	for _, acc in character:GetChildren() do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle and not handle:GetAttribute("HiddenByGear") then
				handle.LocalTransparencyModifier = 0
				handle:SetAttribute("HiddenByGear", handle.Transparency)
				handle.Transparency = 1
			end
		end
	end
	return gear
end

function Npc.Unequip(character)
	local gear = character:FindFirstChild("MatchGear")
	if gear then
		gear:Destroy()
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local hidden = d:GetAttribute("HiddenByGear")
			if hidden ~= nil then
				d.Transparency = type(hidden) == "number" and hidden or 0
				d:SetAttribute("HiddenByGear", nil)
			end
			local color = d:GetAttribute("OrigColor")
			if color then
				d.Color = color
				d.Material = Enum.Material[d:GetAttribute("OrigMaterial") or "Plastic"]
				d:SetAttribute("OrigColor", nil)
				d:SetAttribute("OrigMaterial", nil)
			end
			d:SetAttribute("JerseyPrimary", nil)
		end
	end
	CollectionService:RemoveTag(character, "JerseyFx")
	character:SetAttribute("JerseyId", nil)
	-- their own clothes and body colors back on
	local stored = character:FindFirstChild("StoredLook")
	if stored then
		for _, d in stored:GetChildren() do
			d.Parent = character
		end
		stored:Destroy()
	end
end

-- card: { ovr, pos, attrs = {...} }, info: { last, number }
function Npc.new(slotId, side, card, info, primary, secondary, parent, jersey)
	local self = setmetatable({}, Npc)
	self.slot = slotId
	self.side = side -- "Offense" / "Defense"
	self.info = info or { last = "" }
	self.card = card
	self.attrs = Ratings.Wrap(card.attrs)
	self.speed = MatchConfig.SpeedFor(self.attrs.SPD)
	self.rampTime = MatchConfig.RampTime(self.attrs.ACC)
	self.accelFrom = 0
	self.stunUntil = 0
	self.engagedUntil = 0
	self.engageFactor = 0
	self.slowUntil = 0
	self.slowFactor = 1
	self.nextThink = 0
	self.target = nil

	local model = baseRig(card.pos):Clone()
	model.Name = slotId
	self.model = model
	self.humanoid = model:FindFirstChildOfClass("Humanoid")
	self.root = model:FindFirstChild("HumanoidRootPart")
	self.humanoid.WalkSpeed = self.speed
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.humanoid.BreakJointsOnDeath = false
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

	local skin = SKINS[(tonumber((card.pid or ""):sub(-2), 16) or slotId:len()) % #SKINS + 1]
	dress(model, primary, secondary, skin)
	addPads(model, primary, secondary)
	addHelmet(model, primary, secondary)
	addNumbers(model, info and info.number, info and info.last, primary, secondary)
	applyJersey(model, primary, jersey)
	Npc.SetCollisionGroup(model)

	-- name tag
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(120, 26)
	tag.StudsOffset = Vector3.new(0, 3.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	label.TextScaled = true
	label.Text = ("%s %s"):format(card.pos, string.upper(info and info.last or ""))
	label.Parent = tag
	tag.Parent = model:FindFirstChild("Head")
	self.tagLabel = label

	model.Parent = parent
	self.root:SetNetworkOwner(nil)

	-- animations (Roblox's default R15 run/idle)
	local animator = self.humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.humanoid)
	local function load(id, priority)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, a)
		if ok then
			track.Priority = priority
			return track
		end
		return nil
	end
	self.runTrack = load(Assets.Animations.run, Enum.AnimationPriority.Movement)
	self.idleTrack = load(Assets.Animations.idle, Enum.AnimationPriority.Idle)
	if self.idleTrack then
		self.idleTrack:Play(0.2)
	end
	return self
end

-- Called ~10x a second: run animation follows actual speed.
function Npc:Animate()
	if self.hidden or not self.runTrack then
		return
	end
	local speed = self:Velocity().Magnitude
	if speed > 1.5 then
		if not self.runTrack.IsPlaying then
			self.runTrack:Play(0.15)
		end
		self.runTrack:AdjustSpeed(math.clamp(speed / 16, 0.6, 1.6))
	elseif self.runTrack.IsPlaying then
		self.runTrack:Stop(0.2)
	end
end

-- Knocked down by a tackle
function Npc:Fall()
	if self.hidden then
		return
	end
	self.humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	self.root:ApplyImpulse(self.root.CFrame.LookVector * self.root.AssemblyMass * 12 + Vector3.new(0, self.root.AssemblyMass * 8, 0))
end

function Npc:SetTag(text, color)
	self.tagLabel.Text = text
	self.tagLabel.TextColor3 = color or Color3.new(1, 1, 1)
end

function Npc:Place(cf)
	self.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	self.model:PivotTo(cf + Vector3.new(0, 3, 0))
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.root.AssemblyAngularVelocity = Vector3.zero
	self.humanoid:Move(Vector3.zero)
	self.target = nil
	self.stunUntil = 0
	self.engagedUntil = 0
	self.slowUntil = 0
	if self.runTrack and self.runTrack.IsPlaying then
		self.runTrack:Stop(0.1)
	end
end

function Npc:Position()
	return self.root.Position
end

function Npc:Velocity()
	local v = self.root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z)
end

function Npc:Hide(hidden)
	if hidden and self.hidden then
		return
	end
	self.hidden = hidden
	for _, d in self.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.Transparency = hidden and 1 or (d.Name == "HumanoidRootPart" and 1 or 0)
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d.Enabled = not hidden
		elseif d:IsA("Decal") then
			d.Transparency = hidden and 1 or 0
		end
	end
	self.root.Anchored = hidden
	if hidden then
		self.model:PivotTo(self.model:GetPivot() - Vector3.new(0, 40, 0))
	elseif self.root:IsDescendantOf(workspace) then
		-- unanchoring resets the network owner to automatic (the nearest player's client would
		-- run his physics, and anything welded to him drifts): keep him on the server
		pcall(self.root.SetNetworkOwner, self.root, nil)
	end
end

-- Move toward a world position at this NPC's speed: builds up to top speed (ACC) from the
-- snap or after being knocked off stride, slowed while blocked/jammed or making a cut.
function Npc:MoveTo(pos, now)
	if self.hidden then
		return
	end
	local speed = self.speed * MatchConfig.Ramp(self.rampTime, now - self.accelFrom)
	if now < self.stunUntil then
		speed = 0
		self.accelFrom = self.stunUntil
	elseif now < self.engagedUntil then
		speed *= (1 - self.engageFactor)
	end
	if now < self.slowUntil then
		speed *= self.slowFactor
	end
	self.humanoid.WalkSpeed = speed
	if speed > 0 then
		self.humanoid:MoveTo(pos)
	else
		self.humanoid:Move(Vector3.zero)
	end
end

function Npc:Destroy()
	self.model:Destroy()
end

return Npc

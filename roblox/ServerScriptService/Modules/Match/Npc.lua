-- Footballer NPCs: blocky R15 rigs in team colors, driven by their card's attributes.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local Npc = {}
Npc.__index = Npc

Npc.CollisionGroup = "Footballers"
pcall(function()
	PhysicsService:RegisterCollisionGroup(Npc.CollisionGroup)
	PhysicsService:CollisionGroupSetCollidable(Npc.CollisionGroup, Npc.CollisionGroup, false)
end)

local SKIN = Color3.fromRGB(204, 142, 105)
local templates = {} -- [colorKey] = Model (CreateHumanoidModelFromDescription is slow-ish; clone instead)

local function template(primary, secondary)
	local key = primary:ToHex() .. secondary:ToHex()
	if templates[key] then
		return templates[key]
	end
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = SKIN
	desc.TorsoColor = primary
	desc.LeftArmColor = primary
	desc.RightArmColor = primary
	desc.LeftLegColor = secondary
	desc.RightLegColor = secondary
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = "Footballer"
	-- helmet
	local head = model:FindFirstChild("Head")
	if head then
		local helmet = Instance.new("Part")
		helmet.Name = "Helmet"
		helmet.Shape = Enum.PartType.Ball
		helmet.Size = Vector3.new(1.75, 1.75, 1.75)
		helmet.Color = primary
		helmet.Material = Enum.Material.SmoothPlastic
		helmet.CanCollide = false
		helmet.Massless = true
		helmet.CFrame = head.CFrame * CFrame.new(0, 0.15, 0.1)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = helmet
		weld.Parent = helmet
		helmet.Parent = model
	end
	templates[key] = model
	return model
end

function Npc.SetCollisionGroup(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = Npc.CollisionGroup
		end
	end
end

-- card: { ovr, pos, attrs = {...} }, info: { last, number }
function Npc.new(slotId, side, card, info, primary, secondary, parent)
	local self = setmetatable({}, Npc)
	self.slot = slotId
	self.side = side -- "Offense" / "Defense"
	self.info = info or { last = "" }
	self.card = card
	self.attrs = card.attrs
	self.speed = MatchConfig.SpeedFor(card.attrs.SPD)
	self.stunUntil = 0
	self.engagedUntil = 0
	self.engageFactor = 0
	self.nextThink = 0
	self.target = nil

	local model = template(primary, secondary):Clone()
	model.Name = slotId
	self.model = model
	self.humanoid = model:FindFirstChildOfClass("Humanoid")
	self.root = model:FindFirstChild("HumanoidRootPart")
	self.humanoid.WalkSpeed = self.speed
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.humanoid.BreakJointsOnDeath = false
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	Npc.SetCollisionGroup(model)

	-- name tag
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(110, 34)
	tag.StudsOffset = Vector3.new(0, 3.4, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = ("%s %s"):format(card.pos, string.upper(info and info.last or ""))
	label.Parent = tag
	tag.Parent = model:FindFirstChild("Head")
	self.tagLabel = label

	model.Parent = parent
	self.root:SetNetworkOwner(nil)
	return self
end

function Npc:SetTag(text, color)
	self.tagLabel.Text = text
	self.tagLabel.TextColor3 = color or Color3.new(1, 1, 1)
end

function Npc:Place(cf)
	self.model:PivotTo(cf + Vector3.new(0, 3, 0))
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.humanoid:Move(Vector3.zero)
	self.target = nil
	self.stunUntil = 0
	self.engagedUntil = 0
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
		elseif d:IsA("BillboardGui") then
			d.Enabled = not hidden
		elseif d:IsA("Decal") then
			d.Transparency = hidden and 1 or 0
		end
	end
	self.root.Anchored = hidden
	if hidden then
		self.model:PivotTo(self.model:GetPivot() - Vector3.new(0, 40, 0))
	end
end

-- Move toward a world position at this NPC's speed, slowed when blocked/engaged.
function Npc:MoveTo(pos, now)
	if self.hidden then
		return
	end
	local speed = self.speed
	if now < self.stunUntil then
		speed = 0
	elseif now < self.engagedUntil then
		speed *= (1 - self.engageFactor)
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

-- Builds one 7v7 field for a match, far from the lobby so several matches can run at once.
-- field:ToWorld(x, y, h) converts field coords (x sideways, y studs downfield) to world space.
-- Downfield is world -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local Field = {}
Field.__index = Field

local GROUND_TOP = 1
local slotsInUse = {}

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

function Field.new(homeColor, awayColor)
	local slot = 1
	while slotsInUse[slot] do
		slot += 1
	end
	slotsInUse[slot] = true

	local self = setmetatable({}, Field)
	self.slot = slot
	self.origin = Vector3.new(3000 + slot * 700, 0, 0)

	local L = MatchConfig.FieldLength()
	local EZ = MatchConfig.EndZoneYards * MatchConfig.Yard
	local W = MatchConfig.WidthYards * MatchConfig.Yard
	local model = Instance.new("Model")
	model.Name = "MatchField_" .. slot
	self.model = model

	local center = self:ToWorld(0, L / 2, 0)
	part({ Name = "Ground", Size = Vector3.new(W + 60, 2, L + EZ * 2 + 60), Position = Vector3.new(center.X, GROUND_TOP - 1, center.Z), Color = Color3.fromRGB(46, 120, 58), Material = Enum.Material.Grass }, model)
	part({ Name = "Turf", Size = Vector3.new(W, 0.05, L), Position = Vector3.new(center.X, GROUND_TOP + 0.02, center.Z), Color = Color3.fromRGB(56, 140, 66), CanCollide = false }, model)
	part({ Name = "HomeEndZone", Size = Vector3.new(W, 0.06, EZ), Position = self:ToWorld(0, -EZ / 2, 0.03), Color = homeColor, CanCollide = false }, model)
	part({ Name = "AwayEndZone", Size = Vector3.new(W, 0.06, EZ), Position = self:ToWorld(0, L + EZ / 2, 0.03), Color = awayColor, CanCollide = false }, model)

	-- yard lines every 5 yards + sidelines
	for yd = 0, MatchConfig.FieldYards, 5 do
		part({ Size = Vector3.new(W, 0.07, yd % 10 == 0 and 0.5 or 0.3), Position = self:ToWorld(0, yd * MatchConfig.Yard, 0.04), Color = Color3.new(1, 1, 1), CanCollide = false, Transparency = yd % 10 == 0 and 0 or 0.35 }, model)
	end
	for _, side in { -1, 1 } do
		part({ Size = Vector3.new(0.8, 0.08, L + EZ * 2), Position = self:ToWorld(side * W / 2, L / 2, 0.05), Color = Color3.new(1, 1, 1), CanCollide = false }, model)
		-- low invisible walls so nobody wanders off the ground
		part({ Size = Vector3.new(2, 12, L + EZ * 2 + 60), Position = self:ToWorld(side * (W / 2 + 30), L / 2, 6), Transparency = 1 }, model)
	end
	for _, y in { -EZ - 30, L + EZ + 30 } do
		part({ Size = Vector3.new(W + 60, 12, 2), Position = self:ToWorld(0, y, 6), Transparency = 1 }, model)
	end

	-- markers moved every play
	self.losMarker = part({ Name = "LineOfScrimmage", Size = Vector3.new(W, 0.1, 0.5), Color = Color3.fromRGB(70, 160, 255), CanCollide = false, Material = Enum.Material.Neon }, model)
	self.firstDownMarker = part({ Name = "FirstDown", Size = Vector3.new(W, 0.1, 0.5), Color = Color3.fromRGB(255, 214, 40), CanCollide = false, Material = Enum.Material.Neon }, model)

	model.Parent = workspace
	return self
end

-- Coordinates are always in the frame of the team with the ball: y = studs from THEIR own
-- goal line toward the goal they attack. When the CPU has the ball, `flipped` mirrors the
-- frame so the CPU drives toward your end zone.
function Field:ToWorld(x, y, h)
	if self.flipped then
		x, y = -x, MatchConfig.FieldLength() - y
	end
	return self.origin + Vector3.new(x, GROUND_TOP + (h or 0), -y)
end

-- Field coords (x, y) of a world position, in the offense's frame
function Field:ToField(pos)
	local rel = pos - self.origin
	local x, y = rel.X, -rel.Z
	if self.flipped then
		x, y = -x, MatchConfig.FieldLength() - y
	end
	return x, y
end

-- World direction the offense is attacking
function Field:Downfield()
	return self.flipped and Vector3.new(0, 0, 1) or Vector3.new(0, 0, -1)
end

-- Facing downfield (for the offense) or upfield (for the defense)
function Field:CFrameAt(x, y, h, facingDownfield)
	local p = self:ToWorld(x, y, h)
	local dir = facingDownfield and self:Downfield() or -self:Downfield()
	return CFrame.lookAt(p, p + dir)
end

function Field:SetMarkers(losY, firstDownY)
	self.losMarker.Position = self:ToWorld(0, losY, 0.08)
	self.firstDownMarker.Position = self:ToWorld(0, math.min(firstDownY, MatchConfig.FieldLength()), 0.08)
	self.firstDownMarker.Transparency = firstDownY >= MatchConfig.FieldLength() and 1 or 0
end

function Field:Destroy()
	slotsInUse[self.slot] = nil
	self.model:Destroy()
end

return Field

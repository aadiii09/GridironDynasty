-- JerseyFX (client): animates special jerseys (rainbow, galaxy, lava, neon pulse, metal shine).
-- The server tags each player model (or the avatar's gear folder) wearing one with "JerseyFx"
-- and marks the jersey-colored parts with the JerseyPrimary attribute; every client recolors
-- those parts locally, about 30 times a second.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Jerseys = require(ReplicatedStorage.Shared.Jerseys)

local JerseyFX = {}

local tracked = {} -- [container] = { jersey, parts = { BasePart } }
local started = false

local function track(container)
	local jersey = Jerseys.ById[container:GetAttribute("JerseyId") or ""]
	if not jersey or not jersey.fx then
		return
	end
	local parts = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("JerseyPrimary") then
			table.insert(parts, d)
		end
	end
	tracked[container] = { jersey = jersey, parts = parts }
end

function JerseyFX.Start()
	if started then
		return
	end
	started = true
	for _, c in CollectionService:GetTagged("JerseyFx") do
		task.defer(track, c)
	end
	CollectionService:GetInstanceAddedSignal("JerseyFx"):Connect(function(c)
		task.delay(0.2, track, c) -- let its parts replicate first
	end)
	CollectionService:GetInstanceRemovedSignal("JerseyFx"):Connect(function(c)
		tracked[c] = nil
	end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		acc = 0
		local t = os.clock()
		for container, entry in tracked do
			if not container.Parent then
				tracked[container] = nil
			else
				for _, p in entry.parts do
					-- height on the body shifts the pattern so colors flow up the player
					p.Color = Jerseys.ColorAt(entry.jersey, t, p.Position.Y * 0.07 + p.Position.X * 0.01)
				end
			end
		end
	end)
end

return JerseyFX

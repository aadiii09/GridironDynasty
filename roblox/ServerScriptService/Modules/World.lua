-- World look: evening stadium lighting (atmosphere, bloom, color grading) and the lobby
-- stadium that replaces the plain baseplate at runtime.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Field = require(ServerScriptService.Modules.Match.Field)

local World = {}

local function effect(className, name, props)
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in props do
		e[k] = v
	end
	e.Parent = Lighting
	return e
end

function World.SetupLighting()
	Lighting.ClockTime = 17.1 -- late-afternoon golden light, stadium lights on
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(96, 92, 108)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 144, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	effect("Atmosphere", "StadiumAtmosphere", {
		Density = 0.24,
		Offset = 0.2,
		Color = Color3.fromRGB(255, 214, 180),
		Decay = Color3.fromRGB(140, 120, 160),
		Glare = 0.3,
		Haze = 1.1,
	})
	effect("BloomEffect", "StadiumBloom", { Intensity = 0.45, Size = 24, Threshold = 1.4 })
	effect("ColorCorrectionEffect", "StadiumGrade", { Contrast = 0.12, Saturation = 0.12, Brightness = 0.02, TintColor = Color3.fromRGB(255, 246, 236) })
	effect("SunRaysEffect", "StadiumRays", { Intensity = 0.06, Spread = 0.6 })
end

function World.BuildLobby()
	local L = MatchConfig.LobbyField.FieldYards * MatchConfig.Yard
	local origin = Vector3.new(0, 0, L / 2) -- midfield at the world origin
	local lobby = Field.new(Color3.fromRGB(16, 120, 80), Color3.fromRGB(16, 120, 80), {
		origin = origin,
		dims = MatchConfig.LobbyField,
		name = "LobbyStadium",
		homeName = "GRIDIRON",
		awayName = "DYNASTY",
		screenText = "OPEN PACKS  -  BUILD YOUR LINEUP  -  PLAY",
		crowd = { Color3.fromRGB(46, 255, 140), Color3.fromRGB(20, 22, 30), Color3.fromRGB(240, 240, 245), Color3.fromRGB(64, 160, 255), Color3.fromRGB(255, 196, 46) },
	})
	lobby.losMarker.Transparency = 1
	lobby.firstDownMarker.Transparency = 1

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawn then
		spawn.CFrame = CFrame.new(0, 1.5, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		for _, d in spawn:GetChildren() do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
	end
	return lobby
end

return World

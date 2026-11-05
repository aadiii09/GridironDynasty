-- Hub: you only see your own player on the stage. Everyone in the server stands around midfield
-- of the lobby stadium, and other players (in their gear, name tags on) piled up around you and
-- blocked the showroom view. Players in a game are far away on their own field, so only
-- characters near the lobby are hidden, and only on this client.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local LOBBY_RADIUS = 140 -- the lobby stadium sits around the world origin; match fields are 3000+ away

local hiddenChars = {} -- [Model] = true

local function setHidden(char, hide)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = hide and 1 or 0
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			if hide then
				if d.Enabled then
					d:SetAttribute("HubHidden", true)
					d.Enabled = false
				end
			elseif d:GetAttribute("HubHidden") then
				d:SetAttribute("HubHidden", nil)
				d.Enabled = true
			end
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = hide and Enum.HumanoidDisplayDistanceType.None or Enum.HumanoidDisplayDistanceType.Viewer
	end
	hiddenChars[char] = hide or nil
end

local function inHub()
	local ui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("GridironUI")
	return ui ~= nil and ui.Enabled
end

while true do
	local hub = inHub()
	for _, other in Players:GetPlayers() do
		local char = other ~= player and other.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local hide = hub and root.Position.Magnitude < LOBBY_RADIUS
			if hide or hiddenChars[char] then
				setHidden(char, hide)
			end
		end
	end
	for char in hiddenChars do
		if not char.Parent then
			hiddenChars[char] = nil
		end
	end
	task.wait(0.5)
end

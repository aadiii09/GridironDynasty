-- Studio sync helper (run through the Studio MCP execute_luau tool while
-- `python -m http.server 8766 --bind 127.0.0.1 --directory roblox` is running).
-- Copies every file listed below from roblox/ into the open place.
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8766/"
local files = {
	"ReplicatedStorage/Shared/GameConfig.lua",
	"ReplicatedStorage/Shared/PackConfig.lua",
	"ReplicatedStorage/Shared/LineupConfig.lua",
	"ServerScriptService/Modules/LineupService.lua",
	"ReplicatedStorage/Client/CardData.lua",
	"ReplicatedStorage/Client/CardRenderer.lua",
	"ServerScriptService/Modules/CardDatabase.lua",
	"ServerScriptService/Modules/PlayerData.lua",
	"ServerScriptService/Modules/PackService.lua",
	"ServerScriptService/Bootstrap.server.lua",
	"StarterPlayer/StarterPlayerScripts/MainUI.client.lua",
}
local out = {}
for _, path in files do
	local class = path:match("%.server%.lua$") and "Script" or path:match("%.client%.lua$") and "LocalScript" or "ModuleScript"
	local src = HttpService:GetAsync(BASE .. path, true)
	local parts = string.split(path, "/")
	local parent = game:GetService(parts[1])
	for i = 2, #parts - 1 do
		local child = parent:FindFirstChild(parts[i])
		if not child then
			child = Instance.new("Folder")
			child.Name = parts[i]
			child.Parent = parent
		end
		parent = child
	end
	local name = parts[#parts]:gsub("%.server%.lua$", ""):gsub("%.client%.lua$", ""):gsub("%.lua$", "")
	local inst = parent:FindFirstChild(name)
	if inst and inst.ClassName ~= class then
		inst:Destroy()
		inst = nil
	end
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		inst.Parent = parent
	end
	inst.Source = src
	table.insert(out, inst:GetFullName())
end
return "synced " .. #out .. " scripts:\n" .. table.concat(out, "\n")

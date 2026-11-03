-- Client-side card lookup. Reads the JSON the server mirrors into ReplicatedStorage.CardData.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardData = {}

local data, byId, teamsById = nil, {}, {}
local loadedVersion = -1

local function rebuild()
	local folder = ReplicatedStorage:WaitForChild("CardData")
	while (folder:GetAttribute("Version") or 0) == 0 do
		folder:GetAttributeChangedSignal("Version"):Wait()
	end
	local version = folder:GetAttribute("Version")
	if version == loadedVersion then
		return
	end
	local parts = folder:GetChildren()
	table.sort(parts, function(a, b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)
	local buf = table.create(#parts)
	for i, part in parts do
		buf[i] = part.Value
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, table.concat(buf))
	if not ok then
		task.wait(1) -- chunks still replicating
		return rebuild()
	end
	data = decoded
	table.clear(byId)
	table.clear(teamsById)
	for _, card in data.cards do
		byId[card.id] = card
	end
	for _, team in data.teams do
		teamsById[team.id] = team
	end
	loadedVersion = version
end

function CardData.Ensure()
	rebuild()
	return data
end

function CardData.Get(cardId)
	return byId[cardId]
end

function CardData.Player(pid)
	return data and data.players[pid]
end

function CardData.Team(teamId)
	return teamsById[teamId]
end

function CardData.All()
	return data and data.cards or {}
end

-- Full display info for one card id.
function CardData.Describe(cardId)
	local card = byId[cardId]
	if not card then
		return nil
	end
	local player = data.players[card.pid] or {}
	return {
		card = card,
		first = player.first or "?",
		last = player.last or "?",
		number = player.number,
		team = teamsById[card.team],
	}
end

ReplicatedStorage:WaitForChild("CardData"):GetAttributeChangedSignal("Version"):Connect(function()
	task.spawn(rebuild)
end)

return CardData

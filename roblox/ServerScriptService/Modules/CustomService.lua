-- CustomService (server): custom 7v7 lobbies for friends in the same server.
-- Someone creates a lobby, others join from the PLAY -> CUSTOM list (INVITE brings friends into
-- this server). Everyone picks a team (HOME / AWAY) and one offensive + one defensive spot; the
-- host starts the game. Empty spots are AI. When the game ends the lobby stays, ready to go again.
-- Remotes: CustomLobby (RemoteFunction: action, ...) and CustomLobbyEvent (server -> client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LineupConfig = require(ReplicatedStorage.Shared.LineupConfig)
local CardDatabase = require(ServerScriptService.Modules.CardDatabase)
local PlayerData = require(ServerScriptService.Modules.PlayerData)
local MatchService = require(ServerScriptService.Modules.Match.MatchService)

local CustomService = {}

local MAX_PER_TEAM = 7
local OFF_ORDER = { "QB", "WR1", "WR2", "RB", "TE", "OL1", "OL2" } -- also the order spots are handed out
local DEF_ORDER = { "CB1", "CB2", "S", "LB1", "LB2", "DL1", "DL2" }
local POSITIONS = { "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S" }

local lobbies = {} -- [id] = lobby
local lobbyOf = {} -- [Player] = lobby
local nextId = 1
local lastAction = {} -- [Player] = os.clock()
local event

local function log(...)
	print("[Custom]", ...)
end

-- Spots -----------------------------------------------------------------------------------------

local function teamCount(lobby, team)
	local n = 0
	for _, spot in lobby.spots do
		if spot.team == team then
			n += 1
		end
	end
	return n
end

-- who (other than `except`) has this spot on this team
local function takenBy(lobby, team, field, slotId, except)
	for p, spot in lobby.spots do
		if p ~= except and spot.team == team and spot[field] == slotId then
			return p
		end
	end
	return nil
end

local function freeSlot(lobby, team, field, order, except)
	for _, slotId in order do
		if takenBy(lobby, team, field, slotId, except) == nil then
			return slotId
		end
	end
	return nil
end

-- the player's best OVR at each position (shown on the spot buttons)
local function bestOvrs(player)
	local out = {}
	local profile = PlayerData.Get(player)
	for _, entry in (profile and profile.data.cards or {}) do
		local card = CardDatabase.Get(entry.id)
		if card and (out[card.pos] or 0) < card.ovr then
			out[card.pos] = card.ovr
		end
	end
	for _, pos in POSITIONS do
		out[pos] = out[pos] or 0
	end
	return out
end

-- Views --------------------------------------------------------------------------------------------

local function view(lobby)
	local players = {}
	for _, p in lobby.members do
		local spot = lobby.spots[p]
		table.insert(players, {
			userId = p.UserId,
			name = p.DisplayName,
			team = spot.team,
			off = spot.off,
			def = spot.def,
			host = p == lobby.host,
			busy = MatchService.InMatch(p),
			ovrs = bestOvrs(p),
		})
	end
	return { id = lobby.id, hostId = lobby.host.UserId, hostName = lobby.host.DisplayName, inGame = lobby.inGame, players = players, maxPerTeam = MAX_PER_TEAM }
end

local function summaries()
	local out = {}
	for _, lobby in lobbies do
		table.insert(out, { id = lobby.id, hostName = lobby.host.DisplayName, hostId = lobby.host.UserId, count = #lobby.members, max = MAX_PER_TEAM * 2, inGame = lobby.inGame })
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function push(lobby)
	local v = view(lobby)
	for _, p in lobby.members do
		event:FireClient(p, { kind = "lobby", lobby = v })
	end
end

local function listChanged()
	event:FireAllClients({ kind = "list" })
end

-- Membership -------------------------------------------------------------------------------------

local function addMember(lobby, player)
	local team = teamCount(lobby, "home") <= teamCount(lobby, "away") and "home" or "away"
	if teamCount(lobby, team) >= MAX_PER_TEAM then
		team = team == "home" and "away" or "home"
	end
	table.insert(lobby.members, player)
	lobby.spots[player] = { team = team }
	lobby.spots[player].off = freeSlot(lobby, team, "off", OFF_ORDER, player)
	lobby.spots[player].def = freeSlot(lobby, team, "def", DEF_ORDER, player)
	lobbyOf[player] = lobby
end

local function removeMember(player)
	local lobby = lobbyOf[player]
	if not lobby then
		return
	end
	lobbyOf[player] = nil
	lobby.spots[player] = nil
	local i = table.find(lobby.members, player)
	if i then
		table.remove(lobby.members, i)
	end
	if player.Parent then
		event:FireClient(player, { kind = "left" })
	end
	if #lobby.members == 0 then
		lobbies[lobby.id] = nil
	else
		if lobby.host == player then
			lobby.host = lobby.members[1]
		end
		push(lobby)
	end
	listChanged()
end

-- Starting a game --------------------------------------------------------------------------------

local function start(lobby)
	local home, away = {}, {}
	for _, p in lobby.members do
		local spot = lobby.spots[p]
		if not MatchService.InMatch(p) then
			table.insert(spot.team == "home" and home or away, { player = p, off = spot.off, def = spot.def })
		end
	end
	if #home + #away == 0 then
		return { ok = false, err = "Everyone is in another game." }
	end
	local okStart, err = MatchService.StartCustom({
		home = home,
		away = away,
		onEnd = function()
			lobby.inGame = false
			if lobbies[lobby.id] == lobby then
				push(lobby)
				listChanged()
			end
		end,
	})
	if not okStart then
		return { ok = false, err = err or "Couldn't start the game." }
	end
	lobby.inGame = true
	log(("%s started a custom game: %d vs %d players"):format(lobby.host.Name, #home, #away))
	push(lobby)
	listChanged()
	return { ok = true }
end

-- Remote --------------------------------------------------------------------------------------------

local function onAction(player, action, a, b)
	if type(action) ~= "string" then
		return { ok = false }
	end
	local now = os.clock()
	if action ~= "get" then
		if lastAction[player] and now - lastAction[player] < 0.25 then
			return { ok = false, err = "Slow down!" }
		end
		lastAction[player] = now
	end
	local lobby = lobbyOf[player]

	if action == "get" then
		return { ok = true, mine = lobby and view(lobby) or nil, list = summaries() }
	elseif action == "create" then
		if lobby then
			return { ok = false, err = "You're already in a custom game." }
		end
		if not PlayerData.Get(player) then
			return { ok = false, err = "Still loading, try again in a moment." }
		end
		lobby = { id = nextId, host = player, members = {}, spots = {}, inGame = false }
		nextId += 1
		lobbies[lobby.id] = lobby
		addMember(lobby, player)
		push(lobby)
		listChanged()
		return { ok = true }
	elseif action == "join" then
		local target = lobbies[a]
		if type(a) ~= "number" or not target then
			return { ok = false, err = "That game is gone." }
		end
		if lobby == target then
			return { ok = true }
		end
		if #target.members >= MAX_PER_TEAM * 2 then
			return { ok = false, err = "That game is full." }
		end
		if lobby then
			removeMember(player)
		end
		addMember(target, player)
		push(target)
		listChanged()
		return { ok = true }
	end

	if not lobby then
		return { ok = false, err = "You're not in a custom game." }
	end
	local spot = lobby.spots[player]

	if action == "leave" then
		removeMember(player)
		return { ok = true }
	elseif action == "team" then
		if a ~= "home" and a ~= "away" then
			return { ok = false }
		end
		if spot.team == a then
			return { ok = true }
		end
		if teamCount(lobby, a) >= MAX_PER_TEAM then
			return { ok = false, err = "That team is full." }
		end
		spot.team = a
		-- keep the same spots if they're free on the new team, otherwise the next free ones
		if takenBy(lobby, a, "off", spot.off, player) then
			spot.off = freeSlot(lobby, a, "off", OFF_ORDER, player)
		end
		if takenBy(lobby, a, "def", spot.def, player) then
			spot.def = freeSlot(lobby, a, "def", DEF_ORDER, player)
		end
		push(lobby)
		return { ok = true }
	elseif action == "pos" then
		local order = a == "off" and OFF_ORDER or a == "def" and DEF_ORDER
		if not order or type(b) ~= "string" or not table.find(order, b) then
			return { ok = false }
		end
		local who = takenBy(lobby, spot.team, a, b, player)
		if who then
			return { ok = false, err = who.DisplayName .. " already plays " .. LineupConfig.ById[b].label .. "." }
		end
		spot[a] = b
		push(lobby)
		return { ok = true }
	elseif action == "start" then
		if lobby.host ~= player then
			return { ok = false, err = "Only the host can start the game." }
		end
		if lobby.inGame then
			return { ok = false, err = "The game is already running." }
		end
		return start(lobby)
	end
	return { ok = false }
end

function CustomService.Start(remotes)
	event = remotes:WaitForChild("CustomLobbyEvent")
	remotes:WaitForChild("CustomLobby").OnServerInvoke = onAction
	Players.PlayerRemoving:Connect(function(player)
		removeMember(player)
		lastAction[player] = nil
	end)
end

return CustomService

-- MatchServer (server): runs when this server is a reserved head-to-head match server (two
-- players from different servers were matched and teleported here).
--   * who plays comes from the server-side match record (H2HService), never from the client
--   * waits for both players, then starts the ranked game
--   * anyone else, or anyone left when the game is over, goes back to a public server
--   * if the opponent never shows up, the player who did is sent back (no rating change)

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local PlayerData = require(ServerScriptService.Modules.PlayerData)
local CardDatabase = require(ServerScriptService.Modules.CardDatabase)
local MatchService = require(ServerScriptService.Modules.Match.MatchService)

local MatchServer = {}

local ARRIVE_TIMEOUT = 90

function MatchServer.IsMatchServer()
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function log(...)
	print("[MatchServer]", ...)
end

function MatchServer.Start(remotes, h2h)
	workspace:SetAttribute("MatchServer", true)
	local sentBack = {}

	local function backToLobby(player, reason)
		if sentBack[player] or not player.Parent then
			return
		end
		sentBack[player] = true
		remotes.H2HEvent:FireClient(player, { type = "returning", reason = reason })
		task.wait(2.5)
		for attempt = 1, 3 do
			local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player })
			if ok then
				return
			end
			warn("[MatchServer] teleport back failed:", err)
			task.wait(3)
		end
		player:Kick("Your game is over - please rejoin Gridiron Dynasty.")
	end

	-- who's playing here
	local record
	for _ = 1, 15 do
		record = h2h.GetMatchRecord(game.PrivateServerId)
		if record then
			break
		end
		task.wait(1)
	end
	if not record then
		log("no match record for this server, sending everyone back")
		local function sendBack(p)
			task.spawn(backToLobby, p, "This match isn't available anymore.")
		end
		Players.PlayerAdded:Connect(sendBack)
		for _, p in Players:GetPlayers() do
			sendBack(p)
		end
		return
	end
	workspace:SetAttribute("MatchRanked", record.ranked == true)
	log("match", record.matchId, "between", record.a, "and", record.b)

	local started = false
	local function expected(player)
		return player.UserId == record.a or player.UserId == record.b
	end

	local function tryStart()
		if started then
			return
		end
		local a, b = Players:GetPlayerByUserId(record.a), Players:GetPlayerByUserId(record.b)
		if not (a and b) then
			return
		end
		if not (PlayerData.Get(a) and PlayerData.Get(b) and CardDatabase.IsReady() and a.Character and b.Character) then
			return
		end
		started = true
		local ok, err = MatchService.StartH2H(a, b, record.ranked == true)
		if not ok then
			warn("[MatchServer] couldn't start:", err)
			task.spawn(backToLobby, a, "Couldn't start the game.")
			task.spawn(backToLobby, b, "Couldn't start the game.")
		end
	end

	local function onJoin(player)
		if not expected(player) then
			task.spawn(backToLobby, player, "This is a private match.")
			return
		end
		remotes.H2HEvent:FireClient(player, { type = "matchServer", ranked = record.ranked == true })
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in Players:GetPlayers() do
		onJoin(p)
	end

	-- after the game (or a forfeit), each player heads back to the main game
	MatchService.PlayerExited.Event:Connect(function(player)
		task.spawn(backToLobby, player, "Game over - heading back to the lobby.")
	end)

	task.spawn(function()
		local t0 = os.clock()
		while not started and os.clock() - t0 < ARRIVE_TIMEOUT do
			tryStart()
			task.wait(1)
		end
		if not started then
			log("opponent never arrived")
			for _, p in Players:GetPlayers() do
				task.spawn(backToLobby, p, "Your opponent couldn't make it. No rating change - try again!")
			end
		end
	end)
end

return MatchServer

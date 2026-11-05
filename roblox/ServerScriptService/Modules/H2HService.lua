-- H2HService (server): online head-to-head.
--   Ranked quick match: a queue shared by EVERY server (MemoryStore). Each server pairs its own
--     searching players with the closest-rated player anywhere (the allowed rating gap widens
--     the longer you wait). Same server: the game starts right here. Different servers: a
--     private match server is reserved and both players are teleported into it (MatchServer).
--     If MemoryStore is down, it falls back to matching players in this server.
--   Friendly challenge: invite a player in this server; if they accept, an unranked game starts.
--
-- Pairing is race-safe: an entry is "claimed" with an atomic UpdateAsync before anything else
-- happens, so two servers can never grab the same player.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local RankConfig = require(ReplicatedStorage.Shared.RankConfig)
local PlayerData = require(ServerScriptService.Modules.PlayerData)
local MatchService = require(ServerScriptService.Modules.Match.MatchService)

local H2HService = {}

local STUDIO = RunService:IsStudio()
-- Studio sessions use their own queue so they never match live players
local QUEUE_NAME = STUDIO and "H2HQueue_Studio_v1" or "H2HQueue_v1"
local ENTRY_TTL = 45 -- seconds; refreshed while searching, so entries of dead servers vanish
local TICK = 2

local remotes
local queue = {} -- local searchers: { { player, joinedAt, status } }
local invites = {} -- [id] = { from, to, expiresAt }
local nextInvite = 0
local globalMap, matchRecords
local globalOk = true

local function log(...)
	print("[H2H]", ...)
end

local function h2hOf(player)
	local profile = PlayerData.Get(player)
	local h = profile and profile.data.h2h
	return h or { rating = RankConfig.StartRating, wins = 0, losses = 0, ties = 0 }
end

local function info(player)
	local h = h2hOf(player)
	local div = RankConfig.Division(h.rating)
	return { rating = h.rating, wins = h.wins, losses = h.losses, ties = h.ties, division = div.name }
end

local function send(player, payload)
	if player.Parent then
		remotes.H2HEvent:FireClient(player, payload)
	end
end

local function inQueue(player)
	for i, q in queue do
		if q.player == player then
			return i, q
		end
	end
	return nil
end

local function keyOf(player)
	return tostring(player.UserId)
end

local globalCount = 0

local function broadcastQueue()
	for _, q in queue do
		send(q.player, { type = "queue", searching = true, count = math.max(globalCount, #queue), since = q.joinedAt, global = globalOk })
	end
end

local function removeGlobal(player)
	if globalMap then
		pcall(globalMap.RemoveAsync, globalMap, keyOf(player))
	end
end

local function leaveQueue(player)
	local i = inQueue(player)
	if i then
		table.remove(queue, i)
	end
end

local function cancelInvitesFor(player)
	for id, inv in invites do
		if inv.from == player or inv.to == player then
			invites[id] = nil
			local otherPlayer = inv.from == player and inv.to or inv.from
			send(otherPlayer, { type = "inviteCancelled", id = id })
		end
	end
end

-- Start a game between two players who are both in this server
local function startHere(a, b, ranked)
	leaveQueue(a)
	leaveQueue(b)
	cancelInvitesFor(a)
	cancelInvitesFor(b)
	local ok, err = MatchService.StartH2H(a, b, ranked)
	if ok then
		log(("%s vs %s (%s, this server)"):format(a.Name, b.Name, ranked and "ranked" or "friendly"))
		send(a, { type = "matched", opponent = b.DisplayName, ranked = ranked })
		send(b, { type = "matched", opponent = a.DisplayName, ranked = ranked })
	else
		send(a, { type = "error", err = "Couldn't start the game: " .. tostring(err) })
		send(b, { type = "error", err = "Couldn't start the game: " .. tostring(err) })
	end
	return ok
end

-- Global queue ----------------------------------------------------------------------------

-- claim an entry for a match (atomic). Returns the claimed entry or nil if it was gone/taken.
local function claim(key, matchId, opponentName)
	local claimed
	local ok = pcall(function()
		globalMap:UpdateAsync(key, function(old)
			if not old or old.claimed then
				return nil -- gone or already taken: leave it alone
			end
			old.claimed = matchId
			old.claimedAt = os.time()
			old.opponent = opponentName
			claimed = old
			return old
		end, ENTRY_TTL)
	end)
	return ok and claimed or nil
end

local function unclaim(key, matchId)
	pcall(function()
		globalMap:UpdateAsync(key, function(old)
			if old and old.claimed == matchId then
				old.claimed = nil
				old.opponent = nil
				return old
			end
			return nil
		end, ENTRY_TTL)
	end)
end

local function setAccess(key, matchId, accessCode)
	local ok = pcall(function()
		globalMap:UpdateAsync(key, function(old)
			if old and old.claimed == matchId then
				old.access = accessCode
				return old
			end
			return nil
		end, ENTRY_TTL)
	end)
	return ok
end

-- keep our searchers' entries alive (and see if someone claimed them)
local function refreshEntries()
	for _, q in queue do
		local p = q.player
		local h = h2hOf(p)
		local ok, entry = pcall(function()
			local result
			globalMap:UpdateAsync(keyOf(p), function(old)
				if old and old.claimed then
					if not old.access and os.time() - (old.claimedAt or 0) > 20 then
						-- the server that claimed us never finished (crashed?): back in the queue
						old.claimed, old.claimedAt, old.opponent = nil, nil, nil
					else
						result = old
						return old -- claimed: keep as is
					end
				end
				result = { rating = h.rating, joinedAt = q.joinedAt, job = game.JobId, name = p.DisplayName }
				return result
			end, ENTRY_TTL)
			return result
		end)
		if not ok then
			globalOk = false
			return
		end
		q.entry = entry
	end
	globalOk = true
end

local function teleportToMatch(player, accessCode, opponent)
	leaveQueue(player)
	removeGlobal(player)
	send(player, { type = "teleporting", opponent = opponent })
	if STUDIO then
		send(player, { type = "error", err = "Matched with a player in another server - teleporting only works in the published game." })
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		warn("[H2H] teleport failed:", err)
		send(player, { type = "error", err = "Couldn't join the match server. Try again." })
	end
end

-- our searchers whose entry was claimed by another server (or by us): go play
local function followClaims()
	for _, q in table.clone(queue) do
		local e = q.entry
		if e and e.claimed and e.access then
			log(q.player.Name, "matched across servers vs", e.opponent)
			send(q.player, { type = "matched", opponent = e.opponent or "PLAYER", ranked = true, remote = true })
			teleportToMatch(q.player, e.access, e.opponent)
		end
	end
end

-- Pair one of our searchers (oldest first) with the best unclaimed entry anywhere
local function matchmakeGlobal()
	if #queue == 0 then
		return
	end
	local ok, items = pcall(globalMap.GetRangeAsync, globalMap, Enum.SortDirection.Ascending, 200)
	if not ok then
		globalOk = false
		return
	end
	globalCount = 0
	local now = os.time()
	local entries = {}
	for _, item in items do
		local v = item.value
		if type(v) == "table" and not v.claimed then
			globalCount += 1
			entries[item.key] = v
		end
	end
	table.sort(queue, function(x, y)
		return x.joinedAt < y.joinedAt
	end)
	for _, q in queue do
		local me = q.player
		local myKey = keyOf(me)
		local mine = entries[myKey]
		if mine then
			local myRating = h2hOf(me).rating
			local bestKey, best, bestGap
			for key, v in entries do
				if key ~= myKey then
					local gap = math.abs((v.rating or RankConfig.StartRating) - myRating)
					local allowed = 100 + 25 * math.min(now - q.joinedAt, now - (v.joinedAt or now))
					if gap <= allowed and (not bestGap or gap < bestGap) then
						bestKey, best, bestGap = key, v, gap
					end
				end
			end
			if bestKey then
				local matchId = HttpService:GenerateGUID(false)
				local opponentLocal = best.job == game.JobId and Players:GetPlayerByUserId(tonumber(bestKey))
				-- claim ourselves, then them; back out if they're gone
				if claim(myKey, matchId, best.name) then
					if claim(bestKey, matchId, me.DisplayName) then
						entries[myKey], entries[bestKey] = nil, nil
						if opponentLocal then
							removeGlobal(me)
							removeGlobal(opponentLocal)
							startHere(me, opponentLocal, true)
						else
							local okReserve, accessCode, privateServerId = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
							if okReserve then
								-- the match server reads who's playing from here (not from the client)
								pcall(matchRecords.SetAsync, matchRecords, privateServerId, { a = tonumber(myKey), b = tonumber(bestKey), ranked = true, matchId = matchId }, 900)
								setAccess(bestKey, matchId, accessCode)
								setAccess(myKey, matchId, accessCode)
								log(me.Name, "matched with", best.name, "in another server")
								send(me, { type = "matched", opponent = best.name, ranked = true, remote = true })
								teleportToMatch(me, accessCode, best.name)
							else
								warn("[H2H] couldn't reserve a match server:", accessCode)
								unclaim(bestKey, matchId)
								unclaim(myKey, matchId)
								if STUDIO then
									leaveQueue(me)
									removeGlobal(me)
									send(me, { type = "error", err = "Found a player in another server - cross-server games only work in the published game." })
								end
							end
						end
					else
						unclaim(myKey, matchId)
					end
				end
				return -- one pairing per tick keeps it simple and avoids races
			end
		end
	end
end

-- Fallback when MemoryStore is unavailable: pair players in this server
local function matchmakeLocal()
	if #queue < 2 then
		return
	end
	local now = os.time()
	local bestI, bestJ, bestGap
	for i = 1, #queue do
		for j = i + 1, #queue do
			local a, b = queue[i], queue[j]
			local gap = math.abs(h2hOf(a.player).rating - h2hOf(b.player).rating)
			local allowed = 100 + 25 * math.min(now - a.joinedAt, now - b.joinedAt)
			if gap <= allowed and (not bestGap or gap < bestGap) then
				bestI, bestJ, bestGap = i, j, gap
			end
		end
	end
	if bestI then
		startHere(queue[bestI].player, queue[bestJ].player, true)
	end
end

local function tick()
	if #queue == 0 then
		return
	end
	if globalMap then
		refreshEntries()
	end
	if globalMap and globalOk then
		followClaims()
		matchmakeGlobal()
	else
		matchmakeLocal()
	end
	broadcastQueue()
end

-- Remotes -----------------------------------------------------------------------------------

local function onQueue(player, action)
	if action == "leave" then
		local _, q = inQueue(player)
		if q and q.entry and q.entry.claimed then
			return { ok = false, err = "Match found - joining!" }
		end
		leaveQueue(player)
		removeGlobal(player)
		send(player, { type = "queue", searching = false })
		return { ok = true }
	end
	if MatchService.InMatch(player) then
		return { ok = false, err = "You're already in a game." }
	end
	if not PlayerData.Get(player) then
		return { ok = false, err = "Still loading." }
	end
	if workspace:GetAttribute("MatchServer") then
		return { ok = false, err = "Finish this game first." }
	end
	if not inQueue(player) then
		table.insert(queue, { player = player, joinedAt = os.time() })
	end
	task.spawn(tick)
	return { ok = true, count = math.max(globalCount, #queue) }
end

local function onChallenge(player, targetUserId)
	local target = typeof(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return { ok = false, err = "That player isn't here." }
	end
	if MatchService.InMatch(player) or MatchService.InMatch(target) then
		return { ok = false, err = "One of you is already in a game." }
	end
	for _, inv in invites do
		if inv.from == player then
			return { ok = false, err = "You already have a challenge out." }
		end
	end
	nextInvite += 1
	local id = tostring(nextInvite)
	local inv = { from = player, to = target, expiresAt = os.time() + RankConfig.ChallengeSeconds }
	invites[id] = inv
	send(target, { type = "invite", id = id, from = player.DisplayName, fromId = player.UserId, info = info(player), expiresAt = inv.expiresAt })
	task.delay(RankConfig.ChallengeSeconds, function()
		if invites[id] == inv then
			invites[id] = nil
			send(player, { type = "declined", name = target.DisplayName, reason = "didn't answer" })
			send(target, { type = "inviteCancelled", id = id })
		end
	end)
	return { ok = true, expiresAt = inv.expiresAt }
end

local function onRespond(player, id, accept)
	local inv = invites[id]
	if not inv or inv.to ~= player then
		return { ok = false, err = "That challenge has expired." }
	end
	invites[id] = nil
	if not accept then
		send(inv.from, { type = "declined", name = player.DisplayName, reason = "declined" })
		return { ok = true }
	end
	if not inv.from.Parent then
		return { ok = false, err = "They left the server." }
	end
	removeGlobal(inv.from)
	removeGlobal(player)
	local ok = startHere(inv.from, player, false)
	return { ok = ok }
end

local function onInfo(player)
	PlayerData.WaitFor(player, 30)
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local i = info(p)
			table.insert(others, { userId = p.UserId, name = p.DisplayName, rating = i.rating, division = i.division, busy = MatchService.InMatch(p) })
		end
	end
	return { me = info(player), players = others, queued = inQueue(player) ~= nil, queueCount = math.max(globalCount, #queue), global = globalMap ~= nil and globalOk }
end

function H2HService.Start(remoteFolder)
	remotes = remoteFolder
	local ok, map = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, QUEUE_NAME)
	if ok then
		globalMap = map
		matchRecords = MemoryStoreService:GetHashMap(STUDIO and "H2HMatches_Studio_v1" or "H2HMatches_v1")
	else
		warn("[H2H] MemoryStore unavailable, matching within this server only:", map)
	end
	remotes.H2HQueue.OnServerInvoke = onQueue
	remotes.H2HChallenge.OnServerInvoke = onChallenge
	remotes.H2HRespond.OnServerInvoke = onRespond
	remotes.GetH2HInfo.OnServerInvoke = onInfo
	Players.PlayerRemoving:Connect(function(player)
		local i, q = inQueue(player)
		if i then
			leaveQueue(player)
			if not (q.entry and q.entry.claimed) then
				removeGlobal(player)
			end
		end
		cancelInvitesFor(player)
	end)
	task.spawn(function()
		while true do
			task.wait(TICK + math.random() * 0.8) -- jitter so servers don't all pair at the same instant
			local okTick, err = pcall(tick)
			if not okTick then
				warn("[H2H] tick error:", err)
			end
		end
	end)
end

-- For MatchServer: who should be in this reserved match server
function H2HService.GetMatchRecord(privateServerId)
	if not matchRecords then
		return nil
	end
	local ok, rec = pcall(matchRecords.GetAsync, matchRecords, privateServerId)
	return ok and rec or nil
end

return H2HService

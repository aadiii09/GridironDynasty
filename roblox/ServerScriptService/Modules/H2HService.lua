-- H2HService (server): online head-to-head between players in this server.
--   Ranked quick match: join the queue; you're paired with the closest-rated player (the
--     allowed rating gap widens the longer you wait). Rating, wins and division on the line.
--   Friendly challenge: invite a specific player; if they accept, an unranked game starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RankConfig = require(ReplicatedStorage.Shared.RankConfig)
local PlayerData = require(ServerScriptService.Modules.PlayerData)
local MatchService = require(ServerScriptService.Modules.Match.MatchService)

local H2HService = {}

local remotes
local queue = {} -- { { player, joinedAt } }
local invites = {} -- [id] = { from, to, expiresAt }
local nextInvite = 0

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
			return i
		end
	end
	return nil
end

local function leaveQueue(player)
	local i = inQueue(player)
	if i then
		table.remove(queue, i)
	end
end

local function broadcastQueue()
	for _, q in queue do
		send(q.player, { type = "queue", searching = true, count = #queue, since = q.joinedAt })
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

local function start(a, b, ranked)
	leaveQueue(a)
	leaveQueue(b)
	cancelInvitesFor(a)
	cancelInvitesFor(b)
	local ok, err = MatchService.StartH2H(a, b, ranked)
	if ok then
		log(("%s vs %s (%s)"):format(a.Name, b.Name, ranked and "ranked" or "friendly"))
		send(a, { type = "matched", opponent = b.DisplayName, ranked = ranked })
		send(b, { type = "matched", opponent = a.DisplayName, ranked = ranked })
	else
		send(a, { type = "error", err = "Couldn't start the game: " .. tostring(err) })
		send(b, { type = "error", err = "Couldn't start the game: " .. tostring(err) })
	end
	return ok
end

-- pair the queue: closest ratings first, allowed gap = 100 + 25 per second waited
local function matchmake()
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
		local a, b = queue[bestI].player, queue[bestJ].player
		start(a, b, true)
		broadcastQueue()
	end
end

local function onQueue(player, action)
	if action == "leave" then
		leaveQueue(player)
		send(player, { type = "queue", searching = false })
		broadcastQueue()
		return { ok = true }
	end
	if MatchService.InMatch(player) then
		return { ok = false, err = "You're already in a game." }
	end
	if not PlayerData.Get(player) then
		return { ok = false, err = "Still loading." }
	end
	if not inQueue(player) then
		table.insert(queue, { player = player, joinedAt = os.time() })
	end
	broadcastQueue()
	task.defer(matchmake)
	return { ok = true, count = #queue }
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
	local ok = start(inv.from, player, false)
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
	return { me = info(player), players = others, queued = inQueue(player) ~= nil, queueCount = #queue }
end

function H2HService.Start(remoteFolder)
	remotes = remoteFolder
	remotes.H2HQueue.OnServerInvoke = onQueue
	remotes.H2HChallenge.OnServerInvoke = onChallenge
	remotes.H2HRespond.OnServerInvoke = onRespond
	remotes.GetH2HInfo.OnServerInvoke = onInfo
	Players.PlayerRemoving:Connect(function(player)
		leaveQueue(player)
		cancelInvitesFor(player)
		broadcastQueue()
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			matchmake()
		end
	end)
end

return H2HService

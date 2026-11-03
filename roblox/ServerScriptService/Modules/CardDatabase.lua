-- CardDatabase (server)
-- Loads cards.json from (1) GitHub Pages, (2) the DataStore cache of the last good download,
-- (3) the snapshot bundled in ServerStorage.CardSnapshot, and keeps whichever has the highest
-- version. Card ratings are fixed, so a higher version is always a superset of a lower one.
-- The chosen JSON is mirrored into ReplicatedStorage.CardData so clients can read it.

local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CHUNK = 150000 -- StringValue size limit is 200k characters
local CACHE_KEY = "latest"

local CardDatabase = {}

local data = nil
local byId = {}
local byPlayer = {}
local pools = {} -- pools[program][tier] = { card, ... }
local readySignal = Instance.new("BindableEvent")
local cacheStore = nil

local function log(...)
	print("[CardDatabase]", ...)
end

local function decode(json)
	if type(json) ~= "string" or #json < 2 then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and type(decoded) == "table" and type(decoded.cards) == "table" and type(decoded.version) == "number" then
		return decoded
	end
	return nil
end

local function readChunks(folder)
	if not folder then
		return nil
	end
	local parts = folder:GetChildren()
	table.sort(parts, function(a, b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)
	local out = table.create(#parts)
	for i, part in parts do
		out[i] = part.Value
	end
	return table.concat(out)
end

local function writeChunks(folder, json)
	folder:ClearAllChildren()
	local i = 0
	for start = 1, #json, CHUNK do
		i += 1
		local sv = Instance.new("StringValue")
		sv.Name = tostring(i)
		sv.Value = string.sub(json, start, start + CHUNK - 1)
		sv.Parent = folder
	end
end

local function getCacheStore()
	if cacheStore == nil then
		local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, "CardDataCache_v1")
		cacheStore = ok and store or false
	end
	return cacheStore or nil
end

local function fromHttp()
	local ok, body = pcall(HttpService.GetAsync, HttpService, GameConfig.CardDataUrl .. "?t=" .. os.time(), true)
	if not ok then
		log("download failed:", body)
		return nil
	end
	return body
end

local function fromCache()
	local store = getCacheStore()
	if not store then
		return nil
	end
	local ok, body = pcall(store.GetAsync, store, CACHE_KEY)
	return ok and body or nil
end

local function saveCache(json)
	local store = getCacheStore()
	if store then
		local ok, err = pcall(store.SetAsync, store, CACHE_KEY, json)
		if not ok then
			log("cache save failed:", err)
		end
	end
end

local function index(newData, json)
	data = newData
	table.clear(byId)
	table.clear(byPlayer)
	table.clear(pools)
	for _, card in newData.cards do
		byId[card.id] = card
		byPlayer[card.pid] = byPlayer[card.pid] or {}
		table.insert(byPlayer[card.pid], card)
		pools[card.program] = pools[card.program] or {}
		pools[card.program][card.tier] = pools[card.program][card.tier] or {}
		table.insert(pools[card.program][card.tier], card)
	end

	local folder = ReplicatedStorage:FindFirstChild("CardData")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CardData"
		folder.Parent = ReplicatedStorage
	end
	writeChunks(folder, json)
	folder:SetAttribute("Version", newData.version)
end

-- Fetch all sources and switch to the newest. Safe to call again later (periodic refresh).
function CardDatabase.Refresh()
	local best, bestJson, bestSource = nil, nil, nil
	local cacheVersion = 0
	local sources = {
		{ "http", fromHttp },
		{ "cache", fromCache },
		{ "snapshot", function()
			return readChunks(ServerStorage:FindFirstChild("CardSnapshot"))
		end },
	}
	for _, source in sources do
		local name, fetch = source[1], source[2]
		local json = fetch()
		local decoded = decode(json)
		if decoded then
			if name == "cache" then
				cacheVersion = decoded.version
			end
			if not best or decoded.version > best.version then
				best, bestJson, bestSource = decoded, json, name
			end
		end
	end

	if not best then
		warn("[CardDatabase] no card data available from any source")
		return false
	end
	if data and best.version <= data.version then
		return true -- already on the newest
	end

	index(best, bestJson)
	log(("loaded v%d from %s: %d cards, season %d week %d"):format(best.version, bestSource, #best.cards, best.season, best.week))
	if bestSource == "http" and best.version > cacheVersion then
		task.spawn(saveCache, bestJson)
	end
	readySignal:Fire()
	return true
end

function CardDatabase.Start()
	CardDatabase.Refresh()
	task.spawn(function()
		while true do
			task.wait(GameConfig.CardDataRefreshSeconds)
			CardDatabase.Refresh()
		end
	end)
end

function CardDatabase.WaitReady()
	while not data do
		readySignal.Event:Wait()
	end
end

function CardDatabase.IsReady()
	return data ~= nil
end

function CardDatabase.Version()
	return data and data.version or 0
end

function CardDatabase.Get(cardId)
	return byId[cardId]
end

function CardDatabase.GetPlayerInfo(pid)
	return data and data.players[pid]
end

function CardDatabase.GetCardsForPlayer(pid)
	return byPlayer[pid] or {}
end

function CardDatabase.All()
	return data and data.cards or {}
end

function CardDatabase.Teams()
	return data and data.teams or {}
end

function CardDatabase.GetTeam(teamId)
	if not data then
		return nil
	end
	for _, team in data.teams do
		if team.id == teamId then
			return team
		end
	end
	return nil
end

-- All cards in a program + tier (e.g. "Base", "Common"), optionally filtered.
function CardDatabase.Pool(program, tier, filter)
	local pool = pools[program] and pools[program][tier] or {}
	if not filter then
		return pool
	end
	local out = {}
	for _, card in pool do
		if filter(card) then
			table.insert(out, card)
		end
	end
	return out
end

-- Every card of a tier across all programs (used for pack odds and pulls).
function CardDatabase.TierPool(tier)
	local out = {}
	for _, tiers in pools do
		for _, card in tiers[tier] or {} do
			table.insert(out, card)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function CardDatabase.RandomFrom(pool, rng)
	if #pool == 0 then
		return nil
	end
	return pool[(rng or Random.new()):NextInteger(1, #pool)]
end

-- Studio-only helper: store a JSON string as the bundled snapshot.
function CardDatabase.SetSnapshot(json)
	assert(RunService:IsStudio(), "snapshot can only be set in Studio")
	assert(decode(json), "invalid card json")
	local folder = ServerStorage:FindFirstChild("CardSnapshot") or Instance.new("Folder")
	folder.Name = "CardSnapshot"
	folder.Parent = ServerStorage
	writeChunks(folder, json)
end

return CardDatabase

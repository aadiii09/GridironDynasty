-- PlayerData (server)
-- Session-locked player saves. One server owns a player's save at a time, so cards can't be
-- duplicated by joining two servers. Every change goes through this module.
--
-- Save layout (DataStore "PlayerData_v1", key "u_<UserId>"):
--   coins, cards = { [uid] = { id = cardId, at = unixTime } }, nextUid,
--   lineup, lastFreePack, receipts = { [purchaseId] = unixTime }, stats, lock

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local STORE_NAME = "PlayerData_v1"
local LOCK_STALE_SECONDS = 30 * 60 -- a lock older than this belongs to a crashed server
local AUTOSAVE_SECONDS = 60
local LOAD_ATTEMPTS = 6
local MAX_RECEIPTS = 100

local PlayerData = {}
PlayerData.Changed = Instance.new("BindableEvent") -- (player, profile)

local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles = {} -- [Player] = { data = table, loaded = bool }
local jobId = game.JobId ~= "" and game.JobId or "studio"

local function log(...)
	print("[PlayerData]", ...)
end

local function keyFor(userId)
	return "u_" .. userId
end

local function defaultData()
	return {
		coins = GameConfig.StartingCoins,
		cards = {},
		nextUid = 1,
		lineup = {},
		lastFreePack = 0,
		receipts = {},
		stats = { wins = 0, losses = 0, packsOpened = 0 },
		starterGiven = false,
		createdAt = os.time(),
	}
end

local function reconcile(data)
	for k, v in defaultData() do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

local function trimReceipts(receipts)
	local list = {}
	for id, t in receipts do
		table.insert(list, { id, t })
	end
	if #list <= MAX_RECEIPTS then
		return
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	for i = MAX_RECEIPTS + 1, #list do
		receipts[list[i][1]] = nil
	end
end

-- Write the save. `release` clears our lock (player left / server closing).
local function save(userId, data, release)
	local lostLock = false
	trimReceipts(data.receipts)
	local ok, err = pcall(store.UpdateAsync, store, keyFor(userId), function(old)
		if old and old.lock and old.lock.job ~= jobId then
			lostLock = true
			return nil -- another server owns this save now; never overwrite it
		end
		data.lock = (not release) and { job = jobId, t = os.time() } or nil
		return data
	end)
	if not ok then
		warn("[PlayerData] save failed for", userId, err)
	elseif lostLock then
		warn("[PlayerData] lost session lock for", userId, "- save skipped")
	end
	return ok and not lostLock
end

local function load(userId)
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local ok, result = pcall(store.UpdateAsync, store, keyFor(userId), function(old)
			old = old or defaultData()
			local lock = old.lock
			if lock and lock.job ~= jobId and os.time() - (lock.t or 0) < LOCK_STALE_SECONDS then
				lockedElsewhere = true
				return nil
			end
			old.lock = { job = jobId, t = os.time() }
			return old
		end)
		if ok and not lockedElsewhere and result then
			return reconcile(result)
		end
		if not ok then
			warn("[PlayerData] load error for", userId, result)
		else
			log("save for", userId, "is open in another server, retrying", attempt)
		end
		task.wait(6)
	end
	return nil
end

local function onPlayerAdded(player)
	local data = load(player.UserId)
	if not player.Parent then
		if data then
			save(player.UserId, data, true) -- left while loading
		end
		return
	end
	if not data then
		player:Kick("Your save is still in use by another server. Please rejoin in a minute.")
		return
	end
	profiles[player] = { data = data }
	log("loaded", player.Name, "coins:", data.coins)
	PlayerData.Changed:Fire(player, profiles[player])
end

local function onPlayerRemoving(player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		save(player.UserId, profile.data, true)
	end
end

function PlayerData.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, profile in profiles do
				task.spawn(save, player.UserId, profile.data, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				save(player.UserId, profile.data, true)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait()
		end
	end)
end

-- Returns the live profile (or nil if not loaded yet). Treat profile.data as read-only outside this module.
function PlayerData.Get(player)
	return profiles[player]
end

function PlayerData.WaitFor(player, timeout)
	local start = os.clock()
	while not profiles[player] and player.Parent and os.clock() - start < (timeout or 30) do
		task.wait(0.1)
	end
	return profiles[player]
end

function PlayerData.SaveNow(player)
	local profile = profiles[player]
	return profile ~= nil and save(player.UserId, profile.data, false)
end

-- Cards ---------------------------------------------------------------------

function PlayerData.AddCards(player, cardIds)
	local profile = profiles[player]
	assert(profile, "profile not loaded")
	local data = profile.data
	local uids = {}
	local now = os.time()
	for _, cardId in cardIds do
		local uid = "c" .. data.nextUid
		data.nextUid += 1
		data.cards[uid] = { id = cardId, at = now }
		table.insert(uids, uid)
	end
	PlayerData.Changed:Fire(player, profile)
	return uids
end

function PlayerData.RemoveCard(player, uid)
	local profile = profiles[player]
	if not profile or not profile.data.cards[uid] then
		return false
	end
	profile.data.cards[uid] = nil
	for slot, lineupUid in profile.data.lineup do
		if lineupUid == uid then
			profile.data.lineup[slot] = nil
		end
	end
	PlayerData.Changed:Fire(player, profile)
	return true
end

function PlayerData.CountCards(player)
	local profile = profiles[player]
	local n = 0
	if profile then
		for _ in profile.data.cards do
			n += 1
		end
	end
	return n
end

-- Coins ---------------------------------------------------------------------

function PlayerData.AddCoins(player, amount)
	local profile = profiles[player]
	assert(profile and amount >= 0, "bad AddCoins")
	profile.data.coins += math.floor(amount)
	PlayerData.Changed:Fire(player, profile)
	return profile.data.coins
end

function PlayerData.SpendCoins(player, amount)
	local profile = profiles[player]
	if not profile or amount < 0 or profile.data.coins < amount then
		return false
	end
	profile.data.coins -= math.floor(amount)
	PlayerData.Changed:Fire(player, profile)
	return true
end

-- Robux receipts (used by the pack shop's ProcessReceipt) ------------------

function PlayerData.HasReceipt(player, purchaseId)
	local profile = profiles[player]
	return profile ~= nil and profile.data.receipts[purchaseId] ~= nil
end

function PlayerData.MarkReceipt(player, purchaseId)
	local profile = profiles[player]
	assert(profile, "profile not loaded")
	profile.data.receipts[purchaseId] = os.time()
end

-- Generic edit for other systems (lineup, stats, free pack timer). fn(data) mutates in place.
function PlayerData.Update(player, fn)
	local profile = profiles[player]
	if not profile then
		return false
	end
	fn(profile.data)
	PlayerData.Changed:Fire(player, profile)
	return true
end

return PlayerData

-- LineupService (server): validates and edits each player's 7v7 lineup.
-- Rules: a card can only go in a slot for its position, a card can't be in two slots,
-- and the same real-life player (pid) can't start twice (e.g. his Base + Week Standout cards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LineupConfig = require(ReplicatedStorage.Shared.LineupConfig)
local CardDatabase = require(ServerScriptService.Modules.CardDatabase)
local PlayerData = require(ServerScriptService.Modules.PlayerData)

local LineupService = {}

local function cardFor(data, uid)
	local entry = uid and data.cards[uid]
	return entry and CardDatabase.Get(entry.id)
end

-- Drop anything that is no longer valid (sold cards, wrong positions, duplicates).
local function clean(data)
	local seenUid, seenPid = {}, {}
	for _, slot in LineupConfig.Slots do
		local uid = data.lineup[slot.id]
		local card = cardFor(data, uid)
		if uid and (not card or card.pos ~= slot.pos or seenUid[uid] or seenPid[card.pid]) then
			data.lineup[slot.id] = nil
		elseif card then
			seenUid[uid] = true
			seenPid[card.pid] = true
		end
	end
	for slotId in data.lineup do
		if not LineupConfig.ById[slotId] then
			data.lineup[slotId] = nil
		end
	end
end

function LineupService.Ratings(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return nil
	end
	return LineupConfig.TeamRatings(profile.data.lineup, function(uid)
		return cardFor(profile.data, uid)
	end)
end

-- Put `uid` in `slotId` (uid nil = empty the slot). If the card is already in another slot,
-- the two slots swap. Returns ok, err.
function LineupService.SetSlot(player, slotId, uid)
	local profile = PlayerData.Get(player)
	local slot = type(slotId) == "string" and LineupConfig.ById[slotId]
	if not profile or not slot then
		return false, "Unknown slot."
	end
	if uid ~= nil and type(uid) ~= "string" then
		return false, "Bad card."
	end
	local data = profile.data
	if uid == nil then
		PlayerData.Update(player, function(d)
			d.lineup[slotId] = nil
		end)
		return true
	end

	local card = cardFor(data, uid)
	if not card then
		return false, "You don't own that card."
	end
	if card.pos ~= slot.pos then
		return false, ("That card is a %s, this slot needs a %s."):format(card.pos, slot.pos)
	end

	local fromSlot
	for otherId, otherUid in data.lineup do
		if otherUid == uid then
			fromSlot = otherId
		end
	end
	-- same real player already starting somewhere else (different card)?
	for otherId, otherUid in data.lineup do
		local other = cardFor(data, otherUid)
		if otherId ~= slotId and otherId ~= fromSlot and other and other.pid == card.pid then
			return false, "That player is already in your lineup."
		end
	end

	PlayerData.Update(player, function(d)
		local current = d.lineup[slotId]
		d.lineup[slotId] = uid
		if fromSlot and fromSlot ~= slotId then
			d.lineup[fromSlot] = current -- swap (same position, so always valid)
		end
		clean(d)
	end)
	return true
end

-- Fill every slot with the best eligible card (keeps nothing; rebuilds from scratch).
function LineupService.AutoFill(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return false
	end
	local byPos = {}
	for uid, entry in profile.data.cards do
		local card = CardDatabase.Get(entry.id)
		if card then
			byPos[card.pos] = byPos[card.pos] or {}
			table.insert(byPos[card.pos], { uid = uid, card = card })
		end
	end
	for _, list in byPos do
		table.sort(list, function(a, b)
			return a.card.ovr > b.card.ovr or (a.card.ovr == b.card.ovr and a.uid < b.uid)
		end)
	end
	local lineup, usedPid = {}, {}
	for _, slot in LineupConfig.Slots do
		for _, option in byPos[slot.pos] or {} do
			if not usedPid[option.card.pid] then
				lineup[slot.id] = option.uid
				usedPid[option.card.pid] = true
				break
			end
		end
	end
	PlayerData.Update(player, function(d)
		d.lineup = lineup
	end)
	return true
end

function LineupService.Start(remotes)
	remotes.SetLineupSlot.OnServerInvoke = function(player, slotId, uid)
		local ok, err = LineupService.SetSlot(player, slotId, uid)
		return { ok = ok, err = err }
	end
	remotes.AutoFillLineup.OnServerInvoke = function(player)
		return { ok = LineupService.AutoFill(player) }
	end
	-- Fill an empty lineup for anyone who has cards but no lineup yet; tidy everyone else's.
	PlayerData.Changed.Event:Connect(function(player, profile)
		local data = profile.data
		if next(data.lineup) == nil and next(data.cards) ~= nil and data.starterGiven and not profile.lineupChecked then
			profile.lineupChecked = true
			task.defer(LineupService.AutoFill, player)
		end
	end)
end

LineupService.Clean = clean

return LineupService

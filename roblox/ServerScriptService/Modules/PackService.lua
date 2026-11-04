-- PackService (server)
-- Opens free and Coin packs directly, and Robux packs through Developer Products.
-- Roblox paid-random-item rules handled here:
--   * every pack's exact odds are sent to the client (GetPackOdds) and shown before purchase
--   * PolicyService.ArePaidRandomItemsRestricted blocks Robux packs for that player
--   * receipts are granted once only (purchase id stored in the save before PurchaseGranted)

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PackConfig = require(ReplicatedStorage.Shared.PackConfig)
local StoreConfig = require(ReplicatedStorage.Shared.StoreConfig)
local CardDatabase = require(ServerScriptService.Modules.CardDatabase)
local PlayerData = require(ServerScriptService.Modules.PlayerData)
local ChallengeService = require(ServerScriptService.Modules.ChallengeService)

local PackService = {}

local rng = Random.new()
local policyCache = {} -- [Player] = { paidRandomRestricted = bool }
local lastOpen = {} -- [Player] = os.clock()
local remotes

local function log(...)
	print("[PackService]", ...)
end

-- Odds ------------------------------------------------------------------------

-- Turn a pack's odds table into the exact table we roll with: tiers that have no cards right
-- now are dropped and the rest scaled back up to 100, so what players see is what they get.
local function effectiveOdds(oddsTable)
	local total, out = 0, {}
	for _, tier in GameConfig.TierOrder do
		local pct = oddsTable[tier] or 0
		local count = #CardDatabase.TierPool(tier)
		if pct > 0 and count > 0 then
			out[tier] = { pct = pct, count = count }
			total += pct
		end
	end
	for _, entry in out do
		entry.pct = entry.pct / total * 100
	end
	return out
end

function PackService.GetOdds(pack)
	return {
		slot = effectiveOdds(pack.odds),
		guaranteed = pack.guaranteed and effectiveOdds(pack.guaranteed) or nil,
		dataVersion = CardDatabase.Version(),
	}
end

local function rollTier(odds)
	local roll = rng:NextNumber(0, 100)
	local acc, last = 0, nil
	for _, tier in GameConfig.TierOrder do
		local entry = odds[tier]
		if entry then
			acc += entry.pct
			last = tier
			if roll < acc then
				return tier
			end
		end
	end
	return last -- floating point edge
end

local function rollPack(pack)
	local odds = PackService.GetOdds(pack)
	local ids = {}
	for slot = 1, pack.cards do
		local useGuaranteed = odds.guaranteed and slot == pack.cards
		local tier = rollTier(useGuaranteed and odds.guaranteed or odds.slot)
		local card = CardDatabase.RandomFrom(CardDatabase.TierPool(tier), rng)
		table.insert(ids, card.id)
	end
	return ids
end

-- Policy ------------------------------------------------------------------------

local function getPolicy(player)
	if policyCache[player] then
		return policyCache[player]
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	local policy = {
		-- if the lookup fails, be safe and treat paid random items as restricted
		paidRandomRestricted = not ok or info.ArePaidRandomItemsRestricted == true,
		paidTradingAllowed = ok and info.IsPaidItemTradingAllowed == true,
	}
	if ok then
		policyCache[player] = policy
	end
	return policy
end

-- Granting ------------------------------------------------------------------------

local function grant(player, pack, source)
	local ids = rollPack(pack)
	local uids = PlayerData.AddCards(player, ids)
	PlayerData.Update(player, function(data)
		data.stats.packsOpened += 1
	end)
	local result = { packId = pack.id, cards = {} }
	for i, id in ids do
		table.insert(result.cards, { uid = uids[i], id = id })
	end
	log(("%s opened %s (%s): %s"):format(player.Name, pack.id, source, table.concat(ids, ", ")))
	task.spawn(ChallengeService.Record, player, { packs = 1 })
	return result
end

-- A free pack given as a reward (challenges): rolled, added, and revealed on the client.
-- Not a paid random item (nothing was bought).
function PackService.GrantFree(player, packId, source)
	local pack = PackConfig.ById[packId]
	if not pack or not CardDatabase.IsReady() then
		return nil
	end
	local result = grant(player, pack, source or "reward")
	result.ok = true
	remotes.PackOpened:FireClient(player, result)
	return result
end

local function freePackReadyAt(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return math.huge
	end
	return profile.data.lastFreePack + PackConfig.FreePackCooldown
end

-- Free + Coin packs (RemoteFunction OpenPack)
local function onOpenPack(player, packId)
	local pack = PackConfig.ById[packId]
	if type(packId) ~= "string" or not pack or pack.currency == "Robux" then
		return { ok = false, err = "That pack can't be opened this way." }
	end
	if not CardDatabase.IsReady() or not PlayerData.Get(player) then
		return { ok = false, err = "Still loading, try again in a moment." }
	end
	if lastOpen[player] and os.clock() - lastOpen[player] < 1 then
		return { ok = false, err = "Slow down!" }
	end
	lastOpen[player] = os.clock()

	if pack.currency == "Free" then
		if os.time() < freePackReadyAt(player) then
			return { ok = false, err = "Your free pack isn't ready yet." }
		end
		PlayerData.Update(player, function(data)
			data.lastFreePack = os.time()
		end)
	elseif pack.currency == "Coins" then
		if not PlayerData.SpendCoins(player, pack.price) then
			return { ok = false, err = "Not enough Coins." }
		end
	end

	local result = grant(player, pack, pack.currency)
	task.spawn(PlayerData.SaveNow, player)
	result.ok = true
	return result
end

-- Robux packs: client asks, server checks policy, then prompts
local function onPromptPack(player, packId)
	local pack = PackConfig.ById[packId]
	if type(packId) ~= "string" or not pack or pack.currency ~= "Robux" then
		return { ok = false, err = "Unknown pack." }
	end
	if getPolicy(player).paidRandomRestricted then
		return { ok = false, err = "Robux packs aren't available in your region or for your account." }
	end
	if not pack.productId or pack.productId == 0 then
		return { ok = false, err = "This pack is coming soon." }
	end
	MarketplaceService:PromptProductPurchase(player, pack.productId)
	return { ok = true }
end

-- Coin bundles (Developer Products): add Coins, saved before the purchase is confirmed
local function grantCoins(player, bundle, receipt)
	PlayerData.AddCoins(player, bundle.coins)
	PlayerData.MarkReceipt(player, receipt.PurchaseId)
	if not PlayerData.SaveNow(player) then
		PlayerData.Update(player, function(data)
			data.coins -= bundle.coins
			data.receipts[receipt.PurchaseId] = nil
		end)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	log(("%s bought %d Coins (%s)"):format(player.Name, bundle.coins, receipt.PurchaseId))
	remotes.CoinsPurchased:FireClient(player, { coins = bundle.coins })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local pack = PackConfig.ByProductId[receipt.ProductId]
	local bundle = StoreConfig.BundleByProductId[receipt.ProductId]
	if not player or not (pack or bundle) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = PlayerData.WaitFor(player, 10)
	if not profile or not CardDatabase.IsReady() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if PlayerData.HasReceipt(player, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already delivered
	end
	if bundle then
		return grantCoins(player, bundle, receipt)
	end

	local result = grant(player, pack, "Robux " .. receipt.PurchaseId)
	PlayerData.MarkReceipt(player, receipt.PurchaseId)
	if not PlayerData.SaveNow(player) then
		-- Couldn't save: undo so the retry (Roblox calls again later) doesn't double-grant.
		for _, card in result.cards do
			PlayerData.RemoveCard(player, card.uid)
		end
		PlayerData.Update(player, function(data)
			data.receipts[receipt.PurchaseId] = nil
		end)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	result.ok = true
	remotes.PackOpened:FireClient(player, result)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Shop info for the client ----------------------------------------------------------

local function onGetShop(player)
	PlayerData.WaitFor(player, 30)
	CardDatabase.WaitReady()
	local policy = getPolicy(player)
	local packs = {}
	for _, pack in PackConfig.Packs do
		table.insert(packs, {
			id = pack.id,
			available = not (PackConfig.IsPaidRandom(pack) and policy.paidRandomRestricted)
				and (pack.currency ~= "Robux" or (pack.productId or 0) ~= 0),
			odds = PackService.GetOdds(pack),
		})
	end
	return {
		packs = packs,
		freePackReadyAt = freePackReadyAt(player),
		serverTime = os.time(),
		paidRandomRestricted = policy.paidRandomRestricted,
	}
end

function PackService.GetPolicy(player)
	return getPolicy(player)
end

function PackService.Start(remoteFolder)
	remotes = remoteFolder
	remotes.OpenPack.OnServerInvoke = onOpenPack
	remotes.PromptPack.OnServerInvoke = onPromptPack
	remotes.GetShop.OnServerInvoke = onGetShop
	MarketplaceService.ProcessReceipt = processReceipt
	Players.PlayerRemoving:Connect(function(player)
		policyCache[player] = nil
		lastOpen[player] = nil
	end)
end

return PackService

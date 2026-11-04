-- StoreService (server): Coin bundle prompts, VIP game pass, daily login reward.
-- Coin bundle receipts are granted in PackService.ProcessReceipt (one handler per experience).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StoreConfig = require(ReplicatedStorage.Shared.StoreConfig)
local PlayerData = require(ServerScriptService.Modules.PlayerData)
local PackService = require(ServerScriptService.Modules.PackService)

local StoreService = {}

local vipCache = {} -- [Player] = bool
local remotes

local function today()
	return math.floor(os.time() / 86400) -- UTC day number
end

function StoreService.IsVIP(player)
	if vipCache[player] ~= nil then
		return vipCache[player]
	end
	local id = StoreConfig.VIP.gamePassId
	if not id or id == 0 then
		return false
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
	vipCache[player] = ok and owns == true
	return vipCache[player]
end

-- Called once a player's save is loaded: grant today's login reward (streak bonus).
local function dailyLogin(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local day = today()
	local data = profile.data
	if data.lastLoginDay == day then
		return
	end
	local streak = (data.lastLoginDay == day - 1) and ((data.loginStreak or 0) + 1) or 1
	local amount = StoreConfig.DailyAmount(streak, StoreService.IsVIP(player))
	PlayerData.Update(player, function(d)
		d.lastLoginDay = day
		d.loginStreak = streak
	end)
	PlayerData.AddCoins(player, amount)
	task.spawn(PlayerData.SaveNow, player)
	remotes.DailyReward:FireClient(player, { streak = streak, coins = amount, maxStreak = StoreConfig.Daily.maxStreak })
end

local function getStore(player)
	PlayerData.WaitFor(player, 30)
	local restricted = PackService.GetPolicy(player).paidRandomRestricted
	local bundles = {}
	for _, b in StoreConfig.CoinBundles do
		table.insert(bundles, { id = b.id, available = not restricted and b.productId ~= 0 })
	end
	local profile = PlayerData.Get(player)
	return {
		bundles = bundles,
		coinsRestricted = restricted,
		vip = StoreService.IsVIP(player),
		vipAvailable = StoreConfig.VIP.gamePassId ~= 0,
		streak = profile and profile.data.loginStreak or 0,
	}
end

local function promptCoins(player, bundleId)
	local bundle = StoreConfig.BundleById[bundleId]
	if type(bundleId) ~= "string" or not bundle then
		return { ok = false, err = "Unknown bundle." }
	end
	if PackService.GetPolicy(player).paidRandomRestricted then
		return { ok = false, err = "Coin bundles aren't available for your account." }
	end
	if bundle.productId == 0 then
		return { ok = false, err = "Coin bundles are coming soon." }
	end
	MarketplaceService:PromptProductPurchase(player, bundle.productId)
	return { ok = true }
end

local function promptVIP(player)
	local id = StoreConfig.VIP.gamePassId
	if StoreService.IsVIP(player) then
		return { ok = false, err = "You already have VIP!" }
	end
	if id == 0 then
		return { ok = false, err = "VIP is coming soon." }
	end
	MarketplaceService:PromptGamePassPurchase(player, id)
	return { ok = true }
end

function StoreService.Start(remoteFolder)
	remotes = remoteFolder
	remotes.GetStore.OnServerInvoke = getStore
	remotes.PromptCoins.OnServerInvoke = promptCoins
	remotes.PromptVIP.OnServerInvoke = promptVIP
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == StoreConfig.VIP.gamePassId then
			vipCache[player] = true
			remotes.CoinsPurchased:FireClient(player, { vip = true })
		end
	end)
	PlayerData.Changed.Event:Connect(function(player, profile)
		if not profile.dailyChecked then
			profile.dailyChecked = true
			task.delay(3, dailyLogin, player) -- give the client a moment to load its UI
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		vipCache[player] = nil
	end)
end

return StoreService

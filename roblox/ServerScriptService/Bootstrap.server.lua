-- Server entry point: starts card data, player saves, starter squads and inventory remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CardDatabase = require(ServerScriptService.Modules.CardDatabase)
local PlayerData = require(ServerScriptService.Modules.PlayerData)

-- Remotes ---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function remote(className, name)
	local r = remotes:FindFirstChild(name) or Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local GetInventory = remote("RemoteFunction", "GetInventory")
local InventoryChanged = remote("RemoteEvent", "InventoryChanged")
local QuickSell = remote("RemoteFunction", "QuickSell")
remote("RemoteFunction", "OpenPack")
remote("RemoteFunction", "PromptPack")
remote("RemoteFunction", "GetShop")
remote("RemoteEvent", "PackOpened")
remote("RemoteFunction", "SetLineupSlot")
remote("RemoteFunction", "AutoFillLineup")

local PackService = require(ServerScriptService.Modules.PackService)
local LineupService = require(ServerScriptService.Modules.LineupService)

local function snapshotFor(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return nil
	end
	local cards = {}
	for uid, entry in profile.data.cards do
		table.insert(cards, { uid = uid, id = entry.id, at = entry.at })
	end
	return {
		coins = profile.data.coins,
		cards = cards,
		lineup = profile.data.lineup,
		dataVersion = CardDatabase.Version(),
	}
end

GetInventory.OnServerInvoke = function(player)
	PlayerData.WaitFor(player, 30)
	return snapshotFor(player)
end

-- Starter squad -----------------------------------------------------------------
local rng = Random.new()

local function giveStarterSquad(player)
	CardDatabase.WaitReady()
	local ids = {}
	for pos, count in GameConfig.StarterSquad do
		local pool = CardDatabase.Pool("Base", "Common", function(card)
			return card.pos == pos
		end)
		for _ = 1, count do
			local card = CardDatabase.RandomFrom(pool, rng)
			if card then
				table.insert(ids, card.id)
			end
		end
	end
	PlayerData.AddCards(player, ids)
	PlayerData.Update(player, function(data)
		data.starterGiven = true
	end)
	PlayerData.SaveNow(player)
	print(("[Bootstrap] gave %s a starter squad of %d cards"):format(player.Name, #ids))
end

local givingStarter = {} -- [userId] = true; keyed by user so it survives any profile reload

PlayerData.Changed.Event:Connect(function(player, profile)
	if not profile.data.starterGiven and not givingStarter[player.UserId] then
		givingStarter[player.UserId] = true
		task.spawn(giveStarterSquad, player)
	end
	InventoryChanged:FireClient(player, snapshotFor(player))
end)

-- Quick-sell a card for Coins ---------------------------------------------------------
QuickSell.OnServerInvoke = function(player, uid)
	local profile = PlayerData.Get(player)
	if type(uid) ~= "string" or not profile then
		return { ok = false }
	end
	local entry = profile.data.cards[uid]
	local card = entry and CardDatabase.Get(entry.id)
	if not card then
		return { ok = false, err = "Card not found." }
	end
	local value = GameConfig.QuickSell[card.tier] or 0
	if not PlayerData.RemoveCard(player, uid) then
		return { ok = false, err = "Card not found." }
	end
	PlayerData.AddCoins(player, value)
	task.spawn(PlayerData.SaveNow, player)
	return { ok = true, coins = value }
end

-- Start ---------------------------------------------------------------------------
CardDatabase.Start()
PackService.Start(remotes)
LineupService.Start(remotes)
PlayerData.Start()

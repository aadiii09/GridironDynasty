-- Server entry point: starts card data, player saves, starter squads and inventory remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Jerseys = require(ReplicatedStorage.Shared.Jerseys)
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
remote("RemoteFunction", "GetStore")
remote("RemoteFunction", "PromptCoins")
remote("RemoteFunction", "PromptVIP")
remote("RemoteEvent", "CoinsPurchased")
remote("RemoteEvent", "DailyReward")
remote("RemoteFunction", "StartMatch")
remote("RemoteEvent", "MatchAction")
remote("RemoteEvent", "MatchState")
local SetJersey = remote("RemoteFunction", "SetJersey")
remote("RemoteFunction", "GetChallenges")
remote("RemoteFunction", "ClaimChallenge")
remote("RemoteEvent", "ChallengesChanged")
remote("RemoteFunction", "GetLeaderboard")
remote("RemoteFunction", "H2HQueue")
remote("RemoteFunction", "H2HChallenge")
remote("RemoteFunction", "H2HRespond")
remote("RemoteFunction", "GetH2HInfo")
remote("RemoteEvent", "H2HEvent")

local PackService = require(ServerScriptService.Modules.PackService)
local LineupService = require(ServerScriptService.Modules.LineupService)
local MatchService = require(ServerScriptService.Modules.Match.MatchService)
local World = require(ServerScriptService.Modules.World)
local StoreService = require(ServerScriptService.Modules.StoreService)
local ChallengeService = require(ServerScriptService.Modules.ChallengeService)
local LeaderboardService = require(ServerScriptService.Modules.LeaderboardService)
local H2HService = require(ServerScriptService.Modules.H2HService)
local MatchServer = require(ServerScriptService.Modules.MatchServer)

World.SetupLighting()
local lobby = World.BuildLobby()
LeaderboardService.BuildBoard(lobby)

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
		stats = profile.data.stats,
		jersey = Jerseys.Get(profile.data.jersey).id,
		difficulty = profile.data.difficulty,
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
	if not profile.leaderboardSynced then
		profile.leaderboardSynced = true
		LeaderboardService.SyncTotal(player, profile.data.stats.wins)
	end
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

-- Equip a team jersey (must be unlocked by wins) ---------------------------------------
SetJersey.OnServerInvoke = function(player, id)
	local profile = PlayerData.Get(player)
	if type(id) ~= "string" or not profile or not Jerseys.ById[id] then
		return { ok = false, err = "Unknown jersey." }
	end
	local j = Jerseys.ById[id]
	if not Jerseys.IsUnlocked(id, profile.data.stats.wins) then
		return { ok = false, err = ("Win %d games to unlock %s."):format(j.wins, j.name) }
	end
	PlayerData.Update(player, function(data)
		data.jersey = id
	end)
	return { ok = true, jersey = id }
end

-- Start ---------------------------------------------------------------------------
CardDatabase.Start()
PackService.Start(remotes)
LineupService.Start(remotes)
MatchService.Start(remotes)
StoreService.Start(remotes)
ChallengeService.Start(remotes, PackService.GrantFree)
LeaderboardService.Start(remotes)
H2HService.Start(remotes)
if MatchServer.IsMatchServer() then
	task.spawn(MatchServer.Start, remotes, H2HService)
end
PlayerData.Start()

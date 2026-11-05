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
local SetHubSetting = remote("RemoteFunction", "SetHubSetting")
local TutorialAction = remote("RemoteFunction", "TutorialAction")
local TutorialDone = remote("RemoteEvent", "TutorialDone")

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
		hub = profile.data.settings and profile.data.settings.hub or {},
		h2h = profile.data.h2h,
		tutorial = profile.data.tutorial,
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

-- (BindableEvents pass a COPY of tables, so always work on PlayerData.Get(player), and keep
-- once-per-player flags here rather than on the profile)
local leaderboardSynced = {} -- [Player] = true
game:GetService("Players").PlayerRemoving:Connect(function(player)
	leaderboardSynced[player] = nil
end)
PlayerData.Changed.Event:Connect(function(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	-- players who already played before the tutorial existed don't need it
	if profile.data.tutorial == nil and ((profile.data.stats.wins or 0) + (profile.data.stats.losses or 0) + (profile.data.stats.ties or 0)) > 0 then
		profile.data.tutorial = "done"
	end
	if not leaderboardSynced[player] then
		leaderboardSynced[player] = true
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
local lobbyGear -- defined below (lobby look)
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
	task.spawn(lobbyGear, player)
	return { ok = true, jersey = id }
end

-- Hub layout preferences (which widgets are open / collapsed / hidden) ------------------
local HUB_WIDGETS = { featured = true, challenges = true, topcard = true }
local HUB_STATES = { open = true, collapsed = true, hidden = true }
SetHubSetting.OnServerInvoke = function(player, key, value)
	local ok = (HUB_WIDGETS[key] and HUB_STATES[value]) or (key == "clean" and type(value) == "boolean")
	if type(key) ~= "string" or not ok or not PlayerData.Get(player) then
		return { ok = false }
	end
	PlayerData.Update(player, function(data)
		data.settings = data.settings or {}
		data.settings.hub = data.settings.hub or {}
		data.settings.hub[key] = value
	end)
	return { ok = true }
end

-- Lobby look: you stand on the hub "stage" in your team jersey, helmet and pads -------------
local Npc = require(ServerScriptService.Modules.Match.Npc)
local Jerseys = require(ReplicatedStorage.Shared.Jerseys)
local rngStage = Random.new()

function lobbyGear(player)
	local profile = PlayerData.Get(player)
	local char = player.Character
	if not profile or not char or not char:FindFirstChild("Head") or MatchService.InMatch(player) then
		return
	end
	local jersey = Jerseys.Get(profile.data.jersey)
	if not Jerseys.IsUnlocked(jersey.id, profile.data.stats.wins) then
		jersey = Jerseys.Get(Jerseys.Default)
	end
	Npc.Unequip(char)
	Npc.Equip(char, jersey.primary, jersey.secondary, jersey)
end

local function toStage(player)
	local char = player.Character
	if not char or MatchService.InMatch(player) then
		return
	end
	-- a spot near midfield, facing the hub camera (big screen + leaderboard behind you)
	local spot = Vector3.new(rngStage:NextNumber(-3, 3), 4, rngStage:NextNumber(-2, 2))
	char:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, 1)))
end

local function onCharacter(player)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.3)
		toStage(player)
		PlayerData.WaitFor(player, 30)
		lobbyGear(player)
	end)
	if player.Character then
		task.spawn(function()
			PlayerData.WaitFor(player, 30)
			toStage(player)
			lobbyGear(player)
		end)
	end
end
game:GetService("Players").PlayerAdded:Connect(onCharacter)
for _, p in game:GetService("Players"):GetPlayers() do
	onCharacter(p)
end
MatchService.PlayerExited.Event:Connect(function(player)
	task.wait(0.2)
	toStage(player)
	lobbyGear(player)
	-- first game done (or left): tutorial complete, here's a Starter Pack
	local profile = PlayerData.Get(player)
	if profile and profile.data.tutorial ~= "done" then
		PlayerData.Update(player, function(data)
			data.tutorial = "done"
		end)
		task.wait(1.2)
		TutorialDone:FireClient(player, { pack = "starter" })
		PackService.GrantFree(player, "starter", "tutorial")
		task.spawn(PlayerData.SaveNow, player)
	end
end)

-- skip the tutorial (no reward)
TutorialAction.OnServerInvoke = function(player, action)
	local profile = PlayerData.Get(player)
	if not profile then
		return { ok = false }
	end
	if action == "skip" and profile.data.tutorial ~= "done" then
		PlayerData.Update(player, function(data)
			data.tutorial = "done"
		end)
	end
	return { ok = true }
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

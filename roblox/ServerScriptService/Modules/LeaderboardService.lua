-- LeaderboardService (server): wins leaderboards (this week, all time) and the ranked
-- head-to-head rating leaderboard.
-- OrderedDataStores keyed by UserId; the top 10 of each are fetched every 2 minutes, shared
-- through the GetLeaderboard remote and shown on a big board in the lobby.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChallengeConfig = require(ReplicatedStorage.Shared.ChallengeConfig)

local LeaderboardService = {}

local TOP = 10
local REFRESH = 120
local cache = { week = {}, allTime = {}, ranked = {}, updatedAt = 0 }
local names = {} -- [userId] = display name
local board -- SurfaceGui frames in the lobby
local remotes

local function store(kind)
	local ok, s = pcall(function()
		if kind == "week" then
			return DataStoreService:GetOrderedDataStore("Wins_Week_" .. ChallengeConfig.Week())
		elseif kind == "ranked" then
			return DataStoreService:GetOrderedDataStore("H2H_Rating_v1")
		end
		return DataStoreService:GetOrderedDataStore("Wins_AllTime_v1")
	end)
	return ok and s or nil
end

local function resolveNames(ids)
	local missing = {}
	for _, id in ids do
		if not names[id] then
			local p = Players:GetPlayerByUserId(id)
			if p then
				names[id] = p.DisplayName
			else
				table.insert(missing, id)
			end
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
		if ok then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
	end
end

local function fetch(kind)
	local s = store(kind)
	if not s then
		return nil
	end
	local ok, pages = pcall(s.GetSortedAsync, s, false, TOP)
	if not ok then
		warn("[Leaderboard] fetch failed:", pages)
		return nil
	end
	local rows, ids = {}, {}
	for rank, entry in pages:GetCurrentPage() do
		local id = tonumber(entry.key)
		if id then
			table.insert(rows, { rank = rank, userId = id, wins = entry.value })
			table.insert(ids, id)
		end
	end
	resolveNames(ids)
	for _, r in rows do
		r.name = names[r.userId] or ("Player " .. r.userId)
	end
	return rows
end

local function drawBoard()
	if not board then
		return
	end
	for kind, frame in board do
		for _, c in frame:GetChildren() do
			if c.Name == "Row" then
				c:Destroy()
			end
		end
		local rows = cache[kind] or {}
		for i = 1, 5 do
			local r = rows[i]
			local row = Instance.new("TextLabel")
			row.Name = "Row"
			row.BackgroundColor3 = i == 1 and Color3.fromRGB(70, 56, 10) or Color3.fromRGB(20, 26, 40)
			row.BackgroundTransparency = 0.15
			row.Size = UDim2.new(1, -24, 0.14, 0)
			row.Position = UDim2.new(0, 12, 0.2 + (i - 1) * 0.155, 0)
			row.FontFace = Font.new(Font.fromEnum(Enum.Font.Oswald).Family, Enum.FontWeight.Bold)
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = i == 1 and Color3.fromRGB(255, 214, 40) or Color3.new(1, 1, 1)
			row.Text = r and ("  %d.  %s   -   %d W"):format(i, string.upper(r.name), r.wins) or ("  %d.  ---"):format(i)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.2, 0)
			corner.Parent = row
			row.Parent = frame
		end
	end
end

function LeaderboardService.Refresh()
	local week, all, ranked = fetch("week"), fetch("allTime"), fetch("ranked")
	cache.week = week or cache.week
	cache.allTime = all or cache.allTime
	cache.ranked = ranked or cache.ranked
	cache.updatedAt = os.time()
	cache.weekEndsAt = ChallengeConfig.WeekEnds(ChallengeConfig.Week())
	drawBoard()
end

-- After a win: +1 this week, all-time = the player's saved win total
function LeaderboardService.RecordWin(player, totalWins)
	task.spawn(function()
		local w = store("week")
		if w then
			pcall(w.IncrementAsync, w, tostring(player.UserId), 1)
		end
		local a = store("allTime")
		if a then
			pcall(a.SetAsync, a, tostring(player.UserId), totalWins)
		end
	end)
end

-- Ranked head-to-head: the player's current rating
function LeaderboardService.RecordRating(player, rating)
	task.spawn(function()
		local r = store("ranked")
		if r then
			pcall(r.SetAsync, r, tostring(player.UserId), math.floor(rating))
		end
	end)
end

-- players who already had wins before leaderboards existed get onto the all-time board
function LeaderboardService.SyncTotal(player, totalWins)
	if (totalWins or 0) <= 0 then
		return
	end
	task.spawn(function()
		local a = store("allTime")
		if a then
			pcall(a.UpdateAsync, a, tostring(player.UserId), function(old)
				if (old or 0) >= totalWins then
					return nil
				end
				return totalWins
			end)
		end
	end)
end

-- Big two-column board above the lobby's screen
function LeaderboardService.BuildBoard(lobby)
	local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
	local L = MatchConfig.FieldLength()
	local EZ = MatchConfig.EndZoneYards * MatchConfig.Yard
	-- same spot as the lobby's big screen (Field.lua), just above it
	local at = lobby:ToWorld(0, L + EZ + 50, 54)
	local part = Instance.new("Part")
	part.Name = "LeaderboardBoard"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.new(84, 26, 1.5)
	part.CFrame = CFrame.new(at)
	part.Color = Color3.fromRGB(8, 10, 16)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = lobby.model
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(840, 260)
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.Parent = part
	board = {}
	for i, kind in { "week", "allTime" } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
		f.Size = UDim2.new(0.5, -12, 1, -12)
		f.Position = UDim2.new((i - 1) * 0.5, 6, 0, 6)
		local stroke = Instance.new("UIStroke")
		stroke.Color = i == 1 and Color3.fromRGB(46, 255, 140) or Color3.fromRGB(255, 196, 46)
		stroke.Thickness = 3
		stroke.Parent = f
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0.17, 0)
		title.Position = UDim2.fromScale(0, 0.015)
		title.FontFace = Font.new(Font.fromEnum(Enum.Font.Oswald).Family, Enum.FontWeight.Bold)
		title.TextScaled = true
		title.TextColor3 = stroke.Color
		title.Text = i == 1 and "MOST WINS THIS WEEK" or "MOST WINS ALL TIME"
		title.Parent = f
		f.Parent = sg
		board[kind] = f
	end
	drawBoard()
	return part
end

function LeaderboardService.Start(remoteFolder)
	remotes = remoteFolder
	remotes.GetLeaderboard.OnServerInvoke = function()
		return cache
	end
	task.spawn(function()
		while true do
			LeaderboardService.Refresh()
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService

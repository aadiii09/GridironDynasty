-- CustomLobbyUI (client): the PLAY -> CUSTOM tab (friends' 7v7) and the party pill on the hub.
--   Not in a game: list of this server's custom games + CREATE GAME + INVITE FRIENDS.
--   In a game: both rosters, your team / offensive spot / defensive spot, and START (host).
-- MainUI calls Init once and Render(body) whenever the tab is drawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local LineupConfig = require(ReplicatedStorage.Shared.LineupConfig)
local UI = require(ReplicatedStorage.Client.UIKit)

local C = UI.Color
local F = UI.Font
local new = UI.new

local CustomLobbyUI = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OFF_ORDER = { "QB", "RB", "WR1", "WR2", "TE", "OL1", "OL2" }
local DEF_ORDER = { "DL1", "DL2", "LB1", "LB2", "CB1", "CB2", "S" }
local TEAM_COLOR = { home = C.Accent, away = C.Blue }

local deps = {}
local current -- my lobby (view from the server) or nil
local pill, pillText

local function call(action, a, b)
	local ok, res = pcall(function()
		return Remotes.CustomLobby:InvokeServer(action, a, b)
	end)
	if not ok or type(res) ~= "table" then
		return { ok = false, err = "Couldn't reach the server." }
	end
	if not res.ok and res.err and deps.toast then
		deps.toast(res.err, C.Red)
	end
	return res
end

local function invite()
	task.spawn(function()
		local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
		if not ok or not can then
			deps.toast("Invites aren't available on your account right now", C.Red)
			return
		end
		local opts = Instance.new("ExperienceInviteOptions")
		opts.PromptMessage = "Join my 7v7 custom game in Gridiron Dynasty!"
		pcall(SocialService.PromptGameInvite, SocialService, player, opts)
	end)
end

local function me(lobby)
	for _, p in lobby.players do
		if p.userId == player.UserId then
			return p
		end
	end
	return nil
end

local function updatePill()
	if not pill then
		return
	end
	-- (hidden while the PLAY menu is open: the lobby is right there)
	pill.Visible = current ~= nil and not (deps.menu and deps.menu.Visible)
	if current then
		pillText.Text = ("CUSTOM GAME  -  %d PLAYER%s%s"):format(#current.players, #current.players == 1 and "" or "S", current.inGame and "  -  IN GAME" or "")
	end
end

-- List of games -----------------------------------------------------------------------------------
local function renderList(body, list)
	UI.text({ Text = "PLAY 7v7 WITH FRIENDS IN THIS SERVER  -  PICK YOUR TEAM AND POSITIONS  -  JUST FOR FUN", FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), ZIndex = 71 }).Parent = body
	UI.button({ name = "CreateGame", kind = "gold", icon = "football", text = "CREATE GAME", size = UDim2.fromOffset(250, 52), position = UDim2.fromOffset(0, 30), textSize = 19, z = 72 }, function()
		call("create")
	end).Parent = body
	UI.button({ kind = "primary", icon = "invite", text = "INVITE FRIENDS", size = UDim2.fromOffset(230, 52), position = UDim2.fromOffset(262, 30), textSize = 17, z = 72 }, invite).Parent = body
	local scroll = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 230), Position = UDim2.fromOffset(0, 96), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ZIndex = 71 }, {
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	scroll.Parent = body
	if #list == 0 then
		UI.text({ Text = "No custom games in this server yet. Create one, then invite your friends - when they join they'll see it here.", FontFace = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextScaled = false, TextSize = 16, Size = UDim2.new(1, -10, 0, 50), ZIndex = 72 }).Parent = scroll
	end
	for i, g in list do
		local row = new("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.new(1, -10, 0, 58), LayoutOrder = i, ZIndex = 72 }, { UI.corner(10) })
		local head = new("ImageLabel", { BackgroundColor3 = C.BG, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(8, 7), ZIndex = 73 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		head.Parent = row
		task.spawn(function()
			local ok, img = pcall(Players.GetUserThumbnailAsync, Players, g.hostId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			if ok then
				head.Image = img
			end
		end)
		UI.text({ Text = string.upper(g.hostName) .. "'S GAME", FontFace = F.Display, TextScaled = false, TextSize = 22, Size = UDim2.new(1, -300, 0, 26), Position = UDim2.fromOffset(62, 6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 73 }).Parent = row
		UI.text({ Text = ("%d / %d PLAYERS%s"):format(g.count, g.max, g.inGame and "  -  GAME IN PROGRESS" or ""), FontFace = F.Heavy, TextColor3 = g.inGame and C.Gold or C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(1, -300, 0, 18), Position = UDim2.fromOffset(62, 32), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 73 }).Parent = row
		UI.button({ kind = g.count >= g.max and "dark" or "primary", text = g.count >= g.max and "FULL" or "JOIN", size = UDim2.fromOffset(150, 40), position = UDim2.new(1, -160, 0.5, -20), textSize = 16, z = 73 }, function()
			if g.count < g.max then
				call("join", g.id)
			end
		end).Parent = row
		row.Parent = scroll
	end
end

-- My game ---------------------------------------------------------------------------------------------
local function rosterColumn(body, lobby, team, x)
	local col = new("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.2, Size = UDim2.fromOffset(400, 152), Position = UDim2.fromOffset(x, 34), ZIndex = 71 }, { UI.corner(10), UI.stroke(TEAM_COLOR[team], 1.5, 0.3) })
	col.Parent = body
	local count = 0
	for _, p in lobby.players do
		count += p.team == team and 1 or 0
	end
	local header = new("Frame", { BackgroundColor3 = TEAM_COLOR[team], Size = UDim2.new(1, 0, 0, 26), ZIndex = 72 }, { UI.corner(10) })
	header.Parent = col
	UI.text({ Text = ("%s  -  %d / %d"):format(team == "home" and "HOME" or "AWAY", count, lobby.maxPerTeam), FontFace = F.Display, TextColor3 = C.BG, TextScaled = false, TextSize = 17, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 73 }).Parent = header
	local y = 30
	for _, p in lobby.players do
		if p.team == team then
			local mine = p.userId == player.UserId
			local offPos = p.off and LineupConfig.ById[p.off].pos
			local defPos = p.def and LineupConfig.ById[p.def].pos
			UI.text({ Text = (p.host and "* " or "") .. string.upper(p.name) .. (p.busy and "  (IN A GAME)" or ""), FontFace = F.Bold, TextColor3 = mine and C.Gold or C.Text, TextScaled = false, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -170, 0, 16), Position = UDim2.fromOffset(10, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 72 }).Parent = col
			UI.text({ Text = ("%s %d  /  %s %d"):format(p.off or "-", offPos and p.ovrs[offPos] or 0, p.def or "-", defPos and p.ovrs[defPos] or 0), FontFace = F.Number, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(160, 16), Position = UDim2.new(1, -10, 0, y), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 72 }).Parent = col
			y += 17
		end
	end
	if count == 0 then
		UI.text({ Text = "Nobody yet - the AI plays this team", FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 32), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 72 }).Parent = col
	end
end

local function spotRow(body, lobby, mine, field, order, y, label)
	UI.text({ Text = label, FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.fromOffset(70, 34), Position = UDim2.fromOffset(0, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }).Parent = body
	for i, slotId in order do
		local takenBy
		for _, p in lobby.players do
			if p.userId ~= player.UserId and p.team == mine.team and p[field] == slotId then
				takenBy = p
			end
		end
		local selected = mine[field] == slotId
		local pos = LineupConfig.ById[slotId].pos
		local b = UI.button({ name = "Spot_" .. slotId, kind = selected and (field == "off" and "primary" or "blue") or "dark", text = ("%s %d"):format(slotId, mine.ovrs[pos] or 0), size = UDim2.fromOffset(70, 34), position = UDim2.fromOffset(70 + (i - 1) * 74, y), textSize = 11, z = 72 }, function()
			if not selected and not takenBy then
				call("pos", field, slotId)
			end
		end)
		if takenBy then
			b.BackgroundTransparency = 0.6
			local lbl = b:FindFirstChild("Label", true)
			if lbl then
				lbl.Text = string.sub(string.upper(takenBy.name), 1, 7)
				lbl.TextTransparency = 0.4
			end
		end
		b.Parent = body
	end
end

local function renderLobby(body, lobby)
	local mine = me(lobby)
	if not mine then
		return
	end
	local isHost = lobby.hostId == player.UserId
	UI.text({ Text = string.upper(lobby.hostName) .. "'S GAME", FontFace = F.Display, TextScaled = false, TextSize = 24, Size = UDim2.fromOffset(420, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }).Parent = body
	if lobby.inGame then
		UI.chip("GAME IN PROGRESS", C.Gold, { TextColor3 = C.BG, Position = UDim2.fromOffset(330, 4), ZIndex = 72 }).Parent = body
	end
	UI.button({ kind = "primary", icon = "invite", text = "INVITE", size = UDim2.fromOffset(130, 30), position = UDim2.new(1, -250, 0, 0), textSize = 13, z = 72 }, invite).Parent = body
	UI.button({ name = "LeaveGame", kind = "danger", text = "LEAVE", size = UDim2.fromOffset(110, 30), position = UDim2.new(1, -110, 0, 0), textSize = 13, z = 72 }, function()
		call("leave")
	end).Parent = body

	rosterColumn(body, lobby, "home", 0)
	rosterColumn(body, lobby, "away", 420)

	-- your spot
	UI.text({ Text = "TEAM", FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.fromOffset(70, 34), Position = UDim2.fromOffset(0, 196), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }).Parent = body
	for i, team in { "home", "away" } do
		local selected = mine.team == team
		UI.button({ name = "Team_" .. team, kind = selected and (team == "home" and "primary" or "blue") or "dark", text = team == "home" and "HOME" or "AWAY", size = UDim2.fromOffset(110, 34), position = UDim2.fromOffset(70 + (i - 1) * 118, 196), textSize = 14, z = 72 }, function()
			if not selected then
				call("team", team)
			end
		end).Parent = body
	end
	spotRow(body, lobby, mine, "off", OFF_ORDER, 238, "OFFENSE")
	spotRow(body, lobby, mine, "def", DEF_ORDER, 280, "DEFENSE")

	-- start
	local right = new("Frame", { Name = "StartArea", BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 130), Position = UDim2.new(1, -210, 0, 196), ZIndex = 71 })
	right.Parent = body
	if isHost then
		UI.button({ name = "StartCustom", kind = lobby.inGame and "dark" or "gold", icon = "football", text = lobby.inGame and "IN GAME" or "START", size = UDim2.new(1, 0, 0, 64), textSize = 24, z = 72 }, function()
			if not lobby.inGame then
				local res = call("start")
				if res.ok and deps.started then
					deps.started()
				end
			end
		end).Parent = right
	else
		UI.text({ Text = lobby.inGame and "GAME IN PROGRESS - you'll be in the next one" or ("WAITING FOR %s TO START"):format(string.upper(lobby.hostName)), FontFace = F.Display, TextColor3 = C.Gold, TextWrapped = true, TextScaled = false, TextSize = 17, Size = UDim2.new(1, 0, 0, 64), ZIndex = 72 }).Parent = right
	end
	UI.text({ Text = "You play your best card at each spot. Open spots are AI. No rewards - just for fun.", FontFace = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextScaled = false, TextSize = 12, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 72), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 72 }).Parent = right
end

function CustomLobbyUI.Render(body)
	local res = call("get")
	if not body.Parent then
		return
	end
	if res.ok then
		current = res.mine
		updatePill()
	end
	if current then
		renderLobby(body, current)
	else
		renderList(body, res.list or {})
	end
end

function CustomLobbyUI.InLobby()
	return current ~= nil
end

-- deps: { parent = Instance (hub root), menu = the PLAY menu frame, toast = fn(msg, color), open = fn() (show the tab),
--         refresh = fn() (redraw the tab if it's open), started = fn() (host started a game) }
function CustomLobbyUI.Init(d)
	deps = d
	-- party pill on the hub while you're in a custom game
	pill = UI.glass({ Name = "CustomPill", Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.fromOffset(400, 46), ZIndex = 59 })
	pill:FindFirstChildOfClass("UIStroke").Color = C.Purple
	pill.Parent = d.parent
	pillText = UI.text({ Text = "", FontFace = F.Display, TextScaled = false, TextSize = 16, Size = UDim2.new(1, -130, 1, 0), Position = UDim2.fromOffset(14, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 60 })
	pillText.Parent = pill
	UI.button({ kind = "purple", text = "OPEN", size = UDim2.fromOffset(100, 32), position = UDim2.new(1, -108, 0.5, -16), textSize = 14, z = 60 }, function()
		d.open()
	end).Parent = pill

	if d.menu then
		d.menu:GetPropertyChangedSignal("Visible"):Connect(updatePill)
	end

	Remotes:WaitForChild("CustomLobbyEvent").OnClientEvent:Connect(function(ev)
		if type(ev) ~= "table" then
			return
		end
		if ev.kind == "lobby" then
			local wasIn = current ~= nil
			current = ev.lobby
			updatePill()
			d.refresh()
			if not wasIn then
				d.toast("You're in the custom game - pick your team and spots", C.Accent)
			end
		elseif ev.kind == "left" then
			current = nil
			updatePill()
			d.refresh()
		elseif ev.kind == "list" and not current then
			d.refresh()
		end
	end)
	-- already in one (UI reloaded)
	task.spawn(function()
		local res = call("get")
		if res.ok then
			current = res.mine
			updatePill()
		end
	end)
end

return CustomLobbyUI

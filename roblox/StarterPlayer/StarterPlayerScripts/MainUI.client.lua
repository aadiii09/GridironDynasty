-- Lobby UI: profile + coins, nav dock with PLAY, Pack Shop (full odds before purchase), pack
-- opening, Collection with card details/quick-sell, the 7v7 Lineup builder and the jersey Locker.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PackConfig = require(ReplicatedStorage.Shared.PackConfig)
local StoreConfig = require(ReplicatedStorage.Shared.StoreConfig)
local LineupConfig = require(ReplicatedStorage.Shared.LineupConfig)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Ratings = require(ReplicatedStorage.Shared.Ratings)
local Jerseys = require(ReplicatedStorage.Shared.Jerseys)
local CardData = require(ReplicatedStorage.Client.CardData)
local CardRenderer = require(ReplicatedStorage.Client.CardRenderer)
local UI = require(ReplicatedStorage.Client.UIKit)
local Sounds = require(ReplicatedStorage.Client.Sounds)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local C = UI.Color
local F = UI.Font
local new = UI.new

local state = { coins = 0, cards = {}, lineup = {}, stats = {}, shop = nil }

local gui = new("ScreenGui", { Name = "GridironUI", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

local function toast(msg, color)
	UI.toast(gui, msg, color)
end

local function fmtPct(p)
	if p >= 1 then
		return string.format("%.2f%%", p)
	elseif p >= 0.01 then
		return string.format("%.3f%%", p)
	end
	return string.format("%.4f%%", p)
end

local function fmtDuration(sec)
	sec = math.max(0, math.floor(sec))
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	if h >= 48 then
		return string.format("%dd %dh", math.floor(h / 24), h % 24)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm %ds", m, sec % 60)
end

local function cardByUid(uid)
	for _, entry in state.cards do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

local function lineupSlotOf(uid)
	for slotId, u in state.lineup do
		if u == uid then
			return slotId
		end
	end
	return nil
end

local function teamRatings()
	return LineupConfig.TeamRatings(state.lineup, function(uid)
		local entry = cardByUid(uid)
		return entry and CardData.Get(entry.id)
	end)
end

-- =========================================================================================
-- HUD: profile (top-left), coins (top-right), dock (bottom)
-- =========================================================================================
local hud = new("Frame", { Name = "HUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
hud.Parent = gui

-- profile card: headshot, name, record, team rating, VIP badge
local profile = UI.glass({ Position = UDim2.fromOffset(16, 66), Size = UDim2.fromOffset(320, 84) })
profile.Parent = hud
UI.flowGradient(new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.new(1, -28, 0, 3), Position = UDim2.fromOffset(14, 0), Parent = profile }, { UI.corner(2) }), C.Accent, C.Blue, C.Purple)
local headshot = new("ImageLabel", { BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(11, 11) }, {
	new("UICorner", { CornerRadius = UDim.new(1, 0) }),
	UI.stroke(C.Accent, 2),
})
headshot.Parent = profile
task.spawn(function()
	local ok, img = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	if ok then
		headshot.Image = img
	end
end)
UI.text({ Text = string.upper(player.DisplayName), FontFace = F.Display, TextScaled = false, TextSize = 24, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -96, 0, 28), Position = UDim2.fromOffset(84, 10), TextXAlignment = Enum.TextXAlignment.Left }).Parent = profile
local recordLabel = UI.text({ Text = "", FontFace = F.Display, TextColor3 = C.Muted, TextScaled = false, TextSize = 15, Size = UDim2.new(0, 120, 0, 22), Position = UDim2.fromOffset(84, 46), TextXAlignment = Enum.TextXAlignment.Left })
recordLabel.Parent = profile
local teamChip = UI.chip("TEAM --", C.Accent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 47), TextColor3 = C.BG })
teamChip.Parent = profile
local vipChip = UI.chip("VIP", C.Gold, { Visible = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 47), TextColor3 = C.BG })
vipChip.Parent = profile

-- coins: count-up number + "+" to buy more
local coinPill = UI.glass({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 66), Size = UDim2.fromOffset(230, 56) })
coinPill.Parent = hud
coinPill:FindFirstChildOfClass("UIStroke").Color = C.Gold
coinPill:FindFirstChildOfClass("UIStroke").Transparency = 0.4
local coinIcon = UI.icon("coin", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(12, 10), ImageColor3 = C.Gold })
coinIcon.Parent = coinPill
local coinsLabel = UI.text({ Text = "0", FontFace = F.Number, TextColor3 = C.Gold, TextScaled = false, TextSize = 28, Size = UDim2.new(1, -110, 0, 36), Position = UDim2.fromOffset(56, 10), TextXAlignment = Enum.TextXAlignment.Left })
coinsLabel.Parent = coinPill
local openStore -- forward
local addCoins = UI.button({ kind = "gold", text = "+", size = UDim2.fromOffset(40, 40), position = UDim2.new(1, -48, 0, 8), textSize = 24, font = F.Number }, function()
	openStore("COINS")
end)
addCoins.Parent = coinPill

local dock = new("Frame", {
	Name = "Dock",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(900, 110),
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIScale", { Name = "Fit" }),
})
dock.Parent = hud

-- colorful gradient tile with a big white icon
local function tile(iconName, label, color, color2, order, onClick)
	local t = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(132, 108), LayoutOrder = order }, {
		UI.corner(16),
		UI.stroke(Color3.new(1, 1, 1), 2, 0.75),
		new("UIGradient", { Rotation = 120, Color = ColorSequence.new(color, color2) }),
	})
	UI.icon(iconName, { Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0.5, -25, 0, 12), ImageColor3 = Color3.new(1, 1, 1) }).Parent = t
	UI.text({ Text = label, FontFace = F.Display, TextScaled = false, TextSize = 20, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -34) }).Parent = t
	local scale = new("UIScale")
	scale.Parent = t
	t.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
	end)
	t.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	t.Activated:Connect(onClick)
	t.Parent = dock
	return t
end

-- forward declarations
local openPanel, closePanels, renderShop, renderCollection, renderLineup, renderLocker, startMatch, openDifficulty
local shopPanel, collectionPanel, lineupPanel, lockerPanel, challengesPanel, leaderboardPanel

local packsTile = tile("packs", "STORE", Color3.fromRGB(190, 70, 255), Color3.fromRGB(255, 60, 140), 1, function()
	openStore("PACKS")
end)
UI.shine(packsTile, 4.5)
local hotBadge = UI.chip("HOT", C.Red, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), ZIndex = 5 })
hotBadge.Parent = packsTile
local freeBadge = UI.chip("FREE PACK!", C.Accent, { Visible = false, TextColor3 = C.BG, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -12), ZIndex = 6 })
freeBadge.Parent = packsTile
tile("lineup", "LINEUP", Color3.fromRGB(255, 190, 40), Color3.fromRGB(255, 110, 30), 2, function()
	openPanel(lineupPanel)
	renderLineup()
end)
tile("collection", "CARDS", Color3.fromRGB(40, 170, 255), Color3.fromRGB(60, 90, 255), 3, function()
	openPanel(collectionPanel)
	renderCollection()
end)
local lockerTile = tile("jersey", "LOCKER", Color3.fromRGB(46, 220, 160), Color3.fromRGB(20, 140, 200), 4, function()
	openPanel(lockerPanel)
	renderLocker()
end)
local lockerBadge = UI.chip("1/16", C.BG, { TextColor3 = C.Accent, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), ZIndex = 5 })
lockerBadge.Parent = lockerTile

local playButton = UI.button({ kind = "primary", text = "PLAY", icon = "football", iconScale = 0.5, size = UDim2.fromOffset(270, 108), order = 5, textSize = 44, radius = 18 }, function()
	openDifficulty()
end)
playButton.Parent = dock
local playGlow = UI.stroke(C.Accent, 3, 0.2)
playGlow.Parent = playButton
TweenService:Create(playGlow, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85, Thickness = 7 }):Play()
UI.shine(playButton, 3)
UI.text({ Text = "VS AI  -  7v7  -  PICK YOUR DIFFICULTY", FontFace = F.Display, TextColor3 = Color3.fromRGB(8, 60, 34), TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -22), ZIndex = 2 }).Parent = playButton

-- shrink the dock on narrow (phone) screens
local function fitDock()
	local w = gui.AbsoluteSize.X
	dock.Fit.Scale = math.clamp((w - 24) / 920, 0.4, 1)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitDock)

-- =========================================================================================
-- Panels
-- =========================================================================================
local panels = {}
local backdrop = new("TextButton", { Name = "Backdrop", Visible = false, AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 5 })
backdrop.Parent = gui

local function makePanel(name, title, iconName, color)
	local panel = UI.glass({
		Name = name,
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 20),
		Size = UDim2.new(1, -32, 1, -120),
		ZIndex = 10,
	}, {
		new("UISizeConstraint", { MaxSize = Vector2.new(1120, 740) }),
	})
	-- header: glowing color bar, icon badge, big condensed title
	local bar = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.new(1, -40, 0, 4), Position = UDim2.fromOffset(20, 0), ZIndex = 11 }, { UI.corner(2) })
	new("UIGradient", { Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.3)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.2), NumberSequenceKeypoint.new(1, 1) }) }).Parent = bar
	bar.Parent = panel
	local badge = new("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(18, 12), ZIndex = 11 }, { UI.corner(12) })
	UI.icon(iconName, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(7, 7), ImageColor3 = Color3.new(1, 1, 1), ZIndex = 12 }).Parent = badge
	badge.Parent = panel
	local titleLabel = UI.text({ Name = "Title", Text = title, FontFace = F.Display, TextScaled = false, TextSize = 34, Size = UDim2.new(1, -140, 0, 40), Position = UDim2.fromOffset(72, 12), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 })
	titleLabel.Parent = panel
	local close = UI.button({ kind = "dark", icon = "close", size = UDim2.fromOffset(44, 40), position = UDim2.new(1, -58, 0, 12), z = 11 }, function()
		closePanels()
	end)
	close.Parent = panel
	local body = new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -28, 1, -78),
		Position = UDim2.fromOffset(14, 64),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = color,
		ZIndex = 11,
	})
	body.Parent = panel
	panel.Parent = gui
	table.insert(panels, panel)
	return panel, body
end

local hubOnly = {} -- hub widgets hidden while a menu is open

function closePanels()
	for _, p in panels do
		p.Visible = false
	end
	backdrop.Visible = false
	dock.Visible = true
	for _, w in hubOnly do
		w.Visible = not w:GetAttribute("Dismissed")
	end
	UI.blur(false)
end
backdrop.Activated:Connect(closePanels)

function openPanel(panel)
	for _, p in panels do
		p.Visible = p == panel
	end
	backdrop.Visible = panel ~= nil
	dock.Visible = panel == nil
	for _, w in hubOnly do
		w.Visible = panel == nil and not w:GetAttribute("Dismissed")
	end
	UI.blur(panel ~= nil)
	if panel then
		UI.pop(panel, 0.22)
	end
end

local shopBody, collectionBody, oddsBody, lineupBody, lockerBody, challengesBody, leaderboardBody
shopPanel, shopBody = makePanel("Shop", "STORE", "packs", Color3.fromRGB(220, 70, 220))
collectionPanel, collectionBody = makePanel("Collection", "COLLECTION", "collection", C.Blue)
lineupPanel, lineupBody = makePanel("Lineup", "LINEUP", "lineup", C.Gold)
lockerPanel, lockerBody = makePanel("Locker", "LOCKER", "jersey", C.Accent)
challengesPanel, challengesBody = makePanel("Challenges", "CHALLENGES", "trophy", C.Accent)
leaderboardPanel, leaderboardBody = makePanel("Leaderboard", "LEADERBOARD", "trophy", C.Gold)
local oddsPanel
oddsPanel, oddsBody = makePanel("Odds", "PACK ODDS", "packs", C.Purple)

-- =========================================================================================
-- Shop
-- =========================================================================================
local packButtons = {}
local revealPack -- forward

local function packInfo(id)
	for _, p in state.shop.packs do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function openOdds(pack)
	CardData.Ensure()
	oddsBody:ClearAllChildren()
	oddsPanel.Title.Text = string.upper(pack.name) .. " ODDS"
	local info = packInfo(pack.id)
	if not info then
		return
	end
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = oddsBody
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10) }).Parent = oddsBody
	local order = 0
	local function row(str, color, size, font)
		order += 1
		UI.text({ Text = str, TextScaled = false, TextSize = size or 15, FontFace = font or F.Medium, TextColor3 = color or C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, ZIndex = 12 }).Parent = oddsBody
	end
	local function bar(tier, e)
		order += 1
		local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, ZIndex = 12 })
		UI.text({ Text = tier, FontFace = F.Heavy, TextScaled = false, TextSize = 16, TextColor3 = GameConfig.TierColors[tier], Size = UDim2.fromOffset(80, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }).Parent = r
		local track = new("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.new(1, -330, 0, 12), Position = UDim2.fromOffset(86, 9), ZIndex = 12 }, { UI.corner(6) })
		new("Frame", { BackgroundColor3 = GameConfig.TierColors[tier], Size = UDim2.fromScale(math.max(e.pct / 100, 0.01), 1), ZIndex = 13 }, { UI.corner(6) }).Parent = track
		track.Parent = r
		UI.text({ Text = ("%s   (%d cards, %s each)"):format(fmtPct(e.pct), e.count, fmtPct(e.pct / e.count)), FontFace = F.Bold, TextScaled = false, TextSize = 14, Size = UDim2.new(0, 230, 1, 0), Position = UDim2.new(1, -235, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12 }).Parent = r
		r.Parent = oddsBody
	end
	row(("%d cards per pack. These odds are exact and each table adds up to 100%%."):format(pack.cards), C.Muted)
	local function tierTable(title, odds)
		row(title, C.Accent, 18, F.Heavy)
		for _, tier in GameConfig.TierOrder do
			if odds[tier] then
				bar(tier, odds[tier])
			end
		end
	end
	tierTable(pack.guaranteed and ("CARDS 1-" .. (pack.cards - 1)) or "EVERY CARD", info.odds.slot)
	if info.odds.guaranteed then
		tierTable("CARD " .. pack.cards .. "  -  GUARANTEED SLOT", info.odds.guaranteed)
	end
	row("EVERY CARD YOU CAN GET", C.Accent, 18, F.Heavy)
	local all = table.clone(CardData.All())
	table.sort(all, function(a, b)
		return a.ovr > b.ovr or (a.ovr == b.ovr and a.id < b.id)
	end)
	task.spawn(function()
		for i, card in all do
			local slot = info.odds.slot[card.tier]
			local g = info.odds.guaranteed and info.odds.guaranteed[card.tier]
			if slot or g then
				local d = CardData.Describe(card.id)
				local program = card.program == "Week Standout" and ("Week " .. card.week .. " Standout") or card.program
				local str = ("%d  %s  %s %s  (%s, %s)  -  %s"):format(card.ovr, card.pos, d.first, d.last, card.tier, program, slot and fmtPct(slot.pct / slot.count) or "0%")
				if info.odds.guaranteed then
					str ..= "  |  guaranteed slot: " .. (g and fmtPct(g.pct / g.count) or "0%")
				end
				row(str, C.Text, 13)
			end
			if i % 150 == 0 then
				task.wait()
				if not oddsPanel.Visible then
					return
				end
			end
		end
	end)
	openPanel(oddsPanel)
end

local function priceText(pack, info)
	if pack.currency == "Free" then
		local wait = (state.shop.freePackReadyAt or 0) - os.time()
		return wait > 0 and ("READY IN " .. fmtDuration(wait)) or "OPEN FREE", wait <= 0
	elseif pack.currency == "Coins" then
		return UI.commas(pack.price), state.coins >= pack.price
	end
	if state.shop.paidRandomRestricted then
		return "UNAVAILABLE", false
	elseif not info.available then
		return "COMING SOON", false
	end
	return "R$ " .. pack.price, true
end

local function buyPack(pack)
	if pack.currency == "Robux" then
		local res = Remotes.PromptPack:InvokeServer(pack.id)
		if not res.ok then
			toast(res.err, C.Red)
		end
		return
	end
	local res = Remotes.OpenPack:InvokeServer(pack.id)
	if not res.ok then
		toast(res.err, C.Red)
		return
	end
	if pack.currency == "Free" then
		state.shop.freePackReadyAt = os.time() + PackConfig.FreePackCooldown
		freeBadge.Visible = false
	end
	revealPack(pack, res.cards)
end

local PACK_RIBBON = { elite = { "POPULAR", C.Blue }, dynasty = { "BEST ODDS", C.Red }, daily = { "FREE", Color3.fromRGB(20, 170, 100) } }
local storeTab = "PACKS"

local function renderPacks(body)
	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 12 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(204, 372), CellPadding = UDim2.fromOffset(16, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 10) }),
	})
	grid.Parent = body
	if state.shop.paidRandomRestricted then
		toast("Robux packs aren't available for your account.", C.Gold)
	end
	for i, pack in PackConfig.Packs do
		local info = packInfo(pack.id)
		local tileFrame = UI.glass({ LayoutOrder = i, ZIndex = 12 })
		tileFrame:FindFirstChildOfClass("UIStroke").Color = pack.color
		tileFrame:FindFirstChildOfClass("UIStroke").Thickness = 2
		UI.flowGradient(new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, Size = UDim2.new(1, 0, 0, 250), ZIndex = 12, Parent = tileFrame }, { UI.corner(14) }), pack.color, pack.color:Lerp(Color3.new(0, 0, 0), 0.7), pack.color)
		local art = new("ImageLabel", {
			BackgroundTransparency = Assets.pack ~= "" and 1 or 0,
			BackgroundColor3 = pack.color,
			Image = Assets.pack,
			ImageColor3 = pack.color,
			Size = UDim2.fromOffset(150, 218),
			Position = UDim2.new(0.5, -75, 0, 14),
			ZIndex = 13,
		})
		art.Parent = tileFrame
		UI.text({ Text = string.upper(pack.name):gsub(" PACK", ""):gsub("DAILY FREE", "DAILY"), FontFace = F.Display, TextColor3 = C.Text, TextStrokeTransparency = 0.3, Size = UDim2.new(0.9, 0, 0, 38), Position = UDim2.new(0.05, 0, 0, 152), ZIndex = 14 }).Parent = art
		UI.text({ Text = ("%d CARDS"):format(pack.cards), FontFace = F.Display, TextColor3 = C.BG, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 22), ZIndex = 14 }).Parent = art
		UI.shine(art, 4 + i * 0.4, 15)
		local rb = PACK_RIBBON[pack.id]
		if rb then
			UI.ribbon(tileFrame, rb[1], rb[2], 16)
		end
		UI.text({ Text = pack.blurb, FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 244), ZIndex = 13 }).Parent = tileFrame
		local label, ready = priceText(pack, info)
		local kind = not ready and "disabled" or pack.currency == "Coins" and "gold" or pack.currency == "Robux" and "blue" or "primary"
		local buy = UI.button({ kind = kind, text = label, icon = pack.currency == "Coins" and "coin" or nil, size = UDim2.new(1, -24, 0, 48), position = UDim2.fromOffset(12, 268), textSize = 18, font = F.Number, z = 13 }, function()
			buyPack(pack)
		end)
		packButtons[pack.id] = buy
		buy.Parent = tileFrame
		UI.button({ kind = "dark", text = "VIEW ODDS", size = UDim2.new(1, -24, 0, 34), position = UDim2.fromOffset(12, 326), textSize = 13, z = 13 }, function()
			openOdds(pack)
		end).Parent = tileFrame
		tileFrame.Parent = grid
	end
end

local function coinStack(parent, n, size)
	-- a little pile of coins: bigger bundle, bigger pile
	for k = 1, n do
		local col = (k - 1) % 3
		local row = math.floor((k - 1) / 3)
		UI.icon("coin", {
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, (col - 1) * size * 0.55, 0.5, -row * size * 0.32 + 10),
			ImageColor3 = C.Gold:Lerp(Color3.new(1, 1, 1), (k % 2) * 0.15),
			ZIndex = 13 + k,
		}).Parent = parent
	end
end

local function renderCoins(body)
	local store = state.store or {}
	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 12 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(230, 300), CellPadding = UDim2.fromOffset(16, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 10) }),
	})
	grid.Parent = body
	for i, b in StoreConfig.CoinBundles do
		local avail = false
		for _, s in store.bundles or {} do
			if s.id == b.id then
				avail = s.available
			end
		end
		local card = UI.glass({ LayoutOrder = i, ZIndex = 12 })
		card:FindFirstChildOfClass("UIStroke").Color = C.Gold
		card:FindFirstChildOfClass("UIStroke").Thickness = b.tag and 2 or 1
		local art = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -16, 0, 140), Position = UDim2.fromOffset(8, 8), ZIndex = 12 }, { UI.corner(12) })
		UI.flowGradient(art, Color3.fromRGB(90, 60, 10), Color3.fromRGB(200, 140, 20), Color3.fromRGB(90, 60, 10))
		art.Parent = card
		coinStack(art, i + 2, 44 + i * 4)
		UI.shine(art, 3.5 + i * 0.5, 30)
		if b.tag then
			UI.ribbon(card, b.tag, b.tag == "BEST VALUE" and C.Red or C.Blue, 40)
		end
		UI.text({ Text = UI.commas(b.coins), FontFace = F.Number, TextColor3 = C.Gold, TextScaled = false, TextSize = 36, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 154), ZIndex = 13 }).Parent = card
		UI.text({ Text = "COINS", FontFace = F.Display, TextColor3 = C.Muted, TextScaled = false, TextSize = 16, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 194), ZIndex = 13 }).Parent = card
		local buy = UI.button({ kind = avail and "blue" or "disabled", text = avail and ("R$ " .. b.price) or (store.coinsRestricted and "UNAVAILABLE" or "COMING SOON"), size = UDim2.new(1, -24, 0, 50), position = UDim2.fromOffset(12, 232), textSize = 20, font = F.Number, z = 13 }, function()
			local res = Remotes.PromptCoins:InvokeServer(b.id)
			if not res.ok then
				toast(res.err, C.Gold)
			end
		end)
		buy.Parent = card
		if avail then
			UI.shine(buy, 3)
		end
		card.Parent = grid
	end
	-- how to earn coins for free
	local earn = UI.glass({ Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 12 }, {
		UI.pad(14),
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	UI.text({ Text = "EARN COINS FOR FREE", FontFace = F.Display, TextColor3 = C.Accent, TextScaled = false, TextSize = 22, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, ZIndex = 13 }).Parent = earn
	for i, row in StoreConfig.EarnInfo do
		local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = i, ZIndex = 13 })
		UI.text({ Text = row[1], FontFace = F.Bold, TextScaled = false, TextSize = 15, Size = UDim2.new(0.7, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }).Parent = r
		UI.text({ Text = row[2], FontFace = F.Number, TextColor3 = C.Gold, TextScaled = false, TextSize = 17, Size = UDim2.new(0.3, 0, 1, 0), Position = UDim2.fromScale(0.7, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 13 }).Parent = r
		r.Parent = earn
	end
	if state.store and state.store.vip then
		UI.text({ Text = "VIP: your game rewards and daily bonus are doubled!", FontFace = F.Bold, TextColor3 = C.Gold, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 99, ZIndex = 13 }).Parent = earn
	end
	earn.Parent = body
end

local function renderVIP(body)
	local store = state.store or {}
	local vip = StoreConfig.VIP
	local card = UI.glass({ Size = UDim2.new(1, -20, 0, 330), LayoutOrder = 2, ZIndex = 12 })
	card:FindFirstChildOfClass("UIStroke").Color = C.Gold
	card:FindFirstChildOfClass("UIStroke").Thickness = 2
	local hero = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0.42, -12, 1, -24), Position = UDim2.fromOffset(12, 12), ZIndex = 12 }, { UI.corner(14) })
	UI.flowGradient(hero, Color3.fromRGB(255, 196, 46), Color3.fromRGB(255, 120, 30), Color3.fromRGB(200, 60, 160))
	UI.icon("trophy", { Size = UDim2.fromScale(0.55, 0.55), SizeConstraint = Enum.SizeConstraint.RelativeYY, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), ImageColor3 = Color3.new(1, 1, 1), ZIndex = 13 }).Parent = hero
	UI.text({ Text = "VIP", FontFace = F.Display, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Size = UDim2.new(1, 0, 0.2, 0), Position = UDim2.fromScale(0, 0.74), ZIndex = 13 }).Parent = hero
	UI.shine(hero, 3, 20)
	hero.Parent = card
	local right = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.58, -24, 1, -24), Position = UDim2.new(0.42, 12, 0, 12), ZIndex = 12 }, {
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	UI.text({ Text = vip.name, FontFace = F.Display, TextColor3 = C.Gold, TextScaled = false, TextSize = 40, Size = UDim2.new(1, 0, 0, 46), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 13 }).Parent = right
	UI.text({ Text = "One-time purchase, yours forever", FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 15, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, ZIndex = 13 }).Parent = right
	for i, perk in vip.perks do
		local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 + i, ZIndex = 13 })
		new("Frame", { BackgroundColor3 = C.Accent, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(0, 4), ZIndex = 13 }, { UI.corner(11), UI.text({ Text = "✓", FontFace = F.Heavy, TextColor3 = C.BG, Size = UDim2.fromScale(1, 1), ZIndex = 14 }) }).Parent = r
		UI.text({ Text = perk, FontFace = F.Display, TextScaled = false, TextSize = 20, Size = UDim2.new(1, -34, 1, 0), Position = UDim2.fromOffset(34, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }).Parent = r
		r.Parent = right
	end
	local owned = store.vip
	local buy = UI.button({ kind = owned and "disabled" or (store.vipAvailable and "gold" or "disabled"), text = owned and "OWNED" or (store.vipAvailable and ("R$ " .. vip.price) or "COMING SOON"), size = UDim2.new(1, 0, 0, 56), order = 9, textSize = 24, font = F.Number, z = 13 }, function()
		local res = Remotes.PromptVIP:InvokeServer()
		if not res.ok then
			toast(res.err, C.Gold)
		end
	end)
	buy.Parent = right
	if not owned then
		UI.shine(buy, 2.5)
	end
	right.Parent = card
	card.Parent = body
end

function renderShop(tab)
	storeTab = tab or storeTab
	state.shop = Remotes.GetShop:InvokeServer()
	state.store = Remotes.GetStore:InvokeServer()
	shopBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }).Parent = shopBody
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10) }).Parent = shopBody
	-- tab bar
	local tabs = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 1, ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	for _, t in { { "PACKS", "packs", "purple" }, { "COINS", "coin", "gold" }, { "VIP", "trophy", "danger" } } do
		UI.button({ kind = storeTab == t[1] and t[3] or "dark", text = t[1], icon = t[2], size = UDim2.fromOffset(170, 46), textSize = 20, z = 12 }, function()
			renderShop(t[1])
		end).Parent = tabs
	end
	tabs.Parent = shopBody
	if storeTab == "COINS" then
		renderCoins(shopBody)
	elseif storeTab == "VIP" then
		renderVIP(shopBody)
	else
		renderPacks(shopBody)
	end
end

openStore = function(tab)
	openPanel(shopPanel)
	renderShop(tab)
end

-- free pack countdown + badge
task.spawn(function()
	while true do
		task.wait(1)
		if state.shop then
			local ready = os.time() >= (state.shop.freePackReadyAt or math.huge)
			freeBadge.Visible = ready
			local btn = packButtons.daily
			if btn and btn.Parent and shopPanel.Visible then
				local label, ok = priceText(PackConfig.ById.daily, {})
				UI.setButton(btn, label, ok and "primary" or "disabled")
			end
		end
	end
end)

-- =========================================================================================
-- Pack opening
-- =========================================================================================
local overlay = new("Frame", { Name = "Reveal", Visible = false, BackgroundColor3 = Color3.fromRGB(3, 4, 8), BackgroundTransparency = 0.12, Size = UDim2.fromScale(1, 1), ZIndex = 50 })
overlay.Parent = gui
local rays = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.rays, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 900), ImageTransparency = 1, ZIndex = 50 })
rays.Parent = overlay
local revealTitle = UI.text({ FontFace = F.Heavy, TextScaled = false, TextSize = 34, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72), Size = UDim2.new(1, 0, 0, 40), ZIndex = 53 })
revealTitle.Parent = overlay
local revealHint = UI.text({ FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 15, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(1, 0, 0, 20), ZIndex = 53 })
revealHint.Parent = overlay
local revealRow = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -24, 1, -240), Position = UDim2.fromOffset(12, 140), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 5, ZIndex = 52 })
revealRow.Parent = overlay
local packImage = new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.pack, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(260, 377), Visible = false, ZIndex = 54 })
packImage.Parent = overlay
local flash = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60 })
flash.Parent = overlay
local revealButton = UI.button({ kind = "primary", text = "REVEAL ALL", size = UDim2.fromOffset(240, 54), anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -24), textSize = 20, z = 55 })
revealButton.Parent = overlay

RunService.RenderStepped:Connect(function(dt)
	if overlay.Visible then
		rays.Rotation = (rays.Rotation + dt * 18) % 360
	end
end)

local function doFlash(strength)
	flash.BackgroundTransparency = 1 - (strength or 0.8)
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
end

local function flipSlot(slot, info)
	if slot:GetAttribute("Flipped") then
		return
	end
	slot:SetAttribute("Flipped", true)
	local tierIndex = table.find(GameConfig.TierOrder, info.card.tier) or 1
	local tierColor = GameConfig.TierColors[info.card.tier]
	if tierIndex >= 4 then
		rays.ImageColor3 = tierColor
		TweenService:Create(rays, TweenInfo.new(0.4), { ImageTransparency = 0.25 }):Play()
		revealTitle.Text = info.card.tier == "Icon" and "ICON PULL!" or "ELITE PULL!"
		Sounds.Play("cheer", info.card.tier == "Icon" and 1.2 or 0.8)
		revealTitle.TextColor3 = tierColor
		local back = slot:FindFirstChild("CardBack")
		if back then
			local scale = new("UIScale", { Parent = back })
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 6, true), { Scale = 1.06 }):Play()
		end
		task.wait(0.9)
	end
	local half = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local t = TweenService:Create(slot, half, { Size = UDim2.new(0, 0, 1, 0), Position = UDim2.fromScale(0.5, 0) })
	t:Play()
	t.Completed:Wait()
	local back = slot:FindFirstChild("CardBack")
	if back then
		back:Destroy()
	end
	Sounds.Play("cardFlip", 1, 0.9 + math.random() * 0.25)
	local face = CardRenderer.Create(info)
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 53
	face.Parent = slot
	if tierIndex >= 3 then
		doFlash(tierIndex >= 4 and 0.7 or 0.35)
	end
	TweenService:Create(slot, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0) }):Play()
	if tierIndex >= 4 then
		task.wait(0.6)
	end
end

revealPack = function(pack, cards)
	CardData.Ensure()
	openPanel(nil)
	UI.blur(true)
	dock.Visible = false
	revealRow:ClearAllChildren()
	rays.ImageTransparency = 1
	revealTitle.Text = string.upper(pack.name)
	revealTitle.TextColor3 = C.Text
	revealHint.Text = ""
	revealButton.Visible = false
	overlay.Visible = true

	-- 1) the pack shakes and bursts
	packImage.ImageColor3 = pack.color
	Sounds.Play("packWhoosh")
	packImage.Visible = true
	packImage.Rotation = 0
	UI.pop(packImage, 0.35)
	task.wait(0.4)
	for i = 1, 8 do
		local r = (i % 2 == 0 and 1 or -1) * (2 + i)
		TweenService:Create(packImage, TweenInfo.new(0.06), { Rotation = r }):Play()
		task.wait(0.07)
	end
	doFlash(0.95)
	Sounds.Play("packTear")
	packImage.Visible = false

	-- 2) cards land face down
	new("UIGridLayout", { CellSize = UDim2.fromOffset(176, 264), CellPadding = UDim2.fromOffset(14, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }).Parent = revealRow
	local infos = {}
	for _, c in cards do
		local d = CardData.Describe(c.id)
		if d then
			table.insert(infos, d)
		end
	end
	table.sort(infos, function(a, b)
		return a.card.ovr < b.card.ovr -- best card last
	end)
	local slots = {}
	for i, d in infos do
		local holder = new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 52 })
		local slot = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 52 })
		local back = CardRenderer.Back(nil)
		back.Size = UDim2.fromScale(1, 1)
		back.ZIndex = 53
		back.Parent = slot
		slot.Parent = holder
		holder.Parent = revealRow
		UI.pop(holder, 0.3)
		slots[i] = slot
		slot.Activated:Connect(function()
			task.spawn(flipSlot, slot, d)
		end)
		task.wait(0.08)
	end

	revealHint.Text = "Tap a card to flip it"
	revealButton.Visible = true
	UI.setButton(revealButton, "REVEAL ALL", "primary")
	local conn
	conn = revealButton.Activated:Connect(function()
		if revealButton:GetAttribute("Done") then
			conn:Disconnect()
			revealButton:SetAttribute("Done", nil)
			overlay.Visible = false
			UI.blur(false)
			openPanel(shopPanel)
			renderShop()
			return
		end
		revealButton.Visible = false
		for i, d in infos do
			flipSlot(slots[i], d)
			task.wait(0.12)
		end
		revealTitle.Text = "PACK OPENED"
		revealTitle.TextColor3 = C.Accent
		revealHint.Text = "Cards were added to your collection"
		revealButton:SetAttribute("Done", true)
		UI.setButton(revealButton, "CONTINUE", "primary")
		revealButton.Visible = true
	end)
end

Remotes:WaitForChild("PackOpened").OnClientEvent:Connect(function(result)
	local pack = PackConfig.ById[result.packId]
	if pack and result.ok then
		revealPack(pack, result.cards)
	end
end)

-- =========================================================================================
-- Collection + card details
-- =========================================================================================
local function attrColor(v)
	if v >= 90 then
		return C.Accent
	elseif v >= 80 then
		return Color3.fromRGB(150, 230, 90)
	elseif v >= 70 then
		return C.Gold
	end
	return Color3.fromRGB(255, 130, 80)
end

local detail = UI.glass({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(780, 470), ZIndex = 40 })
detail.Parent = gui

-- One rating: name, value, bar (and what it does, in the roomy KEY view)
local function ratingCell(key, v, size, showEffect, order)
	local cell = new("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.35, Size = size, LayoutOrder = order or 0, ZIndex = 41 }, { UI.corner(8) })
	local w = size.X.Offset
	UI.text({ Text = showEffect and Ratings.Names[key] or (key .. "  " .. string.upper(Ratings.Names[key] or "")), FontFace = F.Bold, TextScaled = false, TextSize = showEffect and 14 or 12, TextColor3 = showEffect and C.Text or Color3.fromRGB(205, 210, 222), Size = UDim2.fromOffset(w - 54, 18), Position = UDim2.fromOffset(10, 5), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42 }).Parent = cell
	UI.text({ Text = tostring(v), FontFace = F.Number, TextScaled = false, TextSize = showEffect and 22 or 18, TextColor3 = attrColor(v), Size = UDim2.fromOffset(44, 22), Position = UDim2.fromOffset(w - 52, showEffect and 4 or 3), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 42 }).Parent = cell
	local track = new("Frame", { BackgroundColor3 = C.BG, Size = UDim2.fromOffset(w - 20, 5), Position = UDim2.fromOffset(10, showEffect and 28 or 25), ZIndex = 42 }, { UI.corner(3) })
	local fill = new("Frame", { BackgroundColor3 = attrColor(v), Size = UDim2.fromScale(0, 1), ZIndex = 43 }, { UI.corner(3) })
	fill.Parent = track
	track.Parent = cell
	TweenService:Create(fill, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(v / 99, 1) }):Play()
	if showEffect then
		UI.text({ Text = Ratings.Effects[key] or "", FontFace = F.Medium, TextScaled = false, TextSize = 11, TextColor3 = C.Muted, Size = UDim2.fromOffset(w - 20, 14), Position = UDim2.fromOffset(10, 37), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42 }).Parent = cell
	end
	return cell
end

local detailView = "KEY"

local function openCard(entry)
	detail:ClearAllChildren()
	UI.corner(14).Parent = detail
	UI.stroke(C.Stroke, 1).Parent = detail
	local d = CardData.Describe(entry.id)
	local tierColor = GameConfig.TierColors[d.card.tier]
	detail:FindFirstChildOfClass("UIStroke").Color = tierColor
	local face = CardRenderer.Create(d)
	face.Size = UDim2.fromOffset(270, 405)
	face.Position = UDim2.fromOffset(22, 32)
	face.ZIndex = 41
	face.Parent = detail
	local x = 312
	local W = 446
	UI.text({ Text = string.upper(d.first .. " " .. d.last), FontFace = F.Display, TextScaled = false, TextSize = 30, Size = UDim2.fromOffset(W, 34), Position = UDim2.fromOffset(x, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }).Parent = detail
	local team = d.team or {}
	UI.text({ Text = ("%s  |  %s %s  |  #%s"):format(d.card.pos, team.city or "", team.name or "", tostring(d.number or "")), FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(W, 18), Position = UDim2.fromOffset(x, 56), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }).Parent = detail
	local chips = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(W, 24), Position = UDim2.fromOffset(x, 80), ZIndex = 41 }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
	UI.chip(d.card.tier:upper(), tierColor, { TextColor3 = C.BG, ZIndex = 41 }).Parent = chips
	UI.chip(d.card.program == "Week Standout" and ("WEEK " .. d.card.week .. " STANDOUT") or "BASE", C.Panel2, { ZIndex = 41 }).Parent = chips
	UI.chip(string.upper(d.card.archetype or ""), C.Panel2, { ZIndex = 41 }).Parent = chips
	chips.Parent = detail

	-- KEY (the ratings that matter at his position, with what they do) | ALL (every rating, grouped)
	local tabs = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(W, 30), Position = UDim2.fromOffset(x, 114), ZIndex = 41 }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
	tabs.Parent = detail
	for _, view in { "KEY", "ALL" } do
		UI.button({ kind = detailView == view and "blue" or "dark", text = view == "KEY" and "KEY RATINGS" or "ALL RATINGS", size = UDim2.fromOffset(130, 30), textSize = 13, z = 41 }, function()
			if detailView ~= view then
				detailView = view
				openCard(entry)
			end
		end).Parent = tabs
	end

	local body = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(W, 236),
		Position = UDim2.fromOffset(x, 152),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = tierColor,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 41,
	})
	body.Parent = detail
	local attrs = d.card.attrs
	local keySet = {}
	for _, k in Ratings.Key[d.card.pos] or {} do
		keySet[k] = true
	end
	if detailView == "KEY" then
		new("UIGridLayout", { CellSize = UDim2.fromOffset(216, 54), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = body
		for i, k in Ratings.Key[d.card.pos] or {} do
			ratingCell(k, Ratings.Get(attrs, k), UDim2.fromOffset(216, 54), true, i).Parent = body
		end
	else
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = body
		-- groups that matter for his position first
		local groups = table.clone(Ratings.Groups)
		local function relevance(g)
			local n = 0
			for _, k in g.keys do
				n += keySet[k] and 1 or 0
			end
			return n
		end
		table.sort(groups, function(a, b)
			return relevance(a) > relevance(b)
		end)
		for gi, g in groups do
			UI.text({ Text = g.name, FontFace = F.Heavy, TextScaled = false, TextSize = 12, TextColor3 = relevance(g) > 0 and tierColor or C.Muted, Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = gi * 2 - 1, ZIndex = 41 }).Parent = body
			local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = gi * 2, ZIndex = 41 }, {
				new("UIGridLayout", { CellSize = UDim2.fromOffset(212, 36), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for i, k in g.keys do
				local cell = ratingCell(k, Ratings.Get(attrs, k), UDim2.fromOffset(212, 36), false, i)
				cell.Parent = grid
			end
			grid.Parent = body
		end
	end

	local starting = lineupSlotOf(entry.uid)
	if starting then
		UI.text({ Text = "STARTING AT " .. starting, FontFace = F.Heavy, TextColor3 = C.Gold, TextScaled = false, TextSize = 13, Size = UDim2.fromOffset(200, 16), Position = UDim2.fromOffset(x + W - 200, 398), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 41 }).Parent = detail
	end
	local value = GameConfig.QuickSell[d.card.tier] or 0
	local armed = false
	local sell
	sell = UI.button({ kind = "gold", icon = "coin", text = "QUICK SELL  " .. UI.commas(value), size = UDim2.fromOffset(200, 44), position = UDim2.fromOffset(x, 400), textSize = 15, z = 41 }, function()
		if not armed then
			armed = true
			UI.setButton(sell, "TAP TO CONFIRM", "danger")
			return
		end
		local res = Remotes.QuickSell:InvokeServer(entry.uid)
		detail.Visible = false
		toast(res.ok and ("Sold for " .. UI.commas(res.coins) .. " Coins") or (res.err or "Couldn't sell"), res.ok and C.Gold or C.Red)
	end)
	sell.Parent = detail
	UI.button({ kind = "dark", text = "CLOSE", size = UDim2.fromOffset(100, 44), position = UDim2.fromOffset(x + 210, 400), textSize = 15, z = 41 }, function()
		detail.Visible = false
	end).Parent = detail
	detail.Visible = true
	UI.pop(detail, 0.2)
end

local collectionFilter = "ALL"
local renderToken = 0
function renderCollection()
	CardData.Ensure()
	renderToken += 1
	local myToken = renderToken
	collectionBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = collectionBody

	local filters = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	for _, f in { "ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S" } do
		UI.button({ kind = f == collectionFilter and "blue" or "dark", text = f, size = UDim2.fromOffset(f == "ALL" and 64 or 52, 34), textSize = 14, z = 12 }, function()
			collectionFilter = f
			renderCollection()
		end).Parent = filters
	end
	filters.Parent = collectionBody

	local list = {}
	for _, entry in state.cards do
		local d = CardData.Describe(entry.id)
		if d and (collectionFilter == "ALL" or d.card.pos == collectionFilter) then
			table.insert(list, { entry = entry, d = d })
		end
	end
	table.sort(list, function(a, b)
		return a.d.card.ovr > b.d.card.ovr or (a.d.card.ovr == b.d.card.ovr and a.entry.uid < b.entry.uid)
	end)
	UI.text({ Text = ("%d CARDS"):format(#list), FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, ZIndex = 12 }).Parent = collectionBody

	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 12 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(156, 234), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	grid.Parent = collectionBody
	for i, item in list do
		local face = CardRenderer.Create(item.d)
		face.LayoutOrder = i
		face.ZIndex = 12
		if lineupSlotOf(item.entry.uid) then
			UI.chip("STARTER", C.Gold, { TextColor3 = C.BG, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), ZIndex = 20 }).Parent = face
		end
		local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 21 })
		hit.Activated:Connect(function()
			openCard(item.entry)
		end)
		hit.Parent = face
		face.Parent = grid
		if i % 16 == 0 then
			task.wait()
			if myToken ~= renderToken then
				return
			end
		end
	end
end

-- =========================================================================================
-- Lineup
-- =========================================================================================
local lineupSide = "Offense"
local picker = UI.glass({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 20), Size = UDim2.new(1, -60, 1, -150), ZIndex = 40 }, {
	new("UISizeConstraint", { MaxSize = Vector2.new(1020, 640) }),
})
picker.Parent = gui
local pickerTitle = UI.text({ FontFace = F.Heavy, TextScaled = false, TextSize = 22, Size = UDim2.new(1, -300, 0, 28), Position = UDim2.fromOffset(20, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 })
pickerTitle.Parent = picker
UI.button({ kind = "dark", icon = "close", size = UDim2.fromOffset(44, 40), position = UDim2.new(1, -58, 0, 10), z = 41 }, function()
	picker.Visible = false
end).Parent = picker
local pickerRemove = UI.button({ kind = "danger", text = "EMPTY SLOT", size = UDim2.fromOffset(150, 40), position = UDim2.new(1, -218, 0, 10), textSize = 14, z = 41 })
pickerRemove.Parent = picker
local pickerBody = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -24, 1, -70), Position = UDim2.fromOffset(12, 60), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 5, ZIndex = 41 })
pickerBody.Parent = picker

local function setSlot(slotId, uid)
	local res = Remotes.SetLineupSlot:InvokeServer(slotId, uid)
	if not res.ok then
		toast(res.err or "Couldn't change lineup", C.Red)
	end
	picker.Visible = false
end

local pickerRemoveConn
local function openPicker(slot)
	pickerBody:ClearAllChildren()
	pickerTitle.Text = "PICK YOUR " .. slot.label .. (slot.id ~= slot.label and (" (" .. slot.id .. ")") or "")
	if pickerRemoveConn then
		pickerRemoveConn:Disconnect()
	end
	pickerRemove.Visible = state.lineup[slot.id] ~= nil
	pickerRemoveConn = pickerRemove.Activated:Connect(function()
		setSlot(slot.id, nil)
	end)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(140, 210), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = pickerBody
	local options = {}
	for _, entry in state.cards do
		local d = CardData.Describe(entry.id)
		if d and d.card.pos == slot.pos then
			table.insert(options, { entry = entry, d = d })
		end
	end
	table.sort(options, function(a, b)
		return a.d.card.ovr > b.d.card.ovr or (a.d.card.ovr == b.d.card.ovr and a.entry.uid < b.entry.uid)
	end)
	if #options == 0 then
		UI.text({ Text = "You don't have any " .. slot.pos .. " cards yet. Open packs to get some!", TextColor3 = C.Muted, Size = UDim2.fromOffset(600, 26), ZIndex = 42 }).Parent = pickerBody
	end
	for i, opt in options do
		local face = CardRenderer.Create(opt.d, { figure = false, shimmer = false })
		face.LayoutOrder = i
		face.ZIndex = 42
		local inSlot = lineupSlotOf(opt.entry.uid)
		-- how many other starters share his team (adding him makes it +1)
		local mates = 0
		for _, other in LineupConfig.Slots do
			if other.id ~= slot.id then
				local e = cardByUid(state.lineup[other.id])
				local c = e and CardData.Get(e.id)
				if c and c.team == opt.d.card.team and c.pid ~= opt.d.card.pid then
					mates += 1
				end
			end
		end
		if mates >= 1 and not inSlot then
			local boost = LineupConfig.ChemBoost(mates + 1)
			UI.chip(("%s x%d%s"):format(opt.d.card.team, mates + 1, boost > 0 and (" +" .. boost .. " CHEM") or ""), boost > 0 and C.Accent or C.Panel2, { TextColor3 = boost > 0 and C.BG or C.Text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -4), ZIndex = 60 }).Parent = face
		end
		if inSlot then
			UI.chip(inSlot == slot.id and "IN THIS SLOT" or ("STARTING: " .. inSlot), inSlot == slot.id and C.Accent or C.Gold, { TextColor3 = C.BG, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), ZIndex = 60 }).Parent = face
		end
		local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 61 })
		hit.Activated:Connect(function()
			if inSlot ~= slot.id then
				setSlot(slot.id, opt.entry.uid)
			end
		end)
		hit.Parent = face
		face.Parent = pickerBody
	end
	picker.Visible = true
	UI.pop(picker, 0.2)
end

function renderLineup()
	CardData.Ensure()
	lineupBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = lineupBody
	local ratings = teamRatings()

	local header = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1, ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	header.Parent = lineupBody
	local function stat(name, value, order, color)
		UI.glass({ Size = UDim2.fromOffset(104, 54), LayoutOrder = order, ZIndex = 12 }, {
			UI.text({ Text = tostring(value), FontFace = F.Heavy, TextColor3 = color, Size = UDim2.new(0.55, 0, 0.75, 0), Position = UDim2.fromScale(0.06, 0.12), ZIndex = 13 }),
			UI.text({ Text = name, FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 12, Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.fromScale(0.6, 0), ZIndex = 13 }),
		}).Parent = header
	end
	stat("TEAM", ratings.ovr, 1, C.Accent)
	stat("OFF", ratings.off, 2, C.Blue)
	stat("DEF", ratings.def, 3, C.Red)
	UI.text({ Text = ("%d/%d"):format(ratings.filled, ratings.total), FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 16, Size = UDim2.fromOffset(60, 20), LayoutOrder = 4, ZIndex = 12 }).Parent = header
	for i, side in { "Offense", "Defense" } do
		UI.button({ kind = side == lineupSide and (side == "Offense" and "blue" or "danger") or "dark", text = string.upper(side), size = UDim2.fromOffset(124, 44), order = 4 + i, textSize = 15, z = 12 }, function()
			lineupSide = side
			renderLineup()
		end).Parent = header
	end
	UI.button({ kind = "gold", text = "AUTO-FILL", icon = "lineup", size = UDim2.fromOffset(150, 44), order = 8, textSize = 15, z = 12 }, function()
		local res = Remotes.AutoFillLineup:InvokeServer()
		if res.ok then
			toast("Lineup filled with your best cards", C.Gold)
		end
	end).Parent = header

	-- team chemistry: 3+ starters from one team boost each other
	local chemRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2, ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	chemRow.Parent = lineupBody
	UI.text({ Text = "CHEMISTRY", FontFace = F.Display, TextColor3 = C.Accent, TextScaled = false, TextSize = 20, Size = UDim2.fromOffset(104, 26), LayoutOrder = 0, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }).Parent = chemRow
	local shown = 0
	for i, g in ratings.chem.groups do
		local team = CardData.Team(g.team) or {}
		local color = team.primary and Color3.fromHex(team.primary) or C.Panel2
		local label = ("%s x%d%s"):format(g.team, g.count, g.boost > 0 and ("  +" .. g.boost) or "")
		UI.chip(label, g.boost > 0 and color or C.Panel2, { TextColor3 = Color3.new(1, 1, 1), LayoutOrder = i, ZIndex = 12 }).Parent = chemRow
		shown += 1
	end
	UI.text({
		Text = shown == 0 and "Start 3+ players from the same team: +1 to their ratings at 3, +2 at 5, +3 at 7" or "+1 at 3 from a team, +2 at 5, +3 at 7",
		FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.fromOffset(520, 20), LayoutOrder = 99, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
	}).Parent = chemRow

	-- field with mowed stripes
	local field = new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 120, 56), Size = UDim2.new(1, 0, 0, 480), LayoutOrder = 3, ZIndex = 12, ClipsDescendants = true }, { UI.corner(14), UI.stroke(Color3.fromRGB(240, 240, 240), 2, 0.4) })
	field.Parent = lineupBody
	for i = 0, 9 do
		new("Frame", { BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(48, 136, 64) or Color3.fromRGB(40, 120, 56), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.1, 0), Position = UDim2.fromScale(0, i / 10), ZIndex = 12 }).Parent = field
		new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, i / 10), ZIndex = 13 }).Parent = field
	end
	new("Frame", { BackgroundColor3 = C.Blue, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromScale(0, 0.05), ZIndex = 13 }).Parent = field
	UI.text({ Text = string.upper(lineupSide) .. "  -  TAP A SPOT TO CHANGE THE PLAYER", FontFace = F.Heavy, TextColor3 = Color3.fromRGB(220, 255, 230), TextTransparency = 0.25, TextScaled = false, TextSize = 13, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -24), ZIndex = 13 }).Parent = field

	for _, slot in LineupConfig.Slots do
		if slot.side == lineupSide then
			local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(slot.x, slot.y), Size = UDim2.fromScale(0.15, 0.44), ZIndex = 14 }, { new("UIAspectRatioConstraint", { AspectRatio = 2 / 3 }) })
			local entry = cardByUid(state.lineup[slot.id])
			local d = entry and CardData.Describe(entry.id)
			if d then
				local face = CardRenderer.Create(d)
				face.Size = UDim2.fromScale(1, 1)
				face.ZIndex = 15
				face.Parent = holder
				local boost = ratings.chem.boost[slot.id] or 0
				if boost > 0 then
					UI.chip(("+%d CHEM"):format(boost), C.Accent, { TextColor3 = C.BG, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 2), ZIndex = 25 }).Parent = holder
				end
			else
				new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), ZIndex = 15 }, {
					UI.corner(12),
					UI.stroke(Color3.new(1, 1, 1), 2, 0.4),
					UI.text({ Text = "+", FontFace = F.Heavy, Size = UDim2.fromScale(0.5, 0.3), Position = UDim2.fromScale(0.25, 0.25), ZIndex = 16 }),
					UI.text({ Text = slot.label, FontFace = F.Heavy, TextColor3 = C.Muted, Size = UDim2.fromScale(0.6, 0.14), Position = UDim2.fromScale(0.2, 0.62), ZIndex = 16 }),
				}).Parent = holder
			end
			local hit = new("TextButton", { Name = "Slot_" .. slot.id, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 30 })
			hit.Activated:Connect(function()
				openPicker(slot)
			end)
			hit.Parent = holder
			holder.Parent = field
		end
	end
end

-- =========================================================================================
-- Hub: featured promo carousel (left) + your top card showcase (right)
-- =========================================================================================
local featured = UI.glass({ Name = "Featured", Position = UDim2.fromOffset(16, 162), Size = UDim2.fromOffset(500, 230), ClipsDescendants = true })
featured.Parent = hud
table.insert(hubOnly, featured)

-- the promo can be closed; a small OFFERS button brings it back
local offersPill = UI.button({ kind = "purple", text = "OFFERS", icon = "packs", size = UDim2.fromOffset(140, 42), position = UDim2.fromOffset(16, 162), textSize = 16 })
offersPill.Visible = false
offersPill:SetAttribute("Dismissed", true)
offersPill.Parent = hud
table.insert(hubOnly, offersPill)
local closePromo = UI.button({ kind = "dark", icon = "close", size = UDim2.fromOffset(34, 34), anchor = Vector2.new(1, 0), position = UDim2.new(1, -10, 0, 10), z = 30, padding = 6 }, function()
	featured:SetAttribute("Dismissed", true)
	local t = TweenService:Create(featured, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(-520, 162) })
	t:Play()
	t.Completed:Wait()
	featured.Visible = false
	featured.Position = UDim2.fromOffset(16, 162)
	offersPill:SetAttribute("Dismissed", nil)
	offersPill.Visible = true
	UI.pop(offersPill, 0.25)
end)
closePromo.Parent = featured
offersPill.Activated:Connect(function()
	offersPill:SetAttribute("Dismissed", true)
	offersPill.Visible = false
	featured:SetAttribute("Dismissed", nil)
	featured.Visible = true
	UI.pop(featured, 0.25)
end)
local slideHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
slideHolder.Parent = featured
local dots = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(120, 10), ZIndex = 20 }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }),
})
dots.Parent = featured

local function tierOddsText(packId)
	local o = PackConfig.ById[packId].odds
	return ("ICON %s%%  -  ELITE %s%%  -  EPIC %s%%"):format(o.Icon, o.Elite, o.Epic)
end

-- The newest Week Standout cards (made from last week's real top performers)
local function latestStandouts()
	CardData.Ensure()
	local week, list = 0, {}
	for _, c in CardData.All() do
		if c.program == "Week Standout" and c.week > week then
			week = c.week
		end
	end
	for _, c in CardData.All() do
		if c.program == "Week Standout" and c.week == week then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		return a.ovr > b.ovr or (a.ovr == b.ovr and a.id < b.id)
	end)
	return week, list
end

local slides = {
	{
		kicker = "NEW THIS WEEK",
		title = function()
			local week = latestStandouts()
			return ("WEEK %d STANDOUTS"):format(week)
		end,
		sub = function()
			local _, list = latestStandouts()
			return ("%d NEW CARDS IN PACKS  -  UP TO %d OVR"):format(#list, list[1] and list[1].ovr or 0)
		end,
		detail = function()
			local _, list = latestStandouts()
			local names = {}
			for i = 1, math.min(2, #list) do
				local d = CardData.Describe(list[i].id)
				if d then
					table.insert(names, ("%s %s %d"):format(d.card.pos, string.upper(d.last), d.card.ovr))
				end
			end
			return "TOP CARDS:  " .. table.concat(names, "  -  ")
		end,
		c1 = Color3.fromRGB(255, 170, 30), c2 = Color3.fromRGB(90, 20, 60), art = "standout",
		button = function() return "OPEN PACKS", "primary" end,
		action = function() openStore("PACKS") end,
	},
	{
		kicker = "FEATURED PACK", title = "THE DYNASTY PACK", sub = "10 CARDS  -  GUARANTEED ELITE OR BETTER",
		detail = function() return tierOddsText("dynasty") end,
		c1 = Color3.fromRGB(20, 160, 90), c2 = Color3.fromRGB(8, 40, 30), art = "pack", tint = Color3.fromRGB(46, 255, 140),
		button = function() return "SHOP NOW", "primary" end,
		action = function() openStore("PACKS") end,
	},
	{
		kicker = "BEST VALUE", title = "55,000 COINS", sub = "+43% BONUS  -  OPEN 22 STARTER PACKS",
		detail = function() return "COINS ALSO COME FROM WINS, DAILY LOGINS AND QUICK-SELLS" end,
		c1 = Color3.fromRGB(230, 150, 20), c2 = Color3.fromRGB(70, 40, 6), art = "coins",
		button = function() return "R$ 499", "gold" end,
		action = function()
			local res = Remotes.PromptCoins:InvokeServer("coins_4")
			if not res.ok then
				toast(res.err, C.Gold)
			end
		end,
	},
	{
		kicker = "VIP PASS", title = "DOUBLE EVERY COIN", sub = "2X GAME REWARDS + 2X DAILY BONUS  -  FOREVER",
		detail = function() return "ONE-TIME PURCHASE" end,
		c1 = Color3.fromRGB(200, 60, 200), c2 = Color3.fromRGB(40, 10, 60), art = "trophy",
		button = function()
			if state.store and state.store.vip then
				return "OWNED", "disabled"
			end
			return "R$ " .. StoreConfig.VIP.price, "purple"
		end,
		action = function() openStore("VIP") end,
	},
	{
		kicker = "EVERY 22 HOURS", title = "FREE DAILY PACK", sub = "3 CARDS ON THE HOUSE",
		detail = function()
			local wait = state.shop and (state.shop.freePackReadyAt or 0) - os.time() or 0
			return wait > 0 and ("NEXT ONE IN " .. fmtDuration(wait)) or "READY NOW!"
		end,
		c1 = Color3.fromRGB(40, 120, 255), c2 = Color3.fromRGB(10, 20, 60), art = "pack", tint = Color3.fromRGB(120, 130, 145),
		button = function()
			local ready = state.shop and os.time() >= (state.shop.freePackReadyAt or math.huge)
			return ready and "OPEN FREE" or "VIEW PACKS", ready and "primary" or "dark"
		end,
		action = function()
			local ready = state.shop and os.time() >= (state.shop.freePackReadyAt or math.huge)
			if ready then
				buyPack(PackConfig.ById.daily)
			else
				openStore("PACKS")
			end
		end,
	},
}

local slideIndex = 0
local slideButton, slideDetail
local function showSlide(i)
	slideIndex = i
	local s = slides[i]
	local function val(x)
		if type(x) == "function" then
			return x()
		end
		return x
	end
	slideHolder:ClearAllChildren()
	local bg = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { UI.corner(14) })
	UI.flowGradient(bg, s.c1, s.c2, s.c1)
	bg.Parent = slideHolder
	-- art on the right
	local artHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 210), Position = UDim2.new(1, -182, 0, 10), ZIndex = 3 })
	artHolder.Parent = slideHolder
	if s.art == "pack" then
		new("ImageLabel", { BackgroundTransparency = 1, Image = Assets.pack, ImageColor3 = s.tint, Size = UDim2.fromOffset(136, 197), Position = UDim2.fromOffset(18, 6), Rotation = 8, ZIndex = 4 }).Parent = artHolder
	elseif s.art == "standout" then
		local _, list = latestStandouts()
		local d = list[1] and CardData.Describe(list[1].id)
		if d then
			local face = CardRenderer.Create(d)
			face.Size = UDim2.fromOffset(120, 180)
			face.Position = UDim2.fromOffset(16, 34)
			face.Rotation = 6
			face.ZIndex = 4
			face.Parent = artHolder
		end
	elseif s.art == "coins" then
		coinStack(artHolder, 7, 64)
	else
		UI.icon("trophy", { Size = UDim2.fromOffset(140, 140), Position = UDim2.fromOffset(15, 30), ImageColor3 = C.Gold, ZIndex = 4 }).Parent = artHolder
	end
	-- copy on the left
	local copy = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -200, 1, -20), Position = UDim2.fromOffset(18, 14), ZIndex = 5 })
	copy.Parent = slideHolder
	UI.chip(s.kicker, Color3.new(0, 0, 0), { BackgroundTransparency = 0.4, TextColor3 = Color3.new(1, 1, 1), ZIndex = 6 }).Parent = copy
	UI.text({ Text = val(s.title), FontFace = F.Display, TextScaled = false, TextSize = 40, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }).Parent = copy
	UI.text({ Text = val(s.sub), FontFace = F.Display, TextColor3 = Color3.fromRGB(235, 240, 250), TextScaled = false, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 74), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }).Parent = copy
	slideDetail = UI.text({ Text = s.detail(), FontFace = F.Bold, TextColor3 = Color3.fromRGB(220, 225, 235), TextTransparency = 0.15, TextScaled = false, TextSize = 12, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 98), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 })
	slideDetail.Parent = copy
	local label, kind = s.button()
	slideButton = UI.button({ kind = kind, text = label, size = UDim2.fromOffset(180, 50), position = UDim2.fromOffset(0, 140), textSize = 20, font = label:find("R%$") and F.Number or F.Display, z = 7 }, s.action)
	slideButton.Parent = copy
	UI.shine(slideButton, 2.8)
	-- slide-in motion
	copy.Position = UDim2.fromOffset(48, 14)
	TweenService:Create(copy, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { Position = UDim2.fromOffset(18, 14) }):Play()
	artHolder.Position = UDim2.new(1, -140, 0, 10)
	TweenService:Create(artHolder, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.new(1, -182, 0, 10) }):Play()
	-- dots
	dots:ClearAllChildren()
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }).Parent = dots
	for k = 1, #slides do
		local d = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = k == i and 0 or 0.6, Size = UDim2.fromOffset(k == i and 22 or 8, 8), ZIndex = 21 }, { UI.corner(4) })
		d.Activated:Connect(function()
			showSlide(k)
		end)
		d.Parent = dots
	end
end

task.spawn(function()
	while true do
		showSlide(slideIndex % #slides + 1)
		for _ = 1, 6 do
			task.wait(1)
			if slideDetail and slideDetail.Parent then
				slideDetail.Text = slides[slideIndex].detail()
			end
		end
	end
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("CardData")
	local shownWeek = latestStandouts()
	folder:GetAttributeChangedSignal("Version"):Connect(function()
		task.wait(1) -- let the new data finish replicating
		local week = latestStandouts()
		if week > shownWeek then
			shownWeek = week
			toast(("WEEK %d STANDOUTS JUST DROPPED - new cards are in packs"):format(week), C.Gold)
			if featured.Visible then
				showSlide(1)
			end
		end
	end)
end)

-- your top card, floating on the right
local showcase = new("Frame", { Name = "Showcase", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 150), Size = UDim2.fromOffset(220, 360) })
showcase.Parent = hud
table.insert(hubOnly, showcase)
local showcaseLabel = UI.chip("YOUR TOP CARD", C.Accent, { TextColor3 = C.BG, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), ZIndex = 5 })
showcaseLabel.Parent = showcase
local showcaseCard = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 315), Position = UDim2.fromOffset(5, 32) })
showcaseCard.Parent = showcase
TweenService:Create(showcaseCard, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(5, 20), Rotation = 2 }):Play()
local showcaseId = nil
local function updateShowcase()
	local best
	for _, entry in state.cards do
		local c = CardData.Get(entry.id)
		if c and (not best or c.ovr > best.ovr) then
			best = c
		end
	end
	if not best or best.id == showcaseId then
		return
	end
	showcaseId = best.id
	showcaseCard:ClearAllChildren()
	local face = CardRenderer.Create(CardData.Describe(best.id))
	face.Size = UDim2.fromScale(1, 1)
	face.Parent = showcaseCard
	local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 30 })
	hit.Activated:Connect(function()
		openPanel(collectionPanel)
		renderCollection()
	end)
	hit.Parent = face
end

local function fitHub()
	local w = gui.AbsoluteSize.X
	featured.Size = UDim2.fromOffset(math.min(500, w - 32), 230)
	local cw = hud:FindFirstChild("ChallengeWidget")
	if cw then
		-- short screens: collapse to the header row so it never covers the dock
		local dockTop = gui.AbsoluteSize.Y - 18 - 110 * dock.Fit.Scale
		local full = cw.Position.Y.Offset + 182 + 12 <= dockTop
		cw.ClipsDescendants = not full
		cw.Size = UDim2.fromOffset(math.min(500, w - 32), full and 182 or 46)
	end
	showcase.Visible = w >= 980 and not backdrop.Visible
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHub)

-- =========================================================================================
-- Daily reward + purchase celebrations
-- =========================================================================================
local function coinBurst(count)
	Sounds.Play("coins")
	local center = gui.AbsoluteSize / 2
	local target = coinIcon.AbsolutePosition - gui.AbsolutePosition + coinIcon.AbsoluteSize / 2
	for k = 1, count do
		local c = UI.icon("coin", { Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X + math.random(-120, 120), center.Y + math.random(-80, 80)), ImageColor3 = C.Gold, ZIndex = 90 })
		c.Parent = gui
		task.delay(0.15 + k * 0.04, function()
			local t = TweenService:Create(c, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(20, 20) })
			t:Play()
			t.Completed:Wait()
			c:Destroy()
			UI.pop(coinPill, 0.15)
		end)
	end
end

local dailyModal = UI.glass({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 340), ZIndex = 80 })
dailyModal.Parent = gui
local function showDaily(info)
	dailyModal:ClearAllChildren()
	UI.corner(14).Parent = dailyModal
	UI.stroke(C.Gold, 2).Parent = dailyModal
	local top = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 96), ZIndex = 80 }, { UI.corner(14) })
	UI.flowGradient(top, Color3.fromRGB(255, 190, 40), Color3.fromRGB(255, 110, 30), Color3.fromRGB(255, 190, 40))
	top.Parent = dailyModal
	UI.text({ Text = "DAILY REWARD", FontFace = F.Display, TextScaled = false, TextSize = 40, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 12), ZIndex = 81 }).Parent = dailyModal
	UI.text({ Text = ("DAY %d STREAK  -  COME BACK TOMORROW FOR MORE"):format(info.streak), FontFace = F.Display, TextColor3 = Color3.fromRGB(60, 30, 0), TextScaled = false, TextSize = 15, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 62), ZIndex = 81 }).Parent = dailyModal
	local track = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 112), ZIndex = 81 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }),
	})
	for d = 1, info.maxStreak do
		local done = d <= info.streak
		local amount = StoreConfig.DailyAmount(d, state.store and state.store.vip)
		local box = new("Frame", { BackgroundColor3 = d == math.min(info.streak, info.maxStreak) and C.Gold or (done and Color3.fromRGB(70, 60, 30) or C.Panel2), Size = UDim2.fromOffset(60, 68), ZIndex = 81 }, { UI.corner(10) })
		UI.text({ Text = "DAY " .. d, FontFace = F.Display, TextColor3 = done and C.BG or C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 6), ZIndex = 82 }).Parent = box
		UI.text({ Text = tostring(amount), FontFace = F.Number, TextColor3 = done and C.BG or C.Text, TextScaled = false, TextSize = 18, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 30), ZIndex = 82 }).Parent = box
		box.Parent = track
	end
	track.Parent = dailyModal
	local amountLabel = UI.text({ Text = "+0", FontFace = F.Number, TextColor3 = C.Gold, TextScaled = false, TextSize = 40, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 196), ZIndex = 81 })
	amountLabel.Parent = dailyModal
	UI.countTo(amountLabel, 0, info.coins, function(v)
		return "+" .. UI.commas(v) .. " COINS"
	end)
	UI.button({ kind = "gold", text = "COLLECT", size = UDim2.fromOffset(220, 52), anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 262), textSize = 22, z = 81 }, function()
		dailyModal.Visible = false
		coinBurst(10)
	end).Parent = dailyModal
	dailyModal.Visible = true
	UI.pop(dailyModal, 0.35)
end
Remotes:WaitForChild("DailyReward").OnClientEvent:Connect(showDaily)

Remotes:WaitForChild("CoinsPurchased").OnClientEvent:Connect(function(info)
	if info.vip then
		vipChip.Visible = true
		if state.store then
			state.store.vip = true
		end
		toast("VIP unlocked! Your Coin rewards are now doubled.", C.Gold)
		return
	end
	coinBurst(14)
	toast(("+%s Coins added!"):format(UI.commas(info.coins)), C.Gold)
end)

-- =========================================================================================
-- Challenges (daily + weekly) and leaderboards
-- =========================================================================================
local challengeState -- snapshot from the server
local renderChallenges, renderLeaderboard -- panels (below)

local function claimChallenge(kind, id)
	local res = Remotes.ClaimChallenge:InvokeServer(kind, id)
	if not res or not res.ok then
		toast(res and res.err or "Couldn't claim", C.Red)
		return
	end
	if res.given and res.given.coins then
		coinBurst(8)
		toast(("+%s Coins"):format(UI.commas(res.given.coins)), C.Gold)
	end
	-- pack rewards open with the normal reveal (PackOpened)
end

local function rewardChip(reward, z)
	local isPack = reward.pack ~= nil
	return UI.chip(isPack and (string.upper(reward.pack) .. " PACK") or ("+" .. UI.commas(reward.coins)), isPack and C.Purple or C.Gold, { TextColor3 = isPack and C.Text or C.BG, ZIndex = z })
end

-- hub widget: today's three challenges under the promo carousel
local challengeWidget = UI.glass({ Name = "ChallengeWidget", Position = UDim2.fromOffset(16, 404), Size = UDim2.fromOffset(500, 182) })
challengeWidget.Parent = hud
table.insert(hubOnly, challengeWidget)
local function placeWidget()
	challengeWidget.Position = UDim2.fromOffset(16, featured:GetAttribute("Dismissed") and 214 or 404)
	fitHub()
end
featured:GetAttributeChangedSignal("Dismissed"):Connect(placeWidget)

local function renderWidget()
	challengeWidget:ClearAllChildren()
	UI.corner(14).Parent = challengeWidget
	UI.stroke(C.Stroke, 1).Parent = challengeWidget
	local snap = challengeState
	UI.text({ Text = "DAILY CHALLENGES", FontFace = F.Display, TextScaled = false, TextSize = 22, Size = UDim2.fromOffset(220, 26), Position = UDim2.fromOffset(16, 10), TextXAlignment = Enum.TextXAlignment.Left }).Parent = challengeWidget
	local timer = UI.text({ Name = "Timer", Text = "", FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 12, Size = UDim2.fromOffset(140, 16), Position = UDim2.fromOffset(196, 16), TextXAlignment = Enum.TextXAlignment.Left })
	timer.Parent = challengeWidget
	UI.button({ kind = "dark", text = "ALL", size = UDim2.fromOffset(64, 30), position = UDim2.new(1, -150, 0, 8), textSize = 13 }, function()
		openPanel(challengesPanel)
		renderChallenges()
	end).Parent = challengeWidget
	UI.button({ kind = "gold", icon = "trophy", text = "RANKS", size = UDim2.fromOffset(78, 30), position = UDim2.new(1, -82, 0, 8), textSize = 13 }, function()
		openPanel(leaderboardPanel)
		renderLeaderboard()
	end).Parent = challengeWidget
	if not snap then
		return
	end
	timer.Text = "RESETS IN " .. fmtDuration(math.max(0, snap.daily.endsAt - os.time()))
	for i, ch in snap.daily.list do
		local y = 46 + (i - 1) * 43
		local row = new("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = ch.claimed and 0.6 or 0.2, Size = UDim2.new(1, -24, 0, 38), Position = UDim2.fromOffset(12, y) }, { UI.corner(8) })
		UI.text({ Text = ch.text, FontFace = F.Bold, TextColor3 = ch.claimed and C.Muted or C.Text, TextScaled = false, TextSize = 14, Size = UDim2.new(1, -190, 0, 18), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = row
		local track = new("Frame", { BackgroundColor3 = C.BG, Size = UDim2.new(1, -190, 0, 5), Position = UDim2.fromOffset(10, 26) }, { UI.corner(3) })
		new("Frame", { BackgroundColor3 = ch.complete and C.Accent or C.Blue, Size = UDim2.fromScale(math.max(0.02, ch.progress / ch.target), 1) }, { UI.corner(3) }).Parent = track
		track.Parent = row
		local reward = rewardChip(ch.reward, 2)
		reward.AnchorPoint = Vector2.new(1, 0.5)
		reward.Position = UDim2.new(1, -96, 0.5, 0)
		reward.Parent = row
		if ch.claimed then
			UI.text({ Text = "CLAIMED", FontFace = F.Heavy, TextColor3 = C.Accent, TextScaled = false, TextSize = 12, Size = UDim2.fromOffset(80, 18), Position = UDim2.new(1, -88, 0.5, -9) }).Parent = row
		elseif ch.complete then
			local b = UI.button({ kind = "primary", text = "CLAIM", size = UDim2.fromOffset(80, 30), position = UDim2.new(1, -86, 0.5, -15), textSize = 14 }, function()
				claimChallenge("challenge", ch.id)
			end)
			b.Parent = row
			UI.shine(b, 2)
		else
			UI.text({ Text = ("%s / %s"):format(UI.commas(ch.progress), UI.commas(ch.target)), FontFace = F.Number, TextColor3 = C.Muted, TextScaled = false, TextSize = 15, Size = UDim2.fromOffset(80, 18), Position = UDim2.new(1, -88, 0.5, -9) }).Parent = row
		end
		row.Parent = challengeWidget
	end
end

-- full panel: daily + weekly + bonus packs
function renderChallenges()
	challengesBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = challengesBody
	local snap = challengeState
	if not snap then
		UI.text({ Text = "Loading...", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 30), ZIndex = 12 }).Parent = challengesBody
		return
	end
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	for _, set in { { key = "daily", title = "DAILY CHALLENGES", bonusKind = "dailyBonus", color = C.Accent }, { key = "weekly", title = "WEEKLY CHALLENGES", bonusKind = "weeklyBonus", color = C.Gold } } do
		local data = snap[set.key]
		local head = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 40), LayoutOrder = nextOrder(), ZIndex = 12 })
		UI.text({ Text = set.title, FontFace = F.Display, TextColor3 = set.color, TextScaled = false, TextSize = 28, Size = UDim2.fromOffset(360, 34), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }).Parent = head
		UI.text({ Text = "RESETS IN " .. fmtDuration(math.max(0, data.endsAt - os.time())), FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(240, 20), Position = UDim2.new(1, -244, 0, 12), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12 }).Parent = head
		head.Parent = challengesBody
		for _, ch in data.list do
			local row = new("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = ch.claimed and 0.6 or 0.15, Size = UDim2.new(1, -10, 0, 62), LayoutOrder = nextOrder(), ZIndex = 12 }, { UI.corner(10), UI.stroke(ch.complete and not ch.claimed and C.Accent or C.Stroke, 1) })
			UI.text({ Text = ch.text, FontFace = F.Bold, TextColor3 = ch.claimed and C.Muted or C.Text, TextScaled = false, TextSize = 18, Size = UDim2.new(1, -330, 0, 24), Position = UDim2.fromOffset(16, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }).Parent = row
			local track = new("Frame", { BackgroundColor3 = C.BG, Size = UDim2.new(1, -330, 0, 8), Position = UDim2.fromOffset(16, 40), ZIndex = 13 }, { UI.corner(4) })
			new("Frame", { BackgroundColor3 = ch.complete and C.Accent or C.Blue, Size = UDim2.fromScale(math.max(0.02, ch.progress / ch.target), 1), ZIndex = 14 }, { UI.corner(4) }).Parent = track
			track.Parent = row
			UI.text({ Text = ("%s / %s"):format(UI.commas(ch.progress), UI.commas(ch.target)), FontFace = F.Number, TextColor3 = C.Muted, TextScaled = false, TextSize = 18, Size = UDim2.fromOffset(110, 22), Position = UDim2.new(1, -306, 0.5, -11), ZIndex = 13 }).Parent = row
			local reward = rewardChip(ch.reward, 13)
			reward.AnchorPoint = Vector2.new(1, 0.5)
			reward.Position = UDim2.new(1, -130, 0.5, 0)
			reward.Parent = row
			if ch.claimed then
				UI.text({ Text = "CLAIMED", FontFace = F.Heavy, TextColor3 = C.Accent, TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(106, 20), Position = UDim2.new(1, -116, 0.5, -10), ZIndex = 13 }).Parent = row
			else
				UI.button({ kind = ch.complete and "primary" or "disabled", text = "CLAIM", size = UDim2.fromOffset(106, 40), position = UDim2.new(1, -116, 0.5, -20), textSize = 16, z = 13 }, function()
					if ch.complete then
						claimChallenge("challenge", ch.id)
					end
				end).Parent = row
			end
			row.Parent = challengesBody
		end
		-- bonus for finishing the whole set
		local bonus = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -10, 0, 56), LayoutOrder = nextOrder(), ZIndex = 12 }, { UI.corner(10) })
		UI.flowGradient(bonus, set.color:Lerp(C.BG, 0.55), C.Panel2, set.color:Lerp(C.BG, 0.7))
		UI.text({ Text = ("CLAIM ALL 3 FOR A FREE %s PACK"):format(string.upper(data.bonus.pack)), FontFace = F.Display, TextScaled = false, TextSize = 20, Size = UDim2.new(1, -160, 1, 0), Position = UDim2.fromOffset(16, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }).Parent = bonus
		if data.bonusClaimed then
			UI.text({ Text = "CLAIMED", FontFace = F.Heavy, TextColor3 = C.Accent, TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(106, 20), Position = UDim2.new(1, -116, 0.5, -10), ZIndex = 13 }).Parent = bonus
		else
			UI.button({ kind = data.bonusReady and "gold" or "disabled", icon = "packs", text = "OPEN", size = UDim2.fromOffset(106, 40), position = UDim2.new(1, -116, 0.5, -20), textSize = 16, z = 13 }, function()
				if data.bonusReady then
					claimChallenge(set.bonusKind)
				end
			end).Parent = bonus
		end
		bonus.Parent = challengesBody
	end
end

local function applyChallenges(snap)
	if not snap then
		return
	end
	if snap.completed then
		for _, text in snap.completed do
			toast("CHALLENGE COMPLETE: " .. text .. "  -  claim your reward!", C.Accent)
		end
		Sounds.Play("cheer", 0.4)
		return
	end
	challengeState = snap
	local ready = 0
	for _, set in { snap.daily, snap.weekly } do
		for _, ch in set.list do
			ready += (ch.complete and not ch.claimed) and 1 or 0
		end
		ready += set.bonusReady and 1 or 0
	end
	challengeWidget:SetAttribute("Ready", ready)
	renderWidget()
	if challengesPanel.Visible then
		renderChallenges()
	end
end
Remotes:WaitForChild("ChallengesChanged").OnClientEvent:Connect(applyChallenges)
task.spawn(function()
	applyChallenges(Remotes:WaitForChild("GetChallenges"):InvokeServer())
	while true do -- keep the reset timers ticking
		task.wait(30)
		if challengeState then
			local t = challengeWidget:FindFirstChild("Timer")
			if t then
				t.Text = "RESETS IN " .. fmtDuration(math.max(0, challengeState.daily.endsAt - os.time()))
			end
			if challengeState.daily.endsAt <= os.time() then
				applyChallenges(Remotes.GetChallenges:InvokeServer()) -- new day
			end
		end
	end
end)
renderWidget()
placeWidget()

-- leaderboard panel
local leaderboardTab = "week"
function renderLeaderboard()
	leaderboardBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = leaderboardBody
	local tabs = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 0, ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
	})
	for _, t in { { "week", "THIS WEEK" }, { "allTime", "ALL TIME" } } do
		UI.button({ kind = leaderboardTab == t[1] and "gold" or "dark", text = t[2], size = UDim2.fromOffset(150, 40), textSize = 16, z = 12 }, function()
			leaderboardTab = t[1]
			renderLeaderboard()
		end).Parent = tabs
	end
	tabs.Parent = leaderboardBody
	local data = Remotes.GetLeaderboard:InvokeServer() or {}
	local rows = data[leaderboardTab] or {}
	if #rows == 0 then
		UI.text({ Text = "No wins yet " .. (leaderboardTab == "week" and "this week" or "") .. " - win a game to claim the top spot!", FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 16, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, ZIndex = 12 }).Parent = leaderboardBody
	end
	local medal = { C.Gold, Color3.fromRGB(200, 205, 215), Color3.fromRGB(205, 127, 70) }
	for i, r in rows do
		local me = r.userId == player.UserId
		local row = new("Frame", { BackgroundColor3 = me and Color3.fromRGB(20, 70, 50) or C.Panel2, BackgroundTransparency = 0.15, Size = UDim2.new(1, -10, 0, 48), LayoutOrder = i, ZIndex = 12 }, { UI.corner(10), UI.stroke(me and C.Accent or (medal[i] or C.Stroke), me and 2 or 1, medal[i] and 0.3 or 0) })
		UI.text({ Text = tostring(r.rank), FontFace = F.Number, TextColor3 = medal[i] or C.Muted, TextScaled = false, TextSize = 26, Size = UDim2.fromOffset(50, 48), ZIndex = 13 }).Parent = row
		UI.text({ Text = string.upper(r.name) .. (me and "  (YOU)" or ""), FontFace = F.Display, TextScaled = false, TextSize = 22, Size = UDim2.new(1, -220, 1, 0), Position = UDim2.fromOffset(60, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13 }).Parent = row
		UI.text({ Text = UI.commas(r.wins) .. " W", FontFace = F.Number, TextColor3 = C.Accent, TextScaled = false, TextSize = 24, Size = UDim2.fromOffset(140, 48), Position = UDim2.new(1, -150, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 13 }).Parent = row
		row.Parent = leaderboardBody
	end
	local foot = leaderboardTab == "week" and ("RESETS IN " .. fmtDuration(math.max(0, (data.weekEndsAt or os.time()) - os.time())) .. "  -  UPDATES EVERY 2 MINUTES")
		or ("YOUR WINS: " .. UI.commas(state.stats.wins or 0) .. "  -  UPDATES EVERY 2 MINUTES")
	UI.text({ Text = foot, FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 100, ZIndex = 12 }).Parent = leaderboardBody
end

-- =========================================================================================
-- Difficulty picker (PLAY)
-- =========================================================================================
local diffModal = UI.glass({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(860, 400), ZIndex = 70 }, {
	new("UIScale", { Name = "Fit" }),
})
diffModal.Parent = gui

function openDifficulty()
	diffModal:ClearAllChildren()
	new("UIScale", { Name = "Fit", Scale = math.clamp((gui.AbsoluteSize.X - 24) / 880, 0.4, 1) }).Parent = diffModal
	UI.corner(14).Parent = diffModal
	UI.stroke(C.Accent, 2).Parent = diffModal
	UI.text({ Text = "CHOOSE DIFFICULTY", FontFace = F.Display, TextScaled = false, TextSize = 36, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 14), ZIndex = 71 }).Parent = diffModal
	local myOvr = teamRatings().ovr
	UI.text({ Text = ("YOUR TEAM: %d OVR  -  EVERY WIN COUNTS FOR JERSEYS AND THE LEADERBOARD"):format(myOvr), FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 60), ZIndex = 71 }).Parent = diffModal
	UI.button({ kind = "dark", icon = "close", size = UDim2.fromOffset(44, 40), position = UDim2.new(1, -58, 0, 12), z = 72 }, function()
		diffModal.Visible = false
	end).Parent = diffModal
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 290), Position = UDim2.fromOffset(20, 96), ZIndex = 71 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12) }),
	})
	row.Parent = diffModal
	local last = state.difficulty or MatchConfig.DefaultDifficulty
	for _, d in MatchConfig.Difficulties do
		local sel = d.id == last
		local card = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(193, 284), LayoutOrder = d.order, ZIndex = 71 }, {
			UI.corner(14),
			UI.stroke(d.color, sel and 3 or 1, sel and 0 or 0.4),
		})
		local top = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 86), ZIndex = 72 }, { UI.corner(14) })
		UI.flowGradient(top, d.color, d.color:Lerp(C.BG, 0.5), d.color)
		top.Parent = card
		UI.text({ Text = d.name, FontFace = F.Display, TextScaled = false, TextSize = 34, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10), ZIndex = 73 }).Parent = card
		UI.text({ Text = ("CPU ~%d OVR"):format(math.clamp(myOvr + d.ovr, 50, 97)), FontFace = F.Heavy, TextColor3 = C.BG, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 54), ZIndex = 73 }).Parent = card
		UI.text({ Text = d.desc, FontFace = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextScaled = false, TextSize = 14, Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 98), ZIndex = 72 }).Parent = card
		UI.text({ Text = "WIN", FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 12, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 148), ZIndex = 72 }).Parent = card
		local vipMult = (state.store and state.store.vip) and 2 or 1
		UI.text({ Text = "+" .. UI.commas(MatchConfig.RewardFor("Win", d.id) * vipMult), FontFace = F.Number, TextColor3 = C.Gold, TextScaled = false, TextSize = 30, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 164), ZIndex = 72 }).Parent = card
		UI.text({ Text = ("COINS  -  x%s"):format(tostring(d.reward)), FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 12, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 198), ZIndex = 72 }).Parent = card
		local go = UI.button({ kind = sel and "primary" or "dark", text = "PLAY", size = UDim2.new(1, -24, 0, 48), position = UDim2.new(0, 12, 1, -60), textSize = 20, z = 73 }, function()
			diffModal.Visible = false
			startMatch(d.id)
		end)
		go.Parent = card
		card.Activated:Connect(function()
			diffModal.Visible = false
			startMatch(d.id)
		end)
		card.Parent = row
	end
	diffModal.Visible = true
	UI.pop(diffModal, 0.25)
end

-- =========================================================================================
-- Play
-- =========================================================================================
local starting = false
function startMatch(difficultyId)
	if starting then
		return
	end
	starting = true
	closePanels()
	UI.setButton(playButton, "LOADING")
	local ok, res = pcall(function()
		return Remotes:WaitForChild("StartMatch"):InvokeServer(difficultyId)
	end)
	UI.setButton(playButton, "PLAY")
	starting = false
	if not ok or not res then
		res = { ok = false }
	end
	if not res.ok then
		toast(res.err or "Couldn't start a game", C.Red)
	end
end

-- =========================================================================================
-- Locker: team jerseys unlocked by wins
-- =========================================================================================
local lockerSelected -- jersey id shown in the big preview
local lockerAnim = {} -- { parts, jersey } for every animated figure on screen
local lockerConn

local function lockerWins()
	return state.stats.wins or 0
end

local function jerseyFigure(j)
	local vp, parts = CardRenderer.Figure(j.primary, j.secondary, j.material)
	if j.fx then
		table.insert(lockerAnim, { parts = parts, jersey = j })
	end
	return vp
end

local function fxLabel(j)
	return ({ shine = "SHINE", pulse = "GLOW", lava = "ANIMATED", galaxy = "ANIMATED", rainbow = "ANIMATED" })[j.fx]
end

function renderLocker()
	lockerBody:ClearAllChildren()
	table.clear(lockerAnim)
	local wins = lockerWins()
	local equipped = state.jersey or Jerseys.Default
	lockerSelected = lockerSelected or equipped
	local sel = Jerseys.Get(lockerSelected)
	local unlocked = Jerseys.IsUnlocked(sel.id, wins)

	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = lockerBody

	-- top: big preview + details + progress -------------------------------------------------
	local top = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 290), LayoutOrder = 1, ZIndex = 12 })
	top.Parent = lockerBody
	local stage = new("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(290, 290), ZIndex = 12 }, {
		UI.corner(14),
		UI.stroke(sel.fx and sel.secondary or sel.primary, 2, 0.3),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(sel.primary:Lerp(C.BG, 0.55), C.BG) }),
	})
	stage.Parent = top
	local big = jerseyFigure(sel)
	big.Size = UDim2.new(1, -10, 1, -10)
	big.Position = UDim2.fromOffset(5, 5)
	big.ZIndex = 13
	big.Parent = stage

	local x = 314
	UI.text({ Text = string.upper(sel.name), FontFace = F.Display, TextScaled = false, TextSize = 40, Size = UDim2.new(1, -x, 0, 44), Position = UDim2.fromOffset(x, 6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }).Parent = top
	local chips = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -x, 0, 24), Position = UDim2.fromOffset(x, 56), ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	chips.Parent = top
	if sel.id == equipped then
		UI.chip("EQUIPPED", C.Accent, { TextColor3 = C.BG, ZIndex = 12 }).Parent = chips
	elseif unlocked then
		UI.chip("UNLOCKED", C.Blue, { ZIndex = 12 }).Parent = chips
	else
		UI.chip("LOCKED", C.Red, { ZIndex = 12 }).Parent = chips
	end
	UI.chip(sel.wins == 0 and "STARTER" or (sel.wins .. " WINS"), C.Panel2, { ZIndex = 12 }).Parent = chips
	if sel.fx then
		UI.chip(fxLabel(sel), C.Purple, { ZIndex = 12 }).Parent = chips
	end
	local desc = unlocked and "Your whole team wears this in every game." or ("Win %d more game%s to unlock it."):format(sel.wins - wins, sel.wins - wins == 1 and "" or "s")
	UI.text({ Text = desc, FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 16, Size = UDim2.new(1, -x, 0, 22), Position = UDim2.fromOffset(x, 92), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }).Parent = top

	-- progress toward the next jersey
	local nextJ = Jerseys.Next(wins)
	local prevWins = 0
	for _, j in Jerseys.List do
		if j.wins <= wins then
			prevWins = math.max(prevWins, j.wins)
		end
	end
	local bar = new("Frame", { BackgroundColor3 = C.BG, Size = UDim2.new(1, -x - 10, 0, 14), Position = UDim2.fromOffset(x, 160), ZIndex = 12 }, { UI.corner(7) })
	bar.Parent = top
	local pct = nextJ and math.clamp((wins - prevWins) / math.max(1, nextJ.wins - prevWins), 0, 1) or 1
	pct = math.max(pct, 0.03) -- always show a sliver so the bar reads as a bar
	local fill = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0, 1), ZIndex = 13 }, { UI.corner(7) })
	UI.flowGradient(fill, C.Accent, C.Blue, C.Purple)
	fill.Parent = bar
	TweenService:Create(fill, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(pct, 1) }):Play()
	UI.text({
		Text = nextJ and ("%d WIN%s  -  %d MORE FOR %s"):format(wins, wins == 1 and "" or "S", nextJ.wins - wins, string.upper(nextJ.name)) or ("%d WINS  -  EVERY JERSEY UNLOCKED"):format(wins),
		FontFace = F.Heavy, TextColor3 = C.Text, TextScaled = false, TextSize = 14,
		Size = UDim2.new(1, -x, 0, 18), Position = UDim2.fromOffset(x, 136), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
	}).Parent = top

	local equipBtn
	if sel.id == equipped then
		equipBtn = UI.button({ kind = "dark", text = "EQUIPPED", size = UDim2.fromOffset(240, 56), position = UDim2.fromOffset(x, 214), textSize = 18, z = 12 }, function() end)
	elseif unlocked then
		equipBtn = UI.button({ kind = "primary", icon = "jersey", text = "EQUIP", size = UDim2.fromOffset(240, 56), position = UDim2.fromOffset(x, 214), textSize = 20, z = 12 }, function()
			local res = Remotes.SetJersey:InvokeServer(sel.id)
			if res and res.ok then
				state.jersey = res.jersey
				Sounds.Play("cardFlip")
				toast(sel.name .. " equipped", C.Accent)
				renderLocker()
			else
				toast(res and res.err or "Couldn't equip", C.Red)
			end
		end)
	else
		equipBtn = UI.button({ kind = "dark", text = ("LOCKED  -  %d WINS"):format(sel.wins), size = UDim2.fromOffset(240, 56), position = UDim2.fromOffset(x, 214), textSize = 16, z = 12 }, function()
			Sounds.Play("click", 0.6, 0.7)
		end)
	end
	equipBtn.Parent = top

	-- grid of every jersey ------------------------------------------------------------------
	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 12 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 196), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	grid.Parent = lockerBody
	for i, j in Jerseys.List do
		local open = Jerseys.IsUnlocked(j.id, wins)
		local tileBtn = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel2, LayoutOrder = i, ZIndex = 12 }, {
			UI.corner(12),
			UI.stroke(j.id == lockerSelected and C.Accent or (j.id == equipped and C.Gold or C.Stroke), j.id == lockerSelected and 3 or 1),
		})
		local fig = jerseyFigure(j)
		fig.Size = UDim2.new(1, -16, 0, 130)
		fig.Position = UDim2.fromOffset(8, 8)
		fig.ZIndex = 13
		fig.ImageTransparency = open and 0 or 0.55
		fig.Parent = tileBtn
		UI.text({ Text = string.upper(j.name), FontFace = F.Display, TextScaled = false, TextSize = 17, TextColor3 = open and C.Text or C.Muted, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 142), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13 }).Parent = tileBtn
		local sub = j.id == equipped and "EQUIPPED" or open and "UNLOCKED" or ("WIN " .. j.wins)
		UI.text({ Text = sub, FontFace = F.Heavy, TextScaled = false, TextSize = 12, TextColor3 = j.id == equipped and C.Accent or open and C.Muted or C.Gold, Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 166), ZIndex = 13 }).Parent = tileBtn
		if not open then
			-- lock badge
			new("Frame", { BackgroundColor3 = C.BG, BackgroundTransparency = 0.15, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 72), Size = UDim2.fromOffset(64, 26), ZIndex = 14 }, {
				UI.corner(13),
				UI.text({ Text = "LOCKED", FontFace = F.Heavy, TextScaled = false, TextSize = 12, TextColor3 = C.Muted, Size = UDim2.fromScale(1, 1), ZIndex = 15 }),
			}).Parent = tileBtn
		end
		if j.fx then
			UI.chip(fxLabel(j), C.Purple, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), ZIndex = 15 }).Parent = tileBtn
		end
		tileBtn.Activated:Connect(function()
			lockerSelected = j.id
			Sounds.Play("click", 0.7)
			renderLocker()
		end)
		tileBtn.Parent = grid
	end

	-- animate the special jerseys while the Locker is open
	if not lockerConn then
		lockerConn = RunService.Heartbeat:Connect(function()
			if not lockerPanel.Visible then
				return
			end
			local t = os.clock()
			for _, a in lockerAnim do
				for _, p in a.parts do
					p.Color = Jerseys.ColorAt(a.jersey, t, p.Position.Y * 0.12)
				end
			end
		end)
	end
end

-- =========================================================================================
-- Inventory sync
-- =========================================================================================
local function applyInventory(inv)
	if not inv then
		return
	end
	local oldCoins = state.coins
	state.coins = inv.coins
	state.cards = inv.cards
	state.lineup = inv.lineup or {}
	state.stats = inv.stats or {}
	state.jersey = inv.jersey or state.jersey
	state.difficulty = inv.difficulty or state.difficulty
	local open = 0
	for _, j in Jerseys.List do
		open += Jerseys.IsUnlocked(j.id, state.stats.wins) and 1 or 0
	end
	lockerBadge.Text = ("%d/%d"):format(open, #Jerseys.List)
	if oldCoins ~= inv.coins then
		UI.countTo(coinsLabel, oldCoins, inv.coins)
	end
	if inv.coins > oldCoins and oldCoins > 0 then
		UI.pop(coinPill, 0.3)
	end
	recordLabel.Text = ("%d W  -  %d L"):format(state.stats.wins or 0, state.stats.losses or 0)
	CardData.Ensure()
	teamChip.Text = "TEAM " .. teamRatings().ovr
	updateShowcase()
	if collectionPanel.Visible and not overlay.Visible then
		renderCollection()
	end
	if lineupPanel.Visible then
		renderLineup()
	end
	if lockerPanel.Visible then
		renderLocker()
	end
end

Remotes:WaitForChild("InventoryChanged").OnClientEvent:Connect(applyInventory)
gui.Parent = player:WaitForChild("PlayerGui")
fitDock()
fitHub()
task.spawn(function()
	applyInventory(Remotes:WaitForChild("GetInventory"):InvokeServer())
	state.shop = Remotes.GetShop:InvokeServer()
	state.store = Remotes:WaitForChild("GetStore"):InvokeServer()
	vipChip.Visible = state.store.vip == true
	if state.store.vip then
		teamChip.Position = UDim2.new(1, -12, 0, 47)
	end
end)

-- lobby music
Sounds.SetLoop("lobbyMusic")

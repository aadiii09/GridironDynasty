-- Lobby UI: profile + coins, nav dock with PLAY, Pack Shop (full odds before purchase), pack
-- opening, Collection with card details/quick-sell, and the 7v7 Lineup builder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PackConfig = require(ReplicatedStorage.Shared.PackConfig)
local LineupConfig = require(ReplicatedStorage.Shared.LineupConfig)
local Assets = require(ReplicatedStorage.Shared.Assets)
local CardData = require(ReplicatedStorage.Client.CardData)
local CardRenderer = require(ReplicatedStorage.Client.CardRenderer)
local UI = require(ReplicatedStorage.Client.UIKit)

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
	if h > 0 then
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

local profile = UI.glass({ Position = UDim2.fromOffset(16, 66), Size = UDim2.fromOffset(300, 78) })
profile.Parent = hud
local headshot = new("ImageLabel", { BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(10, 10) }, {
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
UI.text({ Text = player.DisplayName, FontFace = F.Heavy, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -94, 0, 24), Position = UDim2.fromOffset(80, 10), TextXAlignment = Enum.TextXAlignment.Left }).Parent = profile
local recordLabel = UI.text({ Text = "", FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(0, 130, 0, 22), Position = UDim2.fromOffset(80, 44), TextXAlignment = Enum.TextXAlignment.Left })
recordLabel.Parent = profile
local teamChip = UI.chip("TEAM --", C.Accent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 44), TextColor3 = C.BG })
teamChip.Parent = profile

local coinPill = UI.glass({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 66), Size = UDim2.fromOffset(190, 50) })
coinPill.Parent = hud
UI.icon("coin", { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(12, 9), ImageColor3 = C.Gold }).Parent = coinPill
local coinsLabel = UI.text({ Text = "0", FontFace = F.Heavy, TextColor3 = C.Gold, Size = UDim2.new(1, -60, 0, 28), Position = UDim2.fromOffset(52, 11), TextXAlignment = Enum.TextXAlignment.Left })
coinsLabel.Parent = coinPill

local dock = new("Frame", {
	Name = "Dock",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(760, 110),
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIScale", { Name = "Fit" }),
})
dock.Parent = hud

local function tile(iconName, label, color, order, onClick)
	local t = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, Size = UDim2.fromOffset(124, 100), LayoutOrder = order }, {
		UI.corner(14),
		UI.stroke(C.Stroke, 1),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 170, 185)) }),
	})
	new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0.5, 0, 0, 3), Position = UDim2.fromScale(0.25, 0) }, { UI.corner(2) }).Parent = t
	UI.icon(iconName, { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0.5, -22, 0, 14), ImageColor3 = color }).Parent = t
	UI.text({ Text = label, FontFace = F.Heavy, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -28) }).Parent = t
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
local openPanel, closePanels, renderShop, renderCollection, renderLineup, startMatch
local shopPanel, collectionPanel, lineupPanel

local packsTile = tile("packs", "PACKS", C.Purple, 1, function()
	openPanel(shopPanel)
	renderShop()
end)
local freeBadge = new("Frame", { Visible = false, BackgroundColor3 = C.Red, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(1, -20, 0, 6) }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), UI.stroke(C.BG, 2) })
freeBadge.Parent = packsTile
tile("lineup", "LINEUP", C.Gold, 2, function()
	openPanel(lineupPanel)
	renderLineup()
end)
tile("collection", "COLLECTION", C.Blue, 3, function()
	openPanel(collectionPanel)
	renderCollection()
end)

local playButton = UI.button({ kind = "primary", text = "PLAY", icon = "football", iconScale = 0.5, size = UDim2.fromOffset(250, 100), order = 4, textSize = 34, radius = 16 }, function()
	startMatch()
end)
playButton.Parent = dock
local playGlow = UI.stroke(C.Accent, 3, 0.2)
playGlow.Parent = playButton
TweenService:Create(playGlow, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85, Thickness = 6 }):Play()
UI.text({ Text = "VS AI  -  7v7", FontFace = F.Bold, TextColor3 = Color3.fromRGB(10, 60, 36), TextScaled = false, TextSize = 13, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -22), ZIndex = 2 }).Parent = playButton

-- shrink the dock on narrow (phone) screens
local function fitDock()
	local w = gui.AbsoluteSize.X
	dock.Fit.Scale = math.clamp((w - 24) / 760, 0.45, 1)
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
	-- header
	new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 120, 0, 3), Position = UDim2.fromOffset(20, 0), ZIndex = 11 }, { UI.corner(2) }).Parent = panel
	UI.icon(iconName, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(20, 16), ImageColor3 = color, ZIndex = 11 }).Parent = panel
	local titleLabel = UI.text({ Name = "Title", Text = title, FontFace = F.Heavy, TextScaled = false, TextSize = 26, Size = UDim2.new(1, -140, 0, 30), Position = UDim2.fromOffset(60, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 })
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

function closePanels()
	for _, p in panels do
		p.Visible = false
	end
	backdrop.Visible = false
	dock.Visible = true
	UI.blur(false)
end
backdrop.Activated:Connect(closePanels)

function openPanel(panel)
	for _, p in panels do
		p.Visible = p == panel
	end
	backdrop.Visible = panel ~= nil
	dock.Visible = panel == nil
	UI.blur(panel ~= nil)
	if panel then
		UI.pop(panel, 0.22)
	end
end

local shopBody, collectionBody, oddsBody, lineupBody
shopPanel, shopBody = makePanel("Shop", "PACK SHOP", "packs", C.Purple)
collectionPanel, collectionBody = makePanel("Collection", "COLLECTION", "collection", C.Blue)
lineupPanel, lineupBody = makePanel("Lineup", "LINEUP", "lineup", C.Gold)
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

function renderShop()
	state.shop = Remotes.GetShop:InvokeServer()
	shopBody:ClearAllChildren()
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }).Parent = shopBody
	new("UIGridLayout", { CellSize = UDim2.fromOffset(200, 360), CellPadding = UDim2.fromOffset(16, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }).Parent = shopBody
	if state.shop.paidRandomRestricted then
		toast("Robux packs aren't available for your account.", C.Gold)
	end
	for i, pack in PackConfig.Packs do
		local info = packInfo(pack.id)
		local tileFrame = UI.glass({ LayoutOrder = i, ZIndex = 12 })
		tileFrame:FindFirstChildOfClass("UIStroke").Color = pack.color
		tileFrame:FindFirstChildOfClass("UIStroke").Transparency = 0.3
		local art = new("ImageLabel", {
			BackgroundTransparency = Assets.pack ~= "" and 1 or 0,
			BackgroundColor3 = pack.color,
			Image = Assets.pack,
			ImageColor3 = pack.color,
			Size = UDim2.fromOffset(150, 218),
			Position = UDim2.new(0.5, -75, 0, 12),
			ZIndex = 13,
		})
		art.Parent = tileFrame
		UI.text({ Text = string.upper(pack.name):gsub(" PACK", ""):gsub("DAILY FREE", "DAILY"), FontFace = F.Heavy, TextColor3 = C.Text, TextStrokeTransparency = 0.2, Size = UDim2.new(0.86, 0, 0, 30), Position = UDim2.new(0.07, 0, 0, 160), ZIndex = 14 }).Parent = art
		UI.text({ Text = ("%d CARDS"):format(pack.cards), FontFace = F.Heavy, TextColor3 = C.BG, TextScaled = false, TextSize = 12, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 22), ZIndex = 14 }).Parent = art
		UI.text({ Text = pack.blurb, FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 13, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 238), ZIndex = 13 }).Parent = tileFrame
		local label, ready = priceText(pack, info)
		local kind = not ready and "disabled" or pack.currency == "Coins" and "gold" or pack.currency == "Robux" and "blue" or "primary"
		local buy = UI.button({ kind = kind, text = label, icon = pack.currency == "Coins" and "coin" or nil, size = UDim2.new(1, -24, 0, 44), position = UDim2.fromOffset(12, 262), textSize = 16, z = 13 }, function()
			buyPack(pack)
		end)
		packButtons[pack.id] = buy
		buy.Parent = tileFrame
		UI.button({ kind = "dark", text = "VIEW ODDS", size = UDim2.new(1, -24, 0, 34), position = UDim2.fromOffset(12, 314), textSize = 13, z = 13 }, function()
			openOdds(pack)
		end).Parent = tileFrame
		tileFrame.Parent = shopBody
	end
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
local KEY_ATTRS = {
	QB = { "THP", "THA", "SPD", "AGI", "CAR", "STR" },
	RB = { "SPD", "AGI", "CAR", "CTH", "STR", "BLK" },
	WR = { "SPD", "CTH", "AGI", "CAR", "STR", "BLK" },
	TE = { "CTH", "BLK", "STR", "SPD", "AGI", "CAR" },
	OL = { "BLK", "STR", "AGI", "SPD", "TAK", "PRS" },
	DL = { "PRS", "STR", "TAK", "SPD", "AGI", "COV" },
	LB = { "TAK", "COV", "PRS", "SPD", "STR", "AGI" },
	CB = { "COV", "SPD", "AGI", "TAK", "CTH", "STR" },
	S = { "COV", "TAK", "SPD", "AGI", "CTH", "STR" },
}
local ATTR_NAMES = { SPD = "Speed", AGI = "Agility", STR = "Strength", CTH = "Catching", CAR = "Carrying", THP = "Throw Power", THA = "Throw Accuracy", BLK = "Blocking", TAK = "Tackling", COV = "Coverage", PRS = "Pass Rush" }

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

local detail = UI.glass({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(640, 440), ZIndex = 40 })
detail.Parent = gui

local function openCard(entry)
	detail:ClearAllChildren()
	UI.corner(14).Parent = detail
	UI.stroke(C.Stroke, 1).Parent = detail
	local d = CardData.Describe(entry.id)
	local tierColor = GameConfig.TierColors[d.card.tier]
	detail:FindFirstChildOfClass("UIStroke").Color = tierColor
	local face = CardRenderer.Create(d)
	face.Size = UDim2.fromOffset(260, 390)
	face.Position = UDim2.fromOffset(22, 25)
	face.ZIndex = 41
	face.Parent = detail
	local x = 305
	UI.text({ Text = string.upper(d.first .. " " .. d.last), FontFace = F.Heavy, TextScaled = false, TextSize = 26, Size = UDim2.fromOffset(310, 30), Position = UDim2.fromOffset(x, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }).Parent = detail
	local team = d.team or {}
	UI.text({ Text = ("%s  |  %s %s  |  #%s"):format(d.card.pos, team.city or "", team.name or "", tostring(d.number or "")), FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(310, 18), Position = UDim2.fromOffset(x, 60), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }).Parent = detail
	local chips = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(310, 24), Position = UDim2.fromOffset(x, 86), ZIndex = 41 }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
	UI.chip(d.card.tier:upper(), tierColor, { TextColor3 = C.BG, ZIndex = 41 }).Parent = chips
	UI.chip(d.card.program == "Week Standout" and ("WEEK " .. d.card.week .. " STANDOUT") or "BASE", C.Panel2, { ZIndex = 41 }).Parent = chips
	UI.chip(string.upper(d.card.archetype or ""), C.Panel2, { ZIndex = 41 }).Parent = chips
	chips.Parent = detail
	for i, key in KEY_ATTRS[d.card.pos] or {} do
		local v = d.card.attrs[key] or 0
		local y = 122 + (i - 1) * 36
		UI.text({ Text = ATTR_NAMES[key], FontFace = F.Bold, TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(130, 20), Position = UDim2.fromOffset(x, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }).Parent = detail
		local track = new("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(140, 10), Position = UDim2.fromOffset(x + 130, y + 5), ZIndex = 41 }, { UI.corner(5) })
		local fill = new("Frame", { BackgroundColor3 = attrColor(v), Size = UDim2.fromScale(0, 1), ZIndex = 42 }, { UI.corner(5) })
		fill.Parent = track
		track.Parent = detail
		TweenService:Create(fill, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(v / 99, 1) }):Play()
		UI.text({ Text = tostring(v), FontFace = F.Heavy, TextColor3 = attrColor(v), TextScaled = false, TextSize = 16, Size = UDim2.fromOffset(34, 20), Position = UDim2.fromOffset(x + 278, y), ZIndex = 41 }).Parent = detail
	end
	local starting = lineupSlotOf(entry.uid)
	if starting then
		UI.text({ Text = "STARTING AT " .. starting, FontFace = F.Heavy, TextColor3 = C.Gold, TextScaled = false, TextSize = 13, Size = UDim2.fromOffset(310, 16), Position = UDim2.fromOffset(x, 340), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }).Parent = detail
	end
	local value = GameConfig.QuickSell[d.card.tier] or 0
	local armed = false
	local sell
	sell = UI.button({ kind = "gold", icon = "coin", text = "QUICK SELL  " .. UI.commas(value), size = UDim2.fromOffset(200, 44), position = UDim2.fromOffset(x, 364), textSize = 15, z = 41 }, function()
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
	UI.button({ kind = "dark", text = "CLOSE", size = UDim2.fromOffset(100, 44), position = UDim2.fromOffset(x + 210, 364), textSize = 15, z = 41 }, function()
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

	-- field with mowed stripes
	local field = new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 120, 56), Size = UDim2.new(1, 0, 0, 480), LayoutOrder = 2, ZIndex = 12, ClipsDescendants = true }, { UI.corner(14), UI.stroke(Color3.fromRGB(240, 240, 240), 2, 0.4) })
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
-- Play
-- =========================================================================================
local starting = false
function startMatch()
	if starting then
		return
	end
	starting = true
	closePanels()
	UI.setButton(playButton, "LOADING")
	local ok, res = pcall(function()
		return Remotes:WaitForChild("StartMatch"):InvokeServer()
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
	coinsLabel.Text = UI.commas(inv.coins)
	if inv.coins > oldCoins and oldCoins > 0 then
		UI.pop(coinPill, 0.3)
	end
	recordLabel.Text = ("%d W  -  %d L"):format(state.stats.wins or 0, state.stats.losses or 0)
	CardData.Ensure()
	teamChip.Text = "TEAM " .. teamRatings().ovr
	if collectionPanel.Visible and not overlay.Visible then
		renderCollection()
	end
	if lineupPanel.Visible then
		renderLineup()
	end
end

Remotes:WaitForChild("InventoryChanged").OnClientEvent:Connect(applyInventory)
gui.Parent = player:WaitForChild("PlayerGui")
fitDock()
task.spawn(function()
	applyInventory(Remotes:WaitForChild("GetInventory"):InvokeServer())
	state.shop = Remotes.GetShop:InvokeServer()
end)

-- Main UI: top bar (Coins), Pack Shop (with full odds before purchase), pack-opening reveal,
-- and Collection (with quick-sell).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PackConfig = require(ReplicatedStorage.Shared.PackConfig)
local CardData = require(ReplicatedStorage.Client.CardData)
local CardRenderer = require(ReplicatedStorage.Client.CardRenderer)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local WHITE = Color3.new(1, 1, 1)
local BG = Color3.fromRGB(12, 14, 20)
local PANEL = Color3.fromRGB(22, 26, 36)
local ACCENT = Color3.fromRGB(46, 255, 140)
local MUTED = Color3.fromRGB(150, 158, 175)
local FONT_HEAVY = Font.fromEnum(Enum.Font.GothamBlack)
local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local FONT_MED = Font.fromEnum(Enum.Font.GothamMedium)

local state = { coins = 0, cards = {}, shop = nil }

-- helpers ---------------------------------------------------------------------------

local function new(className, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end

local function text(props)
	local l = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, FontFace = FONT_BOLD, TextScaled = true })
	for k, v in props do
		l[k] = v
	end
	return l
end

local function button(props, onClick)
	local b = new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = ACCENT,
		TextColor3 = BG,
		FontFace = FONT_HEAVY,
		TextScaled = true,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
		new("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	for k, v in props do
		b[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function corner(px)
	return new("UICorner", { CornerRadius = UDim.new(0, px) })
end

local function commas(n)
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
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

local toastLabel
local function toast(msg)
	toastLabel.Text = msg
	toastLabel.Visible = true
	local my = {}
	toastLabel:SetAttribute("Token", tostring(my))
	task.delay(3, function()
		if toastLabel:GetAttribute("Token") == tostring(my) then
			toastLabel.Visible = false
		end
	end)
end

-- root ---------------------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "GridironUI", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

local topBar = new("Frame", {
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.15,
	Size = UDim2.new(1, 0, 0, 56),
	Position = UDim2.fromOffset(0, 0),
}, {
	new("UIPadding", { PaddingLeft = UDim.new(0, 70), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
})
topBar.Parent = gui
text({ Text = "GRIDIRON DYNASTY", FontFace = FONT_HEAVY, TextColor3 = ACCENT, Size = UDim2.new(0, 190, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }).Parent = topBar
local coinsLabel = text({ Text = "0 Coins", Size = UDim2.new(0, 130, 0, 22), TextColor3 = Color3.fromRGB(255, 214, 90), LayoutOrder = 2 })
coinsLabel.Parent = topBar

toastLabel = text({
	Visible = false,
	BackgroundColor3 = Color3.fromRGB(30, 34, 46),
	BackgroundTransparency = 0.05,
	Size = UDim2.new(0, 360, 0, 40),
	Position = UDim2.new(0.5, -180, 1, -70),
	TextSize = 18,
	TextScaled = false,
	ZIndex = 50,
}, nil)
corner(10).Parent = toastLabel
toastLabel.Parent = gui

local function makePanel(name, title)
	local panel = new("Frame", {
		Name = name,
		Visible = false,
		BackgroundColor3 = PANEL,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 28),
		Size = UDim2.new(1, -32, 1, -100),
		ZIndex = 10,
	}, {
		corner(14),
		new("UISizeConstraint", { MaxSize = Vector2.new(1100, 720) }),
		new("UIStroke", { Color = Color3.fromRGB(50, 58, 78), Thickness = 1 }),
	})
	text({ Text = title, FontFace = FONT_HEAVY, Size = UDim2.new(1, -120, 0, 30), Position = UDim2.fromOffset(18, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }).Parent = panel
	button({ Text = "X", Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -54, 0, 12), BackgroundColor3 = Color3.fromRGB(60, 66, 84), TextColor3 = WHITE, ZIndex = 11 }, function()
		panel.Visible = false
	end).Parent = panel
	local body = new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -70),
		Position = UDim2.fromOffset(12, 58),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ZIndex = 11,
	})
	body.Parent = panel
	panel.Parent = gui
	return panel, body
end

local shopPanel, shopBody = makePanel("Shop", "PACK SHOP")
local collectionPanel, collectionBody = makePanel("Collection", "COLLECTION")
local oddsPanel, oddsBody = makePanel("Odds", "PACK ODDS")
oddsPanel.ZIndex = 20

local function showOnly(panel)
	for _, p in { shopPanel, collectionPanel, oddsPanel } do
		p.Visible = p == panel
	end
end

-- shop -------------------------------------------------------------------------------

local packButtons = {} -- [packId] = TextButton
local renderShop

local function openOdds(pack)
	CardData.Ensure()
	oddsBody:ClearAllChildren()
	oddsPanel:FindFirstChildWhichIsA("TextLabel").Text = string.upper(pack.name) .. " ODDS"
	local info
	for _, p in state.shop.packs do
		if p.id == pack.id then
			info = p
		end
	end
	if not info then
		return
	end
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = oddsBody
	local order = 0
	local function row(str, color, height, font)
		order += 1
		text({
			Text = str,
			TextScaled = false,
			TextSize = height and math.floor(height * 0.6) or 16,
			FontFace = font or FONT_MED,
			TextColor3 = color or WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, height or 22),
			LayoutOrder = order,
			ZIndex = 21,
		}).Parent = oddsBody
	end

	row(("%d cards per pack. Odds below are exact and each table adds up to 100%%."):format(pack.cards), MUTED)
	local function tierTable(title, odds)
		row(title, ACCENT, 28, FONT_HEAVY)
		for _, tier in GameConfig.TierOrder do
			local e = odds[tier]
			if e then
				row(("%s: %s   (%d cards, %s each)"):format(tier, fmtPct(e.pct), e.count, fmtPct(e.pct / e.count)), GameConfig.TierColors[tier], 24, FONT_BOLD)
			end
		end
	end
	tierTable(pack.guaranteed and ("CARDS 1-" .. (pack.cards - 1)) or "EVERY CARD", info.odds.slot)
	if info.odds.guaranteed then
		tierTable("CARD " .. pack.cards .. " (GUARANTEED SLOT)", info.odds.guaranteed)
	end

	row("EVERY CARD YOU CAN GET", ACCENT, 28, FONT_HEAVY)
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
				local str = ("%d %s %s %s (%s, %s)  -  %s"):format(card.ovr, card.pos, d.first, d.last, card.tier, program,
					slot and fmtPct(slot.pct / slot.count) or "0%")
				if info.odds.guaranteed then
					str ..= "  |  guaranteed slot: " .. (g and fmtPct(g.pct / g.count) or "0%")
				end
				row(str, WHITE, 20)
			end
			if i % 150 == 0 then
				task.wait()
				if not oddsPanel.Visible then
					return
				end
			end
		end
	end)
	showOnly(oddsPanel)
end

local function priceText(pack, info)
	if pack.currency == "Free" then
		local wait = (state.shop.freePackReadyAt or 0) - os.time()
		return wait > 0 and ("Ready in " .. fmtDuration(wait)) or "OPEN FREE"
	elseif pack.currency == "Coins" then
		return commas(pack.price) .. " COINS"
	end
	if state.shop.paidRandomRestricted then
		return "Unavailable"
	elseif not info.available then
		return "Coming soon"
	end
	return "R$ " .. pack.price
end

local revealPack -- forward declared

local function buyPack(pack)
	if pack.currency == "Robux" then
		local res = Remotes.PromptPack:InvokeServer(pack.id)
		if not res.ok then
			toast(res.err)
		end
		return
	end
	local btn = packButtons[pack.id]
	btn.Active = false
	local res = Remotes.OpenPack:InvokeServer(pack.id)
	btn.Active = true
	if not res.ok then
		toast(res.err)
		return
	end
	if pack.currency == "Free" then
		state.shop.freePackReadyAt = os.time() + PackConfig.FreePackCooldown
	end
	revealPack(pack, res.cards)
end

renderShop = function()
	shopBody:ClearAllChildren()
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }).Parent = shopBody
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(200, 250),
		CellPadding = UDim2.fromOffset(14, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = shopBody
	if state.shop.paidRandomRestricted then
		toast("Robux packs aren't available for your account.")
	end
	for i, pack in PackConfig.Packs do
		local info
		for _, p in state.shop.packs do
			if p.id == pack.id then
				info = p
			end
		end
		local tile = new("Frame", { BackgroundColor3 = Color3.fromRGB(16, 18, 26), LayoutOrder = i, ZIndex = 12 }, {
			corner(12),
			new("UIStroke", { Color = pack.color, Thickness = 2 }),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)) }),
		})
		new("Frame", { BackgroundColor3 = pack.color, Size = UDim2.new(1, -24, 0, 90), Position = UDim2.fromOffset(12, 12), ZIndex = 13 }, {
			corner(10),
			new("UIGradient", { Rotation = 120, Transparency = NumberSequence.new(0, 0.45) }),
			text({ Text = "GRIDIRON\nDYNASTY", FontFace = FONT_HEAVY, TextColor3 = BG, Size = UDim2.new(0.8, 0, 0.6, 0), Position = UDim2.fromScale(0.1, 0.2), ZIndex = 14 }),
		}).Parent = tile
		text({ Text = string.upper(pack.name), FontFace = FONT_HEAVY, Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 110), ZIndex = 13 }).Parent = tile
		text({ Text = pack.blurb, FontFace = FONT_MED, TextColor3 = MUTED, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 138), ZIndex = 13 }).Parent = tile
		local buy = button({ Text = priceText(pack, info), Size = UDim2.new(1, -24, 0, 38), Position = UDim2.fromOffset(12, 164), ZIndex = 13 }, function()
			buyPack(pack)
		end)
		if not info.available or buy.Text:find("Ready in") then
			buy.BackgroundColor3 = Color3.fromRGB(70, 76, 94)
			buy.TextColor3 = MUTED
		end
		packButtons[pack.id] = buy
		buy.Parent = tile
		button({ Text = "VIEW ODDS", BackgroundColor3 = Color3.fromRGB(44, 50, 68), TextColor3 = WHITE, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 208), ZIndex = 13 }, function()
			openOdds(pack)
		end).Parent = tile
		tile.Parent = shopBody
	end
end

-- free pack countdown
task.spawn(function()
	while true do
		task.wait(1)
		if state.shop and shopPanel.Visible then
			local btn = packButtons.daily
			if btn then
				btn.Text = priceText(PackConfig.ById.daily, {})
				local ready = not btn.Text:find("Ready in")
				btn.BackgroundColor3 = ready and ACCENT or Color3.fromRGB(70, 76, 94)
				btn.TextColor3 = ready and BG or MUTED
			end
		end
	end
end)

-- pack reveal -------------------------------------------------------------------------

local overlay = new("Frame", {
	Name = "Reveal",
	Visible = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.15,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 30,
})
overlay.Parent = gui
local revealTitle = text({ FontFace = FONT_HEAVY, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 70), ZIndex = 31 })
revealTitle.Parent = overlay
local revealRow = new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -24, 1, -200),
	Position = UDim2.fromOffset(12, 120),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 6,
	ZIndex = 31,
})
revealRow.Parent = overlay
local revealButton = button({ Text = "REVEAL", Size = UDim2.fromOffset(220, 48), Position = UDim2.new(0.5, -110, 1, -70), ZIndex = 32 })
revealButton.Parent = overlay

local function flip(slot, cardInfo)
	local back = slot:FindFirstChild("CardBack")
	local half = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local t = TweenService:Create(slot, half, { Size = UDim2.new(0, 0, 1, 0), Position = UDim2.fromScale(0.5, 0) })
	t:Play()
	t.Completed:Wait()
	if back then
		back:Destroy()
	end
	local face = CardRenderer.Create(cardInfo)
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 33
	face.Parent = slot
	local t2 = TweenService:Create(slot, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0) })
	t2:Play()
	t2.Completed:Wait()
end

revealPack = function(pack, cards)
	CardData.Ensure()
	showOnly(nil)
	revealRow:ClearAllChildren()
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(170, 255),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = revealRow

	local infos = {}
	for _, c in cards do
		local d = CardData.Describe(c.id)
		if d then
			table.insert(infos, d)
		end
	end
	table.sort(infos, function(a, b)
		return a.card.ovr < b.card.ovr -- best card revealed last
	end)

	local slots = {}
	for i, d in infos do
		local holder = new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 32, ClipsDescendants = false })
		local slot = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 32 })
		local back = CardRenderer.Back(nil)
		back.Size = UDim2.fromScale(1, 1)
		back.ZIndex = 33
		back.Parent = slot
		slot.Parent = holder
		holder.Parent = revealRow
		slots[i] = slot
	end

	revealTitle.Text = string.upper(pack.name)
	overlay.Visible = true
	revealButton.Text = "REVEAL"
	revealButton.Visible = true

	local conn
	conn = revealButton.Activated:Connect(function()
		conn:Disconnect()
		revealButton.Visible = false
		for i, d in infos do
			-- tease the tier with the back's glow before flipping big pulls
			local back = slots[i]:FindFirstChild("CardBack")
			local tierIndex = table.find(GameConfig.TierOrder, d.card.tier) or 1
			if back and tierIndex >= 4 then
				back:FindFirstChildWhichIsA("UIStroke").Color = GameConfig.TierColors[d.card.tier]
				back:FindFirstChildWhichIsA("UIStroke").Thickness = 6
				revealTitle.Text = d.card.tier == "Icon" and "ICON PULL!" or "ELITE PULL!"
				revealTitle.TextColor3 = GameConfig.TierColors[d.card.tier]
				task.wait(0.8)
			end
			flip(slots[i], d)
			task.wait(tierIndex >= 3 and 0.35 or 0.12)
		end
		revealTitle.TextColor3 = WHITE
		revealButton.Text = "CONTINUE"
		revealButton.Visible = true
		local c2
		c2 = revealButton.Activated:Connect(function()
			c2:Disconnect()
			overlay.Visible = false
			showOnly(shopPanel)
		end)
	end)
end

Remotes:WaitForChild("PackOpened").OnClientEvent:Connect(function(result)
	local pack = PackConfig.ById[result.packId]
	if pack and result.ok then
		revealPack(pack, result.cards)
	end
end)

-- collection ---------------------------------------------------------------------------

local collectionFilter = "ALL"
local renderCollection

local sellPopup = new("Frame", {
	Visible = false,
	BackgroundColor3 = PANEL,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(300, 470),
	ZIndex = 40,
}, { corner(14), new("UIStroke", { Color = ACCENT, Thickness = 2 }) })
sellPopup.Parent = gui

local function openCard(entry)
	sellPopup:ClearAllChildren()
	corner(14).Parent = sellPopup
	new("UIStroke", { Color = ACCENT, Thickness = 2 }).Parent = sellPopup
	local d = CardData.Describe(entry.id)
	local face = CardRenderer.Create(d)
	face.Size = UDim2.fromOffset(240, 360)
	face.Position = UDim2.fromOffset(30, 16)
	face.ZIndex = 41
	face.Parent = sellPopup
	local value = GameConfig.QuickSell[d.card.tier] or 0
	local sell = button({ Text = "QUICK SELL: " .. commas(value) .. " COINS", BackgroundColor3 = Color3.fromRGB(255, 196, 46), Size = UDim2.fromOffset(240, 36), Position = UDim2.fromOffset(30, 384), ZIndex = 41 })
	local armed = false
	sell.Activated:Connect(function()
		if not armed then
			armed = true
			sell.Text = "TAP AGAIN TO CONFIRM"
			return
		end
		sell.Active = false
		local res = Remotes.QuickSell:InvokeServer(entry.uid)
		sellPopup.Visible = false
		toast(res.ok and ("Sold for " .. commas(res.coins) .. " Coins") or (res.err or "Couldn't sell"))
	end)
	sell.Parent = sellPopup
	button({ Text = "CLOSE", BackgroundColor3 = Color3.fromRGB(60, 66, 84), TextColor3 = WHITE, Size = UDim2.fromOffset(240, 30), Position = UDim2.fromOffset(30, 426), ZIndex = 41 }, function()
		sellPopup.Visible = false
	end).Parent = sellPopup
	sellPopup.Visible = true
end

local renderToken = 0
renderCollection = function()
	CardData.Ensure()
	renderToken += 1
	local myToken = renderToken
	collectionBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = collectionBody

	local filters = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, ZIndex = 12 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	for _, f in { "ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S" } do
		local b = button({ Text = f, Size = UDim2.fromOffset(52, 32), ZIndex = 12, BackgroundColor3 = f == collectionFilter and ACCENT or Color3.fromRGB(44, 50, 68), TextColor3 = f == collectionFilter and BG or WHITE }, function()
			collectionFilter = f
			renderCollection()
		end)
		b.Parent = filters
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
		return a.d.card.ovr > b.d.card.ovr
	end)

	text({ Text = ("%d cards"):format(#list), FontFace = FONT_MED, TextColor3 = MUTED, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, ZIndex = 12 }).Parent = collectionBody

	local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 12 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 225), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	grid.Parent = collectionBody
	for i, item in list do
		local face = CardRenderer.Create(item.d, { stroke = 2 })
		face.LayoutOrder = i
		face.ZIndex = 12
		local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 20 })
		hit.Activated:Connect(function()
			openCard(item.entry)
		end)
		hit.Parent = face
		face.Parent = grid
		if i % 20 == 0 then
			task.wait()
			if myToken ~= renderToken then
				return -- a newer render started
			end
		end
	end
end

-- top bar buttons -----------------------------------------------------------------------

button({ Text = "PACKS", Size = UDim2.fromOffset(110, 38), LayoutOrder = 3 }, function()
	if shopPanel.Visible then
		shopPanel.Visible = false
		return
	end
	state.shop = Remotes.GetShop:InvokeServer()
	renderShop()
	showOnly(shopPanel)
end).Parent = topBar

button({ Text = "COLLECTION", Size = UDim2.fromOffset(150, 38), LayoutOrder = 4, BackgroundColor3 = Color3.fromRGB(64, 160, 255) }, function()
	if collectionPanel.Visible then
		collectionPanel.Visible = false
		return
	end
	showOnly(collectionPanel)
	renderCollection()
end).Parent = topBar

-- inventory sync -------------------------------------------------------------------------

local function applyInventory(inv)
	if not inv then
		return
	end
	state.coins = inv.coins
	state.cards = inv.cards
	coinsLabel.Text = commas(inv.coins) .. " Coins"
	if collectionPanel.Visible and not overlay.Visible then
		renderCollection()
	end
end

Remotes:WaitForChild("InventoryChanged").OnClientEvent:Connect(applyInventory)
gui.Parent = player:WaitForChild("PlayerGui")
task.spawn(function()
	applyInventory(Remotes:WaitForChild("GetInventory"):InvokeServer())
end)

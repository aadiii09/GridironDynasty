-- Match HUD: broadcast score bug, play/defense call cards with diagrams, snap/throw/switch
-- controls, result banners and the final screen.
-- Keyboard: 1-3 call, Space snap/ready, 1-4 throw, Q switch defender.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Assets = require(ReplicatedStorage.Shared.Assets)
local UI = require(ReplicatedStorage.Client.UIKit)
local MatchCamera = require(ReplicatedStorage.Client.MatchCamera)
local MatchFX = require(ReplicatedStorage.Client.MatchFX)
local JerseyFX = require(ReplicatedStorage.Client.JerseyFX)
JerseyFX.Start()
MatchCamera.BallPosition = function()
	return MatchFX.BallPosition
end

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchAction = Remotes:WaitForChild("MatchAction")
local C = UI.Color
local F = UI.Font
local new = UI.new

local state = nil
local openChips = {} -- [receiver model] = OPEN/COVERED chip on his throw button
local showCallout -- floating text over a player (defined below)
local phaseChangedAt = 0 -- ignore keys for a moment after the phase changes

local gui = new("ScreenGui", { Name = "MatchUI", ResetOnSpawn = false, Enabled = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

-- score bug (top center) ------------------------------------------------------------------
local bug = UI.glass({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(560, 86) })
bug.Parent = gui
local function teamBox(xScale, align)
	local box = new("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.new(0.5, -50, 0, 52), Position = UDim2.new(xScale, xScale == 0 and 8 or 42, 0, 8) }, { UI.corner(10) })
	local logo = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Position = align == "left" and UDim2.fromOffset(6, 6) or UDim2.new(1, -46, 0, 6) })
	logo.Parent = box
	local name = UI.text({ FontFace = F.Display, TextScaled = false, TextSize = 21, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Size = UDim2.new(1, -110, 1, 0), Position = align == "left" and UDim2.fromOffset(52, 0) or UDim2.fromOffset(58, 0), TextXAlignment = align == "left" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right })
	name.Parent = box
	local score = UI.text({ FontFace = F.Display, TextScaled = false, TextSize = 40, Size = UDim2.fromOffset(50, 52), Position = align == "left" and UDim2.new(1, -54, 0, 0) or UDim2.fromOffset(4, 0) })
	score.Parent = box
	local ball = new("Frame", { Visible = false, BackgroundColor3 = C.Gold, Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = align == "left" and UDim2.new(1, -60, 0.5, 0) or UDim2.new(0, 60, 0.5, 0) }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	ball.Parent = box
	box.Parent = bug
	return { box = box, logo = logo, name = name, score = score, ball = ball }
end
local youBox = teamBox(0, "left")
local cpuBox = teamBox(0.5, "right")
UI.text({ Text = "VS", FontFace = F.Heavy, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(30, 20) }).Parent = bug
local situation = UI.text({ FontFace = F.Display, TextColor3 = C.Text, TextScaled = false, TextSize = 17, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 64) })
situation.Parent = bug

local quit = UI.button({ kind = "dark", text = "QUIT", size = UDim2.fromOffset(112, 42), anchor = Vector2.new(1, 0), position = UDim2.new(1, -16, 0, 66), textSize = 14 }, function()
	MatchAction:FireServer("leave")
end)
quit.Parent = gui

-- banner ------------------------------------------------------------------------------------
local banner = new("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, {
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }) }),
})
banner.Parent = gui
local bannerBar = new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C.Accent }, {
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }),
})
bannerBar.Parent = banner
local bannerText = UI.text({ FontFace = F.Display, Size = UDim2.new(0.9, 0, 0, 48), Position = UDim2.new(0.05, 0, 0, 15), TextStrokeTransparency = 0.5 })
bannerText.Parent = banner
local bannerToken = 0
local function showBanner(msg, colorHex)
	bannerToken += 1
	local my = bannerToken
	local color = colorHex and Color3.fromHex(colorHex) or C.Text
	bannerText.Text = msg
	bannerText.TextColor3 = color
	bannerBar.BackgroundColor3 = color
	banner.Visible = true
	banner.Position = UDim2.fromScale(0.5, 0.32) + UDim2.fromOffset(0, -20)
	bannerText.TextTransparency = 1
	TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.32) }):Play()
	TweenService:Create(bannerText, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(2.4, function()
		if bannerToken == my then
			banner.Visible = false
		end
	end)
end

-- bottom controls ------------------------------------------------------------------------------
local controls = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -24, 0, 170), BackgroundTransparency = 1 }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIScale", { Name = "Fit" }),
})
controls.Parent = gui
local hint = UI.text({ FontFace = F.Display, TextColor3 = C.Text, TextStrokeTransparency = 0.35, TextScaled = false, TextSize = 16, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -196), Size = UDim2.new(0.9, 0, 0, 22) })
hint.Parent = gui

local function fit()
	controls.Fit.Scale = math.clamp((gui.AbsoluteSize.X - 24) / 900, 0.5, 1)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

local function clearControls()
	for _, c in controls:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- play/defense call card with diagram
local function callCard(key, name, desc, diagram, color, onClick)
	local b = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.04, Size = UDim2.fromOffset(250, 168), LayoutOrder = key }, {
		UI.corner(14),
		UI.stroke(color, 2, 0.15),
	})
	local field = new("ImageLabel", { BackgroundColor3 = Color3.fromRGB(32, 110, 56), Image = diagram or "", Size = UDim2.new(1, -16, 0, 84), Position = UDim2.fromOffset(8, 8), ScaleType = Enum.ScaleType.Fit }, { UI.corner(10) })
	field.Parent = b
	UI.chip(tostring(key), color, { TextColor3 = C.BG, Position = UDim2.fromOffset(14, 14), TextSize = 14 }).Parent = b
	UI.text({ Text = name, FontFace = F.Display, TextColor3 = color, TextScaled = false, TextSize = 23, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 98) }).Parent = b
	UI.text({ Text = desc, FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 12, TextWrapped = true, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 122) }).Parent = b
	local scale = new("UIScale")
	scale.Parent = b
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onClick)
	return b
end

local function switchButton()
	return UI.button({ kind = "purple", icon = "switch", text = "SWITCH  [Q]", size = UDim2.fromOffset(180, 60), order = 9, textSize = 16 }, function()
		MatchAction:FireServer("switch")
	end)
end

-- final screen ---------------------------------------------------------------------------------
local finalPanel = UI.glass({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(440, 330), ZIndex = 20 })
finalPanel.Parent = gui
UI.icon("trophy", { Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0.5, -28, 0, 18), ImageColor3 = C.Gold, ZIndex = 21 }).Parent = finalPanel
local finalTitle = UI.text({ FontFace = F.Display, TextScaled = false, TextSize = 52, Size = UDim2.new(1, -30, 0, 46), Position = UDim2.fromOffset(15, 80), ZIndex = 21 })
finalTitle.Parent = finalPanel
local finalScore = UI.text({ FontFace = F.Heavy, TextScaled = false, TextSize = 22, Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(15, 132), ZIndex = 21 })
finalScore.Parent = finalPanel
local finalCoins = UI.text({ FontFace = F.Number, TextColor3 = C.Gold, TextScaled = false, TextSize = 20, Size = UDim2.new(1, -30, 0, 26), Position = UDim2.fromOffset(15, 168), ZIndex = 21 })
finalCoins.Parent = finalPanel
local finalUnlock = UI.text({ FontFace = F.Heavy, TextColor3 = C.Accent, TextScaled = false, TextSize = 16, Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 200), ZIndex = 21 })
finalUnlock.Parent = finalPanel
UI.button({ kind = "primary", text = "BACK TO LOBBY", size = UDim2.new(1, -60, 0, 52), position = UDim2.fromOffset(30, 254), textSize = 18, z = 21 }, function()
	MatchAction:FireServer("leave")
end).Parent = finalPanel

-- play clock (head-to-head): seconds left to call / snap ------------------------------------
local clockLabel = UI.text({ Name = "PlayClock", Text = "", FontFace = F.Number, TextScaled = false, TextSize = 30, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 232), Size = UDim2.fromOffset(120, 34), Visible = false })
clockLabel.Parent = gui
RunService.Heartbeat:Connect(function()
	local s = state
	local ends = s and s.clockEndsAt
	if not ends or (s.phase ~= "playcall" and s.phase ~= "defcall" and s.phase ~= "waiting" and s.phase ~= "presnap") then
		clockLabel.Visible = false
		return
	end
	local left = math.max(0, math.ceil(ends - workspace:GetServerTimeNow()))
	clockLabel.Visible = true
	clockLabel.Text = ":" .. string.format("%02d", left)
	clockLabel.TextColor3 = left <= 5 and C.Red or C.Text
end)

-- callouts: floating text over a player when a rating wins a play ----------------------------
function showCallout(model, text, colorHex)
	local head = model and model:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = head
	local label = UI.text({ Text = text, FontFace = F.Display, TextScaled = false, TextSize = 26, TextColor3 = Color3.fromHex(colorHex or "ffffff"), TextStrokeTransparency = 0.2, Size = UDim2.fromScale(1, 1) })
	label.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	bb.Parent = player.PlayerGui
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, 8, 0) }):Play()
	task.delay(0.9, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(1.5, function()
		bb:Destroy()
	end)
end

-- open / covered: target rings and throw buttons colored by each receiver's separation, live ---
local DEFENDER_SLOTS = { CB1 = true, CB2 = true, LB1 = true, LB2 = true, S = true, DL1 = true, DL2 = true }
RunService.RenderStepped:Connect(function()
	local s = state
	if not s or not s.ball or not s.ball.Parent then
		return
	end
	local field = s.ball.Parent
	-- the offense's target rings are only for the offense
	if s.possession ~= "user" then
		for _, m in field:GetChildren() do
			local ring = m:IsA("Model") and m:FindFirstChild("TargetRing")
			if ring then
				ring.LocalTransparencyModifier = 1
			end
		end
		return
	end
	if s.phase ~= "live" or s.playState ~= "dropback" then
		return
	end
	local defs, rings = {}, {}
	for _, m in field:GetChildren() do
		if m:IsA("Model") then
			if DEFENDER_SLOTS[m.Name] then
				local root, head = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChild("Head")
				if root and head and head.Transparency < 1 then
					table.insert(defs, root.Position)
				end
			end
			local ring = m:FindFirstChild("TargetRing")
			if ring then
				table.insert(rings, ring)
			end
		end
	end
	for _, ring in rings do
		ring.LocalTransparencyModifier = 0
		local rcv = ring.Parent
		local root = rcv and rcv:FindFirstChild("HumanoidRootPart")
		if root then
			local sep = math.huge
			for _, d in defs do
				sep = math.min(sep, (Vector3.new(d.X, 0, d.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude)
			end
			local color, word
			if sep >= 7 then
				color, word = C.Accent, "OPEN"
			elseif sep >= 3.5 then
				color, word = C.Gold, "TIGHT"
			else
				color, word = C.Red, "COVERED"
			end
			ring.Color = color
			local chip = openChips[rcv]
			if chip then
				chip.BackgroundColor3 = color
				chip.Text = word
				chip.TextColor3 = C.BG
			end
		end
	end
end)

-- render -------------------------------------------------------------------------------------
local function render()
	local s = state
	if not s then
		return
	end
	local userBall = s.possession == "user"
	youBox.name.Text = string.upper(player.DisplayName)
	youBox.score.Text = tostring(s.you)
	youBox.box.BackgroundColor3 = Color3.fromRGB(16, 60, 40)
	youBox.logo.Image = Assets.icon_football
	youBox.logo.ImageColor3 = C.Accent
	youBox.logo.ScaleType = Enum.ScaleType.Fit
	cpuBox.name.Text = string.upper(s.opponent.name)
	cpuBox.score.Text = tostring(s.cpu)
	cpuBox.box.BackgroundColor3 = Color3.fromHex(s.opponent.primary):Lerp(Color3.new(0, 0, 0), 0.35)
	if s.opponent.human then
		cpuBox.logo.Image = Assets.icon_football
		cpuBox.logo.ImageColor3 = Color3.fromHex(s.opponent.secondary)
	else
		cpuBox.logo.Image = Assets.Logo(s.opponent.id)
		cpuBox.logo.ImageColor3 = Color3.new(1, 1, 1)
	end
	youBox.ball.Visible = userBall
	cpuBox.ball.Visible = not userBall
	local ordinal = ({ "1st", "2nd", "3rd", "4th" })[s.down] or (s.down .. "th")
	situation.Text = ("%s & %s   |   %s   |   DRIVE %d/%d%s"):format(ordinal, s.toGo, s.spot, math.min(s.drive, s.drives), s.drives, (s.mode == "ranked" or s.mode == "friendly") and ("   |   " .. s.difficulty) or "")
	if s.phase == "final" then
		situation.Text = ("FINAL   |   %s   |   TEAM RATING  %d vs %d"):format(s.difficulty or "", s.ratings.you.ovr, s.ratings.cpu.ovr)
	end

	clearControls()
	hint.Text = ""
	finalPanel.Visible = s.phase == "final"

	if s.phase == "playcall" then
		hint.Text = "YOUR BALL  -  call a play (1-3)"
		for i, play in MatchConfig.Plays do
			local color = i == 3 and C.Gold or C.Accent
			callCard(i, play.name, play.desc, Assets["play_" .. play.id], color, function()
				MatchAction:FireServer("call", play.id)
			end).Parent = controls
		end
	elseif s.phase == "defcall" then
		hint.Text = ("DEFENSE  -  call a coverage (1-3). You're the %s %s, Q to switch"):format(s.control and s.control.pos or "", s.control and s.control.name or "")
		for i, call in MatchConfig.DefenseCalls do
			local color = i == 3 and C.Red or C.Blue
			callCard(i, call.name, call.desc, Assets["play_" .. call.id], color, function()
				MatchAction:FireServer("defcall", call.id)
			end).Parent = controls
		end
		switchButton().Parent = controls
	elseif s.phase == "waiting" then
		hint.Text = ("Waiting for %s to call..."):format(s.opponent.name)
	elseif s.phase == "presnap" and not userBall and not s.canSnap then
		hint.Text = ("You're the %s %s  -  %s snaps the ball  -  Q to switch"):format(s.control and s.control.pos or "", s.control and s.control.name or "", s.opponent.name)
		switchButton().Parent = controls
	elseif s.phase == "presnap" and not userBall then
		hint.Text = ("You're the %s %s  -  Space when ready, Q to switch"):format(s.control and s.control.pos or "", s.control and s.control.name or "")
		UI.button({ kind = "primary", icon = "whistle", text = "READY  [SPACE]", size = UDim2.fromOffset(250, 64), textSize = 18 }, function()
			MatchAction:FireServer("snap")
		end).Parent = controls
		switchButton().Parent = controls
	elseif s.phase == "live" and not userBall then
		if s.playState == "air" then
			hint.Text = "BALL IN THE AIR  -  run to the GOLD CIRCLE to pick it off or break it up"
		elseif s.playState == "carry" then
			hint.Text = "Chase the GOLD ball carrier and run into him to tackle  -  Q switches"
		else
			hint.Text = "Rush the QB or cover your man  -  you'll jump to the defender nearest the ball when it's thrown"
		end
		switchButton().Parent = controls
	elseif s.phase == "presnap" then
		hint.Text = s.play == "run" and "Snap it and take the handoff" or "Snap it, then throw to a yellow ring (1-4)"
		UI.button({ kind = "primary", icon = "football", text = "SNAP  [SPACE]", size = UDim2.fromOffset(250, 64), textSize = 18 }, function()
			MatchAction:FireServer("snap")
		end).Parent = controls
	elseif s.phase == "live" and s.playState == "dropback" and s.play ~= "run" then
		hint.Text = "THROW  (1-4)  -  GREEN = open, RED = covered  -  or run past the line to scramble"
		table.clear(openChips)
		for _, t in s.targets do
			if t.available then
				local b = UI.button({ kind = "gold", text = ("%s %s"):format(t.pos, t.name), size = UDim2.fromOffset(210, 66), order = t.key, textSize = 15 }, function()
					MatchAction:FireServer("throw", t.key)
				end)
				UI.chip(tostring(t.key), C.BG, { TextColor3 = C.Gold, Position = UDim2.fromOffset(-6, -8), ZIndex = 3 }).Parent = b
				UI.text({ Text = ("%d OVR  -  SPD %d  -  CTH %d"):format(t.ovr or 0, t.spd or 0, t.cth or 0), FontFace = F.Bold, TextColor3 = C.BG, TextTransparency = 0.15, TextScaled = false, TextSize = 11, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -16), ZIndex = 3 }).Parent = b
				local chip = UI.chip("...", C.BG, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), ZIndex = 3 })
				chip.Parent = b
				if t.model then
					openChips[t.model] = chip
				end
				b.Parent = controls
			end
		end
	elseif s.phase == "live" and s.playState == "carry" then
		hint.Text = "RUN!  Find a hole and reach the end zone"
	end

	if s.final then
		local win = s.final.result == "Win"
		finalTitle.Text = win and "VICTORY" or s.final.result == "Loss" and "DEFEAT" or "TIE GAME"
		finalTitle.TextColor3 = win and C.Accent or s.final.result == "Loss" and C.Red or C.Gold
		finalPanel:FindFirstChildOfClass("UIStroke").Color = finalTitle.TextColor3
		finalScore.Text = ("YOU %d  -  %d %s"):format(s.you, s.cpu, string.upper(s.opponent.name))
		finalCoins.Text = ("+%d COINS%s"):format(s.final.coins, s.final.difficulty and ("  -  %s x%s"):format(s.final.difficulty, tostring(s.final.multiplier)) or "")
		local unlocked = s.final.unlocked or {}
		local lines = {}
		if s.final.rating then
			local r = s.final.rating
			table.insert(lines, ("RATING %d -> %d (%+d)  -  %s"):format(r.old, r.new, r.new - r.old, r.division))
		end
		if #unlocked > 0 then
			table.insert(lines, "NEW JERSEY UNLOCKED: " .. string.upper(table.concat(unlocked, ", ")))
		end
		finalUnlock.Text = table.concat(lines, "   |   ")
	end
end

Remotes:WaitForChild("MatchState").OnClientEvent:Connect(function(s)
	if s.event == "callout" then
		showCallout(s.model, s.text, s.color)
		return
	end
	if s.event == "fall" then
		MatchFX.Fall()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.FallingDown)
		end
		return
	end
	local main = player.PlayerGui:FindFirstChild("GridironUI")
	if s.phase == "ended" then
		state = nil
		MatchCamera.Stop()
		MatchFX.Stop()
		gui.Enabled = false
		if main then
			main.Enabled = true
		end
		return
	end
	if not state or state.phase ~= s.phase then
		phaseChangedAt = os.clock()
	end
	local firstState = state == nil
	state = s
	MatchCamera.Update(s)
	MatchFX.Update(s)
	gui.Enabled = true
	if main then
		main.Enabled = false
	end
	if firstState then
		UI.blur(false)
	end
	if s.message then
		showBanner(s.message, s.messageColor)
	end
	render()
	if s.phase == "final" then
		UI.pop(finalPanel, 0.35)
	end
end)

local keyNumbers = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3, [Enum.KeyCode.KeypadFour] = 4,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not state or os.clock() - phaseChangedAt < 0.5 then
		return
	end
	local n = keyNumbers[input.KeyCode]
	if input.KeyCode == Enum.KeyCode.Q and state.possession == "cpu" then
		MatchAction:FireServer("switch")
	elseif state.phase == "defcall" and n and MatchConfig.DefenseCalls[n] then
		MatchAction:FireServer("defcall", MatchConfig.DefenseCalls[n].id)
	elseif state.phase == "playcall" and n and MatchConfig.Plays[n] then
		MatchAction:FireServer("call", MatchConfig.Plays[n].id)
	elseif state.phase == "presnap" and input.KeyCode == Enum.KeyCode.Space then
		MatchAction:FireServer("snap")
	elseif state.phase == "live" and n then
		MatchAction:FireServer("throw", n)
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
fit()

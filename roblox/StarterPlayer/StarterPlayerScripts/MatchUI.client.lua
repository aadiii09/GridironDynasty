-- Match HUD: scoreboard, play calling, snap/throw controls, banners and the final screen.
-- Keyboard: 1-3 pick a play, Space snaps, 1-4 throw to the matching receiver.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchAction = Remotes:WaitForChild("MatchAction")

local WHITE = Color3.new(1, 1, 1)
local BG = Color3.fromRGB(12, 14, 20)
local ACCENT = Color3.fromRGB(46, 255, 140)
local MUTED = Color3.fromRGB(150, 158, 175)
local FONT_HEAVY = Font.fromEnum(Enum.Font.GothamBlack)
local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local FONT_MED = Font.fromEnum(Enum.Font.GothamMedium)

local state = nil
local phaseChangedAt = 0 -- ignore keys for a moment after the phase changes (no accidental play calls)

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
		new("UICorner", { CornerRadius = UDim.new(0, 10) }),
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	for k, v in props do
		b[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local gui = new("ScreenGui", { Name = "MatchUI", ResetOnSpawn = false, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

-- scoreboard ---------------------------------------------------------------------------
local board = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(520, 70),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.1,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 12) }),
	new("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.4 }),
	new("UISizeConstraint", { MaxSize = Vector2.new(520, 70) }),
})
board.Parent = gui
local youLabel = text({ FontFace = FONT_HEAVY, Size = UDim2.new(0.38, 0, 0, 34), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = ACCENT })
youLabel.Parent = board
local cpuLabel = text({ FontFace = FONT_HEAVY, Size = UDim2.new(0.5, 0, 0, 34), Position = UDim2.new(0.5, -10, 0, 6), TextXAlignment = Enum.TextXAlignment.Right })
cpuLabel.Parent = board
local situation = text({ FontFace = FONT_BOLD, TextColor3 = MUTED, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 44) })
situation.Parent = board

local quit = button({ Text = "QUIT", Size = UDim2.fromOffset(80, 34), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), BackgroundColor3 = Color3.fromRGB(60, 66, 84), TextColor3 = WHITE })
quit.Parent = gui

-- banner ----------------------------------------------------------------------------------
local banner = text({
	FontFace = FONT_HEAVY,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 92),
	Size = UDim2.new(0.8, 0, 0, 44),
	TextStrokeTransparency = 0.3,
	Visible = false,
})
banner.Parent = gui
local bannerToken = 0
local function showBanner(msg, colorHex)
	bannerToken += 1
	local my = bannerToken
	banner.Text = msg
	banner.TextColor3 = colorHex and Color3.fromHex(colorHex) or WHITE
	banner.Visible = true
	task.delay(2.6, function()
		if bannerToken == my then
			banner.Visible = false
		end
	end)
end

-- bottom controls ----------------------------------------------------------------------------
local controls = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(1, -24, 0, 120),
	BackgroundTransparency = 1,
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10) }),
})
controls.Parent = gui
local hint = text({ FontFace = FONT_MED, TextColor3 = WHITE, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -142), Size = UDim2.new(0.9, 0, 0, 22) })
hint.Parent = gui

-- final screen ---------------------------------------------------------------------------------
local finalPanel = new("Frame", {
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(380, 250),
	BackgroundColor3 = BG,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 14) }),
	new("UIStroke", { Color = ACCENT, Thickness = 2 }),
})
finalPanel.Parent = gui
local finalTitle = text({ FontFace = FONT_HEAVY, Size = UDim2.new(1, -30, 0, 50), Position = UDim2.fromOffset(15, 16) })
finalTitle.Parent = finalPanel
local finalScore = text({ FontFace = FONT_BOLD, Size = UDim2.new(1, -30, 0, 30), Position = UDim2.fromOffset(15, 74) })
finalScore.Parent = finalPanel
local finalCoins = text({ FontFace = FONT_BOLD, TextColor3 = Color3.fromRGB(255, 214, 90), Size = UDim2.new(1, -30, 0, 26), Position = UDim2.fromOffset(15, 112) })
finalCoins.Parent = finalPanel
button({ Text = "BACK TO LOBBY", Size = UDim2.new(1, -60, 0, 46), Position = UDim2.fromOffset(30, 176) }, function()
	MatchAction:FireServer("leave")
end).Parent = finalPanel

local function clearControls()
	for _, c in controls:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function switchButton()
	return button({ Text = "SWITCH  [Q]", Size = UDim2.fromOffset(150, 56), BackgroundColor3 = Color3.fromRGB(176, 92, 255), TextColor3 = WHITE }, function()
		MatchAction:FireServer("switch")
	end)
end

local function render()
	local s = state
	if not s then
		return
	end
	youLabel.Text = "YOU  " .. s.you
	cpuLabel.Text = string.upper(s.opponent.name) .. "  " .. s.cpu
	cpuLabel.TextColor3 = Color3.fromHex(s.opponent.secondary)
	local ordinal = ({ "1st", "2nd", "3rd", "4th" })[s.down] or (s.down .. "th")
	local userBall = s.possession == "user"
	situation.Text = ("%s  |  %s & %s  |  %s  |  Drive %d/%d"):format(userBall and "YOUR BALL" or string.upper(s.opponent.name) .. " BALL", ordinal, s.toGo, s.spot, math.min(s.drive, s.drives), s.drives)
	if s.phase == "final" then
		situation.Text = ("FINAL  |  Team rating: You %d vs %d"):format(s.ratings.you.ovr, s.ratings.cpu.ovr)
	end

	clearControls()
	hint.Text = ""
	finalPanel.Visible = s.phase == "final"

	if s.phase == "playcall" then
		hint.Text = "Call a play (keys 1-3)"
		for i, play in MatchConfig.Plays do
			local b = button({ Text = "", Size = UDim2.fromOffset(220, 100), BackgroundColor3 = i == 3 and Color3.fromRGB(255, 196, 46) or ACCENT })
			text({ Text = ("[%d] %s"):format(i, play.name), FontFace = FONT_HEAVY, TextColor3 = BG, Size = UDim2.new(1, 0, 0.42, 0) }).Parent = b
			text({ Text = play.desc, FontFace = FONT_MED, TextColor3 = BG, TextWrapped = true, Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.48) }).Parent = b
			b.Activated:Connect(function()
				MatchAction:FireServer("call", play.id)
			end)
			b.Parent = controls
		end
	elseif s.phase == "defcall" then
		hint.Text = ("Call a defense (keys 1-3)  -  you're playing %s %s, Q to switch"):format(s.control and s.control.pos or "", s.control and s.control.name or "")
		for i, call in MatchConfig.DefenseCalls do
			local b = button({ Text = "", Size = UDim2.fromOffset(220, 100), BackgroundColor3 = i == 3 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(64, 160, 255) })
			text({ Text = ("[%d] %s"):format(i, call.name), FontFace = FONT_HEAVY, TextColor3 = BG, Size = UDim2.new(1, 0, 0.42, 0) }).Parent = b
			text({ Text = call.desc, FontFace = FONT_MED, TextColor3 = BG, TextWrapped = true, Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.48) }).Parent = b
			b.Activated:Connect(function()
				MatchAction:FireServer("defcall", call.id)
			end)
			b.Parent = controls
		end
		switchButton().Parent = controls
	elseif s.phase == "presnap" and not userBall then
		hint.Text = ("You're the %s %s. Space when ready  -  Q to switch player"):format(s.control and s.control.pos or "", s.control and s.control.name or "")
		button({ Text = "READY  [SPACE]", Size = UDim2.fromOffset(240, 70) }, function()
			MatchAction:FireServer("snap")
		end).Parent = controls
		switchButton().Parent = controls
	elseif s.phase == "live" and not userBall then
		hint.Text = "Run into the ball carrier to tackle. Get under a throw to intercept. Q = switch to the defender nearest the ball"
		switchButton().Parent = controls
	elseif s.phase == "presnap" then
		hint.Text = s.play == "run" and "Snap it: you'll take the handoff and run" or "Snap it, then throw with keys 1-4 (yellow tags) or tap a receiver button"
		button({ Text = "SNAP  [SPACE]", Size = UDim2.fromOffset(260, 70) }, function()
			MatchAction:FireServer("snap")
		end).Parent = controls
	elseif s.phase == "live" and s.playState == "dropback" and s.play ~= "run" then
		hint.Text = "Throw: keys 1-4, or run past the line to scramble"
		for _, t in s.targets do
			if t.available then
				button({ Text = ("[%d] %s %s"):format(t.key, t.pos, t.name), Size = UDim2.fromOffset(190, 56), BackgroundColor3 = Color3.fromRGB(255, 214, 40) }, function()
					MatchAction:FireServer("throw", t.key)
				end).Parent = controls
			end
		end
	elseif s.phase == "live" and s.playState == "carry" then
		hint.Text = "Run! Avoid tacklers and reach the end zone"
	elseif s.phase == "cpu" then
		hint.Text = string.upper(s.opponent.city .. " " .. s.opponent.name) .. " have the ball..."
	end

	if s.final then
		finalTitle.Text = s.final.result == "Win" and "YOU WIN!" or s.final.result == "Loss" and "YOU LOSE" or "TIE GAME"
		finalTitle.TextColor3 = s.final.result == "Win" and ACCENT or Color3.fromRGB(255, 196, 46)
		finalScore.Text = ("YOU %d  -  %d %s"):format(s.you, s.cpu, string.upper(s.opponent.name))
		finalCoins.Text = ("+%d Coins"):format(s.final.coins)
	end
end

Remotes:WaitForChild("MatchState").OnClientEvent:Connect(function(s)
	local main = player.PlayerGui:FindFirstChild("GridironUI")
	if s.phase == "ended" then
		state = nil
		gui.Enabled = false
		if main then
			main.Enabled = true
		end
		return
	end
	if not state or state.phase ~= s.phase then
		phaseChangedAt = os.clock()
	end
	state = s
	gui.Enabled = true
	if main then
		main.Enabled = false
	end
	if s.message then
		showBanner(s.message, s.messageColor)
	end
	render()
end)

quit.Activated:Connect(function()
	MatchAction:FireServer("leave")
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

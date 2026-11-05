-- KeybindsUI (client): Settings -> CONTROLS. Every game action with its key; click one, then press
-- any key or mouse button to rebind it. Saved to your account like the other settings.
-- MainUI calls KeybindsUI.Init(gui, save) once and KeybindsUI.Toggle() from the Settings panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SettingsConfig = require(ReplicatedStorage.Shared.SettingsConfig)
local Keybinds = require(ReplicatedStorage.Client.Keybinds)
local UI = require(ReplicatedStorage.Client.UIKit)

local C = UI.Color
local F = UI.Font
local new = UI.new

local KeybindsUI = {}

local panel, status
local chips = {} -- [action] = { chip = Frame, label = TextLabel, row = TextButton }
local listening = nil -- the action waiting for a key
local ignoreUntil = 0
local saveFn
local guiRef

local function draw()
	for action, c in chips do
		local waiting = listening == action
		c.label.Text = waiting and "PRESS A KEY..." or Keybinds.Text(action)
		c.chip.BackgroundColor3 = waiting and C.Gold or Color3.new(1, 1, 1)
		c.row.BackgroundTransparency = waiting and 0.1 or 0.35
	end
end

local function setStatus(text, color)
	status.Text = text
	status.TextColor3 = color or C.Muted
end

local function apply(changed)
	for _, pair in changed do
		saveFn("bind_" .. pair[1], pair[2])
	end
end

local function build()
	panel = UI.glass({ Name = "KeybindsPanel", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(460, 560), ZIndex = 120 })
	panel.Parent = guiRef
	panel:FindFirstChildOfClass("UIStroke").Color = C.Accent
	new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }).Parent = panel
	UI.text({ Text = "CONTROLS", FontFace = F.Display, TextScaled = false, TextSize = 24, Size = UDim2.new(1, -50, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 121 }).Parent = panel
	UI.button({ name = "Close", kind = "dark", text = "X", size = UDim2.fromOffset(36, 36), anchor = Vector2.new(1, 0), position = UDim2.new(1, 0, 0, -4), textSize = 14, z = 122 }, function()
		KeybindsUI.Toggle(false)
	end).Parent = panel
	status = UI.text({ Text = "", FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 12, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 121 })
	status.Parent = panel

	local list = new("ScrollingFrame", { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -110), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Accent, ZIndex = 121 }, {
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})
	list.Parent = panel
	for i, def in SettingsConfig.Binds do
		local row = new("TextButton", { Name = "Bind_" .. def.action, AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.35, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, ZIndex = 122 }, { UI.corner(10) })
		row.Parent = list
		UI.text({ Text = def.label, FontFace = F.Bold, TextScaled = false, TextSize = 14, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 123 }).Parent = row
		UI.text({ Text = def.desc, FontFace = F.Medium, TextColor3 = C.Muted, TextScaled = false, TextSize = 11, Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -150, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 123 }).Parent = row
		local chip = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(128, 32), ZIndex = 123 }, { UI.corner(7) })
		chip.Parent = row
		local label = UI.text({ Text = "", FontFace = F.Heavy, TextColor3 = C.BG, TextScaled = false, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 124 })
		label.Parent = chip
		chips[def.action] = { chip = chip, label = label, row = row }
		row.Activated:Connect(function()
			if os.clock() < ignoreUntil then
				return
			end
			UI.clickSound()
			if listening == def.action then
				listening = nil
				setStatus("Click an action, then press the key or mouse button you want.")
			else
				-- wait a frame so this click doesn't bind itself
				listening = nil
				task.defer(function()
					listening = def.action
					setStatus(("Press a key or mouse button for %s  (ESC to cancel)"):format(def.label), C.Gold)
					draw()
				end)
			end
			draw()
		end)
	end

	UI.button({ name = "Reset", kind = "dark", text = "RESET TO DEFAULT", size = UDim2.fromOffset(200, 42), anchor = Vector2.new(0, 1), position = UDim2.fromScale(0, 1), textSize = 14, z = 122 }, function()
		listening = nil
		apply(Keybinds.Reset())
		setStatus("Back to the default keys.", C.Accent)
		draw()
	end).Parent = panel
	UI.button({ name = "Done", kind = "primary", text = "DONE", size = UDim2.fromOffset(130, 42), anchor = Vector2.new(1, 1), position = UDim2.fromScale(1, 1), textSize = 14, z = 122 }, function()
		KeybindsUI.Toggle(false)
	end).Parent = panel

	UserInputService.InputBegan:Connect(function(input)
		local action = listening
		if not action or not panel.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			listening = nil
			setStatus("Click an action, then press the key or mouse button you want.")
			draw()
			return
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Keyboard and t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.MouseButton2 and t ~= Enum.UserInputType.MouseButton3 then
			return
		end
		local name = Keybinds.NameOf(input)
		if not name then
			setStatus(("%s can't be used (movement, chat and menu keys are taken)."):format(Keybinds.TextFor(input.KeyCode.Name)), C.Red)
			return
		end
		listening = nil
		ignoreUntil = os.clock() + 0.3 -- a click used as the new key doesn't also press a row
		local changed = Keybinds.Set(action, name)
		apply(changed)
		local label = action
		for _, b in SettingsConfig.Binds do
			if b.action == action then
				label = b.label
			end
		end
		if #changed > 1 then
			local other = changed[2][1]
			for _, b in SettingsConfig.Binds do
				if b.action == other then
					setStatus(("%s is now %s. %s moved to %s so they don't clash."):format(label, Keybinds.Text(action), b.label, Keybinds.Text(other)), C.Gold)
				end
			end
		else
			setStatus(("%s is now %s."):format(label, Keybinds.Text(action)), C.Accent)
		end
		draw()
	end)
end

function KeybindsUI.Init(gui, save)
	guiRef = gui
	saveFn = save
end

function KeybindsUI.Toggle(force)
	if not panel then
		build()
	end
	local show = force
	if show == nil then
		show = not panel.Visible
	end
	listening = nil
	panel.Visible = show
	if show then
		setStatus("Click an action, then press the key or mouse button you want.")
		draw()
		UI.pop(panel, 0.2)
	end
end

function KeybindsUI.IsOpen()
	return panel ~= nil and panel.Visible
end

return KeybindsUI

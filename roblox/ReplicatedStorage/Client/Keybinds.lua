-- Keybinds (client): which key or mouse button does each game action. Reads the player's saved
-- "bind_<action>" settings (SettingsConfig.Binds has the actions and defaults).
--   Keybinds.Is(action, input) -> did this InputBegan press that action's key?
--   Keybinds.Text(action)      -> "Q", "SPACE", "LEFT CLICK" (for buttons and hints)
--   Keybinds.Set(action, name) -> rebind (swaps with an action it would clash with); returns the
--                                 list of { action, name } that changed so the caller can save them

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.SettingsConfig)
local Settings = require(ReplicatedStorage.Client.Settings)

local Keybinds = {}

local byAction = {}
for _, b in SettingsConfig.Binds do
	byAction[b.action] = b
end

local MOUSE_TEXT = { MouseButton1 = "LEFT CLICK", MouseButton2 = "RIGHT CLICK", MouseButton3 = "MIDDLE CLICK" }
local KEY_TEXT = {
	Space = "SPACE", LeftShift = "L-SHIFT", RightShift = "R-SHIFT", LeftControl = "L-CTRL", RightControl = "R-CTRL",
	LeftAlt = "L-ALT", RightAlt = "R-ALT", Return = "ENTER", Backspace = "BKSP", CapsLock = "CAPS",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",",
	Period = ".", BackSlash = "\\", Insert = "INS", Delete = "DEL", Home = "HOME", End = "END", PageUp = "PGUP",
	PageDown = "PGDN",
}

function Keybinds.Get(action)
	local def = byAction[action]
	if not def then
		return nil
	end
	local name = Settings.Get("bind_" .. action)
	return SettingsConfig.ValidBind(name) and name or def.default
end

-- Name a key or button from an input ("Q", "MouseButton1"), or nil if it can't be bound
function Keybinds.NameOf(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
		return t.Name
	end
	if t == Enum.UserInputType.Keyboard and SettingsConfig.ValidBind(input.KeyCode.Name) then
		return input.KeyCode.Name
	end
	return nil
end

function Keybinds.Is(action, input)
	local name = Keybinds.Get(action)
	if not name then
		return false
	end
	if MOUSE_TEXT[name] then
		return input.UserInputType.Name == name
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == name
end

function Keybinds.TextFor(name)
	return MOUSE_TEXT[name] or KEY_TEXT[name] or string.upper(name or "?")
end

function Keybinds.Text(action)
	return Keybinds.TextFor(Keybinds.Get(action))
end

-- Is anything other than `except` bound to this key/button?
function Keybinds.UsedBy(name, except)
	for _, b in SettingsConfig.Binds do
		if b.action ~= except and Keybinds.Get(b.action) == name then
			return b.action
		end
	end
	return nil
end

local function shareGroup(a, b)
	for _, g in byAction[a].groups do
		if table.find(byAction[b].groups, g) then
			return true
		end
	end
	return false
end

function Keybinds.Set(action, name)
	local def = byAction[action]
	if not def or not SettingsConfig.ValidBind(name) then
		return {}
	end
	local old = Keybinds.Get(action)
	if old == name then
		return {}
	end
	local changed = {}
	-- an action that's used at the same time and already on this key gets your old key
	for _, b in SettingsConfig.Binds do
		if b.action ~= action and Keybinds.Get(b.action) == name and shareGroup(action, b.action) then
			Settings.Set("bind_" .. b.action, old)
			table.insert(changed, { b.action, old })
		end
	end
	Settings.Set("bind_" .. action, name)
	table.insert(changed, 1, { action, name })
	return changed
end

-- Every action back to its default; returns what changed
function Keybinds.Reset()
	local changed = {}
	for _, b in SettingsConfig.Binds do
		if Keybinds.Get(b.action) ~= b.default then
			Settings.Set("bind_" .. b.action, b.default)
			table.insert(changed, { b.action, b.default })
		end
	end
	return changed
end

return Keybinds

-- Player settings (saved on the server, applied on the client).

local SettingsConfig = {}

SettingsConfig.Defaults = {
	music = 1, -- 0..1, music + stadium crowd
	sfx = 1, -- 0..1, hits, whistles, menus
	shake = true, -- camera shake on big hits
	callouts = true, -- floating rating text (TRUCKED!, BURNED!) over players
	hubMotion = true, -- slow camera drift in the lobby
}

-- Controls (PC): every game action's key, saved as "bind_<action>" = a KeyCode name or
-- MouseButton1/2/3. Actions in the same group can be used at the same moment, so they can't share
-- a key (rebinding onto one swaps the two); actions in different groups may (Q is both SWITCH on
-- defense and JUKE with the ball).
SettingsConfig.Binds = {
	{ action = "throw", label = "THROW", desc = "Throw to where you aim (QB)", default = "MouseButton1", groups = { "qb" } },
	{ action = "snap", label = "SNAP / READY", desc = "Start the play", default = "Space", groups = { "presnap" } },
	{ action = "switch", label = "SWITCH PLAYER", desc = "Take over another defender", default = "Q", groups = { "presnap", "defense", "air" } },
	{ action = "catch", label = "CATCH", desc = "Press as the ball arrives", default = "C", groups = { "air" } },
	{ action = "jump", label = "JUMP", desc = "High-point a pass", default = "Space", groups = { "air" } },
	{ action = "juke", label = "JUKE", desc = "Sidestep a tackler", default = "Q", groups = { "carry" } },
	{ action = "spin", label = "SPIN", desc = "Spin out of a tackle", default = "R", groups = { "carry" } },
	{ action = "stiff", label = "STIFF ARM", desc = "Shove a tackler away", default = "F", groups = { "carry" } },
	{ action = "dive", label = "DIVE", desc = "Dive forward / dive tackle", default = "E", groups = { "carry", "defense" } },
	{ action = "block", label = "BLOCK", desc = "Lock up the nearest defender", default = "X", groups = { "block" } },
}
for _, b in SettingsConfig.Binds do
	SettingsConfig.Defaults["bind_" .. b.action] = b.default
end

-- keys that can't be used: movement, menus, chat, Roblox's own
local BLOCKED = {
	W = true, A = true, S = true, D = true, Up = true, Down = true, Left = true, Right = true,
	Escape = true, Unknown = true, Slash = true, Backquote = true, Tab = true, F9 = true, F12 = true,
	LeftSuper = true, RightSuper = true, Menu = true, Print = true,
}
local MOUSE = { MouseButton1 = true, MouseButton2 = true, MouseButton3 = true }

-- Is this a key/button a player may bind?
function SettingsConfig.ValidBind(name)
	if type(name) ~= "string" or #name > 32 then
		return false
	end
	if MOUSE[name] then
		return true
	end
	if BLOCKED[name] then
		return false
	end
	for _, item in Enum.KeyCode:GetEnumItems() do
		if item.Name == name then
			return true
		end
	end
	return false
end

SettingsConfig.Order = {
	{ key = "music", kind = "slider", label = "MUSIC & CROWD" },
	{ key = "sfx", kind = "slider", label = "SOUND EFFECTS" },
	{ key = "shake", kind = "toggle", label = "CAMERA SHAKE", desc = "On big hits, sacks and picks" },
	{ key = "callouts", kind = "toggle", label = "RATING CALLOUTS", desc = "TRUCKED!, BURNED! over players" },
	{ key = "hubMotion", kind = "toggle", label = "LOBBY CAMERA MOTION", desc = "Slow drift around your player" },
}

-- Server-side check: is this a valid value for this setting? Returns the cleaned value.
function SettingsConfig.Clean(key, value)
	local default = SettingsConfig.Defaults[key]
	if default == nil then
		return nil
	end
	if type(default) == "number" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
	end
	if type(default) == "string" then
		return SettingsConfig.ValidBind(value) and value or nil
	end
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

-- Fill missing keys with defaults
function SettingsConfig.Resolve(saved)
	local out = {}
	for k, v in SettingsConfig.Defaults do
		local s = saved and saved[k]
		if s ~= nil and type(s) == type(v) and (type(v) ~= "string" or SettingsConfig.ValidBind(s)) then
			out[k] = s
		else
			out[k] = v
		end
	end
	return out
end

return SettingsConfig

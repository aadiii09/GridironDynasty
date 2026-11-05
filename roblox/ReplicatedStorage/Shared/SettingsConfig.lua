-- Player settings (saved on the server, applied on the client).

local SettingsConfig = {}

SettingsConfig.Defaults = {
	music = 1, -- 0..1, music + stadium crowd
	sfx = 1, -- 0..1, hits, whistles, menus
	shake = true, -- camera shake on big hits
	callouts = true, -- floating rating text (TRUCKED!, BURNED!) over players
	hubMotion = true, -- slow camera drift in the lobby
}

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
		if s ~= nil and type(s) == type(v) then
			out[k] = s
		else
			out[k] = v
		end
	end
	return out
end

return SettingsConfig

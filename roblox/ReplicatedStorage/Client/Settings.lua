-- Settings (client): the local player's current settings, shared by every client script.
-- MainUI loads them from the save and sends changes to the server; everyone else reads Get().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.SettingsConfig)

local Settings = {}
Settings.Changed = Instance.new("BindableEvent") -- (key, value)

local values = SettingsConfig.Resolve(nil)

function Settings.Get(key)
	return values[key]
end

-- Apply a value locally (fires Changed). Returns true if it changed.
function Settings.Set(key, value)
	if SettingsConfig.Defaults[key] == nil or values[key] == value then
		return false
	end
	values[key] = value
	Settings.Changed:Fire(key, value)
	return true
end

-- Load a whole saved table (from the inventory snapshot)
function Settings.Load(saved)
	for key, value in SettingsConfig.Resolve(saved) do
		Settings.Set(key, value)
	end
end

return Settings

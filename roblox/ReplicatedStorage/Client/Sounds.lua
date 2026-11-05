-- Sounds (client): one place for every sound in the game.
-- All audio is from Roblox's licensed libraries (Pro Sound Effects + APM Music), free for any
-- experience to use.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Settings = require(ReplicatedStorage.Client.Settings)

local Sounds = {}

local IDS = {
	-- match
	whistle = { 9117261163, 0.5 }, -- referee whistle, short double burst
	whoosh = { 9126229267, 0.55 }, -- throw
	catch = { 9113506925, 0.8 }, -- leather glove smack
	tackle = { 9113569832, 0.9 }, -- body impact
	bodyfall = { 9113470178, 0.5 },
	cheer = { 9120975204, 0.7 }, -- big crowd cheer
	groan = { 9114010279, 0.6 }, -- crowd disappointment
	-- menus
	click = { 9113885761, 0.5 },
	packTear = { 9113837029, 0.8 },
	packWhoosh = { 9126228631, 0.5 },
	cardFlip = { 9118104432, 0.6 },
	coins = { 9125500770, 0.45 },
	-- loops
	crowdLoop = { 1839973460, 0.32, true }, -- APM stadium crowd, horns and chants
	lobbyMusic = { 128683938011405, 0.22, true }, -- APM "Ascending Glory"
}

local folder = Instance.new("Folder")
folder.Name = "GridironSounds"
folder.Parent = SoundService
-- volume groups for the settings menu: loops (music + crowd) and everything else
local function group(name, volume)
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	return g
end
local musicGroup = group("GridironMusic", Settings.Get("music"))
local sfxGroup = group("GridironEffects", Settings.Get("sfx"))
Settings.Changed.Event:Connect(function(key, value)
	if key == "music" then
		musicGroup.Volume = value
	elseif key == "sfx" then
		sfxGroup.Volume = value
	end
end)

local sounds = {}
for name, def in IDS do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. def[1]
	s.Volume = def[2]
	s.Looped = def[3] == true
	s.SoundGroup = s.Looped and musicGroup or sfxGroup
	s.Parent = folder
	sounds[name] = s
end

-- Play a one-shot (overlapping plays allowed). pitch adds a little variety.
function Sounds.Play(name, volumeScale, pitch)
	local base = sounds[name]
	if not base then
		return
	end
	local s = base:Clone()
	s.Volume = base.Volume * (volumeScale or 1)
	s.PlaybackSpeed = pitch or 1
	s.Parent = folder
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local currentLoop
-- Crossfade to a background loop ("crowdLoop", "lobbyMusic" or nil for silence)
function Sounds.SetLoop(name)
	if currentLoop == name then
		return
	end
	local old = currentLoop and sounds[currentLoop]
	if old then
		local t = TweenService:Create(old, TweenInfo.new(1.2), { Volume = 0 })
		t:Play()
		t.Completed:Once(function()
			if currentLoop ~= old.Name then
				old:Stop()
				old.Volume = IDS[old.Name][2]
			end
		end)
	end
	currentLoop = name
	local new = name and sounds[name]
	if new then
		new.Volume = 0
		if not new.IsPlaying then
			new:Play()
		end
		TweenService:Create(new, TweenInfo.new(1.2), { Volume = IDS[name][2] }):Play()
	end
end

return Sounds

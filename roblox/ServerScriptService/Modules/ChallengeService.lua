-- ChallengeService (server): daily + weekly challenge progress, resets and reward claims.
-- Saved in the player's data as data.challenges = { day, week, progress = { [id] = n },
-- claimed = { [id] = true }, bonus = { daily = day, weekly = week } }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChallengeConfig = require(ReplicatedStorage.Shared.ChallengeConfig)
local PlayerData = require(ServerScriptService.Modules.PlayerData)

local ChallengeService = {}

local remotes
local grantPack -- set by Start (PackService.GrantFree)
local claiming = {} -- [Player] = true while a claim is being processed

-- Reset the parts of the save that belong to an old day / week
local function current(data)
	local day, week = ChallengeConfig.Day(), ChallengeConfig.Week()
	local c = data.challenges
	if type(c) ~= "table" then
		c = { progress = {}, claimed = {}, bonus = {} }
		data.challenges = c
	end
	c.progress = c.progress or {}
	c.claimed = c.claimed or {}
	c.bonus = c.bonus or {}
	if c.day ~= day then
		for _, ch in ChallengeConfig.Daily do
			c.progress[ch.id] = nil
			c.claimed[ch.id] = nil
		end
		c.day = day
	end
	if c.week ~= week then
		for _, ch in ChallengeConfig.Weekly do
			c.progress[ch.id] = nil
			c.claimed[ch.id] = nil
		end
		c.week = week
	end
	return c, day, week
end

local function list(c, defs)
	local out, done = {}, 0
	for _, ch in defs do
		local progress = math.min(c.progress[ch.id] or 0, ch.target)
		local claimed = c.claimed[ch.id] == true
		if claimed then
			done += 1
		end
		table.insert(out, { id = ch.id, text = ch.text, target = ch.target, progress = progress, reward = ch.reward, claimed = claimed, complete = progress >= ch.target })
	end
	return out, done
end

function ChallengeService.Snapshot(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return nil
	end
	local c, day, week = current(profile.data)
	local daily, dailyDone = list(c, ChallengeConfig.DailyFor(day))
	local weekly, weeklyDone = list(c, ChallengeConfig.WeeklyFor(week))
	return {
		serverTime = os.time(),
		daily = {
			list = daily,
			endsAt = ChallengeConfig.DayEnds(day),
			bonus = ChallengeConfig.DailyBonus,
			bonusReady = dailyDone == #daily and c.bonus.daily ~= day,
			bonusClaimed = c.bonus.daily == day,
		},
		weekly = {
			list = weekly,
			endsAt = ChallengeConfig.WeekEnds(week),
			bonus = ChallengeConfig.WeeklyBonus,
			bonusReady = weeklyDone == #weekly and c.bonus.weekly ~= week,
			bonusClaimed = c.bonus.weekly == week,
		},
	}
end

local function push(player)
	local snap = ChallengeService.Snapshot(player)
	if snap then
		remotes.ChallengesChanged:FireClient(player, snap)
	end
end

-- Add to stats, e.g. { wins = 1, td = 3 }. Only today's / this week's active challenges move.
function ChallengeService.Record(player, deltas)
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local newlyDone = {}
	PlayerData.Update(player, function(data)
		local c, day, week = current(data)
		for _, defs in { ChallengeConfig.DailyFor(day), ChallengeConfig.WeeklyFor(week) } do
			for _, ch in defs do
				local d = deltas[ch.stat]
				if d and d > 0 and not c.claimed[ch.id] then
					local before = c.progress[ch.id] or 0
					c.progress[ch.id] = math.min(ch.target, before + d)
					if before < ch.target and c.progress[ch.id] >= ch.target then
						table.insert(newlyDone, ch.text)
					end
				end
			end
		end
	end)
	push(player)
	if #newlyDone > 0 then
		remotes.ChallengesChanged:FireClient(player, { completed = newlyDone })
	end
end

local function giveReward(player, reward)
	if reward.coins then
		PlayerData.AddCoins(player, reward.coins)
		return { coins = reward.coins }
	elseif reward.pack then
		local result = grantPack(player, reward.pack, "challenge reward")
		return { pack = reward.pack, opened = result }
	end
	return {}
end

-- kind = "challenge" (id = challenge id) | "dailyBonus" | "weeklyBonus"
local function claim(player, kind, id)
	if claiming[player] then
		return { ok = false, err = "One moment..." }
	end
	local profile = PlayerData.Get(player)
	if not profile then
		return { ok = false, err = "Still loading." }
	end
	claiming[player] = true
	local ok, res = pcall(function()
		local c, day, week = current(profile.data)
		local reward
		if kind == "challenge" then
			local ch = ChallengeConfig.ById[id]
			if type(id) ~= "string" or not ch then
				return { ok = false, err = "Unknown challenge." }
			end
			local active = false
			for _, defs in { ChallengeConfig.DailyFor(day), ChallengeConfig.WeeklyFor(week) } do
				for _, a in defs do
					active = active or a.id == id
				end
			end
			if not active then
				return { ok = false, err = "That challenge has ended." }
			end
			if c.claimed[id] then
				return { ok = false, err = "Already claimed." }
			end
			if (c.progress[id] or 0) < ch.target then
				return { ok = false, err = "Not finished yet." }
			end
			PlayerData.Update(player, function()
				c.claimed[id] = true
			end)
			reward = ch.reward
		elseif kind == "dailyBonus" or kind == "weeklyBonus" then
			local snap = ChallengeService.Snapshot(player)
			local set = kind == "dailyBonus" and snap.daily or snap.weekly
			if not set.bonusReady then
				return { ok = false, err = set.bonusClaimed and "Already claimed." or "Claim all three first." }
			end
			PlayerData.Update(player, function()
				if kind == "dailyBonus" then
					c.bonus.daily = day
				else
					c.bonus.weekly = week
				end
			end)
			reward = set.bonus
		else
			return { ok = false, err = "Unknown claim." }
		end
		local given = giveReward(player, reward)
		task.spawn(PlayerData.SaveNow, player)
		return { ok = true, given = given }
	end)
	claiming[player] = nil
	push(player)
	if not ok then
		warn("[Challenges] claim failed:", res)
		return { ok = false, err = "Couldn't claim, try again." }
	end
	return res
end

function ChallengeService.Start(remoteFolder, packGrant)
	remotes = remoteFolder
	grantPack = packGrant
	remotes.GetChallenges.OnServerInvoke = function(player)
		PlayerData.WaitFor(player, 30)
		return ChallengeService.Snapshot(player)
	end
	remotes.ClaimChallenge.OnServerInvoke = claim
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		claiming[player] = nil
	end)
end

return ChallengeService
